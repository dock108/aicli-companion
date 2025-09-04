/**
 * Health Monitor
 * Monitors process health and emits heartbeat events
 */

import { EventEmitter } from 'events';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('HealthMonitor');

export class HealthMonitor extends EventEmitter {
  constructor() {
    super();
    this.activeMonitors = new Map();
  }

  /**
   * Create a health monitor for a specific process
   */
  createForProcess(aicliProcess, sessionId, workingDirectory, requestId, deviceToken) {
    const monitor = new ProcessHealthMonitor(
      aicliProcess,
      sessionId,
      workingDirectory,
      requestId,
      deviceToken,
      this
    );

    this.activeMonitors.set(sessionId, monitor);
    return monitor;
  }

  /**
   * Stop monitoring a session
   */
  stopMonitoring(sessionId) {
    const monitor = this.activeMonitors.get(sessionId);
    if (monitor) {
      monitor.stop();
      this.activeMonitors.delete(sessionId);
    }
  }

  /**
   * Stop all monitors
   */
  stopAll() {
    for (const monitor of this.activeMonitors.values()) {
      monitor.stop();
    }
    this.activeMonitors.clear();
  }
}

/**
 * Individual process health monitor
 */
class ProcessHealthMonitor {
  constructor(aicliProcess, sessionId, workingDirectory, requestId, deviceToken, parent) {
    this.aicliProcess = aicliProcess;
    this.sessionId = sessionId;
    this.workingDirectory = workingDirectory;
    this.requestId = requestId;
    this.deviceToken = deviceToken;
    this.parent = parent;
    this.heartbeatInterval = null;
    this.lastActivity = Date.now();
    this.messageCount = 0;
    this.toolUseCount = 0;
  }

  /**
   * Start health monitoring
   */
  start() {
    const sessionLogger = logger.child({
      sessionId: this.sessionId,
      requestId: this.requestId,
    });

    // Skip if no process to monitor
    if (!this.aicliProcess) {
      sessionLogger.debug('No process to monitor');
      return;
    }

    // Monitor stdout for activity
    this.stdoutHandler = (data) => {
      this.lastActivity = Date.now();
      this.messageCount++;

      const chunk = data.toString();

      // Check for tool use
      if (chunk.includes('tool_use')) {
        this.toolUseCount++;
        sessionLogger.info('Tool use detected in health monitor', {
          toolUseCount: this.toolUseCount,
        });
      }

      // Emit activity event
      this.parent.emit('activity', {
        sessionId: this.sessionId,
        type: 'stdout',
        timestamp: this.lastActivity,
      });
    };

    // Monitor stderr for errors
    this.stderrHandler = (data) => {
      const error = data.toString();
      sessionLogger.warn('Health monitor detected stderr', {
        error: error.substring(0, 200),
      });

      // Check for critical errors
      if (error.includes('rate_limit')) {
        this.parent.emit('rateLimitDetected', {
          sessionId: this.sessionId,
          error,
        });
      } else if (error.includes('session') && error.includes('expired')) {
        this.parent.emit('sessionExpired', {
          sessionId: this.sessionId,
          error,
        });
      }

      // Only emit if parent has listeners for error event
      if (this.parent.listenerCount('error') > 0) {
        this.parent.emit('error', {
          sessionId: this.sessionId,
          type: 'stderr',
          error: error.substring(0, 500),
        });
      }
    };

    // Attach handlers
    if (this.aicliProcess.stdout) {
      this.aicliProcess.stdout.on('data', this.stdoutHandler);
    }
    if (this.aicliProcess.stderr) {
      this.aicliProcess.stderr.on('data', this.stderrHandler);
    }

    // Start heartbeat
    this.heartbeatInterval = setInterval(() => {
      this.sendHeartbeat();
    }, 5000); // Every 5 seconds

    // Send initial heartbeat
    this.sendHeartbeat();

    sessionLogger.info('Health monitoring started', {
      pid: this.aicliProcess.pid,
    });
  }

  /**
   * Send heartbeat event
   */
  sendHeartbeat() {
    const timeSinceLastActivity = Date.now() - this.lastActivity;
    const isActive = timeSinceLastActivity < 30000; // Active if activity within 30s

    const heartbeatData = {
      sessionId: this.sessionId,
      pid: this.aicliProcess.pid,
      workingDirectory: this.workingDirectory,
      requestId: this.requestId,
      deviceToken: this.deviceToken,
      timestamp: Date.now(),
      isActive,
      timeSinceLastActivity,
      messageCount: this.messageCount,
      toolUseCount: this.toolUseCount,
    };

    // Emit heartbeat
    this.parent.emit('heartbeat', heartbeatData);

    // Log heartbeat
    logger.debug('Heartbeat sent', {
      sessionId: this.sessionId,
      isActive,
      messageCount: this.messageCount,
    });

    // Check for timeout
    if (!isActive && timeSinceLastActivity > 60000) {
      logger.warn('Process appears to be hung', {
        sessionId: this.sessionId,
        timeSinceLastActivity,
      });

      this.parent.emit('timeout', {
        sessionId: this.sessionId,
        timeSinceLastActivity,
      });
    }
  }

  /**
   * Stop health monitoring
   */
  stop() {
    // Clear heartbeat interval
    if (this.heartbeatInterval) {
      clearInterval(this.heartbeatInterval);
      this.heartbeatInterval = null;
    }

    // Remove event handlers - check if process exists first
    if (this.aicliProcess) {
      if (this.aicliProcess.stdout && this.stdoutHandler) {
        this.aicliProcess.stdout.removeListener('data', this.stdoutHandler);
      }
      if (this.aicliProcess.stderr && this.stderrHandler) {
        this.aicliProcess.stderr.removeListener('data', this.stderrHandler);
      }
    }

    logger.info('Health monitoring stopped', {
      sessionId: this.sessionId,
      messageCount: this.messageCount,
      toolUseCount: this.toolUseCount,
    });
  }
}

export default HealthMonitor;
