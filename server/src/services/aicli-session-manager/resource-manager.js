/**
 * Resource Manager
 * Manages resource usage and limits for sessions
 */

import os from 'os';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('ResourceManager');

export class ResourceManager {
  constructor(storage, config) {
    this.storage = storage;
    this.config = config;
  }

  /**
   * Check overall resource usage
   */
  checkUsage() {
    const usage = this.getSystemStatus();
    const violations = [];

    // Check concurrent sessions
    if (this.storage.getActiveSessions().length >= this.config.maxConcurrentSessions) {
      violations.push({
        type: 'concurrent_sessions',
        current: this.storage.getActiveSessions().length,
        limit: this.config.maxConcurrentSessions,
      });
    }

    // Check memory usage
    const memoryUsage = process.memoryUsage();
    if (memoryUsage.heapUsed > this.config.maxTotalMemory) {
      violations.push({
        type: 'total_memory',
        current: memoryUsage.heapUsed,
        limit: this.config.maxTotalMemory,
      });
    }

    // Check CPU usage
    if (usage.cpuUsage > this.config.maxCpuUsage) {
      violations.push({
        type: 'cpu_usage',
        current: usage.cpuUsage,
        limit: this.config.maxCpuUsage,
      });
    }

    if (violations.length > 0) {
      logger.warn('Resource violations detected', { violations });

      // Take action on violations
      this.handleResourceViolations(violations);
    }

    return {
      usage,
      violations,
      healthy: violations.length === 0,
    };
  }

  /**
   * Handle resource violations
   */
  handleResourceViolations(violations) {
    for (const violation of violations) {
      switch (violation.type) {
        case 'concurrent_sessions':
          this.handleConcurrentSessionViolation();
          break;
        case 'total_memory':
          this.handleMemoryViolation();
          break;
        case 'cpu_usage':
          this.handleCpuViolation();
          break;
      }
    }
  }

  /**
   * Handle concurrent session limit violation
   */
  handleConcurrentSessionViolation() {
    logger.warn('Concurrent session limit reached', {
      current: this.storage.getActiveSessions().length,
      limit: this.config.maxConcurrentSessions,
    });

    // Find and clean up the oldest inactive session
    const sessions = this.storage.getActiveSessions();
    const now = Date.now();

    let oldestSession = null;
    let oldestInactivity = 0;

    for (const session of sessions) {
      const inactivity = now - (session.lastActivity || session.createdAt);
      if (inactivity > oldestInactivity) {
        oldestInactivity = inactivity;
        oldestSession = session;
      }
    }

    if (oldestSession && oldestInactivity > 60000) {
      // Inactive for > 1 minute
      logger.info('Cleaning up oldest inactive session', {
        sessionId: oldestSession.sessionId,
        inactivity: oldestInactivity,
      });
      // Emit cleanup event - let the lifecycle manager handle it
      this.storage.removeActiveSession(oldestSession.sessionId);
    }
  }

  /**
   * Handle memory violation
   */
  handleMemoryViolation() {
    logger.warn('Memory limit exceeded', {
      current: process.memoryUsage().heapUsed,
      limit: this.config.maxTotalMemory,
    });

    // Force garbage collection if available
    if (global.gc) {
      global.gc();
      logger.info('Forced garbage collection');
    }

    // Clear old message buffers
    this.clearOldMessageBuffers();
  }

  /**
   * Handle CPU violation
   */
  handleCpuViolation() {
    logger.warn('CPU usage too high', {
      current: this.getCpuUsage(),
      limit: this.config.maxCpuUsage,
    });

    // Pause processing for a moment
    // This is handled by emitting an event that the queue manager can listen to
  }

  /**
   * Clear old message buffers to free memory
   */
  clearOldMessageBuffers() {
    const now = Date.now();
    const sessions = this.storage.getActiveSessions();
    let clearedCount = 0;

    for (const session of sessions) {
      const inactivity = now - (session.lastActivity || session.createdAt);

      // Clear buffers for sessions inactive > 1 hour
      if (inactivity > 3600000) {
        const buffer = this.storage.getMessageBuffer(session.sessionId);
        if (buffer) {
          // Keep only recent messages
          const recentThreshold = 10;
          if (buffer.userMessages.length > recentThreshold) {
            buffer.userMessages = buffer.userMessages.slice(-recentThreshold);
            clearedCount++;
          }
          if (buffer.assistantMessages.length > recentThreshold) {
            buffer.assistantMessages = buffer.assistantMessages.slice(-recentThreshold);
            clearedCount++;
          }
        }
      }
    }

    if (clearedCount > 0) {
      logger.info('Cleared old message buffers', { count: clearedCount });
    }
  }

  /**
   * Get session status including resource usage
   */
  getSessionStatus(sessionId) {
    const session = this.storage.getSession(sessionId);
    if (!session) {
      return null;
    }

    const buffer = this.storage.getMessageBuffer(sessionId);
    const bufferSize = this.estimateBufferSize(buffer);

    return {
      sessionId,
      active: true,
      createdAt: new Date(session.createdAt).toISOString(),
      lastActivity: new Date(session.lastActivity || session.createdAt).toISOString(),
      memoryUsage: bufferSize,
      messageCount: buffer ? buffer.userMessages.length + buffer.assistantMessages.length : 0,
      hasInteractiveProcess: this.storage.hasInteractiveSession(sessionId),
    };
  }

  /**
   * Get system resource status
   */
  getSystemStatus() {
    const memoryUsage = process.memoryUsage();
    const cpuUsage = this.getCpuUsage();

    return {
      activeSessions: this.storage.getActiveSessions().length,
      totalSessions: this.storage.getAllActiveSessions().size,
      memoryUsage: {
        heapUsed: memoryUsage.heapUsed,
        heapTotal: memoryUsage.heapTotal,
        external: memoryUsage.external,
        rss: memoryUsage.rss,
      },
      cpuUsage,
      limits: {
        maxConcurrentSessions: this.config.maxConcurrentSessions,
        maxMemoryPerSession: this.config.maxMemoryPerSession,
        maxTotalMemory: this.config.maxTotalMemory,
        maxCpuUsage: this.config.maxCpuUsage,
      },
    };
  }

  /**
   * Estimate buffer size in bytes
   */
  estimateBufferSize(buffer) {
    if (!buffer) return 0;

    let size = 0;

    // Estimate message sizes
    for (const msg of buffer.userMessages || []) {
      size += JSON.stringify(msg).length * 2; // Approximate UTF-16
    }
    for (const msg of buffer.assistantMessages || []) {
      size += JSON.stringify(msg).length * 2;
    }

    return size;
  }

  /**
   * Get CPU usage percentage
   */
  getCpuUsage() {
    const cpus = os.cpus();
    let totalIdle = 0;
    let totalTick = 0;

    for (const cpu of cpus) {
      for (const type in cpu.times) {
        totalTick += cpu.times[type];
      }
      totalIdle += cpu.times.idle;
    }

    const idle = totalIdle / cpus.length;
    const total = totalTick / cpus.length;
    const usage = 100 - ~~((100 * idle) / total);

    return usage;
  }
}

export default ResourceManager;
