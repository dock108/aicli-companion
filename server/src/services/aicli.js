import { spawn, exec } from 'child_process';
import { promisify } from 'util';
import { EventEmitter } from 'events';
import { processMonitor } from '../utils/process-monitor.js';
import { InputValidator, MessageProcessor, AICLIConfig } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';

const execAsync = promisify(exec);

export class AICLIService extends EventEmitter {
  constructor() {
    super();
    this.activeSessions = new Map();
    this.sessionMessageBuffers = new Map(); // Buffer messages per session for intelligent filtering
    // Try to find aicli in common locations
    this.aicliCommand = AICLIConfig.findAICLICommand();
    this.defaultWorkingDirectory = process.cwd();
    this.safeRootDirectory = null; // Will be set from server config
    this.maxSessions = 10;
    this.sessionTimeout = 30 * 60 * 1000; // 30 minutes

    // Permission configuration
    this.permissionMode = 'default'; // 'default', 'acceptEdits', 'bypassPermissions', 'plan'
    this.allowedTools = ['Read', 'Write', 'Edit']; // Default allowed tools for basic operations
    this.disallowedTools = []; // e.g., ['Bash(rm:*)', 'Bash(sudo:*)']
    this.skipPermissions = false; // Whether to use --dangerously-skip-permissions

    // Process monitoring
    this.processHealthCheckInterval = null;
    this.startProcessHealthMonitoring();
  }

  // Configure permission settings
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

  setSafeRootDirectory(dir) {
    this.safeRootDirectory = dir;
  }

  setSkipPermissions(skip) {
    this.skipPermissions = !!skip;
    if (skip) {
      console.log('⚠️  Permission checks will be bypassed (--dangerously-skip-permissions)');
    }
  }

  // Start process health monitoring
  startProcessHealthMonitoring() {
    // Skip in test environment to prevent hanging tests
    if (process.env.NODE_ENV === 'test') {
      return;
    }

    // Check process health every 30 seconds
    this.processHealthCheckInterval = setInterval(() => {
      this.checkAllProcessHealth();
    }, 30000);
  }

  // Stop process health monitoring
  stopProcessHealthMonitoring() {
    if (this.processHealthCheckInterval) {
      clearInterval(this.processHealthCheckInterval);
      this.processHealthCheckInterval = null;
    }
  }

  // Check health of all active AICLI processes
  async checkAllProcessHealth() {
    const activePids = [];

    for (const [sessionId, session] of this.activeSessions) {
      if (session.process && session.process.pid) {
        activePids.push(session.process.pid);

        try {
          const processInfo = await processMonitor.monitorProcess(session.process.pid);

          if (processInfo) {
            const health = processMonitor.checkHealth(processInfo);

            // Emit health status
            this.emit('processHealth', {
              sessionId,
              pid: session.process.pid,
              health: health.healthy ? 'healthy' : 'unhealthy',
              metrics: processInfo,
              warnings: health.warnings,
              critical: health.critical,
              timestamp: new Date().toISOString(),
            });

            // Log warnings or critical issues
            if (health.critical.length > 0) {
              console.error(`🚨 Critical health issues for session ${sessionId}:`, health.critical);
            } else if (health.warnings.length > 0) {
              console.warn(`⚠️  Health warnings for session ${sessionId}:`, health.warnings);
            }
          } else {
            // Process no longer exists
            console.warn(
              `⚠️  Process ${session.process.pid} for session ${sessionId} no longer exists`
            );
            this.cleanupDeadSession(sessionId);
          }
        } catch (error) {
          console.error(`Failed to monitor process ${session.process.pid}:`, error);
        }
      }
    }

    // Clean up old metrics
    processMonitor.cleanup(activePids);
  }

  // Cleanup dead session
  cleanupDeadSession(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isActive = false;
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);

