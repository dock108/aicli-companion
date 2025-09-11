/**
 * Command Executor
 * Handles one-time AICLI command execution
 */

import { createLogger } from '../../utils/logger.js';
import { commandSecurity } from '../command-security.js';
import { OutputProcessor } from './output-processor.js';
import { HealthMonitor } from './health-monitor.js';
import { ServerConfig } from '../../config/server-config.js';

const logger = createLogger('CommandExecutor');

export class CommandExecutor {
  constructor(processManager, config) {
    this.processManager = processManager;
    this.config = config;
    this.outputProcessor = new OutputProcessor();
    this.healthMonitor = new HealthMonitor();
    this.serverConfig = new ServerConfig();
  }

  /**
   * Execute a one-time AICLI command
   */
  async execute(session, prompt, attachmentPaths = []) {
    const { sessionId, workingDirectory, requestId, deviceToken, claudeSessionId } = session;

    // Create logger with session context
    const sessionLogger = logger.child({ sessionId });

    // Security validation for working directory
    const dirValidation = await commandSecurity.validateDirectory(workingDirectory);
    if (!dirValidation.allowed) {
      sessionLogger.warn('Security violation: Working directory not allowed', {
        workingDirectory,
        reason: dirValidation.reason,
      });

      throw new Error(`Security violation: ${dirValidation.reason}`);
    }

    // Build AICLI CLI arguments - use stream-json to avoid buffer limits
    // Include --print flag as required by AICLI CLI for stdin input
    const args = ['--print', '--output-format', 'stream-json', '--verbose'];

    // Add --resume flag with Claude session ID if this is a continuing conversation
    // Use the claudeSessionId from the session, which is the ID from Claude's previous response
    if (claudeSessionId && claudeSessionId !== 'null' && claudeSessionId !== 'new') {
      args.push('--resume', claudeSessionId);
      sessionLogger.info('Using --resume with Claude session ID', {
        claudeSessionId,
        ourSessionId: sessionId,
      });
    } else {
      sessionLogger.info('Starting new Claude conversation (no --resume flag)', {
        sessionId,
        claudeSessionId,
      });
    }

    // Add permission configuration
    sessionLogger.info('Permission config before adding args', {
      skipPermissions: this.config.skipPermissions,
      allowedTools: this.config.allowedTools,
      argsBefore: [...args],
    });
    this.config.addPermissionArgs(args);
    sessionLogger.info('Permission config after adding args', {
      argsAfter: [...args],
    });

    // Add attachment file paths if provided
    if (attachmentPaths && attachmentPaths.length > 0) {
      for (const filePath of attachmentPaths) {
        args.push('--file', filePath);
      }
    }

    // Handle workspace mode - use the projects directory instead of __workspace__
    const actualWorkingDirectory =
      workingDirectory === '__workspace__' ? this.serverConfig.configPath : workingDirectory;

    // Log for better debugging
    sessionLogger.info('Executing AICLI command', {
      sessionId,
      originalWorkingDirectory: workingDirectory,
      actualWorkingDirectory,
      isWorkspace: workingDirectory === '__workspace__',
      configPath: this.serverConfig.configPath,
      attachmentCount: attachmentPaths.length,
      requestId,
    });

    try {
      const result = await this.runAICLIProcess(
        args,
        {
          cwd: actualWorkingDirectory,
          sessionId,
          requestId,
          deviceToken,
          workingDirectory, // Pass original working directory for workspace detection
        },
        prompt
      );

      sessionLogger.info('AICLI command completed', {
        sessionId,
        success: result.success,
        hasResponse: !!result.response,
      });

      return result;
    } catch (error) {
      sessionLogger.error('AICLI command failed', {
        sessionId,
        error: error.message,
        code: error.code,
      });

      // Check for specific error types
      if (error.message?.includes('Session expired') || error.code === 'SESSION_EXPIRED') {
        throw Object.assign(new Error('Session expired'), { code: 'SESSION_EXPIRED' });
      }

      throw error;
    }
  }

