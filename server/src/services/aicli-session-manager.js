/**
 * AICLI Session Manager
 * Re-exports the refactored modular implementation
 */

export { AICLISessionManager } from './aicli-session-manager/index.js';
export { SessionStorage } from './aicli-session-manager/session-storage.js';
export { SessionMonitor } from './aicli-session-manager/session-monitor.js';
export { SessionLifecycle } from './aicli-session-manager/session-lifecycle.js';
export { SessionRouter } from './aicli-session-manager/session-router.js';
export { MessageBufferManager } from './aicli-session-manager/message-buffer-manager.js';
export { ResourceManager } from './aicli-session-manager/resource-manager.js';

// Default export for backward compatibility
export { AICLISessionManager as default } from './aicli-session-manager/index.js';
