import { spawn, exec, execSync } from 'child_process';
import { promisify } from 'util';
import { EventEmitter } from 'events';
import { resolve } from 'path';
import { access, constants } from 'fs/promises';
import { existsSync } from 'fs';
import { processMonitor } from '../utils/process-monitor.js';

const execAsync = promisify(exec);

// Input validation and sanitization utilities
class InputValidator {
  static sanitizePrompt(prompt) {
    if (typeof prompt !== 'string') {
      throw new Error('Prompt must be a string');
    }

    // Remove null bytes and limit length
    const sanitized = prompt.replace(/\0/g, '').substring(0, 50000);

    if (sanitized.length === 0) {
      throw new Error('Prompt cannot be empty');
    }

    return sanitized;
  }

  static validateFormat(format) {
    const allowedFormats = ['json', 'text', 'markdown'];

    if (!format || typeof format !== 'string') {
      return 'json'; // default
    }

    const cleanFormat = format.toLowerCase().trim();

    if (!allowedFormats.includes(cleanFormat)) {
      throw new Error(`Invalid format. Must be one of: ${allowedFormats.join(', ')}`);
    }

    return cleanFormat;
  }

  static async validateWorkingDirectory(workingDir, safeRoot = null) {
    if (!workingDir || typeof workingDir !== 'string') {
      // If no working directory provided, use safe root or current directory
      return safeRoot || process.cwd();
    }

    // Resolve to absolute path
    const resolvedPath = resolve(workingDir);

    // If a safe root is provided, ensure the resolved path is within it
    if (safeRoot) {
      const resolvedSafeRoot = resolve(safeRoot);
      if (!resolvedPath.startsWith(resolvedSafeRoot)) {
        throw new Error(`Working directory must be within the configured project directory`);
      }
    }

    try {
      // Check if directory exists and is accessible
      await access(resolvedPath, constants.F_OK | constants.R_OK);
      return resolvedPath;
    } catch (error) {
      throw new Error(`Working directory is not accessible: ${resolvedPath}`);
    }
  }

  static sanitizeSessionId(sessionId) {
    if (!sessionId || typeof sessionId !== 'string') {
      return null;
    }

    // Only allow alphanumeric characters, hyphens, and underscores
    const sanitized = sessionId.replace(/[^a-zA-Z0-9_-]/g, '').substring(0, 64);

    if (sanitized.length === 0) {
      return null;
    }

    return sanitized;
  }

  static validateClaudeArgs(args) {
    if (!Array.isArray(args)) {
      throw new Error('Arguments must be an array');
    }

    const allowedArgs = [
      '--print',
      '--output-format',
      '--verbose',
      '--help',
      '--version',
      '--continue',
      '--dangerously-skip-permissions',
      '--permission-mode',
      '--allowedTools',
      '--disallowedTools',
    ];

    const allowedFormats = ['json', 'text', 'markdown', 'stream-json'];
    const allowedPermissionModes = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];