  /**
   * Run AICLI process with given arguments and input
   */
  async runAICLIProcess(args, options, prompt) {
    const { cwd, sessionId, requestId, deviceToken } = options;

    return new Promise((resolve, reject) => {
      let aicliProcess;
      let stdout = '';
      let stderr = '';
      let processExited = false;
      let healthMonitor = null;

      try {
        // Spawn the AICLI process
        aicliProcess = this.processManager.spawnProcess(args, {
          cwd,
          timeout: 300000, // 5 minute timeout
        });

        // Register process for tracking
        if (sessionId) {
          this.processManager.registerProcess(sessionId, aicliProcess);
        }

        // Start monitoring
        this.processManager.startProcessMonitoring(aicliProcess.pid);

        // Log activity
        logger.info('Command started', {
          sessionId,
          pid: aicliProcess.pid,
          cwd,
        });

        // Create output handler
        const outputHandler = this.createOutputHandler(sessionId, requestId);

        // Handle stdout
        aicliProcess.stdout.on('data', (data) => {
          stdout += data.toString();
          outputHandler.handleData(data);
        });

        // Handle stderr
        aicliProcess.stderr.on('data', (data) => {
          const chunk = data.toString();
          stderr += chunk;
          outputHandler.handleError(chunk);
        });

        // Handle process exit/close
        const exitHandler = (code, signal) => {
          if (processExited) return; // Avoid duplicate handling
          processExited = true;

          // Get human-readable signal name if available
          const signalName = signal ? `${signal} (${code})` : code;

          logger.info('Command ended', {
            sessionId,
            code,
            signal,
            signalName,
            exitReason: signal ? `killed by signal ${signal}` : `exited with code ${code}`,
          });

          // Stop health monitor
          if (healthMonitor) {
            healthMonitor.stop();
          }

          if (code === 0 || code === 143) {
            // Process output for both success (0) and SIGTERM (143)
            // SIGTERM is not an error - Claude has completed work and returned a session
            try {
              // Special handling for SIGTERM - log it
              if (code === 143) {
                logger.info(
                  'AICLI process exited with SIGTERM (143) - treating as successful completion',
                  {
                    code,
                    signal,
                    toolCount: healthMonitor?.toolUseCount || 0,
                    messageCount: healthMonitor?.messageCount || 0,
                    processRunTime: Date.now() - (healthMonitor?.startTime || Date.now()),
                  }
                );
              }

              // Pass SIGTERM info to output processor
              const result = this.outputProcessor.processOutput(
                stdout,
                sessionId,
                resolve,
                reject,
                requestId,
                code === 143
                  ? {
                      isSigterm: true,
                      sigtermReason: `after ${healthMonitor?.toolUseCount || 'unknown'} tools`,
                    }
                  : null
              );

              if (!result) {
                // If processOutput didn't resolve/reject, do it here
                resolve({
                  success: true,
                  stdout,
                  stderr,
                  code,
                  isSigterm: code === 143,
                  sigtermReason:
                    code === 143
                      ? `after ${healthMonitor?.toolUseCount || 'unknown'} tools`
                      : undefined,
                });
              }
            } catch (error) {
              reject(error);
            }
          } else {
            // Any other non-zero exit code is treated as an error
            logger.error('AICLI process exited with error', {
              code,
              signal,
              stderr: stderr.substring(0, 500),
            });
            reject(new Error(`AICLI CLI exited with code ${code}: ${stderr}`));
          }
        };

        // Listen for both exit and close events
        aicliProcess.on('exit', exitHandler);
        aicliProcess.on('close', exitHandler);

        // Handle process errors
        aicliProcess.on('error', (error) => {
          logger.error('AICLI process error', {
            error: error.message,
            code: error.code,
          });
          reject(error);
        });

        // Send prompt via stdin if provided
        if (prompt) {
          // Check if this is workspace mode based on the cwd
          const isWorkspaceMode =
            options.cwd === this.serverConfig.configPath &&
            options.workingDirectory === '__workspace__';
          this.handleStdinInput(aicliProcess, prompt, isWorkspaceMode, options.cwd);
        }

        // Create health monitor
        healthMonitor = this.healthMonitor.createForProcess(
          aicliProcess,
          sessionId,
          cwd,
          requestId,
          deviceToken
        );

        // Start health monitoring
        healthMonitor.start();

        // Clean up on completion
        const cleanupHandler = () => {
          healthMonitor.stop();
        };
        aicliProcess.once('exit', cleanupHandler);
        aicliProcess.once('close', cleanupHandler);
      } catch (error) {
        logger.error('Failed to run AICLI process', {
          error: error.message,
          sessionId,
        });
        reject(error);
      }
    });
  }

