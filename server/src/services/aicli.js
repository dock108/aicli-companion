import { spawn, exec } from 'child_process';
import { promisify } from 'util';
import { EventEmitter } from 'events';
import { processMonitor } from '../utils/process-monitor.js';
import { InputValidator, MessageProcessor, AICLIConfig } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';
import { ClaudeStreamParser } from './stream-parser.js';
import { pushNotificationService } from './push-notification.js';
import { AICLISessionManager } from './aicli-session-manager.js';
import { AICLIProcessRunner } from './aicli-process-runner.js';
import { AICLILongRunningTaskManager } from './aicli-long-running-task-manager.js';
import { AICLIValidationService } from './aicli-validation-service.js';

const execAsync = promisify(exec);

export class AICLIService extends EventEmitter {
  constructor() {
    super();
    
    // Initialize session manager
    this.sessionManager = new AICLISessionManager({
      maxSessions: 10,
      sessionTimeout: 30 * 60 * 1000, // 30 minutes
    });
    
    // Initialize process runner
    this.processRunner = new AICLIProcessRunner();
    
    // Initialize long-running task manager
    this.longRunningTaskManager = new AICLILongRunningTaskManager();
    
    // Forward events from all managers
    this.sessionManager.on('sessionCleaned', (data) => {
      this.emit('sessionCleaned', data);
    });
    
    this.processRunner.on('streamChunk', (data) => {
      this.emit('streamChunk', data);
    });
    
    this.processRunner.on('commandProgress', (data) => {
      this.emit('commandProgress', data);
    });
    
    this.processRunner.on('processStart', (data) => {
      this.emit('processStart', data);
    });
    
    this.processRunner.on('processExit', (data) => {
      this.emit('processExit', data);
    });
    
    this.processRunner.on('processStderr', (data) => {
      this.emit('processStderr', data);
    });
    
    this.processRunner.on('aicliResponse', (data) => {
      this.emitAICLIResponse(data.sessionId, data.response, data.isLast);
    });
    
    this.longRunningTaskManager.on('assistantMessage', (data) => {
      this.emit('assistantMessage', data);
    });
    
    this.longRunningTaskManager.on('streamError', (data) => {
      this.emit('streamError', data);
    });
    
    // Configuration (will be delegated to appropriate managers)
    this.aicliCommand = this.processRunner.aicliCommand;
    this.defaultWorkingDirectory = process.cwd();
    this.safeRootDirectory = null; // Will be set from server config

    // Legacy permission properties (delegated to process runner)
    this.permissionMode = this.processRunner.permissionMode;
    this.allowedTools = this.processRunner.allowedTools;
    this.disallowedTools = this.processRunner.disallowedTools;
    this.skipPermissions = this.processRunner.skipPermissions;

    // Process monitoring
    this.processHealthCheckInterval = null;
    this.startProcessHealthMonitoring();
  }

  // Configure permission settings (delegated to process runner)
  setPermissionMode(mode) {
    this.processRunner.setPermissionMode(mode);
    this.permissionMode = this.processRunner.permissionMode;
  }

  setAllowedTools(tools) {
    this.processRunner.setAllowedTools(tools);
    this.allowedTools = this.processRunner.allowedTools;
  }

  setDisallowedTools(tools) {
    this.processRunner.setDisallowedTools(tools);
    this.disallowedTools = this.processRunner.disallowedTools;
  }

  setSafeRootDirectory(dir) {
    this.safeRootDirectory = dir;
  }

  setSkipPermissions(skip) {
    this.processRunner.setSkipPermissions(skip);
    this.skipPermissions = this.processRunner.skipPermissions;
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
    this.sessionManager.cleanupDeadSession(sessionId);
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

    // Check if session already exists
    if (this.sessionManager.hasSession(sessionKey)) {
      return this.sendToExistingSession(sessionKey, sanitizedPrompt);
    }

    // Create new interactive session
    return this.createInteractiveSession(sessionKey, sanitizedPrompt, validatedWorkingDir);
  }

  async createInteractiveSession(sessionId, initialPrompt, workingDirectory) {
    return this.sessionManager.createInteractiveSession(sessionId, initialPrompt, workingDirectory);
  }

