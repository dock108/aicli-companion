import { spawn } from 'child_process';
import { promisify } from 'util';
import { exec } from 'child_process';
import { EventEmitter } from 'events';
import { resolve } from 'path';
import { access, constants } from 'fs/promises';

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

  static async validateWorkingDirectory(workingDir) {
    const SAFE_ROOT = '/safe/root/dir'; // Define the safe root directory

    if (!workingDir || typeof workingDir !== 'string') {
      return SAFE_ROOT; // Default to the safe root directory
    }

    // Resolve to absolute path
    const resolvedPath = resolve(workingDir);

    // Ensure the resolved path is within the safe root directory
    if (!resolvedPath.startsWith(SAFE_ROOT)) {
      throw new Error('Working directory must be within the safe root directory');
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

    const allowedArgs = ['--print', '--output-format', '--verbose', '--help', '--version'];

    const allowedFormats = ['json', 'text', 'markdown', 'stream-json'];

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
      }
    }

    return args;
  }
}

export class ClaudeCodeService extends EventEmitter {
  constructor() {
    super();
    this.activeSessions = new Map();
    this.claudeCommand = 'claude';
    this.defaultWorkingDirectory = process.cwd();
    this.maxSessions = 10;
    this.sessionTimeout = 30 * 60 * 1000; // 30 minutes
  }

  async checkAvailability() {
    try {
      const { stdout, _stderr } = await execAsync(`${this.claudeCommand} --version`);
      const version = stdout.trim();
      console.log(`Claude Code version: ${version}`);
      return true;
    } catch (error) {
      console.error('Claude Code not available:', error.message);
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
      const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);
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
    // Input validation already done in sendPrompt, but double-check critical params
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);
    const validatedFormat = InputValidator.validateFormat(format);

    const args = ['--print', '--output-format', validatedFormat, sanitizedPrompt];

    // Validate arguments before spawning
    InputValidator.validateClaudeArgs(args);

    console.log(`🚀 Starting Claude CLI with validated args:`, args.slice(0, 3)); // Don't log full prompt
    console.log(`   Working directory: ${workingDirectory}`);

