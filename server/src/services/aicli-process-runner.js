import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import { processMonitor } from '../utils/process-monitor.js';
import { InputValidator, MessageProcessor } from './aicli-utils.js';
import { ClaudeStreamParser } from './stream-parser.js';

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
      console.log(`🔐 Permission mode set to: ${mode}`);
    } else {
      console.warn(`⚠️  Invalid permission mode: ${mode}`);
    }
  }

  setAllowedTools(tools) {
    if (Array.isArray(tools)) {
      this.allowedTools = tools;
      console.log(`✅ Allowed tools set to: ${tools.join(', ')}`);
    }
  }

  setDisallowedTools(tools) {
    if (Array.isArray(tools)) {
      this.disallowedTools = tools;
      console.log(`🚫 Disallowed tools set to: ${tools.join(', ')}`);
    }
  }

  setSkipPermissions(skip) {
    this.skipPermissions = !!skip;
    if (skip) {
      console.log('⚠️  Permission checks will be bypassed (--dangerously-skip-permissions)');
    }
  }

  /**
   * Execute AICLI CLI command for a session
   * This method handles both regular and long-running commands
   */
  async executeAICLICommand(session, prompt) {
    const { sessionId, workingDirectory, conversationStarted, initialPrompt, isRestoredSession } =
      session;

    // Build AICLI CLI arguments - use stream-json to avoid buffer limits
    const args = ['--print', '--output-format', 'stream-json', '--verbose'];

    // For continuing conversations or restored sessions, use --resume instead of --session-id
    // Restored sessions must use --resume because AICLI CLI already knows about them
    if (conversationStarted || isRestoredSession) {
      args.push('--resume');
      args.push(sessionId);
    } else {
      // For truly new conversations, use --session-id
      args.push('--session-id');
      args.push(sessionId);
    }

    // Add permission configuration
    this.addPermissionArgs(args);

    // Validate arguments
    InputValidator.validateAICLIArgs(args);

    // Determine the prompt to send
    let finalPrompt = prompt;
    if (!conversationStarted && initialPrompt) {
      finalPrompt = `${initialPrompt}\n\n${prompt}`;
      console.log(`   📝 Combined initial prompt with command prompt`);
    }

    console.log(`🚀 Executing AICLI CLI with args:`, args);
    console.log(`   Working directory: ${workingDirectory}`);
    console.log(`   Original prompt: "${prompt?.substring(0, 50)}..."`);
    console.log(`   Initial prompt: "${initialPrompt?.substring(0, 50)}..."`);
    console.log(`   Final prompt length: ${finalPrompt?.length} chars`);
    console.log(
      `   Final prompt preview: "${finalPrompt?.substring(0, 100).replace(/\n/g, '\\n')}..."`
    );
    console.log(`   Conversation started: ${conversationStarted}`);
    console.log(`   Restored session: ${isRestoredSession || false}`);
    console.log(
      `   Using CLI flag: ${conversationStarted || isRestoredSession ? '--resume' : '--session-id'}`
    );

    console.log(`📤 Calling runAICLIProcess with:`);
    console.log(`   Args (${args.length}):`, args);
    console.log(
      `   Prompt: "${finalPrompt?.substring(0, 100)}${finalPrompt?.length > 100 ? '...' : ''}"`
    );
    console.log(`   SessionId: ${sessionId}`);

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
    console.log(`\n🔧 === runAICLIProcess CALLED ===`);
    console.log(`🔧 Running AICLI CLI process:`);
    console.log(`   Args (${args.length}): ${JSON.stringify(args)}`);
    console.log(`   Prompt provided: ${!!prompt}`);
    console.log(`   Prompt length: ${prompt ? prompt.length : 0}`);
    console.log(
      `   Prompt preview: ${prompt ? `"${prompt.substring(0, 100).replace(/\n/g, '\\n')}${prompt.length > 100 ? '...' : ''}"` : 'none'}`
    );
    console.log(`   Working dir: ${workingDirectory}`);
    console.log(`   Session ID: ${sessionId}`);

    return new Promise((promiseResolve, reject) => {
      let aicliProcess;

      try {
        // Build the complete command arguments
        // When using --print with stdin, don't include prompt in args
        const useStdin = prompt && args.includes('--print');
        const fullArgs = useStdin ? args : prompt ? [...args, prompt] : args;

        console.log(`📝 Final args being passed to AICLI CLI:`);
        console.log(`   Command: ${this.aicliCommand}`);
        console.log(
          `   Full args array (${fullArgs.length} items):`,
          fullArgs.map((arg, i) => `[${i}] ${arg.substring(0, 100)}`)
        );
        console.log(`   Has prompt: ${!!prompt}`);
        console.log(`   Using stdin for prompt: ${useStdin}`);

        aicliProcess = this.spawnFunction(this.aicliCommand, fullArgs, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (spawnError) {
        console.error(`❌ Failed to spawn AICLI CLI:`, spawnError);
        const errorMsg =
          spawnError.code === 'ENOENT'
            ? 'AICLI CLI not found. Please ensure AICLI CLI is installed and in your PATH.'
            : `Failed to start AICLI CLI: ${spawnError.message}`;
        reject(new Error(errorMsg));
        return;
      }

      console.log(`   Process started with PID: ${aicliProcess.pid}`);

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
        console.error(`❌ AICLI CLI process error:`, error);
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
      console.log(`   📝 Writing prompt to stdin instead of args`);
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
          console.log(
            `📊 Initial process metrics: Memory: ${(info.rss / 1024 / 1024).toFixed(2)}MB, CPU: ${info.cpu}%`
          );
        }
      } catch (err) {
        console.warn(`⚠️  Failed to get initial process metrics: ${err.message}`);
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
      console.log(
        `📊 AICLI CLI STDOUT (${chunk.length} chars, total: ${stdout.length}):`,
        JSON.stringify(chunk.substring(0, 200))
      );

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
        console.error('❌ Failed to parse stream chunk:', parseError);
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
      console.log(
        `📛 AICLI CLI STDERR (${chunk.length} chars, total: ${stderr.length}):`,
        JSON.stringify(chunk)
      );

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
        console.log(`🔚 AICLI CLI process closed with code: ${code}`);

        // Reconstruct complete output from buffers to prevent encoding issues
        let completeStdout = '';
        let completeStderr = '';

        try {
          if (stdoutBuffers.length > 0) {
            const combinedBuffer = Buffer.concat(stdoutBuffers);
            completeStdout = combinedBuffer.toString('utf8');
            console.log(
              `   STDOUT reconstructed: ${completeStdout.length} chars (${stdoutBuffers.length} chunks)`
            );
          }

          if (stderrBuffers.length > 0) {
            const combinedBuffer = Buffer.concat(stderrBuffers);
            completeStderr = combinedBuffer.toString('utf8');
            console.log(
              `   STDERR reconstructed: ${completeStderr.length} chars (${stderrBuffers.length} chunks)`
            );
          }
        } catch (bufferError) {
          console.error(`❌ Failed to reconstruct buffers:`, bufferError);
          // Fallback to the string concatenation approach
          completeStdout = stdout;
          completeStderr = stderr;
        }

        console.log(`   Final STDOUT length: ${completeStdout.length}`);
        console.log(`   Final STDERR length: ${completeStderr.length}`);

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
          console.error('❌ Failed to emit final chunks:', parseError);
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
      console.log(`✅ AICLI CLI command completed successfully`);
      console.log(`   Parsed ${responses.length} response objects from stream-json`);

      if (responses.length === 0) {
        reject(new Error('No valid JSON objects found in AICLI CLI output'));
        return;
      }

      // Find the final result
      const finalResult =
        responses.find((r) => r.type === 'result') || responses[responses.length - 1];

      // Emit all responses for detailed tracking
      responses.forEach((response, index) => {
        console.log(
          `   Response ${index + 1}: type=${response.type}, subtype=${response.subtype || 'none'}`
        );
        this.emit('aicliResponse', {
          sessionId,
          response,
          isLast: index === responses.length - 1,
        });
      });

      promiseResolve(finalResult);
    } catch (error) {
      console.error(`❌ Failed to parse AICLI CLI response:`, error);
      console.error(`   Raw stdout length:`, completeStdout.length);
      console.error(`   First 200 chars:`, completeStdout.substring(0, 200));
      console.error(
        `   Last 200 chars:`,
        completeStdout.substring(Math.max(0, completeStdout.length - 200))
      );

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
  createHealthMonitor(aicliProcess, _sessionId) {
    const startTime = Date.now();
    let lastActivityTime = Date.now();

    // Simple status logging every 10 seconds
    const statusInterval = setInterval(() => {
      if (aicliProcess && aicliProcess.pid) {
        const runtime = Math.round((Date.now() - startTime) / 1000);
        const timeSinceActivity = Math.round((Date.now() - lastActivityTime) / 1000);
        console.log(
          `📊 AICLI CLI PID ${aicliProcess.pid} still running... (runtime: ${runtime}s, last activity: ${timeSinceActivity}s ago)`
        );
      }
    }, 10000); // Log status every 10 seconds

    return {
      recordActivity: () => {
        lastActivityTime = Date.now();
        console.log(`💓 AICLI CLI activity detected`);
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
    console.log(`🧪 Testing AICLI CLI command: ${testType}`);

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
