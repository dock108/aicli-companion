/**
 * AICLI Process Runner
 * Re-exports the refactored modular implementation
 */

export { AICLIProcessRunner } from './aicli-process-runner/index.js';
export { ProcessManager } from './aicli-process-runner/process-manager.js';
export { InteractiveSession } from './aicli-process-runner/interactive-session.js';
export { CommandExecutor } from './aicli-process-runner/command-executor.js';
export { PermissionHandler } from './aicli-process-runner/permission-handler.js';
export { OutputProcessor } from './aicli-process-runner/output-processor.js';
export { HealthMonitor } from './aicli-process-runner/health-monitor.js';
export { AICLIConfig } from './aicli-process-runner/config.js';

// Default export for backward compatibility
export { AICLIProcessRunner as default } from './aicli-process-runner/index.js';
