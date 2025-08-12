/**
 * Activity Monitor Service
 *
 * Tracks all Claude operations in real-time
 * Generates security reports and alerts on suspicious patterns
 */

import { EventEmitter } from 'events';
import { createLogger } from '../utils/logger.js';
import fs from 'fs/promises';
import path from 'path';

const logger = createLogger('ActivityMonitor');

export class ActivityMonitor extends EventEmitter {
  constructor(options = {}) {
    super();

    this.activities = [];
    this.sessionActivities = new Map();
    this.suspiciousPatterns = new Map();
    this.alertThresholds = {
      rapidCommands: { count: 10, window: 60000 }, // 10 commands in 1 minute
      failedCommands: { count: 5, window: 300000 }, // 5 failures in 5 minutes
      deletions: { count: 3, window: 60000 }, // 3 deletions in 1 minute
      largeFileOps: { size: 50 * 1024 * 1024, count: 3 }, // 3 files over 50MB
    };

    this.maxActivities = options.maxActivities || 10000;
    this.exportPath = options.exportPath || './logs/activity';
    this.enableAlerts = options.enableAlerts !== false;

    // Statistics
    this.stats = {
      totalCommands: 0,
      blockedCommands: 0,
      allowedCommands: 0,
      fileOperations: 0,
      errors: 0,
      startTime: new Date(),
    };

    // Start periodic analysis
    this.analysisInterval = setInterval(() => {
      this.analyzePatterns();
    }, 60000); // Every minute
  }

  /**
   * Track a new activity
   */
  trackActivity(activity) {
    const entry = {
      id: this.generateActivityId(),
      timestamp: new Date().toISOString(),
      ...activity,
    };

    // Add to general activities
    this.activities.push(entry);

    // Add to session-specific activities
    if (activity.sessionId) {
      if (!this.sessionActivities.has(activity.sessionId)) {
        this.sessionActivities.set(activity.sessionId, []);
      }
      this.sessionActivities.get(activity.sessionId).push(entry);
    }

    // Update statistics
    this.updateStats(entry);

    // Check for suspicious patterns
    if (this.enableAlerts) {
      this.checkSuspiciousActivity(entry);
    }

    // Limit activity log size
    if (this.activities.length > this.maxActivities) {
      this.activities = this.activities.slice(-this.maxActivities / 2);
    }

    // Emit activity event
    this.emit('activity', entry);

    return entry.id;
  }

  /**
   * Track command execution
   */
  trackCommand(command, result, sessionId = null) {
    return this.trackActivity({
      type: 'command',
      command,
      result: result.allowed ? 'allowed' : 'blocked',
      reason: result.reason,
      sessionId,
      workingDirectory: result.workingDirectory,
    });
  }

  /**
   * Track file operation
   */
  trackFileOperation(operation, filePath, size = 0, sessionId = null) {
    return this.trackActivity({
      type: 'file_operation',
      operation,
      filePath,
      size,
      sessionId,
    });
  }

  /**
   * Track security violation
   */
  trackSecurityViolation(violation, sessionId = null) {
    const activityId = this.trackActivity({
      type: 'security_violation',
      violation: violation.type,
      details: violation.details,
      sessionId,
      severity: violation.severity || 'medium',
    });

    // Always alert on security violations
    this.emit('securityAlert', {
      activityId,
      violation,
      timestamp: new Date().toISOString(),
    });

    return activityId;
  }

  /**
   * Track error
   */
  trackError(error, context = {}, sessionId = null) {
    return this.trackActivity({
      type: 'error',
      error: error.message,
      code: error.code,
      context,
      sessionId,
    });
  }

  /**
   * Update statistics
   */
  updateStats(activity) {
    switch (activity.type) {
      case 'command':
        this.stats.totalCommands++;
        if (activity.result === 'allowed') {
          this.stats.allowedCommands++;
        } else {
          this.stats.blockedCommands++;
        }
        break;

      case 'file_operation':
        this.stats.fileOperations++;
        break;

      case 'error':
        this.stats.errors++;
        break;
    }
  }

