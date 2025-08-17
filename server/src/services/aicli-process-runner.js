import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import { processMonitor } from '../utils/process-monitor.js';
import { InputValidator, MessageProcessor } from './aicli-utils.js';
import { UnifiedMessageParser } from './message-parser.js';
import { createLogger } from '../utils/logger.js';
import { commandSecurity } from './command-security.js';
import { permissionManager } from './permission-manager.js';
import { activityMonitor } from './activity-monitor.js';

const logger = createLogger('AICLIProcess');

/**
 * Handles AICLI CLI process execution, monitoring, and stream parsing
 */
export class AICLIProcessRunner extends EventEmitter {
  constructor(options = {}) {
    super();

    // Allow dependency injection for testing - set this first
    this.spawnFunction = options.spawnFunction || spawn;

    // Configuration
    // Lazy initialization - command will be detected on first use
    this._aicliCommand = null;
    this.permissionMode = 'default';
    this.allowedTools = ['Read', 'Write', 'Edit'];
    this.disallowedTools = [];
    this.skipPermissions = false;
  }

  // Lazy getter for AICLI command
  get aicliCommand() {
    if (!this._aicliCommand) {
      // Skip command detection in test environment to avoid spawning processes
      this._aicliCommand = process.env.NODE_ENV === 'test' ? 'claude' : this.findAICLICommand();
    }
    return this._aicliCommand;
  }

