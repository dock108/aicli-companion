import { spawn, exec } from 'child_process';
import { promisify } from 'util';
import { EventEmitter } from 'events';
import { processMonitor } from '../utils/process-monitor.js';
import { InputValidator, MessageProcessor, AICLIConfig } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';
// import { ClaudeStreamParser } from './stream-parser.js';
// import { pushNotificationService } from './push-notification.js';
import { AICLISessionManager } from './aicli-session-manager.js';
import { AICLIProcessRunner } from './aicli-process-runner.js';
// Long-running task manager removed - trusting Claude CLI timeouts
import { AICLIValidationService } from './aicli-validation-service.js';
import { sessionPersistence } from './session-persistence.js';

const execAsync = promisify(exec);

export class AICLIService extends EventEmitter {
  constructor(options = {}) {
    super();

    // Initialize session manager
    this.sessionManager =
      options.sessionManager ||
      new AICLISessionManager({
        maxSessions: 10,
        sessionTimeout: 30 * 60 * 1000, // 30 minutes
      });

    // Initialize process runner with dependency injection support
    this.processRunner =
      options.processRunner || new AICLIProcessRunner(options.processRunnerOptions);

    // Initialize long-running task manager
    // Long-running task manager removed - trusting Claude CLI timeouts

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
      // Clean up the session when process exits
      if (data.sessionId && data.code !== 0) {
        console.log(
          `🧹 Cleaning up session ${data.sessionId} after process exit with code ${data.code}`
        );
        this.sessionManager.cleanupDeadSession(data.sessionId).catch((error) => {
          console.warn(`⚠️ Failed to cleanup dead session ${data.sessionId}:`, error.message);
        });
      }
      this.emit('processExit', data);
    });

    this.processRunner.on('processStderr', (data) => {
      this.emit('processStderr', data);
    });

    this.processRunner.on('aicliResponse', async (data) => {
      await this.emitAICLIResponse(data.sessionId, data.response, data.isLast);
    });

    // Event handlers removed with long-running task manager

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

    // Perform startup cleanup to handle stale sessions
    this.performStartupCleanup().catch((error) => {
      console.warn('⚠️ Startup cleanup failed:', error.message);
    });
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

    for (const [sessionId, session] of this.sessionManager.activeSessions) {
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
            this.cleanupDeadSession(sessionId).catch((error) => {
              console.warn(`⚠️ Failed to cleanup dead session ${sessionId}:`, error.message);
            });
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
  async cleanupDeadSession(sessionId) {
    await this.sessionManager.cleanupDeadSession(sessionId);
  }

  async checkAvailability() {
    // Skip real execution in test environment
    if (process.env.NODE_ENV === 'test') {
      return true;
    }

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
      skipPermissions = false,
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
          skipPermissions,
        });
      } else {
        return await this.sendOneTimePrompt(sanitizedPrompt, {
          format: validatedFormat,
          workingDirectory: validatedWorkingDir,
          skipPermissions,
        });
      }
    } catch (error) {
      console.error('Error sending prompt to AICLI Code:', error);
      throw new Error(`AICLI Code execution failed: ${error.message}`);
    }
  }

  async sendOneTimePrompt(
    prompt,
    { format = 'json', workingDirectory = process.cwd(), skipPermissions = false }
  ) {
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

    const args = ['--output-format', validatedFormat];

    // Add permission flags before the prompt
    if (skipPermissions || this.skipPermissions) {
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

      // No timeout - trust Claude CLI
      aicliProcess.on('close', () => {
        // Process closed
      });
    });
  }

  async sendStreamingPrompt(
    prompt,
    { sessionId, workingDirectory = process.cwd(), skipPermissions = false }
  ) {
    // Validate inputs
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);
    const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);

    console.log(
      `🌊 sendStreamingPrompt called with sessionId: ${sessionId || 'none (fresh chat)'}`
    );

    // If sessionId provided, check if it exists
    if (sessionId && this.sessionManager.hasSession(sessionId)) {
      console.log(`📋 Found existing session ${sessionId}, sending to existing session`);
      return this.sendToExistingSession(sessionId, sanitizedPrompt);
    }

    // If sessionId was provided but session doesn't exist, it might be a Claude session
    // that the server doesn't know about yet
    if (sessionId) {
      console.log(
        `⚠️ Session ${sessionId} not found locally - will attempt to use with Claude CLI`
      );
    }

    // For fresh chats (no sessionId) or unknown sessions, let Claude handle session creation
    console.log(
      `🚀 Sending prompt to Claude CLI ${sessionId ? `with session ${sessionId}` : 'without session (fresh chat)'}`
    );
    return this.sendPromptToClaude(
      sanitizedPrompt,
      validatedWorkingDir,
      skipPermissions,
      sessionId // Pass through the session ID if provided, or undefined for fresh chats
    );
  }

  async sendPromptToClaude(prompt, workingDirectory, _skipPermissions = false, sessionId = null) {
    // Create a minimal session object for Claude CLI
    const session = {
      sessionId: sessionId || null, // null for fresh chats
      workingDirectory,
      conversationStarted: !!sessionId, // true if we have a session ID
      initialPrompt: sessionId ? null : prompt, // Only set for new sessions
      isRestoredSession: false,
    };

    // If we have a session ID, register it temporarily for response routing
    if (sessionId) {
      // Create minimal session tracking for response routing only
      await this.sessionManager.trackSessionForRouting(sessionId, workingDirectory);
    }

    try {
      // Mark session as processing if tracked
      if (sessionId) {
        this.sessionManager.setSessionProcessing(sessionId, true);
      }

      // Execute the command - Claude will handle session creation/continuation
      const response = await this.executeAICLICommand(session, prompt);

      // Mark processing as complete if tracked
      if (sessionId) {
        this.sessionManager.setSessionProcessing(sessionId, false);
      }

      // Extract session ID from Claude's response if available
      let extractedSessionId = sessionId;
      if (!sessionId && response && response.session_id) {
        extractedSessionId = response.session_id;
        console.log(`🔑 Extracted session ID from Claude response: ${extractedSessionId}`);
      }

      if (!extractedSessionId) {
        console.warn(`⚠️ No session ID available - messages may not persist`);
      }

      return {
        sessionId: extractedSessionId || null,
        success: true,
        response,
      };
    } catch (error) {
      console.error(`❌ Failed to execute prompt:`, error);
      if (sessionId) {
        this.sessionManager.setSessionProcessing(sessionId, false);
      }

      return {
        sessionId: sessionId || null,
        success: false,
        error: error.message,
      };
    }
  }

  async createInteractiveSession(
    sessionId,
    initialPrompt,
    workingDirectory,
    skipPermissions = false
  ) {
    // First create the session metadata
    const sessionResult = await this.sessionManager.createInteractiveSession(
      sessionId,
      initialPrompt,
      workingDirectory,
      { skipPermissions }
    );

    // If session was created successfully, execute the initial prompt
    if (sessionResult.success && initialPrompt) {
      console.log(`🚀 Executing initial prompt for new session ${sessionId}`);

      // Get the created session
      const session = await this.sessionManager.getSession(sessionId);
      if (session) {
        try {
          // Mark session as processing
          this.sessionManager.setSessionProcessing(sessionId, true);

          // Execute the initial prompt
          const response = await this.executeAICLICommand(session, initialPrompt);

          // Mark processing as complete
          this.sessionManager.setSessionProcessing(sessionId, false);

          return {
            sessionId,
            success: true,
            response,
          };
        } catch (error) {
          console.error(`❌ Failed to execute initial prompt:`, error);
          this.sessionManager.setSessionProcessing(sessionId, false);

          return {
            sessionId,
            success: false,
            error: error.message,
          };
        }
      }
    }

    // Return original result if no prompt to execute
    return sessionResult;
  }

  async sendToExistingSession(sessionId, prompt) {
    // Validate inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);

    if (!sanitizedSessionId) {
      throw new Error('Invalid session ID');
    }

    const session = await this.sessionManager.getSession(sanitizedSessionId);

    if (!session || !session.isActive) {
      throw new Error(`Session ${sanitizedSessionId} not found or inactive`);
    }

    try {
      // Update activity and processing state
      await this.sessionManager.updateSessionActivity(sanitizedSessionId);
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
    try {
      // Delegate to process runner
      const result = await this.processRunner.executeAICLICommand(session, prompt);

      // Mark conversation as started AFTER successful first command
      if (!session.conversationStarted) {
        await this.sessionManager.markConversationStarted(session.sessionId);
      }

      return result;
    } catch (error) {
      // Check if this is a "No conversation found" error
      if (error.message && error.message.includes('No conversation found with session ID')) {
        console.log(
          `⚠️ Claude CLI doesn't have session ${session.sessionId}, creating new session`
        );

        // Mark conversation as not started to force new session creation
        session.conversationStarted = false;
        session.isRestoredSession = false;

        // Retry without session ID (will create new session in Claude)
        try {
          const result = await this.processRunner.executeAICLICommand(session, prompt);

          // Mark conversation as started after successful creation
          await this.sessionManager.markConversationStarted(session.sessionId);

          return result;
        } catch (retryError) {
          console.error(`❌ Failed to create new session after retry:`, retryError);
          throw retryError;
        }
      }

      // Re-throw other errors
      throw error;
    }
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

  async emitAICLIResponse(sessionId, response, _isComplete = false, options = {}) {
    const buffer = this.sessionManager.getSessionBuffer(sessionId);
    if (!buffer) {
      console.warn(`No message buffer found for session ${sessionId}`);
      return;
    }

    // Use extracted message handler for pure business logic
    const result = AICLIMessageHandler.processResponse(response, buffer, options);

    // Persist buffer after processing if messages were added
    if (result.action === 'buffer' || result.action === 'tool_use') {
      // Messages were added to buffer, persist them
      await sessionPersistence.saveMessageBuffer(sessionId, buffer);
    }

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
        await this.handleFinalResultEmission(sessionId, result.data, options);
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

  async handleFinalResultEmission(sessionId, resultData, _options = {}) {
    const { response, buffer, aggregatedContent, sendAggregated, embeddedPermission } = resultData;

    // Extract Claude's session ID from buffer if available
    const claudeSessionId = buffer.claudeSessionId || response.session_id;

    if (claudeSessionId && claudeSessionId !== sessionId) {
      console.log(
        `🔄 Claude CLI returned different session ID: ${claudeSessionId} (was: ${sessionId})`
      );
    }

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
          claudeSessionId,
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
      // Send regular conversation result with Claude's session ID
      this.emit('conversationResult', {
        sessionId,
        data: {
          type: 'final_result',
          success: !response.is_error,
          sessionId: claudeSessionId || response.session_id,
          claudeSessionId,
          duration: response.duration_ms,
          cost: response.total_cost_usd,
          usage: response.usage,
          timestamp: new Date().toISOString(),
        },
      });
    }

    // Persist buffer one final time before clearing
    await sessionPersistence.saveMessageBuffer(sessionId, buffer);

    // Clear the buffer for next command
    AICLIMessageHandler.clearSessionBuffer(buffer);
  }

  // Old handler methods removed - message processing now handled by AICLIMessageHandler via emitAICLIResponse

  // Message handling methods moved to AICLIMessageHandler - using proxy methods below for backward compatibility

  clearSessionBuffer(sessionId) {
    // Clear in session manager's buffer
    if (this.sessionManager?.sessionMessageBuffers?.has(sessionId)) {
      const buffer = this.sessionManager.sessionMessageBuffers.get(sessionId);
      if (buffer && typeof buffer === 'object') {
        buffer.assistantMessages = [];
        buffer.permissionRequestSent = false;
        buffer.toolUseInProgress = false;
        buffer.permissionRequests = [];
        buffer.deliverables = [];
      }
    }

    // Also delegate to session manager's method if it exists
    if (this.sessionManager?.clearSessionBuffer) {
      this.sessionManager.clearSessionBuffer(sessionId);
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
    return this.sessionManager.closeSession(sessionId);
  }

  hasSession(sessionId) {
    return this.sessionManager.hasSession(sessionId);
  }

  getSession(sessionId) {
    return this.sessionManager.getSession(sessionId);
  }

  getActiveSessions() {
    return this.sessionManager.getActiveSessions();
  }

  async markSessionBackgrounded(sessionId) {
    return this.sessionManager.markSessionBackgrounded(sessionId);
  }

  async markSessionForegrounded(sessionId) {
    return this.sessionManager.markSessionForegrounded(sessionId);
  }

  // Startup cleanup to handle stale Claude CLI sessions
  async performStartupCleanup() {
    // Skip real execution in test environment
    if (process.env.NODE_ENV === 'test') {
      console.log('🧹 Skipping startup cleanup in test environment');
      return;
    }

    console.log('🧹 Performing startup cleanup...');

    try {
      // Check if Claude CLI has any active sessions that might conflict
      const { stdout } = await execAsync(
        'claude --list-sessions 2>/dev/null || echo "no-sessions"'
      );

      if (stdout && stdout.trim() !== 'no-sessions' && !stdout.includes('No active sessions')) {
        console.log('🔍 Found potential stale Claude CLI sessions, attempting cleanup...');

        // Try to clear any stale sessions
        try {
          await execAsync('claude --clear-sessions 2>/dev/null || true');
          console.log('✅ Cleared stale Claude CLI sessions');
        } catch (clearError) {
          console.warn('⚠️ Could not clear stale sessions, may cause session ID conflicts');
        }
      }

      // Also cleanup any orphaned processes
      await processMonitor.cleanup();

      console.log('✅ Startup cleanup completed');
    } catch (error) {
      // Don't fail startup if cleanup fails
      console.warn('⚠️ Startup cleanup encountered issues:', error.message);
    }
  }

  // Cleanup method for graceful shutdown
  async shutdown() {
    console.log('🔄 Shutting down AICLI Code Service...');

    try {
      // Stop health monitoring
      this.stopProcessHealthMonitoring();

      // Shutdown session manager with timeout
      const shutdownPromise = this.sessionManager.shutdown();
      const timeoutPromise = new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Shutdown timeout')), 10000)
      );

      await Promise.race([shutdownPromise, timeoutPromise]);

      console.log('✅ AICLI Code Service shut down complete');
    } catch (error) {
      console.warn('⚠️ Shutdown completed with warnings:', error.message);
      // Don't throw - we want shutdown to complete even if there are issues
    }
  }

  async healthCheck() {
    try {
      const isAvailable = await this.checkAvailability();

      // Get system resources
      const systemResources = await processMonitor.getSystemResources();

      // Get active sessions count
      const activeSessionIds = this.getActiveSessions();
      const sessionCount = activeSessionIds.length;

      return {
        status: isAvailable ? 'healthy' : 'degraded',
        aicliCodeAvailable: isAvailable,
        activeSessions: activeSessionIds,
        sessionCount,
        resources: {
          system: systemResources,
          sessions: [], // No process metrics since sessions don't have processes
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
    const session = this.sessionManager.getSession(sessionId);
    if (!session) {
      return null;
    }
    const now = Date.now();
    const lastActivity = session.lastActivity || session.createdAt;
    if (!lastActivity) {
      // No activity recorded - consider inactive
      return {
        sessionId,
        isActive: false,
        timeSinceLastActivity: Infinity,
        lastActivity: null,
      };
    }
    const timeSinceLastActivity = now - lastActivity;
    const isActive = timeSinceLastActivity < 30 * 60 * 1000; // 30 minutes
    return {
      sessionId,
      isActive,
      timeSinceLastActivity,
      lastActivity,
    };
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
          claudeSessionId: message.session_id, // Claude's actual session ID
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

  isPermissionPrompt(message) {
    return MessageProcessor.isPermissionPrompt(message);
  }
}