  /**
   * Check for suspicious activity patterns
   */
  checkSuspiciousActivity(activity) {
    const now = Date.now();
    const sessionId = activity.sessionId || 'global';

    // Get recent activities
    const recentActivities = this.getRecentActivities(300000); // Last 5 minutes

    // Check rapid command execution
    const recentCommands = recentActivities.filter(
      (a) => a.type === 'command' && a.sessionId === sessionId
    );

    if (recentCommands.length >= this.alertThresholds.rapidCommands.count) {
      const windowStart = now - this.alertThresholds.rapidCommands.window;
      const commandsInWindow = recentCommands.filter(
        (c) => new Date(c.timestamp).getTime() > windowStart
      );

      if (commandsInWindow.length >= this.alertThresholds.rapidCommands.count) {
        this.raiseSuspiciousAlert('rapid_commands', {
          sessionId,
          count: commandsInWindow.length,
          window: this.alertThresholds.rapidCommands.window,
        });
      }
    }

    // Check failed commands
    const failedCommands = recentCommands.filter((c) => c.result === 'blocked');
    if (failedCommands.length >= this.alertThresholds.failedCommands.count) {
      this.raiseSuspiciousAlert('excessive_failures', {
        sessionId,
        count: failedCommands.length,
        commands: failedCommands.map((c) => c.command),
      });
    }

    // Check deletion patterns
    if (activity.type === 'command' && activity.command && activity.command.includes('rm')) {
      const recentDeletions = recentActivities.filter(
        (a) =>
          a.type === 'command' &&
          a.command &&
          (a.command.includes('rm') || a.command.includes('delete'))
      );

      if (recentDeletions.length >= this.alertThresholds.deletions.count) {
        this.raiseSuspiciousAlert('excessive_deletions', {
          sessionId,
          count: recentDeletions.length,
          commands: recentDeletions.map((d) => d.command),
        });
      }
    }

    // Check large file operations
    if (
      activity.type === 'file_operation' &&
      activity.size > this.alertThresholds.largeFileOps.size
    ) {
      const largeFileOps = recentActivities.filter(
        (a) => a.type === 'file_operation' && a.size > this.alertThresholds.largeFileOps.size
      );

      if (largeFileOps.length >= this.alertThresholds.largeFileOps.count) {
        this.raiseSuspiciousAlert('large_file_operations', {
          sessionId,
          count: largeFileOps.length,
          totalSize: largeFileOps.reduce((sum, op) => sum + op.size, 0),
          files: largeFileOps.map((op) => op.filePath),
        });
      }
    }
  }

  /**
   * Raise suspicious activity alert
   */
  raiseSuspiciousAlert(type, details) {
    const alert = {
      id: this.generateActivityId(),
      type,
      details,
      timestamp: new Date().toISOString(),
      severity: this.calculateSeverity(type),
    };

    // Track the pattern
    const key = `${type}_${details.sessionId || 'global'}`;
    const lastAlert = this.suspiciousPatterns.get(key);

    // Avoid duplicate alerts within 5 minutes
    if (lastAlert && Date.now() - lastAlert.timestamp < 300000) {
      return;
    }

    this.suspiciousPatterns.set(key, {
      timestamp: Date.now(),
      alert,
    });

    logger.warn('Suspicious activity detected', alert);

    this.emit('suspiciousActivity', alert);
  }

  /**
   * Calculate alert severity
   */
  calculateSeverity(type) {
    const severityMap = {
      rapid_commands: 'low',
      excessive_failures: 'medium',
      excessive_deletions: 'high',
      large_file_operations: 'medium',
      security_violation: 'high',
    };

    return severityMap[type] || 'medium';
  }

  /**
   * Analyze patterns periodically
   */
  analyzePatterns() {
    const analysis = {
      timestamp: new Date().toISOString(),
      stats: { ...this.stats },
      activeSessions: this.sessionActivities.size,
      recentAlerts: Array.from(this.suspiciousPatterns.values())
        .filter((p) => Date.now() - p.timestamp < 3600000) // Last hour
        .map((p) => p.alert),
      trends: this.calculateTrends(),
    };

    this.emit('analysisComplete', analysis);

    // Log analysis summary
    logger.info('Activity analysis complete', {
      totalCommands: analysis.stats.totalCommands,
      blockedRate: `${((analysis.stats.blockedCommands / analysis.stats.totalCommands) * 100).toFixed(2)}%`,
      activeSessions: analysis.activeSessions,
      recentAlerts: analysis.recentAlerts.length,
    });
  }

  /**
   * Calculate activity trends
   */
  calculateTrends() {
    const now = Date.now();
    const hourAgo = now - 3600000;
    const dayAgo = now - 86400000;

    const lastHour = this.activities.filter((a) => new Date(a.timestamp).getTime() > hourAgo);

    const lastDay = this.activities.filter((a) => new Date(a.timestamp).getTime() > dayAgo);

    return {
      commandsPerHour: lastHour.filter((a) => a.type === 'command').length,
      commandsPerDay: lastDay.filter((a) => a.type === 'command').length,
      errorsPerHour: lastHour.filter((a) => a.type === 'error').length,
      violationsPerDay: lastDay.filter((a) => a.type === 'security_violation').length,
    };
  }

  /**
   * Get recent activities
   */
  getRecentActivities(windowMs = 300000) {
    const cutoff = Date.now() - windowMs;
    return this.activities.filter((a) => new Date(a.timestamp).getTime() > cutoff);
  }

  /**
   * Get session activities
   */
  getSessionActivities(sessionId, options = {}) {
    const activities = this.sessionActivities.get(sessionId) || [];
    const { limit = 100, type } = options;

    let filtered = [...activities];

    if (type) {
      filtered = filtered.filter((a) => a.type === type);
    }

    return filtered.slice(-limit).reverse();
  }