  /**
   * Configure permission settings
   */
  setPermissionMode(mode) {
    const validModes = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];
    if (validModes.includes(mode)) {
      this.permissionMode = mode;
      logger.info('Permission mode set', { mode });
    } else {
      logger.warn('Invalid permission mode', { mode, validModes });
    }
  }

  /**
   * Create an interactive Claude CLI session that stays running
   * Returns the process and initial session info
   */
  async createInteractiveSession(workingDirectory) {
    const sessionLogger = logger.child({ workingDirectory });

    // Build args for interactive mode (no --print flag)
    const args = ['--output-format', 'stream-json', '--verbose'];

    // Add permission configuration
    this.addPermissionArgs(args);

    sessionLogger.info('Creating interactive Claude session', {
      workingDirectory,
      args: args.slice(0, 3), // Log first few args
    });

    return new Promise((resolve, reject) => {
      let claudeProcess;
      let initialSessionId = null;
      let initComplete = false;

      try {
        // Spawn Claude in interactive mode
        claudeProcess = this.spawnFunction(this.aicliCommand, args, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'], // Keep pipes open for communication
        });
      } catch (spawnError) {
        sessionLogger.error('Failed to spawn interactive Claude CLI', {
          error: spawnError.message,
          code: spawnError.code,
        });
        reject(new Error(`Failed to start Claude CLI: ${spawnError.message}`));
        return;
      }

      if (!claudeProcess.pid) {
        reject(new Error('Claude CLI process failed to start (no PID)'));
        return;
      }

      sessionLogger.info('Interactive process started', { pid: claudeProcess.pid });

      // Set up stream parser for this session
      const streamParser = new UnifiedMessageParser();

      // Handle stdout - parse initial response to get session ID
      claudeProcess.stdout.on('data', (data) => {
        const chunk = data.toString();
        sessionLogger.debug('Interactive stdout chunk', {
          length: chunk.length,
          preview: chunk.substring(0, 200),
        });

        // Parse stream JSON to look for session ID
        const lines = chunk.split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const parsed = JSON.parse(line);
            sessionLogger.debug('Parsed JSON from Claude', {
              type: parsed.type,
              subtype: parsed.subtype,
              hasSessionId: !!parsed.session_id,
            });

            // Look for session ID in system init message
            if (parsed.type === 'system' && parsed.subtype === 'init' && parsed.session_id) {
              initialSessionId = parsed.session_id;
              sessionLogger.info('Got session ID from Claude', { sessionId: initialSessionId });

              if (!initComplete) {
                initComplete = true;
                // Resolve with process and session info
                resolve({
                  process: claudeProcess,
                  sessionId: initialSessionId,
                  pid: claudeProcess.pid,
                  streamParser,
                  workingDirectory,
                });
              }
            }
          } catch (e) {
            sessionLogger.debug('Failed to parse line as JSON', {
              line: line.substring(0, 100),
              error: e.message,
            });
          }
        }
      });

      // Handle stderr
      claudeProcess.stderr.on('data', (data) => {
        const error = data.toString();
        sessionLogger.error('Claude stderr', { error });

        if (!initComplete) {
          initComplete = true;
          reject(new Error(`Claude CLI error: ${error}`));
        }
      });

      // Handle process exit
      claudeProcess.on('exit', (code) => {
        sessionLogger.info('Claude process exited', { code });

        if (!initComplete) {
          initComplete = true;
          reject(new Error(`Claude CLI exited immediately with code ${code}`));
        }
      });

      // Handle process errors
      claudeProcess.on('error', (error) => {
        sessionLogger.error('Claude process error', { error: error.message });

        if (!initComplete) {
          initComplete = true;
          reject(error);
        }
      });

      // Set a timeout for initialization (30 seconds for interactive mode)
      setTimeout(() => {
        if (!initComplete) {
          initComplete = true;
          sessionLogger.error('Timeout waiting for Claude to initialize', {
            pid: claudeProcess?.pid,
            receivedSessionId: initialSessionId,
          });
          reject(new Error('Timeout waiting for Claude CLI to initialize (30s)'));
        }
      }, 30000); // 30 second timeout for interactive mode
    });
  }

  /**
   * Send a message to an interactive Claude session and get response
   */
  async sendToInteractiveSession(sessionInfo, message) {
    const { process: claudeProcess, sessionId } = sessionInfo;
    const sessionLogger = logger.child({ sessionId });

    return new Promise((resolve, reject) => {
      let responseComplete = false;
      const responses = [];

      // Set up one-time listeners for this message
      const dataHandler = (data) => {
        const chunk = data.toString();

        // Parse each line as stream JSON
        const lines = chunk.split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const parsed = JSON.parse(line);
            responses.push(parsed);

            // Check if this is the final result
            if (parsed.type === 'result') {
              responseComplete = true;
              claudeProcess.stdout.removeListener('data', dataHandler);

              // Extract session ID from result
              const resultSessionId = parsed.session_id || sessionId;

              sessionLogger.info('Got complete response', {
                responseCount: responses.length,
                sessionId: resultSessionId,
              });

              // Return the final result with all responses
              resolve({
                result: parsed.result,
                sessionId: resultSessionId,
                responses,
                success: !parsed.is_error,
              });
            }
          } catch (e) {
            // Not valid JSON, continue collecting
          }
        }
      };

      const errorHandler = (data) => {
        const error = data.toString();
        sessionLogger.error('Error during message send', { error });
        claudeProcess.stderr.removeListener('data', errorHandler);
        reject(new Error(`Claude error: ${error}`));
      };

      // Attach handlers
      claudeProcess.stdout.on('data', dataHandler);
      claudeProcess.stderr.once('data', errorHandler);

      // Send the message
      sessionLogger.info('Sending message to interactive session', {
        messageLength: message.length,
      });

      claudeProcess.stdin.write(`${message}\n`, (err) => {
        if (err) {
          sessionLogger.error('Failed to write to stdin', { error: err.message });
          claudeProcess.stdout.removeListener('data', dataHandler);
          claudeProcess.stderr.removeListener('data', errorHandler);
          reject(err);
        }
      });

      // Set a timeout for response
      setTimeout(() => {
        if (!responseComplete) {
          claudeProcess.stdout.removeListener('data', dataHandler);
          claudeProcess.stderr.removeListener('data', errorHandler);
          reject(new Error('Timeout waiting for Claude response'));
        }
      }, 120000); // 2 minute timeout per message
    });
  }

  setAllowedTools(tools) {
    if (Array.isArray(tools)) {
      this.allowedTools = tools;
      logger.info('Allowed tools configured', { tools });
    }
  }

  setDisallowedTools(tools) {
    if (Array.isArray(tools)) {
      this.disallowedTools = tools;
      logger.info('Disallowed tools configured', { tools });
    }
  }

  setSkipPermissions(skip) {
    this.skipPermissions = !!skip;
    if (skip) {
      logger.warn('Permission checks bypassed - dangerously-skip-permissions enabled');
    }
  }

  /**
   * Intercept and validate tool use from Claude
   * This is called when we detect Claude is trying to use a tool
   */
  async validateToolUse(toolName, toolInput, sessionId) {
    // Only validate Bash commands for now
    if (toolName !== 'Bash') {
      return { allowed: true };
    }

    // Extract command from tool input
    const command = toolInput.command || toolInput;

    // Validate the command with security service
    const validation = await commandSecurity.validateCommand(
      command,
      this.currentWorkingDirectory,
      { sessionId }
    );

    // Track the command in activity monitor
    activityMonitor.trackCommand(command, validation, sessionId);

    if (!validation.allowed) {
      logger.warn('Security blocked command', {
        sessionId,
        command,
        reason: validation.reason,
        code: validation.code,
      });

      // Track security violation
      activityMonitor.trackSecurityViolation(
        {
          type: 'COMMAND_BLOCKED',
          details: { command, reason: validation.reason },
          severity: 'high',
        },
        sessionId
      );

      // Emit security violation
      this.emit('securityViolation', {
        sessionId,
        type: 'COMMAND_BLOCKED',
        command,
        reason: validation.reason,
        code: validation.code,
      });
    } else if (validation.requiresConfirmation) {
      // Request permission for destructive command
      logger.info('Requesting permission for destructive command', { command, sessionId });

      const permission = await permissionManager.requestPermission(`Execute command: ${command}`, {
        command,
        workingDirectory: this.currentWorkingDirectory,
        sessionId,
      });

      if (!permission.approved) {
        validation.allowed = false;
        validation.reason = permission.reason || 'Permission denied';

        // Track denial
        activityMonitor.trackActivity({
          type: 'permission_denied',
          command,
          reason: validation.reason,
          sessionId,
        });
      }
    }

    return validation;
  }

  /**
   * Execute AICLI CLI command for a session
   * This method handles both regular and long-running commands
   */
  async executeAICLICommand(session, prompt, attachmentPaths = []) {
    const { sessionId, workingDirectory, requestId } = session;

    // Create logger with session context
    const sessionLogger = logger.child({ sessionId });

    // Security validation for working directory
    const dirValidation = await commandSecurity.validateDirectory(workingDirectory);
    if (!dirValidation.allowed) {
      sessionLogger.warn('Security violation: Working directory not allowed', {
        workingDirectory,
        reason: dirValidation.reason,
      });

      // Emit security violation event
      this.emit('securityViolation', {
        sessionId,
        type: 'DIRECTORY_VIOLATION',
        workingDirectory,
        reason: dirValidation.reason,
      });

      throw new Error(`Security violation: ${dirValidation.reason}`);
    }

    // Build AICLI CLI arguments - use stream-json to avoid buffer limits
    // Include --print flag as required by AICLI CLI for stdin input
    const args = ['--print', '--output-format', 'stream-json', '--verbose'];

    // CURRENT BROKEN SESSION FLOW:
    // 1. Client sends message with optional sessionId
    // 2. Server spawns NEW Claude process with --session-id flag
    // 3. Claude REJECTS duplicate session IDs with "Session ID already in use" error
    // 4. This is WRONG - needs interactive sessions instead (persistent processes)
    //
    // The --session-id flag is meant to CREATE a new session with that ID,
    // not resume an existing one. Each message spawns a new process which
    // can't access the context from previous processes.
    
    // Only add session arguments if we have a valid sessionId
    if (sessionId) {
      // PROBLEM: This tries to create a NEW session with this ID, not resume
      args.push('--session-id');
      args.push(sessionId);
      sessionLogger.info('Using --session-id with session ID', { sessionId });
    } else {
      // For fresh chats (no sessionId), let Claude CLI create its own session ID
      sessionLogger.info('Starting new conversation (no session ID)');
    }

    // Add attachment file paths if provided
    if (attachmentPaths && attachmentPaths.length > 0) {
      // Claude CLI accepts files as additional arguments after the prompt
      sessionLogger.info('Adding attachment file paths to command', {
        count: attachmentPaths.length,
      });
      for (const filePath of attachmentPaths) {
        args.push(filePath);
      }
    }

    // Add permission configuration
    this.addPermissionArgs(args);

    // Validate arguments
    InputValidator.validateAICLIArgs(args);

    // Use the prompt as-is for stateless operation
    const finalPrompt = prompt;

    // Validate we have a prompt
    if (!finalPrompt || finalPrompt.trim().length === 0) {
      sessionLogger.error('No prompt provided for AICLI command');
      throw new Error('Prompt is required for AICLI CLI execution');
    }

    sessionLogger.info('Executing AICLI command', {
      workingDirectory,
      promptLength: finalPrompt?.length,
      hasSessionId: !!sessionId,
      sessionId: sessionId || 'new',
    });

    sessionLogger.debug('Command details', {
      argCount: args.length,
      promptPreview: finalPrompt?.substring(0, 100) + (finalPrompt?.length > 100 ? '...' : ''),
    });

    // No more timeout calculations - trust Claude CLI
    return this.runAICLIProcess(args, finalPrompt, workingDirectory, sessionId, requestId);
  }

  /**
   * Add permission arguments to the command
   */
  addPermissionArgs(args) {
    if (this.skipPermissions) {
      args.push('--dangerously-skip-permissions');
    } else {
      // Only add permission configuration if not skipping permissions

      // Add permission mode if configured
      if (this.permissionMode && this.permissionMode !== 'default') {
        args.push('--permission-mode');
        args.push(this.permissionMode);
      }

      // Add allowed tools if configured
      if (this.allowedTools.length > 0) {
        args.push('--allowedTools');
        args.push(this.allowedTools.join(','));
      }

      // Add disallowed tools if configured
      if (this.disallowedTools.length > 0) {
        args.push('--disallowedTools');
        args.push(this.disallowedTools.join(','));
      }
    }
  }

  /**
   * Run AICLI CLI process with comprehensive monitoring and parsing
   */
  async runAICLIProcess(args, prompt, workingDirectory, sessionId, requestId = null) {
    const processLogger = logger.child({ sessionId });

    processLogger.debug('Running AICLI process', {
      argCount: args.length,
      hasPrompt: !!prompt,
      promptLength: prompt?.length || 0,
      workingDirectory,
    });

    // Store working directory for command validation
    this.currentWorkingDirectory = workingDirectory;
    this.currentSessionId = sessionId;

    return new Promise((promiseResolve, reject) => {
      let aicliProcess;

      try {
        // Build the complete command arguments
        // With --print flag, prompt is sent via stdin, not as argument
        const fullArgs = args;

        processLogger.debug('Spawning AICLI process', {
          command: this.aicliCommand,
          fullArgCount: fullArgs.length,
        });

        // Safety check for test environment
        if (process.env.NODE_ENV === 'test' && this.spawnFunction === spawn) {
          console.error(
            'WARNING: Using real spawn in test environment! This will create real processes.'
          );
          console.trace('Stack trace for real spawn call:');
        }

        aicliProcess = this.spawnFunction(this.aicliCommand, fullArgs, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (spawnError) {
        processLogger.error('Failed to spawn AICLI CLI', {
          error: spawnError.message,
          code: spawnError.code,
        });
        const errorMsg =
          spawnError.code === 'ENOENT'
            ? 'AICLI CLI not found. Please ensure AICLI CLI is installed and in your PATH.'
            : `Failed to start AICLI CLI: ${spawnError.message}`;
        reject(new Error(errorMsg));
        return;
      }

      processLogger.info('Process started', {
        pid: aicliProcess.pid,
        hasPrompt: !!prompt,
        promptLength: prompt?.length || 0,
      });

      // Handle stdin input - pass the prompt
      this.handleStdinInput(aicliProcess, prompt);

      // Start monitoring this process
      this.startProcessMonitoring(aicliProcess.pid);

      // Emit process start event
      this.emit('processStart', {
        sessionId,
        requestId, // Include original request ID
        pid: aicliProcess.pid,
        command: this.aicliCommand,
        args,
        workingDirectory,
        type: 'command',
      });

      // Set up health monitoring (no timeouts, just monitoring)
      const healthMonitor = this.createHealthMonitor(aicliProcess, sessionId);

      // Set up output handling
      const outputHandler = this.createOutputHandler(
        sessionId,
        aicliProcess,
        promiseResolve,
        reject,
        healthMonitor,
        processLogger,
        requestId
      );

      // Handle process events
      aicliProcess.on('close', (code) => {
        outputHandler.handleClose(code);
        healthMonitor.cleanup();
      });

      aicliProcess.on('error', (error) => {
        processLogger.error('AICLI process error', { error: error.message });
        healthMonitor.cleanup();
        reject(new Error(`AICLI CLI process error: ${error.message}`));
      });
    });
  }

  /**
   * Handle stdin input for the process
   */
  handleStdinInput(aicliProcess, prompt) {
    // With --print mode, send prompt via stdin
    try {
      if (prompt && prompt.trim().length > 0) {
        // Write the prompt and close stdin
        aicliProcess.stdin.write(prompt, 'utf8', (error) => {
          if (error) {
            logger.error('Failed to write prompt to stdin', { error: error.message });
          }
          aicliProcess.stdin.end();
        });
      } else {
        // For empty prompts, still need to close stdin
        logger.warn('Empty prompt provided to AICLI CLI');
        aicliProcess.stdin.end();
      }
    } catch (error) {
      logger.error('Error handling stdin input', { error: error.message });
      // Ensure stdin is closed even on error
      try {
        aicliProcess.stdin.end();
      } catch (endError) {
        logger.error('Failed to close stdin', { error: endError.message });
      }
    }
  }

  /**
   * Start process monitoring
   */
  async startProcessMonitoring(pid) {
    if (pid) {
      try {
        const info = await processMonitor.monitorProcess(pid);
        if (info) {
          logger.debug('Initial process metrics', {
            pid,
            memoryMB: (info.rss / 1024 / 1024).toFixed(2),
            cpuPercent: info.cpu,
          });
        }
      } catch (err) {
        logger.debug('Failed to get initial process metrics', { error: err.message });
      }
    }
  }

  /**
   * Create output handler for process stdout/stderr
   */
  createOutputHandler(
    sessionId,
    aicliProcess,
    promiseResolve,
    reject,
    healthMonitor,
    processLogger,
    requestId = null
  ) {
    let stdout = '';
    let stderr = '';
    const stdoutBuffers = []; // Store raw buffers to prevent encoding issues
    const stderrBuffers = [];

    // Initialize stream parser for this command
    const streamParser = new UnifiedMessageParser();

    aicliProcess.stdout.on('data', (data) => {
      // Store raw buffer to prevent encoding truncation
      stdoutBuffers.push(data);

      const chunk = data.toString();
      stdout += chunk;
      // Only log stdout at debug level to reduce spam
      if (logger.shouldLog('debug')) {
        processLogger.debug('STDOUT chunk received', {
          chunkLength: chunk.length,
          totalLength: stdout.length,
        });
      }

      if (healthMonitor) {
        healthMonitor.recordActivity();
      }

      // Parse the chunk into structured messages
      try {
        const parsedChunks = streamParser.parseStreamData(chunk, false);

        // Emit each parsed chunk as a separate stream event
        for (const parsedChunk of parsedChunks) {
          this.emit('streamChunk', {
            sessionId,
            requestId, // Include original request ID
            chunk: parsedChunk,
            timestamp: new Date().toISOString(),
          });
        }
      } catch (parseError) {
        processLogger.error('Failed to parse stream chunk', { error: parseError.message });
        // Fallback to emitting raw data
        this.emit('commandProgress', {
          sessionId,
          pid: aicliProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      }
    });

    aicliProcess.stderr.on('data', (data) => {
      // Store raw buffer to prevent encoding truncation
      stderrBuffers.push(data);

      const chunk = data.toString();
      stderr += chunk;

      // Emit stderr event for monitoring
      this.emit('processStderr', {
        sessionId,
        data: chunk,
        timestamp: new Date().toISOString(),
      });

      // Log stderr at warn level since it might indicate issues
      if (chunk.trim()) {
        processLogger.warn('STDERR output', {
          length: chunk.length,
          content: chunk.substring(0, 200),
        });
      }

      if (healthMonitor) {
        healthMonitor.recordActivity();
      }
    });

    return {
      handleClose: (code) => {
        logger.info('AICLI process closed', { sessionId, exitCode: code });

        // Reconstruct complete output from buffers to prevent encoding issues
        let completeStdout = '';
        let completeStderr = '';

        try {
          if (stdoutBuffers.length > 0) {
            const combinedBuffer = Buffer.concat(stdoutBuffers);
            completeStdout = combinedBuffer.toString('utf8');
            logger.debug('STDOUT reconstructed', {
              sessionId,
              length: completeStdout.length,
              chunks: stdoutBuffers.length,
            });
          }

          if (stderrBuffers.length > 0) {
            const combinedBuffer = Buffer.concat(stderrBuffers);
            completeStderr = combinedBuffer.toString('utf8');
            logger.debug('STDERR reconstructed', {
              sessionId,
              length: completeStderr.length,
              chunks: stderrBuffers.length,
            });
          }
        } catch (bufferError) {
          logger.error('Failed to reconstruct buffers', { sessionId, error: bufferError.message });
          // Fallback to the string concatenation approach
          completeStdout = stdout;
          completeStderr = stderr;
        }

        logger.debug('Final output lengths', {
          sessionId,
          stdout: completeStdout.length,
          stderr: completeStderr.length,
        });

        // Emit any remaining chunks with final flag
        try {
          const finalChunks = streamParser.parseStreamData('', true); // Pass empty string with isComplete=true
          for (const chunk of finalChunks) {
            this.emit('streamChunk', {
              sessionId,
              requestId, // Include original request ID
              chunk,
              timestamp: new Date().toISOString(),
            });
          }
        } catch (parseError) {
          logger.error('Failed to emit final chunks', { sessionId, error: parseError.message });
        }

        // Emit process exit event
        this.emit('processExit', {
          sessionId,
          requestId, // Include original request ID
          pid: aicliProcess.pid,
          code,
          stdout: completeStdout.substring(0, 1000),
          stderr: completeStderr,
          timestamp: new Date().toISOString(),
        });

        if (code !== 0) {
          reject(new Error(`AICLI CLI exited with code ${code}: ${completeStderr}`));
          return;
        }

        this.processOutput(completeStdout, sessionId, promiseResolve, reject, requestId);
      },
    };
  }

  /**
   * Process the complete output from AICLI CLI
   */
  processOutput(completeStdout, sessionId, promiseResolve, reject, requestId = null) {
    try {
      // Validate JSON before parsing
      if (!completeStdout || completeStdout.length === 0) {
        reject(new Error('AICLI CLI returned empty output'));
        return;
      }

      // For stream-json format, we don't need strict JSON validation since it's newline-delimited
      const trimmedOutput = completeStdout.trim();
      if (!trimmedOutput || trimmedOutput.length === 0) {
        reject(new Error('AICLI CLI returned empty output'));
        return;
      }

      // Parse stream-json format - newline-delimited JSON objects
      const responses = MessageProcessor.parseStreamJsonOutput(trimmedOutput);
      logger.info('AICLI command completed', {
        sessionId,
        responseCount: responses.length,
      });

      if (responses.length === 0) {
        reject(new Error('No valid JSON objects found in AICLI CLI output'));
        return;
      }

      // Find the final result and extract session ID from any message that has it
      const finalResult =
        responses.find((r) => r.type === 'result') || responses[responses.length - 1];

      // Look for session_id in any of the responses (system messages often have it)
      let claudeSessionId = null;
      for (const response of responses) {
        if (response.session_id) {
          claudeSessionId = response.session_id;
          logger.info('Found Claude session ID in response', {
            sessionId,
            claudeSessionId,
            responseType: response.type,
          });
          break;
        }
      }

      // If we found a session ID, add it to the final result
      if (claudeSessionId && finalResult) {
        finalResult.session_id = claudeSessionId;
      }

      // Emit all responses for detailed tracking
      responses.forEach((response, index) => {
        logger.debug('Processing response', {
          sessionId,
          index: index + 1,
          type: response.type,
          subtype: response.subtype || 'none',
        });
        this.emit('aicliResponse', {
          sessionId,
          requestId, // Include original request ID
          response,
          isLast: index === responses.length - 1,
        });
      });

      promiseResolve(finalResult);
    } catch (error) {
      logger.error('Failed to parse AICLI response', {
        sessionId,
        error: error.message,
        stdoutLength: completeStdout.length,
        firstChars: completeStdout.substring(0, 200),
        lastChars: completeStdout.substring(Math.max(0, completeStdout.length - 200)),
      });

      // Try to provide more helpful error information
      if (error.message.includes('Unterminated string')) {
        reject(new Error('AICLI CLI response was truncated - output is incomplete'));
      } else if (error.message.includes('Unexpected end')) {
        reject(new Error('AICLI CLI response ended unexpectedly - possible truncation'));
      } else {
        reject(new Error(`Failed to parse AICLI CLI response: ${error.message}`));
      }
    }
  }

  /**
   * Create simple health monitor - no timeouts, just monitoring
   */
  createHealthMonitor(aicliProcess, sessionId) {
    const startTime = Date.now();
    let lastActivityTime = Date.now();
    let intervalCleared = false;

    // Simple status logging every 30 seconds (reduced frequency)
    const statusInterval = setInterval(() => {
      if (aicliProcess && aicliProcess.pid && !intervalCleared) {
        const runtime = Math.round((Date.now() - startTime) / 1000);
        const timeSinceActivity = Math.round((Date.now() - lastActivityTime) / 1000);
        logger.debug('AICLI process status', {
          pid: aicliProcess.pid,
          sessionId,
          runtime,
          lastActivity: timeSinceActivity,
        });
      }
    }, 30000); // Log status every 30 seconds (reduced frequency)

    return {
      recordActivity: () => {
        lastActivityTime = Date.now();
      },
      cleanup: () => {
        if (statusInterval && !intervalCleared) {
          clearInterval(statusInterval);
          intervalCleared = true;
          logger.debug('Health monitor cleaned up', { sessionId });
        }
      },
    };
  }

  /**
   * Find the Claude CLI command
   */
  findAICLICommand() {
    // CRITICAL: Never spawn real processes in test environment
    if (process.env.NODE_ENV === 'test') {
      return 'claude';
    }

    // Try different command names
    const commandNames = ['claude', 'aicli'];

    for (const cmd of commandNames) {
      try {
        const result = this.spawnFunction(cmd, ['--version'], { stdio: 'pipe' });
        if (result.pid) {
          result.kill();
          return cmd;
        }
      } catch (error) {
        // Command not found, try next
      }
    }

    // Default to 'claude' if nothing found
    return 'claude';
  }

  /**
   * Test AICLI CLI command availability and functionality
   */
  async testAICLICommand(testType = 'version') {
    logger.info('Testing AICLI command', { testType });

    let args = [];
    let prompt = null;

    switch (testType) {
      case 'version':
        args = ['--version'];
        break;
      case 'help':
        args = ['--help'];
        break;
      case 'simple':
        args = ['--output-format', 'stream-json'];
        prompt = 'Hello world';
        break;
      case 'json':
        args = ['--output-format', 'json'];
        prompt = 'Hello world';
        break;
      default:
        throw new Error(`Unknown test type: ${testType}`);
    }

    return this.runAICLIProcess(args, prompt, process.cwd(), 'test-session');
  }
}