    for (let i = 0; i < args.length; i++) {
      const arg = args[i];

      if (typeof arg !== 'string') {
        throw new Error('All arguments must be strings');
      }

      // Check for suspicious characters
      if (/[;&|`$(){}[\]<>]/.test(arg)) {
        throw new Error(`Argument contains suspicious characters: ${arg}`);
      }

      // Validate known flags
      if (arg.startsWith('--')) {
        if (!allowedArgs.includes(arg)) {
          throw new Error(`Disallowed argument: ${arg}`);
        }

        // Validate format values
        if (arg === '--output-format' && i + 1 < args.length) {
          const format = args[i + 1];
          if (!allowedFormats.includes(format)) {
            throw new Error(`Invalid format: ${format}`);
          }
        }

        // Validate permission mode values
        if (arg === '--permission-mode' && i + 1 < args.length) {
          const mode = args[i + 1];
          if (!allowedPermissionModes.includes(mode)) {
            throw new Error(`Invalid permission mode: ${mode}`);
          }
        }
      }
    }

    return args;
  }
}

export class ClaudeCodeService extends EventEmitter {
  constructor() {
    super();
    this.activeSessions = new Map();
    this.sessionMessageBuffers = new Map(); // Buffer messages per session for intelligent filtering
    // Try to find claude in common locations
    this.claudeCommand = this.findClaudeCommand();
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

  // Check health of all active Claude processes
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

  findClaudeCommand() {
    // First check if CLAUDE_CLI_PATH env variable is set
    if (process.env.CLAUDE_CLI_PATH) {
      console.log(`Using Claude CLI path from CLAUDE_CLI_PATH: ${process.env.CLAUDE_CLI_PATH}`);
      return process.env.CLAUDE_CLI_PATH;
    }

    // Try to use 'which' command to find claude
    try {
      const path = execSync('which claude', { encoding: 'utf8' }).trim();
      if (path) {
        console.log(`Found Claude CLI at: ${path}`);
        return path;
      }
    } catch (error) {
      // 'which' failed, try common locations
    }

    // Common installation paths to check
    const commonPaths = [
      '/Users/michaelfuscoletti/.nvm/versions/node/v20.19.1/bin/claude',
      '/usr/local/bin/claude',
      '/opt/homebrew/bin/claude',
      `${process.env.HOME}/.local/bin/claude`,
      `${process.env.HOME}/.npm/bin/claude`,
      `${process.env.HOME}/.yarn/bin/claude`,
    ];

    // Also check NVM paths dynamically
    if (process.env.NVM_BIN) {
      commonPaths.unshift(`${process.env.NVM_BIN}/claude`);
    }

    for (const path of commonPaths) {
      try {
        if (existsSync(path)) {
          console.log(`Found Claude CLI at: ${path}`);
          return path;
        }
      } catch (error) {
        // Path doesn't exist, continue
      }
    }

    // If not found, fall back to 'claude' and hope it's in PATH
    console.warn('Claude CLI not found in common locations, falling back to PATH lookup');
    return 'claude';
  }

  async checkAvailability() {
    try {
      console.log(`Checking Claude CLI availability at: ${this.claudeCommand}`);
      const { stdout, _stderr } = await execAsync(`${this.claudeCommand} --version`);
      const version = stdout.trim();
      console.log(`Claude Code version: ${version}`);
      return true;
    } catch (error) {
      console.error('Claude Code not available:', error.message);
      console.error(`Tried to execute: ${this.claudeCommand} --version`);
      console.error('To fix this issue:');
      console.error('1. Make sure Claude CLI is installed: npm install -g @anthropic-ai/claude');
      console.error('2. Set CLAUDE_CLI_PATH environment variable to the full path');
      console.error('3. Or ensure claude is in your PATH');
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
      console.error('Error sending prompt to Claude Code:', error);
      throw new Error(`Claude Code execution failed: ${error.message}`);
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
    InputValidator.validateClaudeArgs(args);

    console.log(`🚀 Starting Claude CLI with validated args:`, args.slice(0, -1)); // Log all args except prompt
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
      let claudeProcess;
      try {
        claudeProcess = spawn(this.claudeCommand, args, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (spawnError) {
        console.error(`❌ Failed to spawn Claude CLI:`, spawnError);
        const errorMsg =
          spawnError.code === 'ENOENT'
            ? 'Claude CLI not found. Please ensure Claude CLI is installed and in your PATH.'
            : `Failed to start Claude CLI: ${spawnError.message}`;

        // Emit error event
        this.emit('processError', {
          error: errorMsg,
          timestamp: new Date().toISOString(),
        });

        reject(new Error(errorMsg));
        return;
      }

      // Close stdin immediately since we're not sending any input
      claudeProcess.stdin.end();

      let stdout = '';
      let stderr = '';

      console.log(`   Process started with PID: ${claudeProcess.pid}`);

      // Check if process actually started
      if (!claudeProcess.pid) {
        const errorMsg = 'Claude CLI process failed to start (no PID)';
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
        pid: claudeProcess.pid,
        command: this.claudeCommand,
        args: args.slice(0, 3), // Don't include full prompt
        workingDirectory,
        type: 'one-time',
      });

      claudeProcess.stdout.on('data', (data) => {
        const chunk = data.toString();
        console.log(`   STDOUT chunk: ${chunk.length} chars`);
        stdout += chunk;

        // Emit stdout data for logging
        this.emit('processStdout', {
          pid: claudeProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      claudeProcess.stderr.on('data', (data) => {
        const chunk = data.toString();
        console.log(`   STDERR chunk: ${chunk}`);
        stderr += chunk;

        // Emit stderr data for logging
        this.emit('processStderr', {
          pid: claudeProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      claudeProcess.on('close', (code) => {
        console.log(`   Process closed with code: ${code}`);
        console.log(`   STDOUT length: ${stdout.length}`);
        console.log(`   STDERR length: ${stderr.length}`);

        // Emit process exit event
        this.emit('processExit', {
          pid: claudeProcess.pid,
          code,
          stdout: stdout.substring(0, 1000), // First 1000 chars for debugging
          stderr,
          timestamp: new Date().toISOString(),
        });

        if (code !== 0) {
          reject(new Error(`Claude Code exited with code ${code}: ${stderr}`));
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
          reject(new Error(`Failed to parse Claude Code response: ${error.message}`));
        }
      });

      claudeProcess.on('error', (error) => {
        console.log(`   ❌ Process error: ${error.message}`);
        reject(new Error(`Failed to start Claude Code: ${error.message}`));
      });

      // Add timeout protection
      const timeout = setTimeout(() => {
        console.log(`   ⏰ Process timeout, killing...`);
        claudeProcess.kill('SIGTERM');
        reject(new Error('Claude Code process timed out'));
      }, 30000);

      claudeProcess.on('close', () => {
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

    console.log(`🚀 Creating Claude CLI session (metadata-only)`);
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
    this.sessionMessageBuffers.set(sanitizedSessionId, {
      assistantMessages: [],
      systemInit: null,
      toolUseInProgress: false,
      permissionRequests: [],
      deliverables: [],
      pendingFinalResponse: null,
      permissionRequestSent: false,
    });

    // Set up session timeout
    setTimeout(() => {
      if (this.activeSessions.has(sanitizedSessionId)) {
        console.log(`Session ${sanitizedSessionId} timed out, cleaning up`);
        this.closeSession(sanitizedSessionId);
      }
    }, this.sessionTimeout);

    console.log(`✅ Claude CLI session metadata created successfully`);

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
        `📝 Executing Claude CLI command for session ${sanitizedSessionId}: "${sanitizedPrompt}"`
      );
      console.log(`   Session object:`, {
        sessionId: session.sessionId,
        workingDirectory: session.workingDirectory,
        conversationStarted: session.conversationStarted,
        initialPrompt: `${session.initialPrompt?.substring(0, 50)}...`,
        isActive: session.isActive,
      });

      // Execute Claude CLI with continuation and print mode
      const response = await this.executeClaudeCommand(session, sanitizedPrompt);

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

  async testClaudeCommand(testType = 'version') {
    console.log(`🧪 Testing Claude CLI command: ${testType}`);

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

    return this.runClaudeProcess(args, prompt, process.cwd(), 'test-session', 30000);
  }

  async executeClaudeCommand(session, prompt) {
    const { sessionId, workingDirectory, conversationStarted, initialPrompt } = session;

    // Build Claude CLI arguments - use stream-json to avoid buffer limits
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
    InputValidator.validateClaudeArgs(args);

    // Determine the prompt to send
    let finalPrompt = prompt;
    if (!conversationStarted && initialPrompt) {
      finalPrompt = `${initialPrompt}\n\n${prompt}`;
      session.conversationStarted = true;
      console.log(`   📝 Combined initial prompt with command prompt`);
    } else if (!conversationStarted) {
      session.conversationStarted = true;
    }

    console.log(`🚀 Executing Claude CLI with args:`, args);
    console.log(`   Working directory: ${workingDirectory}`);
    console.log(`   Original prompt: "${prompt?.substring(0, 50)}..."`);
    console.log(`   Initial prompt: "${initialPrompt?.substring(0, 50)}..."`);
    console.log(`   Final prompt length: ${finalPrompt?.length} chars`);
    console.log(
      `   Final prompt preview: "${finalPrompt?.substring(0, 100).replace(/\n/g, '\\n')}..."`
    );
    console.log(`   Conversation started: ${conversationStarted}`);

    // Calculate dynamic timeout based on command complexity
    const timeoutMs = this.calculateTimeoutForCommand(prompt);

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

    console.log(`📤 Calling runClaudeProcess with:`);
    console.log(`   Args (${args.length}):`, args);
    console.log(
      `   Prompt: "${finalPrompt?.substring(0, 100)}${finalPrompt?.length > 100 ? '...' : ''}"`
    );
    console.log(`   SessionId: ${sessionId}`);

    return this.runClaudeProcess(args, finalPrompt, workingDirectory, sessionId, timeoutMs);
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
      // Run the actual Claude process
      const result = await this.runClaudeProcess(
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
          this.sessionMessageBuffers.set(sessionId, {
            assistantMessages: [],
            systemInit: null,
            toolUseInProgress: false,
            permissionRequests: [],
            deliverables: [],
            permissionRequestSent: false,
          });
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

  async runClaudeProcess(args, prompt, workingDirectory, sessionId, timeoutMs) {
    console.log(`\n🔧 === runClaudeProcess CALLED ===`);
    console.log(`🔧 Running Claude CLI process:`);
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
      let claudeProcess;

      try {
        // Build the complete command arguments
        // When using --print with stdin, don't include prompt in args
        const useStdin = prompt && args.includes('--print');
        const fullArgs = useStdin ? args : prompt ? [...args, prompt] : args;

        console.log(`📝 Final args being passed to Claude CLI:`);
        console.log(`   Command: ${this.claudeCommand}`);
        console.log(
          `   Full args array (${fullArgs.length} items):`,
          fullArgs.map((arg, i) => `[${i}] ${arg.substring(0, 100)}`)
        );
        console.log(`   Has prompt: ${!!prompt}`);
        console.log(`   Using stdin for prompt: ${useStdin}`);

        claudeProcess = spawn(this.claudeCommand, fullArgs, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'],
        });
      } catch (spawnError) {
        console.error(`❌ Failed to spawn Claude CLI:`, spawnError);
        const errorMsg =
          spawnError.code === 'ENOENT'
            ? 'Claude CLI not found. Please ensure Claude CLI is installed and in your PATH.'
            : `Failed to start Claude CLI: ${spawnError.message}`;
        reject(new Error(errorMsg));
        return;
      }

      console.log(`   Process started with PID: ${claudeProcess.pid}`);

      // When using --print, Claude CLI might expect input from stdin
      // Try writing the prompt to stdin instead of passing as argument
      if (prompt && args.includes('--print')) {
        console.log(`   📝 Writing prompt to stdin instead of args`);
        claudeProcess.stdin.write(prompt);
        claudeProcess.stdin.end();
      } else {
        // Close stdin immediately if no prompt
        claudeProcess.stdin.end();
      }

      // Start monitoring this process
      if (claudeProcess.pid) {
        processMonitor
          .monitorProcess(claudeProcess.pid)
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
        pid: claudeProcess.pid,
        command: this.claudeCommand,
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

      claudeProcess.stdout.on('data', (data) => {
        // Store raw buffer to prevent encoding truncation
        stdoutBuffers.push(data);

        const chunk = data.toString();
        stdout += chunk;
        console.log(
          `📊 Claude CLI STDOUT (${chunk.length} chars, total: ${stdout.length}):`,
          JSON.stringify(chunk.substring(0, 200))
        );

        resetActivityTimer();

        // Emit partial data for progress tracking
        this.emit('commandProgress', {
          sessionId,
          pid: claudeProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      claudeProcess.stderr.on('data', (data) => {
        // Store raw buffer to prevent encoding truncation
        stderrBuffers.push(data);

        const chunk = data.toString();
        stderr += chunk;
        console.log(
          `📛 Claude CLI STDERR (${chunk.length} chars, total: ${stderr.length}):`,
          JSON.stringify(chunk)
        );

        resetActivityTimer();

        // Emit stderr for logging
        this.emit('processStderr', {
          sessionId,
          pid: claudeProcess.pid,
          data: chunk,
          timestamp: new Date().toISOString(),
        });
      });

      claudeProcess.on('close', (code) => {
        console.log(`🔚 Claude CLI process closed with code: ${code}`);

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
          pid: claudeProcess.pid,
          code,
          stdout: completeStdout.substring(0, 1000),
          stderr: completeStderr,
          timestamp: new Date().toISOString(),
        });

        if (code !== 0) {
          reject(new Error(`Claude CLI exited with code ${code}: ${completeStderr}`));
          return;
        }

        try {
          // Validate JSON before parsing
          if (!completeStdout || completeStdout.length === 0) {
            reject(new Error('Claude CLI returned empty output'));
            return;
          }

          // For stream-json format, we don't need strict JSON validation since it's newline-delimited
          const trimmedOutput = completeStdout.trim();
          if (!trimmedOutput || trimmedOutput.length === 0) {
            reject(new Error('Claude CLI returned empty output'));
            return;
          }

          // Parse stream-json format - newline-delimited JSON objects
          const responses = this.parseStreamJsonOutput(trimmedOutput);
          console.log(`✅ Claude CLI command completed successfully`);
          console.log(`   Parsed ${responses.length} response objects from stream-json`);

          if (responses.length === 0) {
            reject(new Error('No valid JSON objects found in Claude CLI output'));
            return;
          }

          // Find the final result
          const finalResult =
            responses.find((r) => r.type === 'result') || responses[responses.length - 1];

          // Ensure message buffer exists for this session
          if (!this.sessionMessageBuffers.has(sessionId)) {
            this.sessionMessageBuffers.set(sessionId, {
              assistantMessages: [],
              systemInit: null,
              toolUseInProgress: false,
              permissionRequests: [],
              deliverables: [],
              permissionRequestSent: false,
            });
            console.log(`🔧 Created missing message buffer for session ${sessionId}`);
          }

          // Emit all responses for detailed tracking
          responses.forEach((response, index) => {
            console.log(
              `   Response ${index + 1}: type=${response.type}, subtype=${response.subtype || 'none'}`
            );
            this.emitClaudeResponse(sessionId, response, index === responses.length - 1);
          });

          promiseResolve(finalResult);
        } catch (error) {
          console.error(`❌ Failed to parse Claude CLI response:`, error);
          console.error(`   Raw stdout length:`, completeStdout.length);
          console.error(`   First 200 chars:`, completeStdout.substring(0, 200));
          console.error(
            `   Last 200 chars:`,
            completeStdout.substring(Math.max(0, completeStdout.length - 200))
          );

          // Try to provide more helpful error information
          if (error.message.includes('Unterminated string')) {
            reject(new Error('Claude CLI response was truncated - output is incomplete'));
          } else if (error.message.includes('Unexpected end')) {
            reject(new Error('Claude CLI response ended unexpectedly - possible truncation'));
          } else {
            reject(new Error(`Failed to parse Claude CLI response: ${error.message}`));
          }
        }
      });

      claudeProcess.on('error', (error) => {
        console.error(`❌ Claude CLI process error:`, error);
        reject(new Error(`Claude CLI process error: ${error.message}`));
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
              `⏰ Claude CLI process silent timeout (${Math.round(timeSinceActivity / 1000)}s since last activity), killing PID ${claudeProcess.pid}...`
            );
            reject(
              new Error(
                `Claude CLI process timed out after ${Math.round(timeSinceActivity / 1000)}s of silence`
              )
            );
          } else {
            console.log(
              `⏰ Claude CLI process initial timeout (${Math.round(totalRuntime / 1000)}s total), killing PID ${claudeProcess.pid}...`
            );
            reject(new Error('Claude CLI process timed out'));
          }
          claudeProcess.kill('SIGTERM');
        }, timeoutToUse);
      };

      // Define the reset function now that updateTimeout exists
      resetActivityTimer = () => {
        lastActivityTime = Date.now();
        const wasFirstOutput = !hasReceivedOutput;
        hasReceivedOutput = true;
        console.log(
          `💓 Claude CLI activity detected${wasFirstOutput ? ' (first output)' : ''}, resetting timeout timer`
        );
        updateTimeout();
      };

      // Initial timeout
      updateTimeout();

      // Add periodic status logging
      const statusInterval = setInterval(
        () => {
          if (claudeProcess && claudeProcess.pid) {
            console.log(
              `📊 Claude CLI PID ${claudeProcess.pid} still running... (stdout: ${stdout.length} chars, stderr: ${stderr.length} chars)`
            );
          }
        },
        Math.min(timeoutMs / 4, 10000)
      ); // Status every 1/4 of timeout or 10s max

      claudeProcess.on('close', () => {
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
        const extracted = this.extractCompleteObjectsFromLine(line);
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

  emitClaudeResponse(sessionId, response, _isComplete = false, options = {}) {
    const buffer = this.sessionMessageBuffers.get(sessionId);
    if (!buffer) {
      console.warn(`No message buffer found for session ${sessionId}`);
      return;
    }

    // Process different types of Claude CLI responses
    switch (response.type) {
      case 'system':
        this.handleSystemResponse(sessionId, response, buffer);
        break;

      case 'assistant':
        this.handleAssistantResponse(sessionId, response, buffer);
        break;

      case 'user':
        // User messages are tool results - don't send to iOS
        console.log(`📝 Buffering user/tool result for session ${sessionId}`);
        break;

      case 'result':
        this.handleFinalResult(sessionId, response, buffer, options);
        break;

      default:
        console.log(`🤷 Unknown message type: ${response.type}, skipping`);
        break;
    }
  }

  handleSystemResponse(sessionId, response, buffer) {
    if (response.subtype === 'init') {
      // Store system init but don't send to iOS immediately
      buffer.systemInit = response;
      console.log(`📋 Buffered system init for session ${sessionId}`);
    }
  }

  handleAssistantResponse(sessionId, response, buffer) {
    if (!response.message || !response.message.content) {
      return;
    }

    console.log(`🎯 Processing assistant message for session ${sessionId}`);
    console.log(`   Message ID: ${response.message.id}`);
    console.log(`   Content blocks: ${response.message.content.length}`);

    // Check if this contains permission requests or immediate action items
    const hasPermissionRequest = this.containsPermissionRequest(response.message.content);
    const hasToolUse = this.containsToolUse(response.message.content);
    const codeBlocks = this.extractCodeBlocks(response.message.content);

    if (hasPermissionRequest) {
      // Send permission requests immediately
      console.log(`🔐 Sending permission request immediately for session ${sessionId}`);

      // Mark that we've sent a permission request to avoid duplicates
      buffer.permissionRequestSent = true;

      // Extract the permission prompt text
      const permissionPrompt = this.extractPermissionPrompt(
        response.message.content.map((c) => c.text || '').join(' ')
      );

      // Emit the permissionRequired event that WebSocket expects
      this.emit('permissionRequired', {
        sessionId,
        prompt: permissionPrompt,
        options: ['y', 'n'],
        default: 'n',
      });

      // Also emit as assistantMessage for UI display
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'permission_request',
          messageId: response.message.id,
          content: response.message.content,
          timestamp: new Date().toISOString(),
        },
        isComplete: false,
      });

      // Don't buffer permission requests since they're sent immediately
      return;
    }

    if (codeBlocks.length > 0) {
      // Send completed code blocks as deliverables
      console.log(`💻 Found ${codeBlocks.length} code blocks, adding to deliverables`);
      buffer.deliverables.push(...codeBlocks);
    }

    if (hasToolUse) {
      buffer.toolUseInProgress = true;
    }

    // Buffer all other assistant messages for aggregation
    buffer.assistantMessages.push({
      messageId: response.message.id,
      content: response.message.content,
      model: response.message.model,
      usage: response.message.usage,
      timestamp: new Date().toISOString(),
    });

    console.log(`📦 Buffered assistant message (total: ${buffer.assistantMessages.length})`);
  }

  handleFinalResult(sessionId, response, buffer, options = {}) {
    console.log(`🏁 Processing final result for session ${sessionId}`);
    console.log(`   Buffered messages: ${buffer.assistantMessages.length}`);
    console.log(`   Deliverables: ${buffer.deliverables.length}`);
    console.log(`   Options:`, options);

    // For long-running completions, always send the results immediately
    if (options.isLongRunningCompletion) {
      console.log(`🚀 Long-running completion detected, sending results immediately`);
      this.sendFinalAggregatedResponse(sessionId, response, buffer);
      return;
    }

    // If we already sent a permission request from the assistant messages,
    // don't check again in the final result to avoid duplicates
    if (buffer.permissionRequestSent) {
      console.log(`⏭️  Permission request already sent, skipping final result permission check`);

      // Store the pending response in buffer for later when permission is granted
      buffer.pendingFinalResponse = {
        aggregatedContent: this.aggregateBufferedContent(buffer),
        finalResult: response.result,
        conversationResult: {
          type: 'final_result',
          success: !response.is_error,
          // result field intentionally omitted to prevent duplicate display
          sessionId,
          duration: response.duration_ms,
          cost: response.total_cost_usd,
          usage: response.usage,
          timestamp: new Date().toISOString(),
        },
      };
      return;
    }

    // Check if the final result contains an embedded permission request
    const finalResultContent = response.result
      ? [
          {
            type: 'text',
            text: response.result,
          },
        ]
      : [];

    const hasEmbeddedPermission = this.containsPermissionRequest(finalResultContent);

    if (hasEmbeddedPermission) {
      console.log(`🔐 Found embedded permission request in final result for session ${sessionId}`);

      // Extract the permission request and send it as a structured prompt
      const permissionPrompt = this.extractPermissionPrompt(response.result);

      // Emit the permissionRequired event that WebSocket expects
      this.emit('permissionRequired', {
        sessionId,
        prompt: permissionPrompt,
        options: ['y', 'n'],
        default: 'n',
      });

      // Send permission request immediately
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'permission_request',
          content: finalResultContent,
          permissionPrompt,
          requiresApproval: true,
          timestamp: new Date().toISOString(),
        },
        isComplete: false,
      });

      // Don't send aggregated response yet - wait for approval
      console.log(`⏸️  Waiting for user approval before sending aggregated response`);

      // Store the pending response in buffer for later
      buffer.pendingFinalResponse = {
        aggregatedContent: this.aggregateBufferedContent(buffer),
        finalResult: response.result,
        conversationResult: {
          type: 'final_result',
          success: !response.is_error,
          // result field removed to prevent duplicate display
          sessionId,
          duration: response.duration_ms,
          cost: response.total_cost_usd,
          usage: response.usage,
          timestamp: new Date().toISOString(),
        },
      };

      return; // Don't proceed with normal flow
    }

    // Normal flow - no permission needed
    this.sendFinalAggregatedResponse(sessionId, response, buffer);
  }

  sendFinalAggregatedResponse(sessionId, response, buffer) {
    // Aggregate all buffered content into a single response
    const aggregatedContent = this.aggregateBufferedContent(buffer);

    // Note: response.result is already included in the aggregated content from buffered messages
    // so we don't need to add it again to avoid duplication

    // Send the complete aggregated response to iOS
    console.log(`📱 Sending aggregated response to iOS for session ${sessionId}`);
    this.emit('assistantMessage', {
      sessionId,
      data: {
        type: 'assistant_response',
        content: aggregatedContent,
        deliverables: buffer.deliverables,
        aggregated: true,
        messageCount: buffer.assistantMessages.length,
        timestamp: new Date().toISOString(),
      },
      isComplete: true,
    });

    // Send conversation result for completion tracking
    // Note: Don't include the result text here as it's already sent in assistantMessage
    this.emit('conversationResult', {
      sessionId,
      data: {
        type: 'final_result',
        success: !response.is_error,
        // result field removed to prevent duplicate display in iOS
        sessionId,
        duration: response.duration_ms,
        cost: response.total_cost_usd,
        usage: response.usage,
        timestamp: new Date().toISOString(),
      },
    });

    // Clear the buffer for next command
    this.clearSessionBuffer(sessionId);
  }

  extractPermissionPrompt(resultText) {
    if (!resultText) return null;

    // Look for the specific permission question in the text
    const lines = resultText.split('\n');

    // Find lines that contain permission-related questions
    const permissionLines = lines.filter((line) => {
      const lowerLine = line.toLowerCase();
      return (
        lowerLine.includes('would you like') ||
        lowerLine.includes('should i') ||
        lowerLine.includes('need permission') ||
        lowerLine.includes('need write') ||
        lowerLine.includes('proceed') ||
        line.endsWith('?')
      );
    });

    if (permissionLines.length > 0) {
      return permissionLines.join(' ').trim();
    }

    // Fallback - return last paragraph if it seems like a question
    const lastParagraph = resultText.split('\n\n').pop();
    if (lastParagraph && lastParagraph.includes('?')) {
      return lastParagraph.trim();
    }

    return 'Permission required to proceed';
  }

  containsPermissionRequest(content) {
    if (!Array.isArray(content)) return false;

    return content.some((block) => {
      if (block.type === 'text' && block.text) {
        const text = block.text.toLowerCase();

        // Traditional permission patterns
        if (
          text.includes('permission') ||
          text.includes('approve') ||
          text.includes('(y/n)') ||
          text.includes('[y/n]') ||
          text.includes('confirm')
        ) {
          return true;
        }

        // Conversational permission patterns
        const conversationalPatterns = [
          'would you like me to proceed',
          'should i proceed',
          'should i continue',
          'would you like me to continue',
          'shall i proceed',
          'shall i continue',
          'may i proceed',
          'can i proceed',
          'do you want me to',
          'i need write permissions',
          'i need permissions',
          'need write access',
          'require write permissions',
          'would you like me to create',
          'should i create',
          'shall i create',
          'would you like me to execute',
          'should i execute',
          'would you like me to implement',
          'should i implement',
        ];

        const hasConversationalPattern = conversationalPatterns.some((pattern) =>
          text.includes(pattern)
        );

        if (hasConversationalPattern) {
          console.log(
            `🔍 Detected conversational permission request: "${text.substring(0, 100)}..."`
          );
          return true;
        }

        // Questions ending with "?" that might need approval
        const questionPatterns = [
          /would you like.*\?/,
          /should i.*\?/,
          /shall i.*\?/,
          /do you want.*\?/,
          /can i.*\?/,
          /may i.*\?/,
        ];

        const hasQuestionPattern = questionPatterns.some((pattern) => pattern.test(text));

        if (hasQuestionPattern) {
          console.log(
            `❓ Detected question-based permission request: "${text.substring(0, 100)}..."`
          );
          return true;
        }
      }
      return false;
    });
  }

  containsToolUse(content) {
    if (!Array.isArray(content)) return false;
    return content.some((block) => block.type === 'tool_use');
  }

  containsApprovalResponse(text) {
    if (!text || typeof text !== 'string') return false;

    const normalizedText = text.toLowerCase().trim();

    // Direct approval phrases
    const directApprovals = [
      'yes',
      'y',
      'yep',
      'yeah',
      'yup',
      'approved',
      'approve',
      'approval',
      'ok',
      'okay',
      'k',
      'sure',
      'fine',
      'good',
      'proceed',
      'continue',
      'go ahead',
      'go for it',
      'do it',
      'execute',
      'run it',
      'confirm',
      'confirmed',
      'allow',
      'permit',
      'authorized',
    ];

    // Check for exact matches or phrases that start with approval
    const hasDirectApproval = directApprovals.some(
      (approval) =>
        normalizedText === approval ||
        normalizedText.startsWith(`${approval} `) ||
        normalizedText.startsWith(`${approval},`) ||
        normalizedText.startsWith(`${approval}.`)
    );

    if (hasDirectApproval) {
      console.log(`✅ Detected approval response: "${text}"`);
      return true;
    }

    // Longer approval phrases
    const phraseApprovals = [
      'go ahead',
      'go for it',
      'sounds good',
      'looks good',
      'that works',
      'do it',
      'make it so',
      "let's do it",
      'i approve',
      'you have permission',
      'you can proceed',
      'please proceed',
      'please continue',
      'yes please',
      'sure thing',
      'absolutely',
      'definitely',
    ];

    const hasPhraseApproval = phraseApprovals.some((phrase) => normalizedText.includes(phrase));

    if (hasPhraseApproval) {
      console.log(`✅ Detected phrase-based approval: "${text}"`);
      return true;
    }

    return false;
  }

  extractCodeBlocks(content) {
    if (!Array.isArray(content)) return [];

    const codeBlocks = [];
    content.forEach((block) => {
      if (block.type === 'text' && block.text) {
        // Look for code blocks in text (```language...```)
        const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
        let match;
        while ((match = codeBlockRegex.exec(block.text)) !== null) {
          codeBlocks.push({
            type: 'code_block',
            language: match[1] || 'text',
            code: match[2].trim(),
          });
        }
      }
    });

    return codeBlocks;
  }

  aggregateBufferedContent(buffer) {
    const aggregatedContent = [];

    // Combine all text content from assistant messages
    const textBlocks = [];

    buffer.assistantMessages.forEach((message) => {
      message.content.forEach((block) => {
        if (block.type === 'text' && block.text) {
          textBlocks.push(block.text);
        }
      });
    });

    // Combine text blocks, removing duplicates and tool usage details
    const combinedText = textBlocks
      .filter((text) => text.trim().length > 0)
      .filter((text, index, array) => array.indexOf(text) === index) // Remove duplicates
      .join('\n\n');

    if (combinedText) {
      aggregatedContent.push({
        type: 'text',
        text: combinedText,
      });
    }

    return aggregatedContent;
  }

  clearSessionBuffer(sessionId) {
    const buffer = this.sessionMessageBuffers.get(sessionId);
    if (buffer) {
      buffer.assistantMessages = [];
      buffer.toolUseInProgress = false;
      buffer.permissionRequests = [];
      buffer.deliverables = [];
      buffer.permissionRequestSent = false;
      console.log(`🧹 Cleared message buffer for session ${sessionId}`);
    }
  }

  async closeSession(sessionId) {
    const session = this.activeSessions.get(sessionId);

    if (!session) {
      console.log(`⚠️  Attempted to close non-existent session: ${sessionId}`);
      return { success: false, message: 'Session not found' };
    }

    console.log(`🔚 Closing Claude CLI session: ${sessionId}`);
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
    console.log(`📊 Active Claude CLI sessions: ${sessions.length}`);
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
    console.log('🔄 Shutting down Claude Code Service...');

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

    console.log('✅ Claude Code Service shut down complete');
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
        claudeCodeAvailable: isAvailable,
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
  calculateTimeoutForCommand(command) {
    if (!command || typeof command !== 'string') {
      return 60000; // 1 minute default
    }

    const length = command.length;
    const lowerCommand = command.toLowerCase();

    // Keywords that indicate complex operations
    const complexKeywords = [
      'review',
      'analyze',
      'audit',
      'assess',
      'evaluate',
      'examine',
      'refactor',
      'optimize',
      'improve',
      'redesign',
      'restructure',
      'debug',
      'troubleshoot',
      'investigate',
      'diagnose',
      'document',
      'explain',
      'summarize',
      'overview',
      'test',
      'benchmark',
      'profile',
      'performance',
    ];

    const veryComplexKeywords = [
      'expert',
      'comprehensive',
      'thorough',
      'complete',
      'full',
      'entire project',
      'whole codebase',
      'all files',
    ];

    // Check for very complex operations
    const hasVeryComplexKeywords = veryComplexKeywords.some((keyword) =>
      lowerCommand.includes(keyword)
    );

    // Check for complex operations
    const hasComplexKeywords = complexKeywords.some((keyword) => lowerCommand.includes(keyword));

    // Calculate base timeout
    let timeoutMs;

    if (hasVeryComplexKeywords) {
      timeoutMs = 600000; // 10 minutes for very complex operations
    } else if (hasComplexKeywords) {
      timeoutMs = 300000; // 5 minutes for complex operations
    } else if (length > 200) {
      timeoutMs = 300000; // 5 minutes for long commands
    } else if (length > 50) {
      timeoutMs = 180000; // 3 minutes for medium commands
    } else {
      timeoutMs = 120000; // 2 minutes for simple commands
    }

    console.log(
      `🕐 Calculated timeout for command: ${timeoutMs}ms (${Math.round(timeoutMs / 1000)}s)`
    );
    console.log(`   Command length: ${length} chars`);
    console.log(`   Has complex keywords: ${hasComplexKeywords}`);
    console.log(`   Has very complex keywords: ${hasVeryComplexKeywords}`);

    return timeoutMs;
  }

  // Classify different types of Claude Code messages
  classifyClaudeMessage(message) {
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
    // Claude's response messages
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

  // Permission prompt detection
  isPermissionPrompt(message) {
    if (!message || typeof message !== 'object') return false;

    // Check for common permission prompt patterns
    const text = this.extractTextFromMessage(message);
    if (!text) return false;

    const permissionPatterns = [
      /\(y\/n\)/i,
      /allow.*\?/i,
      /proceed.*\?/i,
      /continue.*\?/i,
      /\[Y\/n\]/i,
      /\[y\/N\]/i,
    ];

    return permissionPatterns.some((pattern) => pattern.test(text));
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
}
