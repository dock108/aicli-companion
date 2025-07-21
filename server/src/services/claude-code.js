import { spawn } from 'child_process';
import { promisify } from 'util';
import { exec } from 'child_process';
import { EventEmitter } from 'events';

const execAsync = promisify(exec);

export class ClaudeCodeService extends EventEmitter {
  constructor() {
    super();
    this.activeSessions = new Map();
    this.claudeCommand = 'claude';
    this.defaultWorkingDirectory = process.cwd();
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
      if (streaming) {
        return this.sendStreamingPrompt(prompt, { sessionId, workingDirectory });
      } else {
        return this.sendOneTimePrompt(prompt, { format, workingDirectory });
      }
    } catch (error) {
      console.error('Error sending prompt to Claude Code:', error);
      throw new Error(`Claude Code execution failed: ${error.message}`);
    }
  }

  async sendOneTimePrompt(prompt, { format = 'json', workingDirectory = process.cwd() }) {
    const args = ['--print', '--output-format', format, prompt];

    console.log(`🚀 Starting Claude CLI with args:`, args);
    console.log(`   Working directory: ${workingDirectory}`);

    return new Promise((resolve, reject) => {
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
            resolve(response);
          } else {
            console.log(`   ✅ Returning raw text response`);
            resolve({ result: stdout });
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
    const sessionKey = sessionId || `session_${Date.now()}`;

    // Check if session already exists
    if (this.activeSessions.has(sessionKey)) {
      return this.sendToExistingSession(sessionKey, prompt);
    }

    // Create new interactive session
    return this.createInteractiveSession(sessionKey, prompt, workingDirectory);
  }

  async createInteractiveSession(sessionId, initialPrompt, workingDirectory) {
    // Use streaming format with verbose for full tool output
    const args = ['--output-format', 'stream-json', '--verbose'];

    console.log(`🚀 Starting Claude Code interactive session with args:`, args);
    console.log(`   Session ID: ${sessionId}`);
    console.log(`   Working directory: ${workingDirectory}`);
    console.log(
      `   Initial prompt: "${initialPrompt?.substring(0, 100)}${initialPrompt?.length > 100 ? '...' : ''}"`
    );

    const claudeProcess = spawn(this.claudeCommand, args, {
      cwd: workingDirectory,
      stdio: ['pipe', 'pipe', 'pipe'],
      env: { ...process.env },
    });

    const session = {
      process: claudeProcess,
      sessionId,
      workingDirectory,
      isActive: true,
    };

    this.activeSessions.set(sessionId, session);

    // Set up event handlers for Claude Code output
    claudeProcess.stdout.on('data', (data) => {
      const dataStr = data.toString();
      console.log(`📊 Claude ${sessionId} STDOUT:`, dataStr.length, 'chars');

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
              sessionId,
              prompt: this.extractPermissionPrompt(message),
              options: ['y', 'n'],
              default: 'n',
            });
          } else {
            console.log(`   📡 Emitting ${classifiedMessage.eventType}`);
            this.emit(classifiedMessage.eventType, {
              sessionId,
              data: classifiedMessage.data,
              originalMessage: message,
              isComplete: message.type === 'result',
            });
          }
        } catch (error) {
          // Not JSON, treat as raw text output
          console.log(`   📝 Raw text line`);
          this.emit('streamData', {
            sessionId,
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
      this.emit('streamError', { sessionId, error: data.toString() });
    });

    claudeProcess.on('close', (code) => {
      this.activeSessions.delete(sessionId);
      this.emit('sessionClosed', { sessionId, code });
    });

    claudeProcess.on('error', (error) => {
      this.activeSessions.delete(sessionId);
      this.emit('sessionError', { sessionId, error: error.message });
    });

    // Send initial prompt
    claudeProcess.stdin.write(`${initialPrompt}\n`);

    return {
      sessionId,
      success: true,
      message: 'Interactive session started',
    };
  }

  async sendToExistingSession(sessionId, prompt) {
    const session = this.activeSessions.get(sessionId);

    if (!session || !session.isActive) {
      throw new Error(`Session ${sessionId} not found or inactive`);
    }

    try {
      session.process.stdin.write(`${prompt}\n`);

      return {
        sessionId,
        success: true,
        message: 'Prompt sent to existing session',
      };
    } catch (error) {
      this.activeSessions.delete(sessionId);
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
