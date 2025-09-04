import { exec } from 'child_process';
import { promisify } from 'util';
import { EventEmitter } from 'events';
import { InputValidator, AICLIConfig } from '../aicli-utils.js';
import { AICLISessionManager } from '../aicli-session-manager.js';
import { AICLIProcessRunner } from '../aicli-process-runner.js';
import { AICLIValidationService } from '../aicli-validation-service.js';
import { createLogger } from '../../utils/logger.js';

// Import extracted modules
import { MessageClassifier } from './message-classifier.js';
import { PermissionHandler } from '../aicli-process-runner/permission-handler.js';
import { AttachmentProcessor } from './attachment-processor.js';
import { ResponseEmitter } from './response-emitter.js';
import { HealthMonitor } from './health-monitor.js';
import { SessionOperations } from './session-operations.js';
import { OneTimePrompt } from './one-time-prompt.js';

const execAsync = promisify(exec);
const logger = createLogger('AICLIService');

export class AICLIService extends EventEmitter {
  constructor(options = {}) {
    super();

    // Initialize session manager
    this.sessionManager =
      options.sessionManager ||
      new AICLISessionManager({
        sessionTimeout: 24 * 60 * 60 * 1000, // 24 hours - matches Claude CLI's session lifetime
      });

    // Initialize process runner with dependency injection support
    this.processRunner =
      options.processRunner || new AICLIProcessRunner(options.processRunnerOptions);

    // Initialize extracted handlers
    this.permissionHandler = new PermissionHandler(this.processRunner.config);
    this.responseEmitter = new ResponseEmitter(this.sessionManager, this);
    this.healthMonitor = new HealthMonitor(this.sessionManager, this);
    this.sessionOperations = new SessionOperations(this.sessionManager, this.processRunner, this);
    this.oneTimePrompt = new OneTimePrompt(this.permissionHandler);
    this.oneTimePrompt.setAicliCommand(this.aicliCommand);

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
          console.warn('⚠️ Failed to cleanup dead session %s:', data.sessionId, error.message);
        });
      }
      this.emit('processExit', data);
    });

    this.processRunner.on('processStderr', (data) => {
      this.emit('processStderr', data);
    });

    this.processRunner.on('aicliResponse', async (data) => {
      // Process final results (we now only emit one event per response)
      await this.responseEmitter.emitAICLIResponse(data.sessionId, data.response, data.isLast);
    });

    // Configuration (will be delegated to appropriate managers)
    this.aicliCommand = this.processRunner.aicliCommand;
    this.defaultWorkingDirectory = process.cwd();
    this.safeRootDirectory = null; // Will be set from server config

    // Forward security violations from process runner
    this.processRunner.on('securityViolation', (data) => {
      this.emit('securityViolation', data);
    });

    // Legacy permission properties (delegated to permission handler)
    this.permissionMode = this.permissionHandler.permissionMode;
    this.allowedTools = this.permissionHandler.allowedTools;
    this.disallowedTools = this.permissionHandler.disallowedTools;
    this.skipPermissions = this.permissionHandler.skipPermissions;

    // Process monitoring
    this.healthMonitor.setCheckAvailabilityFn(this.checkAvailability.bind(this));
    this.healthMonitor.startProcessHealthMonitoring();
  }

  // Configure permission settings (delegated to permission handler)
  setPermissionMode(mode) {
    this.permissionHandler.setPermissionMode(mode);
    this.permissionMode = this.permissionHandler.permissionMode;
  }

  setAllowedTools(tools) {
    this.permissionHandler.setAllowedTools(tools);
    this.allowedTools = this.permissionHandler.allowedTools;
  }

  setDisallowedTools(tools) {
    this.permissionHandler.setDisallowedTools(tools);
    this.disallowedTools = this.permissionHandler.disallowedTools;
  }

  setSafeRootDirectory(dir) {
    this.safeRootDirectory = dir;
  }

  setSkipPermissions(skip) {
    this.permissionHandler.setSkipPermissions(skip);
    this.skipPermissions = this.permissionHandler.skipPermissions;
  }

  // Process health monitoring (delegated to HealthMonitor)
  startProcessHealthMonitoring() {
    return this.healthMonitor.startProcessHealthMonitoring();
  }

  stopProcessHealthMonitoring() {
    return this.healthMonitor.stopProcessHealthMonitoring();
  }

  async checkAllProcessHealth() {
    return this.healthMonitor.checkAllProcessHealth();
  }

  async cleanupDeadSession(sessionId) {
    return this.sessionManager.cleanupDeadSession(sessionId);
  }

  async checkAvailability() {
    // Skip in test environment
    if (process.env.NODE_ENV === 'test') {
      return { available: true, version: 'test' };
    }

    // Get the AICLI command - now returns a string fallback immediately
    const aicliPath = this.aicliCommand || (await AICLIConfig.findAICLICommand());
    try {
      const { stdout } = await execAsync(`"${aicliPath}" --version`);
      return {
        available: true,
        version: stdout.trim(),
        path: aicliPath,
      };
    } catch (error) {
      logger.error('AICLI availability check failed:', error);
      return {
        available: false,
        error: error.message,
      };
    }
  }

  isAvailable() {
    return this.checkAvailability()
      .then((result) => result.available)
      .catch(() => false);
  }

  /**
   * Process attachments by creating temporary files
   * @param {Array} attachments - Array of attachment objects with base64 data
   * @returns {Object} Object with filePaths and cleanup function
   */
  async processAttachments(attachments) {
    return AttachmentProcessor.processAttachments(attachments);
  }

  async sendPrompt(prompt, options = {}) {
    const {
      sessionId = null,
      streaming = true,
      skipPermissions = false,
      attachments = null,
    } = options;

    // Process attachments first
    let attachmentData = { filePaths: [], cleanup: () => {} };
    try {
      if (attachments && attachments.length > 0) {
        console.log(`📎 Processing ${attachments.length} attachment(s)`);
        attachmentData = await this.processAttachments(attachments);
      }

      // Validate input
      const validationResult = InputValidator.validateInput(prompt);
      if (!validationResult.isValid) {
        throw new Error(`Invalid input: ${validationResult.error}`);
      }

      const processedPrompt = validationResult.processedPrompt;

      // Build enhanced prompt with attachment references
      const enhancedPrompt = AttachmentProcessor.buildEnhancedPrompt(
        processedPrompt,
        attachmentData.filePaths
      );

      if (streaming) {
        return await this.sendStreamingPrompt(enhancedPrompt, {
          sessionId,
          skipPermissions,
          attachmentPaths: attachmentData.filePaths, // Pass file paths
          workingDirectory: options.workingDirectory || this.defaultWorkingDirectory,
        });
      } else {
        return await this.sendOneTimePrompt(enhancedPrompt, {
          ...options,
          skipPermissions,
          attachmentPaths: attachmentData.filePaths, // Pass file paths
        });
      }
    } finally {
      // Clean up temp files
      await attachmentData.cleanup();
    }
  }

  async sendOneTimePrompt(prompt, options) {
    return this.oneTimePrompt.sendOneTimePrompt(prompt, options);
  }

  async sendStreamingPrompt(prompt, options) {
    return this.sessionOperations.sendStreamingPrompt(prompt, options);
  }

  async sendPromptToClaude(prompt, options) {
    return this.sessionOperations.sendPromptToClaude(prompt, {
      ...options,
      defaultWorkingDirectory: this.defaultWorkingDirectory,
    });
  }

  // Message classification (delegated to MessageClassifier)
  classifyAICLIMessage(message) {
    return MessageClassifier.classifyAICLIMessage(message);
  }

  handleSystemMessage(message) {
    return MessageClassifier.handleSystemMessage(message);
  }

  handleAssistantMessage(message) {
    return MessageClassifier.handleAssistantMessage(message);
  }

  handleResultMessage(message) {
    return MessageClassifier.handleResultMessage(message);
  }

  handleToolUseMessage(message) {
    return MessageClassifier.handleToolUseMessage(message);
  }

  handleToolResultMessage(message) {
    return MessageClassifier.handleToolResultMessage(message);
  }

  // Permission handling (delegated to PermissionHandler)
  async handlePermissionPrompt(sessionId, response) {
    return this.permissionHandler.handlePermissionPrompt(
      sessionId,
      response,
      this.sessionManager,
      this.emit.bind(this)
    );
  }

  containsPermissionRequest(content) {
    return MessageClassifier.containsPermissionRequest(content);
  }

  containsToolUse(content) {
    return MessageClassifier.containsToolUse(content);
  }

  containsApprovalResponse(text) {
    return this.permissionHandler.containsApprovalResponse(text);
  }

  // Response emission (delegated to ResponseEmitter)
  async emitAICLIResponse(sessionId, response, isComplete, options) {
    return this.responseEmitter.emitAICLIResponse(sessionId, response, isComplete, options);
  }

  async emitDeferredResult(sessionId) {
    return this.responseEmitter.emitDeferredResult(sessionId);
  }

  async handleFinalResultEmission(sessionId, data, options) {
    return this.responseEmitter.handleFinalResultEmission(sessionId, data, options);
  }

  getSessionBuffer(sessionId) {
    return this.responseEmitter.getSessionBuffer(sessionId);
  }

  clearSessionBuffer(sessionId) {
    return this.responseEmitter.clearSessionBuffer(sessionId);
  }

  // Utility methods (delegated to MessageClassifier)
  extractCodeBlocks(content) {
    return MessageClassifier.extractCodeBlocks(content);
  }

  aggregateBufferedContent(buffer) {
    return MessageClassifier.aggregateBufferedContent(buffer);
  }

  extractPermissionPrompt(text) {
    return MessageClassifier.extractPermissionPrompt(text);
  }

  extractPermissionPromptFromMessage(message) {
    return MessageClassifier.extractPermissionPromptFromMessage(message);
  }

  extractTextFromMessage(message) {
    return MessageClassifier.extractTextFromMessage(message);
  }

  // Delegate validation methods to AICLIValidationService
  isValidCompleteJSON(jsonString) {
    return AICLIValidationService.isValidCompleteJSON(jsonString);
  }

  parseStreamJsonOutput(output) {
    return AICLIValidationService.parseStreamJsonOutput(output);
  }

  async executeAICLICommand(session, prompt, attachmentPaths = [], retryCount = 3) {
    return this.sessionOperations.executeAICLICommand(session, prompt, attachmentPaths, retryCount);
  }

  // Session management methods (delegated to SessionOperations)
  async closeSession(sessionId) {
    return this.sessionOperations.closeSession(sessionId);
  }

  async killSession(sessionId, reason = 'User requested cancellation') {
    return this.sessionOperations.killSession(sessionId, reason);
  }

  hasSession(sessionId) {
    return this.sessionOperations.hasSession(sessionId);
  }

  getSession(sessionId) {
    return this.sessionOperations.getSession(sessionId);
  }

  getActiveSessions() {
    return this.sessionOperations.getActiveSessions();
  }

  async markSessionBackgrounded(sessionId, reason = null, metadata = {}) {
    return this.sessionOperations.markSessionBackgrounded(sessionId, reason, metadata);
  }

  async markSessionForegrounded(sessionId, metadata = {}) {
    return this.sessionOperations.markSessionForegrounded(sessionId, metadata);
  }

  // Lifecycle management
  async performStartupCleanup() {
    console.log('🧹 Performing startup cleanup...');
    await this.sessionManager.cleanupAllSessions();
  }

  async shutdown() {
    console.log('🛑 Shutting down AICLI service...');

    this.healthMonitor.stopProcessHealthMonitoring();

    // Give sessions time to clean up gracefully
    // Use shorter timeout in test environment
    const timeoutMs = process.env.NODE_ENV === 'test' ? 1000 : 10000;
    await Promise.race([
      this.sessionManager.cleanupAllSessions(),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error('Shutdown timeout')), timeoutMs)
      ),
    ]).catch((error) => {
      // Ignore timeout errors in test mode - just continue with cleanup
      if (process.env.NODE_ENV !== 'test') {
        throw error;
      }
    });

    // Remove all listeners
    this.removeAllListeners();

    console.log('✅ AICLI service shutdown complete');
  }

  async healthCheck() {
    return this.healthMonitor.healthCheck();
  }

  checkSessionTimeout(sessionId) {
    return this.healthMonitor.checkSessionTimeout(sessionId);
  }
}
