import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import { processMonitor } from '../utils/process-monitor.js';
import { InputValidator, MessageProcessor } from './aicli-utils.js';
import { ClaudeStreamParser } from './stream-parser.js';
import { createLogger } from '../utils/logger.js';

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
    // Skip command detection in test environment to avoid spawning processes
    this.aicliCommand = process.env.NODE_ENV === 'test' ? 'claude' : this.findAICLICommand();
    this.permissionMode = 'default';
    this.allowedTools = ['Read', 'Write', 'Edit'];
    this.disallowedTools = [];
    this.skipPermissions = false;
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
   * Execute AICLI CLI command for a session
   * This method handles both regular and long-running commands
   */
  async executeAICLICommand(session, prompt) {
    const { sessionId, workingDirectory, conversationStarted, initialPrompt, isRestoredSession } =
      session;
    
    // Create logger with session context
    const sessionLogger = logger.child({ sessionId });

    // Build AICLI CLI arguments - use stream-json to avoid buffer limits
    const args = ['--print', '--output-format', 'stream-json', '--verbose'];

    // Only add session arguments if we have a valid sessionId
    if (sessionId) {
      // For continuing conversations or restored sessions, use --resume instead of --session-id
      // Restored sessions must use --resume because AICLI CLI already knows about them
      if (conversationStarted || isRestoredSession) {
        // For established conversations or sessions that were restored from persistence,
        // use --resume to continue the existing Claude CLI session
        args.push('--resume');
        args.push(sessionId);
      } else {
        // For truly new conversations with provided session ID, use --session-id
        args.push('--session-id');
        args.push(sessionId);
      }
    }
    // For fresh chats (no sessionId), let Claude CLI create its own session ID

    // Add permission configuration
    this.addPermissionArgs(args);

    // Validate arguments
    InputValidator.validateAICLIArgs(args);

    // Determine the prompt to send
    let finalPrompt = prompt;
    if (!conversationStarted && initialPrompt) {
      finalPrompt = `${initialPrompt}\n\n${prompt}`;
      sessionLogger.debug('Combined initial prompt with command prompt');
    }

    sessionLogger.info('Executing AICLI command', {
      workingDirectory,
      promptLength: finalPrompt?.length,
      conversationStarted,
      isRestoredSession: isRestoredSession || false,
      cliFlag: conversationStarted || isRestoredSession ? '--resume' : '--session-id'
    });
    
    sessionLogger.debug('Command details', {
      argCount: args.length,
      promptPreview: finalPrompt?.substring(0, 100) + (finalPrompt?.length > 100 ? '...' : '')
    });

    // No more timeout calculations - trust Claude CLI
    return this.runAICLIProcess(args, finalPrompt, workingDirectory, sessionId);
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
  async runAICLIProcess(args, prompt, workingDirectory, sessionId) {
    const processLogger = logger.child({ sessionId });
    
    processLogger.debug('Running AICLI process', {
      argCount: args.length,
      hasPrompt: !!prompt,
      promptLength: prompt?.length || 0,
      workingDirectory
    });

    return new Promise((promiseResolve, reject) => {
      let aicliProcess;

      try {
        // Build the complete command arguments
        // When using --print with stdin, don't include prompt in args
        const useStdin = prompt && args.includes('--print');
        const fullArgs = useStdin ? args : prompt ? [...args, prompt] : args;

        processLogger.debug('Spawning AICLI process', {
          command: this.aicliCommand,
          fullArgCount: fullArgs.length,
          useStdin
        });

        aicliProcess = this.spawnFunction(this.aicliCommand, fullArgs, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (spawnError) {
        processLogger.error('Failed to spawn AICLI CLI', { error: spawnError.message, code: spawnError.code });
        const errorMsg =
          spawnError.code === 'ENOENT'
            ? 'AICLI CLI not found. Please ensure AICLI CLI is installed and in your PATH.'
            : `Failed to start AICLI CLI: ${spawnError.message}`;
        reject(new Error(errorMsg));
        return;
      }

      processLogger.info('Process started', { pid: aicliProcess.pid });

      // Handle stdin input
      this.handleStdinInput(aicliProcess, prompt, args);

      // Start monitoring this process
      this.startProcessMonitoring(aicliProcess.pid);

      // Emit process start event
      this.emit('processStart', {
        sessionId,
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
        healthMonitor
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
  handleStdinInput(aicliProcess, prompt, args) {
    // When using --print, AICLI CLI might expect input from stdin
    // Try writing the prompt to stdin instead of passing as argument
    if (prompt && args.includes('--print')) {
      logger.debug('Writing prompt to stdin');
      aicliProcess.stdin.write(prompt);
      aicliProcess.stdin.end();
    } else {
      // Close stdin immediately if no prompt
      aicliProcess.stdin.end();
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
            cpuPercent: info.cpu
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
  createOutputHandler(sessionId, aicliProcess, promiseResolve, reject, healthMonitor) {
    let stdout = '';
    let stderr = '';
    const stdoutBuffers = []; // Store raw buffers to prevent encoding issues
    const stderrBuffers = [];

    // Initialize stream parser for this command
    const streamParser = new ClaudeStreamParser();

    aicliProcess.stdout.on('data', (data) => {
      // Store raw buffer to prevent encoding truncation
      stdoutBuffers.push(data);

      const chunk = data.toString();
      stdout += chunk;
      // Only log stdout at debug level to reduce spam
      if (logger.shouldLog('debug')) {
        processLogger.debug('STDOUT chunk received', {
          chunkLength: chunk.length,
          totalLength: stdout.length
        });
      }

      if (healthMonitor) {
        healthMonitor.recordActivity();
      }

      // Parse the chunk into structured messages
      try {
        const parsedChunks = streamParser.parseData(chunk, false);

        // Emit each parsed chunk as a separate stream event
        for (const parsedChunk of parsedChunks) {
          this.emit('streamChunk', {
            sessionId,
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
      // Log stderr at warn level since it might indicate issues
      if (chunk.trim()) {
        processLogger.warn('STDERR output', {
          length: chunk.length,
          content: chunk.substring(0, 200)
        });
      }

      if (healthMonitor) {
        healthMonitor.recordActivity();
      }

      // Emit stderr for logging
      this.emit('processStderr', {
        sessionId,
        pid: aicliProcess.pid,
        data: chunk,
        timestamp: new Date().toISOString(),
      });
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
              chunks: stdoutBuffers.length
            });
          }

          if (stderrBuffers.length > 0) {
            const combinedBuffer = Buffer.concat(stderrBuffers);
            completeStderr = combinedBuffer.toString('utf8');
            logger.debug('STDERR reconstructed', {
              sessionId,
              length: completeStderr.length,
              chunks: stderrBuffers.length
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
          stderr: completeStderr.length
        });

        // Emit any remaining chunks with final flag
        try {
          const finalChunks = streamParser.parseData('', true); // Pass empty string with isComplete=true
          for (const chunk of finalChunks) {
            this.emit('streamChunk', {
              sessionId,
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

        this.processOutput(completeStdout, sessionId, promiseResolve, reject);
      },
    };
  }

  /**
   * Process the complete output from AICLI CLI
   */
  processOutput(completeStdout, sessionId, promiseResolve, reject) {
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
        responseCount: responses.length
      });

      if (responses.length === 0) {
        reject(new Error('No valid JSON objects found in AICLI CLI output'));
        return;
      }

      // Find the final result
      const finalResult =
        responses.find((r) => r.type === 'result') || responses[responses.length - 1];

      // Emit all responses for detailed tracking
      responses.forEach((response, index) => {
        logger.debug('Processing response', {
          sessionId,
          index: index + 1,
          type: response.type,
          subtype: response.subtype || 'none'
        });
        this.emit('aicliResponse', {
          sessionId,
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
        lastChars: completeStdout.substring(Math.max(0, completeStdout.length - 200))
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

    // Simple status logging every 10 seconds
    const statusInterval = setInterval(() => {
      if (aicliProcess && aicliProcess.pid) {
        const runtime = Math.round((Date.now() - startTime) / 1000);
        const timeSinceActivity = Math.round((Date.now() - lastActivityTime) / 1000);
        logger.debug('AICLI process status', {
          pid: aicliProcess.pid,
          sessionId,
          runtime,
          lastActivity: timeSinceActivity
        });
      }
    }, 10000); // Log status every 10 seconds

    return {
      recordActivity: () => {
        lastActivityTime = Date.now();
        logger.debug('AICLI activity detected', { sessionId });
      },
      cleanup: () => {
        if (statusInterval) {
          clearInterval(statusInterval);
        }
      },
    };
  }

  /**
   * Find the Claude CLI command
   */
  findAICLICommand() {
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
    const prompt = null;

    switch (testType) {
      case 'version':
        args = ['--version'];
        break;
      case 'help':
        args = ['--help'];
        break;
      case 'simple':
        args = ['--print', 'Hello world'];
        break;
      case 'json':
        args = ['--print', '--output-format', 'json', 'Hello world'];
        break;
      default:
        throw new Error(`Unknown test type: ${testType}`);
    }

    return this.runAICLIProcess(args, prompt, process.cwd(), 'test-session', 30000);
  }
}
