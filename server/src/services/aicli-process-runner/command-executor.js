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
    this.config.addPermissionArgs(args);

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

          logger.info('Command ended', {
            sessionId,
            code,
            signal,
          });

          if (code === 0) {
            // Process output
            try {
              const result = this.outputProcessor.processOutput(
                stdout,
                sessionId,
                resolve,
                reject,
                requestId
              );

              if (!result) {
                // If processOutput didn't resolve/reject, do it here
                resolve({
                  success: true,
                  stdout,
                  stderr,
                  code,
                });
              }
            } catch (error) {
              reject(error);
            }
          } else {
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
          this.handleStdinInput(aicliProcess, prompt);
        }

        // Create health monitor
        const healthMonitor = this.healthMonitor.createForProcess(
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
  handleStdinInput(aicliProcess, prompt) {
    // Ensure prompt is properly formatted
    const formattedPrompt = prompt.endsWith('\n') ? prompt : `${prompt}\n`;

    aicliProcess.stdin.write(formattedPrompt, (err) => {
      if (err) {
        logger.error('Failed to write to stdin', { error: err.message });
      } else {
        logger.debug('Prompt sent to AICLI CLI', {
          length: formattedPrompt.length,
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