      this.emit('sessionCleaned', {
        sessionId,
        reason: 'process_died',
        timestamp: new Date().toISOString(),
      });
    }
  }

  async checkAvailability() {
    try {
      console.log(`Checking AICLI CLI availability at: ${this.aicliCommand}`);
      const { stdout, _stderr } = await execAsync(`${this.aicliCommand} --version`);
      const version = stdout.trim();
      console.log(`AICLI Code version: ${version}`);
      return true;
    } catch (error) {
      console.error('AICLI Code not available:', error.message);
      console.error(`Tried to execute: ${this.aicliCommand} --version`);
      console.error('To fix this issue:');
      console.error('1. Make sure AICLI CLI is installed: npm install -g @anthropic-ai/aicli');
      console.error('2. Set AICLI_CLI_PATH environment variable to the full path');
      console.error('3. Or ensure aicli is in your PATH');
      return false;
    }
  }

  isAvailable() {
    // Quick synchronous check (can be enhanced)
    return true; // Assume available for now
  }

  async sendPrompt(prompt, options = {}) {
    const {
      sessionId = null,
      format = 'json',
      workingDirectory = process.cwd(),
      streaming = false,
    } = options;

    try {
      // Validate and sanitize inputs
      const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);
      const validatedFormat = InputValidator.validateFormat(format);
      const validatedWorkingDir = await InputValidator.validateWorkingDirectory(
        workingDirectory,
        this.safeRootDirectory
      );
      const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);

      if (streaming) {
        return await this.sendStreamingPrompt(sanitizedPrompt, {
          sessionId: sanitizedSessionId,
          workingDirectory: validatedWorkingDir,
        });
      } else {
        return await this.sendOneTimePrompt(sanitizedPrompt, {
          format: validatedFormat,
          workingDirectory: validatedWorkingDir,
        });
      }
    } catch (error) {
      console.error('Error sending prompt to AICLI Code:', error);
      throw new Error(`AICLI Code execution failed: ${error.message}`);
    }
  }

  async sendOneTimePrompt(prompt, { format = 'json', workingDirectory = process.cwd() }) {
    console.log(
      `📝 sendOneTimePrompt called with prompt: "${prompt?.substring(0, 50)}${prompt?.length > 50 ? '...' : ''}"`
    );

    // Input validation already done in sendPrompt, but double-check critical params
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);
    const validatedFormat = InputValidator.validateFormat(format);

    console.log(
      `   Sanitized prompt: "${sanitizedPrompt.substring(0, 50)}${sanitizedPrompt.length > 50 ? '...' : ''}"`
    );
    console.log(`   Format: ${validatedFormat}`);

    const args = ['--print', '--output-format', validatedFormat];

    // Add permission flags before the prompt
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

    // Add the prompt at the end
    args.push(sanitizedPrompt);

    // Validate arguments before spawning
    InputValidator.validateAICLIArgs(args);

    console.log(`🚀 Starting AICLI CLI with validated args:`, args.slice(0, -1)); // Log all args except prompt
    console.log(
      `   Prompt: "${sanitizedPrompt.substring(0, 50)}${sanitizedPrompt.length > 50 ? '...' : ''}"`
    );
    console.log(`   Working directory: ${workingDirectory}`);
    console.log(`   Full args array length: ${args.length}`);
    console.log(
      `   Last arg (should be prompt): "${args[args.length - 1]?.substring(0, 50)}${args[args.length - 1]?.length > 50 ? '...' : ''}"`
    );

    // Double-check the prompt is actually in the args
    if (!args.includes(sanitizedPrompt)) {
      console.error(`❌ ERROR: Prompt not found in args array!`);
    }

    return new Promise((resolvePromise, reject) => {
      let aicliProcess;
      try {
        aicliProcess = spawn(this.aicliCommand, args, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (spawnError) {
        console.error(`❌ Failed to spawn AICLI CLI:`, spawnError);
        const errorMsg =
          spawnError.code === 'ENOENT'
            ? 'AICLI CLI not found. Please ensure AICLI CLI is installed and in your PATH.'
            : `Failed to start AICLI CLI: ${spawnError.message}`;

        // Emit error event
        this.emit('processError', {
          error: errorMsg,
          timestamp: new Date().toISOString(),
        });

        reject(new Error(errorMsg));
        return;
      }

      // Close stdin immediately since we're not sending any input
      aicliProcess.stdin.end();

      let stdout = '';
      let stderr = '';

      console.log(`   Process started with PID: ${aicliProcess.pid}`);

      // Check if process actually started
      if (!aicliProcess.pid) {
        const errorMsg = 'AICLI CLI process failed to start (no PID)';
        console.error(`❌ ${errorMsg}`);
        this.emit('processError', {
          error: errorMsg,
          timestamp: new Date().toISOString(),
        });
        reject(new Error(errorMsg));
        return;
      }

      // Emit process start event
      this.emit('processStart', {
        pid: aicliProcess.pid,
        command: this.aicliCommand,
        args: args.slice(0, 3), // Don't include full prompt
        workingDirectory,
        type: 'one-time',
      });

      aicliProcess.stdout.on('data', (data) => {
        const chunk = data.toString();
        console.log(`   STDOUT chunk: ${chunk.length} chars`);
        stdout += chunk;

        // Emit stdout data for logging
        this.emit('processStdout', {
          pid: aicliProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      aicliProcess.stderr.on('data', (data) => {
        const chunk = data.toString();
        console.log(`   STDERR chunk: ${chunk}`);
        stderr += chunk;

        // Emit stderr data for logging
        this.emit('processStderr', {
          pid: aicliProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      aicliProcess.on('close', (code) => {
        console.log(`   Process closed with code: ${code}`);
        console.log(`   STDOUT length: ${stdout.length}`);
        console.log(`   STDERR length: ${stderr.length}`);

        // Emit process exit event
        this.emit('processExit', {
          pid: aicliProcess.pid,
          code,
          stdout: stdout.substring(0, 1000), // First 1000 chars for debugging
          stderr,
          timestamp: new Date().toISOString(),
        });

        if (code !== 0) {
          reject(new Error(`AICLI Code exited with code ${code}: ${stderr}`));
          return;
        }

        try {
          if (format === 'json') {
            const response = JSON.parse(stdout);
            console.log(`   ✅ Parsed JSON response successfully`);
            resolvePromise(response);
          } else {
            console.log(`   ✅ Returning raw text response`);
            resolvePromise({ result: stdout });
          }
        } catch (error) {
          console.log(`   ❌ JSON parse error: ${error.message}`);
          reject(new Error(`Failed to parse AICLI Code response: ${error.message}`));
        }
      });

      aicliProcess.on('error', (error) => {
        console.log(`   ❌ Process error: ${error.message}`);
        reject(new Error(`Failed to start AICLI Code: ${error.message}`));
      });

      // Add timeout protection
      const timeout = setTimeout(() => {
        console.log(`   ⏰ Process timeout, killing...`);
        aicliProcess.kill('SIGTERM');
        reject(new Error('AICLI Code process timed out'));
      }, 30000);

      aicliProcess.on('close', () => {
        clearTimeout(timeout);
      });
    });
  }

  async sendStreamingPrompt(prompt, { sessionId, workingDirectory = process.cwd() }) {
    // Validate inputs
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);
    const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);
    const sessionKey = sessionId || `session_${Date.now()}`;

    // Check session limits
    if (this.activeSessions.size >= this.maxSessions) {
      throw new Error(`Maximum number of sessions (${this.maxSessions}) reached`);
    }

    // Check if session already exists
    if (this.activeSessions.has(sessionKey)) {
      return this.sendToExistingSession(sessionKey, sanitizedPrompt);
    }

    // Create new interactive session
    return this.createInteractiveSession(sessionKey, sanitizedPrompt, validatedWorkingDir);
  }

  async createInteractiveSession(sessionId, initialPrompt, workingDirectory) {
    // Validate and sanitize inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(initialPrompt);
    const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);

    console.log(`🚀 Creating AICLI CLI session (metadata-only)`);
    console.log(`   Session ID: ${sanitizedSessionId}`);
    console.log(`   Working directory: ${validatedWorkingDir}`);
    console.log(`   Initial prompt: "${sanitizedPrompt}"`);

    // Create session metadata (no long-running process)
    const session = {
      sessionId: sanitizedSessionId,
      workingDirectory: validatedWorkingDir,
      isActive: true,
      createdAt: Date.now(),
      lastActivity: Date.now(),
      initialPrompt: sanitizedPrompt,
      conversationStarted: false,
    };

    this.activeSessions.set(sanitizedSessionId, session);

    // Initialize message buffer for this session
    this.sessionMessageBuffers.set(sanitizedSessionId, AICLIMessageHandler.createSessionBuffer());

    // Set up session timeout
    setTimeout(() => {
      if (this.activeSessions.has(sanitizedSessionId)) {
        console.log(`Session ${sanitizedSessionId} timed out, cleaning up`);
        this.closeSession(sanitizedSessionId);
      }
    }, this.sessionTimeout);

    console.log(`✅ AICLI CLI session metadata created successfully`);

    return {
      sessionId: sanitizedSessionId,
      success: true,
      message: 'Session ready for commands',
    };
  }

  async sendToExistingSession(sessionId, prompt) {
    // Validate inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);

    if (!sanitizedSessionId) {
      throw new Error('Invalid session ID');
    }

    const session = this.activeSessions.get(sanitizedSessionId);

    if (!session || !session.isActive) {
      throw new Error(`Session ${sanitizedSessionId} not found or inactive`);
    }

    try {
      // Update last activity
      session.lastActivity = Date.now();

      console.log(
        `📝 Executing AICLI CLI command for session ${sanitizedSessionId}: "${sanitizedPrompt}"`
      );
      console.log(`   Session object:`, {
        sessionId: session.sessionId,
        workingDirectory: session.workingDirectory,
        conversationStarted: session.conversationStarted,
        initialPrompt: `${session.initialPrompt?.substring(0, 50)}...`,
        isActive: session.isActive,
      });

      // Execute AICLI CLI with continuation and print mode
      const response = await this.executeAICLICommand(session, sanitizedPrompt);

      // Emit command sent event
      this.emit('commandSent', {
        sessionId: sanitizedSessionId,
        prompt: sanitizedPrompt.substring(0, 100) + (sanitizedPrompt.length > 100 ? '...' : ''),
        timestamp: new Date().toISOString(),
      });

      return {
        sessionId: sanitizedSessionId,
        success: true,
        message: 'Command executed successfully',
        response,
      };
    } catch (error) {
      console.error('❌ Failed to execute command for session %s:', sanitizedSessionId, error);
      throw new Error(`Failed to execute command: ${error.message}`);
    }
  }

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

  async executeAICLICommand(session, prompt) {
    const { sessionId, workingDirectory, conversationStarted, initialPrompt } = session;

    // Build AICLI CLI arguments - use stream-json to avoid buffer limits
    const args = ['--print', '--output-format', 'stream-json', '--verbose'];

    // Add continue flag if conversation has started
    if (conversationStarted) {
      args.push('--continue');
    }

    // Add skip permissions flag if configured
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

    // Validate arguments
    InputValidator.validateAICLIArgs(args);

    // Determine the prompt to send
    let finalPrompt = prompt;
    if (!conversationStarted && initialPrompt) {
      finalPrompt = `${initialPrompt}\n\n${prompt}`;
      session.conversationStarted = true;
      console.log(`   📝 Combined initial prompt with command prompt`);
    } else if (!conversationStarted) {
      session.conversationStarted = true;
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

    // Calculate dynamic timeout based on command complexity
    const timeoutMs = AICLIConfig.calculateTimeoutForCommand(prompt);

    // Check if this is a long-running operation (> 5 minutes)
    if (timeoutMs > 300000) {
      const estimatedMinutes = Math.round(timeoutMs / 60000);
      console.log(`🕐 Long-running operation detected (${estimatedMinutes} min timeout)`);

      // Send immediate status response
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: [
            {
              type: 'text',
              text: `🔍 **Processing Complex Request**\n\nI'm working on your request: "${prompt.substring(0, 100)}${prompt.length > 100 ? '...' : ''}"\n\n⏱️ **Estimated time:** ${estimatedMinutes} minutes\n📊 **Status:** Starting analysis...\n\nI'll send you the complete results when finished. You can continue using the chat - I'm working in the background!`,
            },
          ],
          timestamp: new Date().toISOString(),
        },
        isComplete: false,
      });

      // Run the process in the background and send results when complete
      this.runLongRunningProcess(args, finalPrompt, workingDirectory, sessionId, timeoutMs, prompt);

      // Return immediate acknowledgment
      return {
        type: 'status',
        subtype: 'long_running_started',
        is_error: false,
        result: `Long-running operation started. Estimated completion: ${estimatedMinutes} minutes.`,
        session_id: sessionId,
        estimated_duration_ms: timeoutMs,
        status: 'processing',
      };
    }

    console.log(`📤 Calling runAICLIProcess with:`);
    console.log(`   Args (${args.length}):`, args);
    console.log(
      `   Prompt: "${finalPrompt?.substring(0, 100)}${finalPrompt?.length > 100 ? '...' : ''}"`
    );
    console.log(`   SessionId: ${sessionId}`);

    return this.runAICLIProcess(args, finalPrompt, workingDirectory, sessionId, timeoutMs);
  }

  async runLongRunningProcess(
    args,
    prompt,
    workingDirectory,
    sessionId,
    timeoutMs,
    originalPrompt
  ) {
    console.log(`🔄 Starting long-running background process for session ${sessionId}`);

    // Send periodic status updates
    const statusUpdateInterval = setInterval(() => {
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: [
            {
              type: 'text',
              text: `⏳ Still working on your request: "${originalPrompt.substring(0, 60)}..."\n\n📊 **Status:** Processing in background...`,
            },
          ],
          timestamp: new Date().toISOString(),
        },
        isComplete: false,
      });
    }, 120000); // Send update every 2 minutes

    try {
      // Run the actual AICLI process
      const result = await this.runAICLIProcess(
        args,
        prompt,
        workingDirectory,
        sessionId,
        timeoutMs
      );

      // Clear the status updates
      clearInterval(statusUpdateInterval);

      // Log the result structure for debugging
      console.log(`📊 Long-running result structure:`, {
        type: result?.type,
        hasResult: !!result?.result,
        resultLength: result?.result?.length,
        isError: result?.is_error,
      });

      // For long-running processes, just send the actual results directly
      if (result && result.type === 'result' && result.result) {
        // Create a fresh buffer for the long-running completion
        if (!this.sessionMessageBuffers.has(sessionId)) {
          this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());
        }

        // Create an assistant message with the actual result content (removed unused variable)

        // Process and send the assistant message immediately
        this.emit('assistantMessage', {
          sessionId,
          data: {
            type: 'assistant_response',
            content: [
              {
                type: 'text',
                text: result.result,
              },
            ],
            timestamp: new Date().toISOString(),
          },
          isComplete: true,
        });
      } else {
        console.error(`❌ Unexpected result type from long-running process:`, result?.type);
      }

      console.log(`✅ Long-running process completed for session ${sessionId}`);
    } catch (error) {
      // Clear the status updates
      clearInterval(statusUpdateInterval);

      console.error(`❌ Long-running process failed for session ${sessionId}:`, error);

      // Send error notification
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: [
            {
              type: 'text',
              text: `❌ **Complex Request Failed**\n\nYour request: "${originalPrompt.substring(0, 80)}${originalPrompt.length > 80 ? '...' : ''}"\n\n🔍 **Error:** ${error.message}\n\n💡 **Suggestion:** Try breaking this into smaller, more specific requests.`,
            },
          ],
          timestamp: new Date().toISOString(),
        },
        isComplete: true,
      });

      // Also emit error through normal channels
      this.emit('streamError', {
        sessionId,
        error: error.message,
      });
    }
  }

  async runAICLIProcess(args, prompt, workingDirectory, sessionId, timeoutMs) {
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
    console.log(`   Timeout: ${timeoutMs}ms`);

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

        aicliProcess = spawn(this.aicliCommand, fullArgs, {
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

      // Start monitoring this process
      if (aicliProcess.pid) {
        processMonitor
          .monitorProcess(aicliProcess.pid)
          .then((info) => {
            if (info) {
              console.log(
                `📊 Initial process metrics: Memory: ${(info.rss / 1024 / 1024).toFixed(2)}MB, CPU: ${info.cpu}%`
              );
            }
          })
          .catch((err) => {
            console.warn(`⚠️  Failed to get initial process metrics: ${err.message}`);
          });
      }

      // Emit process start event
      this.emit('processStart', {
        sessionId,
        pid: aicliProcess.pid,
        command: this.aicliCommand,
        args,
        workingDirectory,
        type: 'command',
      });

      let stdout = '';
      let stderr = '';
      let lastActivityTime = Date.now();
      let hasReceivedOutput = false;
      const stdoutBuffers = []; // Store raw buffers to prevent encoding issues
      const stderrBuffers = [];

      // Function to reset activity timer on any output (will be updated below)
      // eslint-disable-next-line prefer-const
      let resetActivityTimer;

      aicliProcess.stdout.on('data', (data) => {
        // Store raw buffer to prevent encoding truncation
        stdoutBuffers.push(data);

        const chunk = data.toString();
        stdout += chunk;
        console.log(
          `📊 AICLI CLI STDOUT (${chunk.length} chars, total: ${stdout.length}):`,
          JSON.stringify(chunk.substring(0, 200))
        );

        resetActivityTimer();

        // Emit partial data for progress tracking
        this.emit('commandProgress', {
          sessionId,
          pid: aicliProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
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

        resetActivityTimer();

        // Emit stderr for logging
        this.emit('processStderr', {
          sessionId,
          pid: aicliProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      aicliProcess.on('close', (code) => {
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

          // Ensure message buffer exists for this session
          if (!this.sessionMessageBuffers.has(sessionId)) {
            this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());
            console.log(`🔧 Created missing message buffer for session ${sessionId}`);
          }

          // Emit all responses for detailed tracking
          responses.forEach((response, index) => {
            console.log(
              `   Response ${index + 1}: type=${response.type}, subtype=${response.subtype || 'none'}`
            );
            this.emitAICLIResponse(sessionId, response, index === responses.length - 1);
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
      });

      aicliProcess.on('error', (error) => {
        console.error(`❌ AICLI CLI process error:`, error);
        reject(new Error(`AICLI CLI process error: ${error.message}`));
      });

      // Implement intelligent timeout with heartbeat detection
      let timeoutHandle;
      const startTime = Date.now();
      const maxSilentTime = Math.min(timeoutMs / 3, 180000); // Max 3 minutes of silence, or 1/3 the total timeout

      const updateTimeout = () => {
        if (timeoutHandle) {
          clearTimeout(timeoutHandle);
        }

        const timeoutToUse = hasReceivedOutput ? maxSilentTime : timeoutMs;

        console.log(
          `🕐 Setting timeout: ${Math.round(timeoutToUse / 1000)}s (${hasReceivedOutput ? 'heartbeat mode' : 'initial mode'})`
        );

        timeoutHandle = setTimeout(() => {
          const timeSinceActivity = Date.now() - lastActivityTime;
          const totalRuntime = Date.now() - startTime;

          if (hasReceivedOutput) {
            console.log(
              `⏰ AICLI CLI process silent timeout (${Math.round(timeSinceActivity / 1000)}s since last activity), killing PID ${aicliProcess.pid}...`
            );
            reject(
              new Error(
                `AICLI CLI process timed out after ${Math.round(timeSinceActivity / 1000)}s of silence`
              )
            );
          } else {
            console.log(
              `⏰ AICLI CLI process initial timeout (${Math.round(totalRuntime / 1000)}s total), killing PID ${aicliProcess.pid}...`
            );
            reject(new Error('AICLI CLI process timed out'));
          }
          aicliProcess.kill('SIGTERM');
        }, timeoutToUse);
      };

      // Define the reset function now that updateTimeout exists
      resetActivityTimer = () => {
        lastActivityTime = Date.now();
        const wasFirstOutput = !hasReceivedOutput;
        hasReceivedOutput = true;
        console.log(
          `💓 AICLI CLI activity detected${wasFirstOutput ? ' (first output)' : ''}, resetting timeout timer`
        );
        updateTimeout();
      };

      // Initial timeout
      updateTimeout();

      // Add periodic status logging
      const statusInterval = setInterval(
        () => {
          if (aicliProcess && aicliProcess.pid) {
            console.log(
              `📊 AICLI CLI PID ${aicliProcess.pid} still running... (stdout: ${stdout.length} chars, stderr: ${stderr.length} chars)`
            );
          }
        },
        Math.min(timeoutMs / 4, 10000)
      ); // Status every 1/4 of timeout or 10s max

      aicliProcess.on('close', () => {
        if (timeoutHandle) {
          clearTimeout(timeoutHandle);
        }
        clearInterval(statusInterval);
      });
    });
  }

  // Validate that JSON is complete and not truncated
  isValidCompleteJSON(jsonString) {
    if (!jsonString || jsonString.length === 0) {
      console.log(`JSON validation: Empty or null input`);
      return false;
    }

    try {
      // First, try basic JSON parsing
      const parsed = JSON.parse(jsonString);

      // Additional checks for completeness
      const trimmed = jsonString.trim();

      // Check that it starts and ends properly
      if (trimmed.startsWith('[')) {
        if (!trimmed.endsWith(']')) {
          console.log(`JSON validation: Array doesn't end with ]`);
          return false;
        }
      } else if (trimmed.startsWith('{')) {
        if (!trimmed.endsWith('}')) {
          console.log(`JSON validation: Object doesn't end with }`);
          return false;
        }
      } else {
        console.log(`JSON validation: Doesn't start with [ or {`);
        return false;
      }

      // Check for common truncation indicators
      // Only check if the JSON doesn't end properly
      if (!trimmed.endsWith('}') && !trimmed.endsWith(']')) {
        console.log(`JSON validation: Doesn't end with } or ]`);
        return false;
      }

      // Simplified truncation detection - primarily rely on JSON.parse
      // Only check for obvious incomplete endings
      if (
        trimmed.endsWith(',') ||
        trimmed.endsWith(':') ||
        (trimmed.endsWith('"') && !trimmed.endsWith('"}') && !trimmed.endsWith('"]'))
      ) {
        console.log(`JSON validation: Ends with incomplete syntax`);
        return false;
      }

      // For arrays, check if the parsed result looks complete
      if (Array.isArray(parsed)) {
        // Check if each object in the array has expected structure
        for (const item of parsed) {
          if (typeof item === 'object' && item !== null) {
            // Check for objects that seem incomplete (very basic check)
            if (item.type && Object.keys(item).length === 1) {
              console.log(
                `JSON validation: Object with only 'type' field detected:`,
                JSON.stringify(item)
              );
              return false;
            }
          }
        }
      }

      console.log(`✅ JSON validation passed for ${trimmed.length} character response`);
      return true;
    } catch (parseError) {
      console.log(`JSON validation failed:`, parseError.message);
      console.log(`   Error type: ${parseError.name}`);

      // Provide more specific error information for debugging
      if (parseError.message.includes('Unterminated string')) {
        console.log(`   Detected unterminated string - likely truncation`);
      } else if (parseError.message.includes('Unexpected end')) {
        console.log(`   Detected unexpected end - likely truncation`);
      } else if (parseError.message.includes('Unexpected token')) {
        console.log(`   Detected unexpected token - possible corruption`);
      }

      return false;
    }
  }

  // Parse stream-json output format (newline-delimited JSON)
  parseStreamJsonOutput(output) {
    const responses = [];
    const lines = output.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) continue;

      try {
        const parsed = JSON.parse(line);
        responses.push(parsed);
        console.log(`📦 Parsed stream-json line ${i + 1}: type=${parsed.type}`);
      } catch (error) {
        console.log(`⚠️  Failed to parse line ${i + 1} as JSON:`, line.substring(0, 100));
        // Try to extract any complete JSON objects from this line
        const extracted = MessageProcessor.extractCompleteObjectsFromLine(line);
        responses.push(...extracted);
      }
    }

    return responses;
  }

  // Extract complete JSON objects from a potentially malformed line
  extractCompleteObjectsFromLine(line) {
    const objects = [];
    let depth = 0;
    let currentObject = '';
    let inString = false;
    let escaped = false;
    let objectStart = -1;

    for (let i = 0; i < line.length; i++) {
      const char = line[i];

      if (escaped) {
        escaped = false;
        if (depth > 0) currentObject += char;
        continue;
      }

      if (char === '\\' && inString) {
        escaped = true;
        if (depth > 0) currentObject += char;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        if (depth > 0) currentObject += char;
        continue;
      }

      if (inString) {
        if (depth > 0) currentObject += char;
        continue;
      }

      if (char === '{') {
        if (depth === 0) {
          objectStart = i;
          currentObject = '';
        }
        depth++;
        currentObject += char;
      } else if (char === '}') {
        depth--;
        currentObject += char;

        if (depth === 0 && objectStart >= 0) {
          try {
            const parsed = JSON.parse(currentObject);
            objects.push(parsed);
            console.log(`🔧 Extracted object from line: type=${parsed.type}`);
            currentObject = '';
            objectStart = -1;
          } catch (error) {
            // Object is malformed, continue
          }
        }
      } else if (depth > 0) {
        currentObject += char;
      }
    }

    return objects;
  }

  // Try to extract the last complete JSON object from a truncated response
  extractLastCompleteJSON(truncatedJSON) {
    try {
      // Look for complete JSON objects/arrays by finding balanced braces/brackets
      const lastCompleteStart = this.findLastCompleteJSONStart(truncatedJSON);
      if (lastCompleteStart >= 0) {
        const candidate = truncatedJSON.substring(lastCompleteStart);
        const parsed = JSON.parse(candidate);
        console.log(`Found complete JSON from position ${lastCompleteStart}:`, typeof parsed);
        return parsed;
      }
    } catch (error) {
      // Try different approaches
    }

    // If it's an array, try to extract the last complete object
    if (truncatedJSON.startsWith('[')) {
      try {
        const objects = this.extractCompleteObjectsFromArray(truncatedJSON);
        if (objects.length > 0) {
          return objects[objects.length - 1];
        }
      } catch (error) {
        // Continue to next approach
      }
    }

    return null;
  }

  findLastCompleteJSONStart(text) {
    let braceCount = 0;
    let bracketCount = 0;
    let inString = false;
    let escaped = false;

    for (let i = text.length - 1; i >= 0; i--) {
      const char = text[i];

      if (escaped) {
        escaped = false;
        continue;
      }

      if (char === '\\' && inString) {
        escaped = true;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        continue;
      }

      if (inString) continue;

      if (char === '}') braceCount++;
      else if (char === '{') braceCount--;
      else if (char === ']') bracketCount++;
      else if (char === '[') bracketCount--;

      // Found a complete structure
      if ((braceCount === 0 && char === '{') || (bracketCount === 0 && char === '[')) {
        return i;
      }
    }

    return -1;
  }

  extractCompleteObjectsFromArray(arrayText) {
    const objects = [];
    let depth = 0;
    let currentObject = '';
    let inString = false;
    let escaped = false;
    let objectStart = -1;

    for (let i = 0; i < arrayText.length; i++) {
      const char = arrayText[i];

      if (escaped) {
        escaped = false;
        currentObject += char;
        continue;
      }

      if (char === '\\' && inString) {
        escaped = true;
        currentObject += char;
        continue;
      }

      if (char === '"') {
        inString = !inString;
        currentObject += char;
        continue;
      }

      if (inString) {
        currentObject += char;
        continue;
      }

      if (char === '{') {
        if (depth === 0) {
          objectStart = i;
          currentObject = '';
        }
        depth++;
        currentObject += char;
      } else if (char === '}') {
        depth--;
        currentObject += char;

        if (depth === 0 && objectStart >= 0) {
          try {
            const parsed = JSON.parse(currentObject);
            objects.push(parsed);
            currentObject = '';
            objectStart = -1;
          } catch (error) {
            // Object is malformed, continue
          }
        }
      } else if (depth > 0) {
        currentObject += char;
      }
    }

    return objects;
  }

  emitAICLIResponse(sessionId, response, _isComplete = false, options = {}) {
    const buffer = this.sessionMessageBuffers.get(sessionId);
    if (!buffer) {
      console.warn(`No message buffer found for session ${sessionId}`);
      return;
    }

    // Use extracted message handler for pure business logic
    const result = AICLIMessageHandler.processResponse(response, buffer, options);

    // Handle the processing result and emit appropriate events
    switch (result.action) {
      case 'permission_request':
        console.log(`🔐 Sending permission request immediately for session ${sessionId}`);
        this.emit('permissionRequired', {
          sessionId,
          prompt: result.data.prompt,
          options: result.data.options,
          default: result.data.default,
        });
        this.emit('assistantMessage', {
          sessionId,
          data: {
            type: 'permission_request',
            messageId: result.data.messageId,
            content: result.data.content,
            model: result.data.model,
            usage: result.data.usage,
            timestamp: new Date().toISOString(),
          },
        });
        break;

      case 'tool_use':
        console.log(`🔧 Tool use in progress for session ${sessionId}`);
        this.emit('assistantMessage', {
          sessionId,
          data: {
            type: 'tool_use',
            messageId: result.data.messageId,
            content: result.data.content,
            model: result.data.model,
            usage: result.data.usage,
            timestamp: new Date().toISOString(),
          },
        });
        break;

      case 'final_result':
        this.handleFinalResultEmission(sessionId, result.data, options);
        break;

      case 'buffer':
        console.log(`📝 ${result.reason} for session ${sessionId}`);
        break;

      case 'skip':
        console.log(`🤷 ${result.reason}, skipping`);
        break;

      case 'error':
        console.error(`❌ Error processing response for session ${sessionId}: ${result.reason}`);
        break;

      default:
        console.log(`🤷 Unknown processing result: ${result.action}, skipping`);
        break;
    }
  }

  handleFinalResultEmission(sessionId, resultData, _options = {}) {
    const { response, buffer, aggregatedContent, sendAggregated, embeddedPermission } = resultData;

    if (sendAggregated && aggregatedContent) {
      // Send aggregated response
      console.log(`📱 Sending aggregated response to iOS for session ${sessionId}`);
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: aggregatedContent,
          deliverables: buffer.deliverables || [],
          aggregated: true,
          messageCount: buffer.assistantMessages.length,
          timestamp: new Date().toISOString(),
        },
        isComplete: true,
      });
    }

    if (embeddedPermission) {
      // Handle embedded permission in result
      console.log(`🔐 Found embedded permission in result for session ${sessionId}`);
      this.emit('permissionRequired', {
        sessionId,
        prompt: embeddedPermission.prompt,
        options: embeddedPermission.options,
        default: embeddedPermission.default,
      });
    } else {
      // Send regular conversation result
      this.emit('conversationResult', {
        sessionId,
        data: {
          type: 'final_result',
          success: !response.is_error,
          sessionId: response.session_id,
          duration: response.duration_ms,
          cost: response.total_cost_usd,
          usage: response.usage,
          timestamp: new Date().toISOString(),
        },
      });
    }

    // Clear the buffer for next command
    AICLIMessageHandler.clearSessionBuffer(buffer);
  }

  // Old handler methods removed - message processing now handled by AICLIMessageHandler via emitAICLIResponse

  // Message handling methods moved to AICLIMessageHandler - using proxy methods below for backward compatibility

  clearSessionBuffer(sessionId) {
    const buffer = this.sessionMessageBuffers.get(sessionId);
    if (buffer) {
      AICLIMessageHandler.clearSessionBuffer(buffer);
      console.log(`🧹 Cleared message buffer for session ${sessionId}`);
    }
  }

  // Proxy methods for message handler functionality (for backward compatibility and testing)
  containsPermissionRequest(content) {
    return AICLIMessageHandler.containsPermissionRequest(content);
  }

  containsToolUse(content) {
    return AICLIMessageHandler.containsToolUse(content);
  }

  containsApprovalResponse(text) {
    return AICLIMessageHandler.containsApprovalResponse(text);
  }

  extractCodeBlocks(content) {
    return AICLIMessageHandler.extractCodeBlocks(content);
  }

  aggregateBufferedContent(buffer) {
    return AICLIMessageHandler.aggregateBufferedContent(buffer);
  }

  extractPermissionPrompt(text) {
    return AICLIMessageHandler.extractPermissionPrompt(text);
  }

  extractPermissionPromptFromMessage(message) {
    const text = this.extractTextFromMessage(message);
    if (!text) return 'Permission required';

    // Clean up the prompt text
    return text.replace(/\s*\([yn]\/[yn]\)\s*$/i, '').trim();
  }

  extractTextFromMessage(message) {
    if (typeof message === 'string') return message;

    if (message.result) return message.result;
    if (message.text) return message.text;
    if (message.message && message.message.content) {
      const content = message.message.content;
      if (typeof content === 'string') return content;
      if (Array.isArray(content)) {
        for (const block of content) {
          if (block.type === 'text' && block.text) {
            return block.text;
          }
        }
      }
    }

    return null;
  }

  async closeSession(sessionId) {
    const session = this.activeSessions.get(sessionId);

    if (!session) {
      console.log(`⚠️  Attempted to close non-existent session: ${sessionId}`);
      return { success: false, message: 'Session not found' };
    }

    console.log(`🔚 Closing AICLI CLI session: ${sessionId}`);
    console.log(`   Session type: metadata-only (no long-running process)`);

    try {
      // Mark session as inactive
      session.isActive = false;

      // Remove from active sessions and clean up message buffer
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);

      console.log(`✅ Session ${sessionId} closed successfully`);
      console.log(`   Remaining active sessions: ${this.activeSessions.size}`);

      return { success: true, message: 'Session closed' };
    } catch (error) {
      console.error('Error closing session:', error);
      return { success: false, message: error.message };
    }
  }

  hasSession(sessionId) {
    return this.activeSessions.has(sessionId);
  }

  getActiveSessions() {
    const sessions = Array.from(this.activeSessions.keys());
    console.log(`📊 Active AICLI CLI sessions: ${sessions.length}`);
    sessions.forEach((sessionId, index) => {
      const session = this.activeSessions.get(sessionId);
      const age = Math.round((Date.now() - session.createdAt) / 1000);
      console.log(
        `   ${index + 1}. ${sessionId} (age: ${age}s, conversation: ${session.conversationStarted ? 'started' : 'pending'})`
      );
    });
    return sessions;
  }

  // Cleanup method for graceful shutdown
  shutdown() {
    console.log('🔄 Shutting down AICLI Code Service...');

    // Stop health monitoring
    this.stopProcessHealthMonitoring();

    // Close all active sessions
    for (const [sessionId, _] of this.activeSessions) {
      try {
        this.closeSession(sessionId);
      } catch (error) {
        console.warn(`Failed to close session ${sessionId}:`, error.message);
      }
    }

    // Clear all buffers
    this.sessionMessageBuffers.clear();

    // Clear all data structures
    this.activeSessions.clear();

    console.log('✅ AICLI Code Service shut down complete');
  }

  async healthCheck() {
    try {
      const isAvailable = await this.checkAvailability();

      // Get system resources
      const systemResources = await processMonitor.getSystemResources();

      // Get process metrics for active sessions
      const sessionMetrics = [];
      for (const [sessionId, session] of this.activeSessions) {
        if (session.process && session.process.pid) {
          const metrics = processMonitor.getMetricsSummary(session.process.pid);
          if (metrics) {
            sessionMetrics.push({
              sessionId,
              ...metrics,
            });
          }
        }
      }

      return {
        status: isAvailable ? 'healthy' : 'degraded',
        aicliCodeAvailable: isAvailable,
        activeSessions: this.activeSessions.size,
        resources: {
          system: systemResources,
          sessions: sessionMetrics,
        },
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      return {
        status: 'unhealthy',
        error: error.message,
        timestamp: new Date().toISOString(),
      };
    }
  }

  // Handle permission prompts
  async handlePermissionPrompt(sessionId, response) {
    const session = this.activeSessions.get(sessionId);

    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    try {
      // In non-interactive mode, we need to send the permission response as a new command
      console.log(`📝 Handling permission response for session ${sessionId}: "${response}"`);

      // Check if the session has a pending permission request
      const buffer = this.sessionMessageBuffers.get(sessionId);
      if (buffer && buffer.pendingFinalResponse) {
        console.log(`✅ Found pending response, processing permission approval`);

        // If user approved, send the pending final response
        if (this.containsApprovalResponse(response)) {
          console.log(`✅ User approved, sending pending final response`);

          // Send the aggregated response
          this.emit('assistantMessage', {
            sessionId,
            data: {
              type: 'assistant_response',
              content: buffer.pendingFinalResponse.aggregatedContent,
              timestamp: new Date().toISOString(),
            },
            isComplete: false,
          });

          // Send the final result
          this.emit('conversationResult', {
            sessionId,
            data: buffer.pendingFinalResponse.conversationResult,
          });

          // Clear the pending response
          buffer.pendingFinalResponse = null;
        } else {
          console.log(`❌ User denied permission, clearing pending response`);

          // Send denial message
          this.emit('assistantMessage', {
            sessionId,
            data: {
              type: 'assistant_response',
              content: [
                {
                  type: 'text',
                  text: 'Permission denied. The requested action was not performed.',
                },
              ],
              timestamp: new Date().toISOString(),
            },
            isComplete: true,
          });

          // Clear the pending response
          buffer.pendingFinalResponse = null;
        }

        return { success: true, handled: true };
      }

      // For active conversations, send the response as a new message
      return this.sendToExistingSession(sessionId, response);
    } catch (error) {
      throw new Error(`Failed to respond to permission prompt: ${error.message}`);
    }
  }

  // Calculate timeout based on command complexity

  // Classify different types of AICLI Code messages
  classifyAICLIMessage(message) {
    if (!message || typeof message !== 'object') {
      return { eventType: 'streamData', data: message };
    }

    switch (message.type) {
      case 'system':
        return this.handleSystemMessage(message);

      case 'assistant':
        return this.handleAssistantMessage(message);

      case 'result':
        return this.handleResultMessage(message);

      case 'tool_use':
        return this.handleToolUseMessage(message);

      case 'tool_result':
        return this.handleToolResultMessage(message);

      default:
        return {
          eventType: 'streamData',
          data: {
            type: 'unknown',
            content: message,
            timestamp: new Date().toISOString(),
          },
        };
    }
  }

  handleSystemMessage(message) {
    // System initialization messages
    if (message.subtype === 'init') {
      return {
        eventType: 'systemInit',
        data: {
          type: 'system_init',
          sessionId: message.session_id,
          workingDirectory: message.cwd,
          availableTools: message.tools || [],
          mcpServers: message.mcp_servers || [],
          model: message.model,
          timestamp: new Date().toISOString(),
        },
      };
    }

    return {
      eventType: 'streamData',
      data: {
        type: 'system',
        content: message,
        timestamp: new Date().toISOString(),
      },
    };
  }

  handleAssistantMessage(message) {
    // AICLI's response messages
    const content = message.message?.content;

    if (Array.isArray(content)) {
      // Handle multi-part content (text + tool usage)
      return {
        eventType: 'assistantMessage',
        data: {
          type: 'assistant_response',
          messageId: message.message?.id,
          content,
          model: message.message?.model,
          usage: message.message?.usage,
          timestamp: new Date().toISOString(),
        },
      };
    }

    return {
      eventType: 'streamData',
      data: {
        type: 'assistant',
        content: message,
        timestamp: new Date().toISOString(),
      },
    };
  }

  handleResultMessage(message) {
    // Final result of the conversation
    return {
      eventType: 'conversationResult',
      data: {
        type: 'final_result',
        success: !message.is_error,
        result: message.result,
        sessionId: message.session_id,
        duration: message.duration_ms,
        cost: message.total_cost_usd,
        usage: message.usage,
        timestamp: new Date().toISOString(),
      },
    };
  }

  handleToolUseMessage(message) {
    // Tool usage notifications
    return {
      eventType: 'toolUse',
      data: {
        type: 'tool_use',
        toolName: message.tool_name,
        toolInput: message.tool_input,
        toolId: message.tool_id,
        timestamp: new Date().toISOString(),
      },
    };
  }

  handleToolResultMessage(message) {
    // Tool execution results
    return {
      eventType: 'toolResult',
      data: {
        type: 'tool_result',
        toolName: message.tool_name,
        toolId: message.tool_id,
        result: message.result,
        success: !message.is_error,
        error: message.error,
        timestamp: new Date().toISOString(),
      },
    };
  }

  // Duplicate methods removed - using the proxy methods above for backward compatibility

  // Proxy methods for backward compatibility with tests
  findAICLICommand() {
    return AICLIConfig.findAICLICommand();
  }

  calculateTimeoutForCommand(command) {
    return AICLIConfig.calculateTimeoutForCommand(command);
  }

  isPermissionPrompt(message) {
    return MessageProcessor.isPermissionPrompt(message);
  }
}
