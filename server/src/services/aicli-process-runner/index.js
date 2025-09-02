/**
 * AICLI Process Runner
 * Main entry point for process execution and management
 */

import { EventEmitter } from 'events';
import { ProcessManager } from './process-manager.js';
import { InteractiveSession } from './interactive-session.js';
import { CommandExecutor } from './command-executor.js';
import { PermissionHandler } from './permission-handler.js';
import { OutputProcessor } from './output-processor.js';
import { HealthMonitor } from './health-monitor.js';
import { AICLIConfig } from './config.js';

// Logger will be created in components that need it

export class AICLIProcessRunner extends EventEmitter {
  constructor(options = {}) {
    super();

    // Initialize configuration
    this.config = new AICLIConfig(options);

    // Initialize components
    this.processManager = new ProcessManager(this.config, options.spawnFunction);
    this.interactiveSession = new InteractiveSession(this.processManager, this.config);
    this.commandExecutor = new CommandExecutor(this.processManager, this.config);
    this.permissionHandler = new PermissionHandler(this.config);
    this.outputProcessor = new OutputProcessor();
    this.healthMonitor = new HealthMonitor();

    // Forward events from components
    this.setupEventForwarding();
  }

  // Getters for backward compatibility
  get aicliCommand() {
    return this.config.aicliCommand;
  }

  get allowedTools() {
    return this.config.allowedTools;
  }

  get disallowedTools() {
    return this.config.disallowedTools;
  }

  get skipPermissions() {
    return this.config.skipPermissions;
  }

  setupEventForwarding() {
    // Forward process manager events
    this.processManager.on('processStarted', (data) => this.emit('processStarted', data));
    this.processManager.on('processExited', (data) => this.emit('processExited', data));
    this.processManager.on('processError', (data) => this.emit('processError', data));

    // Forward health monitor events
    this.healthMonitor.on('heartbeat', (data) => this.emit('heartbeat', data));
    this.healthMonitor.on('healthCheck', (data) => this.emit('healthCheck', data));
    // Handle health monitor error events to prevent unhandled errors
    this.healthMonitor.on('error', (data) => this.emit('healthMonitorError', data));
    this.healthMonitor.on('activity', (data) => this.emit('healthMonitorActivity', data));
    this.healthMonitor.on('timeout', (data) => this.emit('healthMonitorTimeout', data));
    this.healthMonitor.on('rateLimitDetected', (data) => this.emit('rateLimitDetected', data));
    this.healthMonitor.on('sessionExpired', (data) => this.emit('sessionExpired', data));

    // Forward permission events
    this.permissionHandler.on('permissionRequired', (data) =>
      this.emit('permissionRequired', data)
    );
    this.permissionHandler.on('permissionGranted', (data) => this.emit('permissionGranted', data));
    this.permissionHandler.on('permissionDenied', (data) => this.emit('permissionDenied', data));
  }

  // Delegation methods for backward compatibility
  setPermissionMode(mode) {
    return this.permissionHandler.setPermissionMode(mode);
  }

  setAllowedTools(tools) {
    return this.permissionHandler.setAllowedTools(tools);
  }

  setDisallowedTools(tools) {
    return this.permissionHandler.setDisallowedTools(tools);
  }

  setSkipPermissions(skip) {
    return this.permissionHandler.setSkipPermissions(skip);
  }

  async validateToolUse(toolName, toolInput, sessionId) {
    return this.permissionHandler.validateToolUse(toolName, toolInput, sessionId);
  }

  async createInteractiveSession(workingDirectory) {
    return this.interactiveSession.create(workingDirectory);
  }

  async sendToInteractiveSession(sessionInfo, message) {
    return this.interactiveSession.sendMessage(sessionInfo, message);
  }

  async executeAICLICommand(session, prompt, attachmentPaths = []) {
    return this.commandExecutor.execute(session, prompt, attachmentPaths);
  }

  async killProcess(sessionId, reason = 'User requested cancellation') {
    return this.processManager.killProcess(sessionId, reason);
  }

  getActiveProcessCount() {
    return this.processManager.getActiveProcessCount();
  }

  hasActiveProcess(sessionId) {
    return this.processManager.hasActiveProcess(sessionId);
  }

  findAICLICommand() {
    return this.config.findAICLICommand();
  }

  async testAICLICommand(testType = 'version') {
    return this.config.testAICLICommand(testType);
  }

  addPermissionArgs(args) {
    return this.config.addPermissionArgs(args);
  }

  broadcastHeartbeat(data) {
    this.emit('heartbeat', data);
  }

  // Backward compatibility for tests
  createHealthMonitor(aicliProcess, sessionId, workingDirectory, requestId, deviceToken) {
    const monitor = this.healthMonitor.createForProcess(
      aicliProcess,
      sessionId,
      workingDirectory,
      requestId,
      deviceToken
    );

    // Add backward compatible methods
    monitor.recordActivity = () => {};
    monitor.cleanup = () => monitor.stop();

    return monitor;
  }
}

// Export for backward compatibility
export default AICLIProcessRunner;