    return new Promise((resolvePromise, reject) => {
      const claudeProcess = spawn(this.claudeCommand, args, {
        cwd: workingDirectory,
        stdio: ['pipe', 'pipe', 'pipe'],
      });

      // Close stdin immediately since we're not sending any input
      claudeProcess.stdin.end();

      let stdout = '';
      let stderr = '';

      console.log(`   Process started with PID: ${claudeProcess.pid}`);

      claudeProcess.stdout.on('data', (data) => {
        const chunk = data.toString();
        console.log(`   STDOUT chunk: ${chunk.length} chars`);
        stdout += chunk;
      });

      claudeProcess.stderr.on('data', (data) => {
        const chunk = data.toString();
        console.log(`   STDERR chunk: ${chunk}`);
        stderr += chunk;
      });

      claudeProcess.on('close', (code) => {
        console.log(`   Process closed with code: ${code}`);
        console.log(`   STDOUT length: ${stdout.length}`);
        console.log(`   STDERR length: ${stderr.length}`);

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

    // Use streaming format with verbose for full tool output
    const args = ['--output-format', 'stream-json', '--verbose'];

    // Validate arguments
    InputValidator.validateClaudeArgs(args);

    console.log(`🚀 Starting Claude Code interactive session with args:`, args);
    console.log(`   Session ID: ${sanitizedSessionId}`);
    console.log(`   Working directory: ${validatedWorkingDir}`);
    console.log(`   Initial prompt length: ${sanitizedPrompt?.length} chars`);

    const claudeProcess = spawn(this.claudeCommand, args, {
      cwd: validatedWorkingDir,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
      timeout: this.sessionTimeout,
    });

    const session = {
      process: claudeProcess,
      sessionId: sanitizedSessionId,
      workingDirectory: validatedWorkingDir,
      isActive: true,
      createdAt: Date.now(),
      lastActivity: Date.now(),
    };

    this.activeSessions.set(sanitizedSessionId, session);

    // Set up session timeout
    setTimeout(() => {
      if (this.activeSessions.has(sanitizedSessionId)) {
        console.log(`Session ${sanitizedSessionId} timed out, cleaning up`);
        this.closeSession(sanitizedSessionId);
      }
    }, this.sessionTimeout);

    // Set up event handlers for Claude Code output
    claudeProcess.stdout.on('data', (data) => {
      // Update last activity
      if (session) {
        session.lastActivity = Date.now();
      }

      const dataStr = data.toString();
      console.log('📊 Claude %s STDOUT:', sanitizedSessionId, dataStr.length, 'chars');

      const lines = dataStr.split('\n').filter((line) => line.trim());

      for (const line of lines) {
        console.log(
          `   Processing line:`,
          line.substring(0, 150) + (line.length > 150 ? '...' : '')
        );
        try {
          const message = JSON.parse(line);
          console.log(`   📋 Message type: ${message.type}, subtype: ${message.subtype || 'none'}`);

          // Classify and handle different types of Claude Code messages
          const classifiedMessage = this.classifyClaudeMessage(message);

          // Check for permission prompts
          if (this.isPermissionPrompt(message)) {
            console.log(`   🔐 Permission prompt detected`);
            this.emit('permissionRequired', {
              sessionId: sanitizedSessionId,
              prompt: this.extractPermissionPrompt(message),
              options: ['y', 'n'],
              default: 'n',
            });
          } else {
            console.log(`   📡 Emitting ${classifiedMessage.eventType}`);
            this.emit(classifiedMessage.eventType, {
              sessionId: sanitizedSessionId,
              data: classifiedMessage.data,
              originalMessage: message,
              isComplete: message.type === 'result',
            });
          }
        } catch (error) {
          // Not JSON, treat as raw text output
          console.log(`   📝 Raw text line`);
          this.emit('streamData', {
            sessionId: sanitizedSessionId,
            data: {
              type: 'text',
              content: line,
              timestamp: new Date().toISOString(),
            },
            isComplete: false,
          });
        }
      }
    });

    claudeProcess.stderr.on('data', (data) => {
      this.emit('streamError', { sessionId: sanitizedSessionId, error: data.toString() });
    });

    claudeProcess.on('close', (code) => {
      this.activeSessions.delete(sanitizedSessionId);
      this.emit('sessionClosed', { sessionId: sanitizedSessionId, code });
    });

    claudeProcess.on('error', (error) => {
      this.activeSessions.delete(sanitizedSessionId);
      this.emit('sessionError', { sessionId: sanitizedSessionId, error: error.message });
    });

    // Send initial prompt
    claudeProcess.stdin.write(`${sanitizedPrompt}\n`);

    return {
      sessionId: sanitizedSessionId,
      success: true,
      message: 'Interactive session started',
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

      session.process.stdin.write(`${sanitizedPrompt}\n`);

      return {
        sessionId: sanitizedSessionId,
        success: true,
        message: 'Prompt sent to existing session',
      };
    } catch (error) {
      this.activeSessions.delete(sanitizedSessionId);
      throw new Error(`Failed to send to session: ${error.message}`);
    }
  }

  async closeSession(sessionId) {
    const session = this.activeSessions.get(sessionId);

    if (!session) {
      return { success: false, message: 'Session not found' };
    }

    try {
      session.process.stdin.end();
      session.process.kill('SIGTERM');
      this.activeSessions.delete(sessionId);

      return { success: true, message: 'Session closed' };
    } catch (error) {
      console.error('Error closing session:', error);
      return { success: false, message: error.message };
    }
  }

  getActiveSessions() {
    return Array.from(this.activeSessions.keys());
  }

  async healthCheck() {
    try {
      const isAvailable = await this.checkAvailability();

      return {
        status: isAvailable ? 'healthy' : 'degraded',
        claudeCodeAvailable: isAvailable,
        activeSessions: this.activeSessions.size,
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
      session.process.stdin.write(`${response}\n`);
      return { success: true };
    } catch (error) {
      throw new Error(`Failed to respond to permission prompt: ${error.message}`);
    }
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

  extractPermissionPrompt(message) {
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