  async sendToExistingSession(sessionId, prompt) {
    // Validate inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);

    if (!sanitizedSessionId) {
      throw new Error('Invalid session ID');
    }

    const session = this.sessionManager.getSession(sanitizedSessionId);

    if (!session || !session.isActive) {
      throw new Error(`Session ${sanitizedSessionId} not found or inactive`);
    }

    try {
      // Update activity and processing state
      this.sessionManager.updateSessionActivity(sanitizedSessionId);
      this.sessionManager.setSessionProcessing(sanitizedSessionId, true);

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

      // Mark processing as complete
      this.sessionManager.setSessionProcessing(sanitizedSessionId, false);

      return {
        sessionId: sanitizedSessionId,
        success: true,
        message: 'Command executed successfully',
        response,
      };
    } catch (error) {
      // Mark processing as complete even on error
      this.sessionManager.setSessionProcessing(sanitizedSessionId, false);
      console.error('❌ Failed to execute command for session %s:', sanitizedSessionId, error);
      throw new Error(`Failed to execute command: ${error.message}`);
    }
  }

  async testAICLICommand(testType = 'version') {
    return this.processRunner.testAICLICommand(testType);
  }

  async executeAICLICommand(session, prompt) {
    // Mark conversation as started if needed
    if (!session.conversationStarted) {
      this.sessionManager.markConversationStarted(session.sessionId);
    }
    
    // Delegate to process runner with long-running task manager
    return this.processRunner.executeAICLICommand(session, prompt, this.longRunningTaskManager);
  }



  // Delegate validation methods to AICLIValidationService
  isValidCompleteJSON(jsonString) {
    return AICLIValidationService.isValidCompleteJSON(jsonString);
  }

  parseStreamJsonOutput(output) {
    return AICLIValidationService.parseStreamJsonOutput(output);
  }

  extractCompleteObjectsFromLine(line) {
    return AICLIValidationService.extractCompleteObjectsFromLine(line);
  }

  extractLastCompleteJSON(truncatedJSON) {
    return AICLIValidationService.extractLastCompleteJSON(truncatedJSON);
  }

  findLastCompleteJSONStart(text) {
    return AICLIValidationService.findLastCompleteJSONStart(text);
  }

  extractCompleteObjectsFromArray(arrayText) {
    return AICLIValidationService.extractCompleteObjectsFromArray(arrayText);
  }

  emitAICLIResponse(sessionId, response, _isComplete = false, options = {}) {
    const buffer = this.sessionManager.getSessionBuffer(sessionId);
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
    this.sessionManager.clearSessionBuffer(sessionId);
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
    return this.sessionManager.closeSession(sessionId);
  }

  hasSession(sessionId) {
    return this.sessionManager.hasSession(sessionId);
  }

  getActiveSessions() {
    return this.sessionManager.getActiveSessions();
  }

  // Cleanup method for graceful shutdown
  shutdown() {
    console.log('🔄 Shutting down AICLI Code Service...');

    // Stop health monitoring
    this.stopProcessHealthMonitoring();

    // Shutdown session manager
    this.sessionManager.shutdown();

    console.log('✅ AICLI Code Service shut down complete');
  }

  async healthCheck() {
    try {
      const isAvailable = await this.checkAvailability();

      // Get system resources
      const systemResources = await processMonitor.getSystemResources();

      // Get process metrics for active sessions
      const sessionMetrics = [];
      const activeSessions = this.sessionManager.activeSessions;
      for (const [sessionId, session] of activeSessions) {
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
        activeSessions: activeSessions.size,
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

  // Check if session should timeout
  checkSessionTimeout(sessionId) {
    this.sessionManager.checkSessionTimeout(sessionId);
  }

  // Handle permission prompts
  async handlePermissionPrompt(sessionId, response) {
    const session = this.sessionManager.getSession(sessionId);

    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }

    try {
      // In non-interactive mode, we need to send the permission response as a new command
      console.log(`📝 Handling permission response for session ${sessionId}: "${response}"`);

      // Check if the session has a pending permission request
      const buffer = this.sessionManager.getSessionBuffer(sessionId);
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