  /**
   * Generate security report
   */
  generateReport(options = {}) {
    const {
      startDate = new Date(Date.now() - 86400000), // Last 24 hours
      endDate = new Date(),
      sessionId,
    } = options;

    let activities = sessionId ? this.sessionActivities.get(sessionId) || [] : this.activities;

    // Filter by date range
    activities = activities.filter((a) => {
      const timestamp = new Date(a.timestamp);
      return timestamp >= startDate && timestamp <= endDate;
    });

    // Group by type
    const byType = {};
    activities.forEach((a) => {
      if (!byType[a.type]) {
        byType[a.type] = [];
      }
      byType[a.type].push(a);
    });

    // Calculate statistics
    const report = {
      generated: new Date().toISOString(),
      period: {
        start: startDate.toISOString(),
        end: endDate.toISOString(),
      },
      sessionId,
      summary: {
        totalActivities: activities.length,
        commands: {
          total: byType.command?.length || 0,
          allowed: byType.command?.filter((c) => c.result === 'allowed').length || 0,
          blocked: byType.command?.filter((c) => c.result === 'blocked').length || 0,
        },
        fileOperations: byType.file_operation?.length || 0,
        errors: byType.error?.length || 0,
        violations: byType.security_violation?.length || 0,
      },
      topBlockedCommands: this.getTopItems(
        byType.command?.filter((c) => c.result === 'blocked') || [],
        'command',
        5
      ),
      recentViolations: (byType.security_violation || []).slice(-10),
      alerts: Array.from(this.suspiciousPatterns.values())
        .filter((p) => {
          const timestamp = new Date(p.alert.timestamp);
          return timestamp >= startDate && timestamp <= endDate;
        })
        .map((p) => p.alert),
    };

    return report;
  }

  /**
   * Get top items by frequency
   */
  getTopItems(items, field, limit = 5) {
    const counts = {};

    items.forEach((item) => {
      const value = item[field];
      if (value) {
        counts[value] = (counts[value] || 0) + 1;
      }
    });

    return Object.entries(counts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, limit)
      .map(([value, count]) => ({ value, count }));
  }

  /**
   * Export activities to file
   */
  async exportActivities(options = {}) {
    const { format = 'json', sessionId } = options;

    const activities = sessionId ? this.sessionActivities.get(sessionId) || [] : this.activities;

    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const filename = `activities_${sessionId || 'all'}_${timestamp}.${format}`;
    const filepath = path.join(this.exportPath, filename);

    try {
      // Ensure directory exists
      await fs.mkdir(this.exportPath, { recursive: true });

      let content;
      if (format === 'json') {
        content = JSON.stringify(activities, null, 2);
      } else if (format === 'csv') {
        content = this.convertToCSV(activities);
      } else {
        throw new Error(`Unsupported format: ${format}`);
      }

      await fs.writeFile(filepath, content, 'utf-8');

      logger.info('Activities exported', { filepath, count: activities.length });

      return filepath;
    } catch (error) {
      logger.error('Failed to export activities', { error: error.message });
      throw error;
    }
  }

  /**
   * Convert activities to CSV
   */
  convertToCSV(activities) {
    if (activities.length === 0) {
      return 'timestamp,type,sessionId,details\n';
    }

    const headers = ['timestamp', 'type', 'sessionId'];
    const rows = activities.map((a) => {
      const details = { ...a };
      delete details.timestamp;
      delete details.type;
      delete details.sessionId;
      delete details.id;

      return [a.timestamp, a.type, a.sessionId || '', JSON.stringify(details)].join(',');
    });

    return `${headers.join(',')}\n${rows.join('\n')}`;
  }

  /**
   * Clear activities
   */
  clearActivities(sessionId = null) {
    if (sessionId) {
      const count = this.sessionActivities.get(sessionId)?.length || 0;
      this.sessionActivities.delete(sessionId);
      logger.info('Session activities cleared', { sessionId, count });
      return count;
    } else {
      const count = this.activities.length;
      this.activities = [];
      this.sessionActivities.clear();
      this.suspiciousPatterns.clear();
      logger.info('All activities cleared', { count });
      return count;
    }
  }

  /**
   * Get statistics
   */
  getStats() {
    const runtime = Date.now() - this.stats.startTime.getTime();
    const hours = runtime / 3600000;

    return {
      ...this.stats,
      runtime: Math.floor(runtime / 1000), // seconds
      commandsPerHour: (this.stats.totalCommands / hours).toFixed(2),
      blockRate:
        this.stats.totalCommands > 0
          ? `${((this.stats.blockedCommands / this.stats.totalCommands) * 100).toFixed(2)}%`
          : '0%',
      activeSessions: this.sessionActivities.size,
    };
  }

  /**
   * Generate activity ID
   */
  generateActivityId() {
    return `act_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Cleanup
   */
  destroy() {
    if (this.analysisInterval) {
      clearInterval(this.analysisInterval);
    }
  }
}

// Export singleton instance
export const activityMonitor = new ActivityMonitor();