  /**
   * Handle stdin input for the process
   */
  handleStdinInput(aicliProcess, prompt, isWorkspaceMode = false, projectPath = null) {
    let finalPrompt = prompt;

    // Add path-based security restrictions for project mode
    if (!isWorkspaceMode) {
      const projectSecurityPrompt = `[PROJECT MODE SECURITY CONTEXT]

⚠️  CRITICAL: You are operating with FULL SYSTEM ACCESS via --dangerously-skip-permissions.
    The security model relies entirely on your adherence to these guidelines.

🎯 PROJECT SCOPE: ${projectPath}

✅ ALLOWED WITHIN PROJECT DIRECTORY:
- Full file system access (read, write, edit, delete)
- Execute any Bash commands and tools
- Create, modify, and delete files and directories
- Install dependencies and run development tools
- Access and modify project configuration files

⛔ RESTRICTED OUTSIDE PROJECT DIRECTORY:
- READ-ONLY access to files outside the project (for reference only)
- NO writing, editing, or deleting files outside project scope
- NO executing commands that modify system or other projects
- NO accessing sensitive files (credentials, SSH keys, system configs)
- NO modifying other projects or system-wide settings

🛡️ SECURITY PRINCIPLES:
- ALWAYS confirm the file path is within the project before write operations
- When reading external files, explicitly state this is for reference only
- If unsure about a path, ask the user for clarification
- Respect the user's trust - this system has no permission boundaries

USER REQUEST:
${prompt}`;

      finalPrompt = projectSecurityPrompt;
      logger.info('Added project security prompt', {
        projectDir: projectPath,
        originalLength: prompt.length,
        finalLength: finalPrompt.length,
      });
    }
    // Add workspace mode system prompt if in workspace mode
    else if (isWorkspaceMode) {
      const workspaceSystemPrompt = `[WORKSPACE MODE SECURITY CONTEXT]

⚠️  CRITICAL: You are operating with FULL SYSTEM ACCESS via --dangerously-skip-permissions.
    The security model relies entirely on your adherence to these workspace restrictions.

🌐 WORKSPACE SCOPE: Cross-project operations and new project creation

✅ ALLOWED OPERATIONS:
📖 READ-ONLY ANALYSIS:
- Browse, search, and read files across ALL existing projects
- Analyze project structures, dependencies, and patterns
- Compare implementations between projects
- View and understand existing codebases
- Generate project summaries and documentation

🆕 NEW PROJECT CREATION:
- Create entirely new project directories and structures
- Generate starter files and boilerplate code for NEW projects
- Set up initial configuration files (package.json, tsconfig.json, etc.)
- Create initial README, documentation, and planning files
- Copy templates and patterns from existing projects to new ones

⛔ STRICT RESTRICTIONS:
🚫 EXISTING PROJECT MODIFICATIONS:
- NO modifications to ANY existing project files
- NO writing, editing, or deleting files in established projects  
- NO Bash commands that modify existing project directories
- NO installing dependencies in existing projects
- NO running build/test commands that modify existing projects

🛡️ SECURITY PRINCIPLES:
- READ-ONLY means READ-ONLY for all existing projects
- Only create files in NEW project directories you create
- When creating new projects, explicitly state this is a new project
- For ANY modifications to existing projects: inform user to switch to project mode
- Respect the user's trust - this system has no permission boundaries

USER REQUEST:
${prompt}`;

      finalPrompt = workspaceSystemPrompt;
      logger.info('Added workspace mode system prompt', {
        originalLength: prompt.length,
        finalLength: finalPrompt.length,
      });
    }

    // Ensure prompt is properly formatted
    const formattedPrompt = finalPrompt.endsWith('\n') ? finalPrompt : `${finalPrompt}\n`;

    aicliProcess.stdin.write(formattedPrompt, (err) => {
      if (err) {
        logger.error('Failed to write to stdin', { error: err.message });
      } else {
        logger.debug('Prompt sent to AICLI CLI', {
          length: formattedPrompt.length,
          isWorkspaceMode,
        });
      }
      // Close stdin to signal end of input
      aicliProcess.stdin.end();
    });
  }

  /**
   * Create output handler for process stdout/stderr
   */
  createOutputHandler(sessionId, requestId) {
    const sessionLogger = logger.child({ sessionId, requestId });
    let buffer = '';

    return {
      handleData: (data) => {
        const chunk = data.toString();
        buffer += chunk;

        // Try to parse streaming JSON
        const lines = chunk.split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const parsed = JSON.parse(line);

            // Log significant events
            if (parsed.type === 'message_start') {
              sessionLogger.info('Claude message started', {
                id: parsed.message?.id,
                model: parsed.message?.model,
              });
            } else if (parsed.type === 'content_block_start') {
              if (parsed.content_block?.type === 'tool_use') {
                sessionLogger.info('Tool use detected', {
                  tool: parsed.content_block.name,
                });
              }
            } else if (parsed.type === 'message_stop') {
              sessionLogger.info('Claude message completed');
            }
          } catch (e) {
            // Not JSON, just regular output
          }
        }
      },

      handleError: (chunk) => {
        sessionLogger.warn('Process stderr', {
          preview: chunk.substring(0, 200),
        });

        // Check for known error patterns
        if (chunk.includes('Session expired') || chunk.includes('session not found')) {
          sessionLogger.error('Session expired detected');
        } else if (chunk.includes('rate_limit')) {
          sessionLogger.error('Rate limit detected');
        }
      },

      getBuffer: () => buffer,
    };
  }
}

export default CommandExecutor;
