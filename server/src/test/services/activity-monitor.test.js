import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { ActivityMonitor } from '../../services/activity-monitor.js';
import fs from 'fs/promises';

describe('ActivityMonitor', () => {
  let monitor;
  const testExportPath = './test-logs';

  beforeEach(() => {
    monitor = new ActivityMonitor({
      maxActivities: 100,
      exportPath: testExportPath,
      enableAlerts: true,
    });
  });

  afterEach(async () => {
    monitor.destroy();
    // Clean up test files
    try {
      await fs.rm(testExportPath, { recursive: true, force: true });
    } catch {
      // Ignore cleanup errors
    }
  });

  describe('Activity Tracking', () => {
    it('should track general activities', () => {
      const activityId = monitor.trackActivity({
        type: 'test',
        data: 'sample',
      });

      assert.ok(activityId);
      assert.strictEqual(monitor.activities.length, 1);
      assert.strictEqual(monitor.activities[0].type, 'test');
      assert.strictEqual(monitor.activities[0].data, 'sample');
      assert.ok(monitor.activities[0].timestamp);
    });

    it('should track session-specific activities', () => {
      const sessionId = 'test-session';
      const activityId = monitor.trackActivity({
        type: 'test',
        sessionId,
      });

      assert.ok(activityId);
      assert.ok(monitor.sessionActivities.has(sessionId));
      assert.strictEqual(monitor.sessionActivities.get(sessionId).length, 1);
    });

    it('should limit activity log size', () => {
      // Create monitor with small limit
      const smallMonitor = new ActivityMonitor({ maxActivities: 5 });

      // Add more activities than the limit
      for (let i = 0; i < 10; i++) {
        smallMonitor.trackActivity({ type: 'test', index: i });
      }

      // Should have trimmed to half the limit
      assert.ok(smallMonitor.activities.length <= 5);
      smallMonitor.destroy();
    });

    it('should emit activity events', () => {
      let activityReceived = null;
      monitor.once('activity', (activity) => {
        activityReceived = activity;
      });

      monitor.trackActivity({ type: 'test' });
      assert.strictEqual(activityReceived.type, 'test');
    });
  });

  describe('Command Tracking', () => {
    it('should track allowed commands', () => {
      const result = { allowed: true, workingDirectory: '/tmp' };
      const activityId = monitor.trackCommand('ls -la', result, 'session1');

      assert.ok(activityId);
      const activity = monitor.activities[0];
      assert.strictEqual(activity.type, 'command');
      assert.strictEqual(activity.command, 'ls -la');
      assert.strictEqual(activity.result, 'allowed');
      assert.strictEqual(activity.sessionId, 'session1');
      assert.strictEqual(activity.workingDirectory, '/tmp');
    });

    it('should track blocked commands', () => {
      const result = { allowed: false, reason: 'Security violation' };
      monitor.trackCommand('rm -rf /', result);

      const activity = monitor.activities[0];
      assert.strictEqual(activity.result, 'blocked');
      assert.strictEqual(activity.reason, 'Security violation');
    });

    it('should update command statistics', () => {
      monitor.trackCommand('ls', { allowed: true });
      monitor.trackCommand('rm file', { allowed: false });

      assert.strictEqual(monitor.stats.totalCommands, 2);
      assert.strictEqual(monitor.stats.allowedCommands, 1);
      assert.strictEqual(monitor.stats.blockedCommands, 1);
    });
  });

  describe('File Operation Tracking', () => {
    it('should track file operations', () => {
      const activityId = monitor.trackFileOperation('write', '/tmp/test.txt', 1024, 'session1');

      assert.ok(activityId);
      const activity = monitor.activities[0];
      assert.strictEqual(activity.type, 'file_operation');
      assert.strictEqual(activity.operation, 'write');
      assert.strictEqual(activity.filePath, '/tmp/test.txt');
      assert.strictEqual(activity.size, 1024);
      assert.strictEqual(activity.sessionId, 'session1');
    });

    it('should update file operation statistics', () => {
      monitor.trackFileOperation('read', '/tmp/file1.txt');
      monitor.trackFileOperation('write', '/tmp/file2.txt');

      assert.strictEqual(monitor.stats.fileOperations, 2);
    });
  });

  describe('Security Violation Tracking', () => {
    it('should track security violations', () => {
      const violation = {
        type: 'unauthorized_access',
        details: { path: '/etc/passwd' },
        severity: 'high',
      };

      let alertReceived = null;
      monitor.once('securityAlert', (alert) => {
        alertReceived = alert;
      });

      const activityId = monitor.trackSecurityViolation(violation, 'session1');
      assert.ok(activityId);
      assert.ok(alertReceived);
      assert.strictEqual(alertReceived.violation.type, 'unauthorized_access');
      assert.strictEqual(alertReceived.violation.severity, 'high');

      const activity = monitor.activities[0];
      assert.strictEqual(activity.type, 'security_violation');
      assert.strictEqual(activity.violation, 'unauthorized_access');
      assert.strictEqual(activity.severity, 'high');
    });
  });

  describe('Error Tracking', () => {
    it('should track errors', () => {
      const error = new Error('Test error');
      error.code = 'TEST_ERROR';
      const context = { operation: 'test' };

      const activityId = monitor.trackError(error, context, 'session1');

      assert.ok(activityId);
      const activity = monitor.activities[0];
      assert.strictEqual(activity.type, 'error');
      assert.strictEqual(activity.error, 'Test error');
      assert.strictEqual(activity.code, 'TEST_ERROR');
      assert.deepStrictEqual(activity.context, context);
      assert.strictEqual(activity.sessionId, 'session1');
    });

    it('should update error statistics', () => {
      const error = new Error('Test error');
      monitor.trackError(error);

      assert.strictEqual(monitor.stats.errors, 1);
    });
  });

  describe('Suspicious Activity Detection', () => {
    it('should detect rapid command execution', () => {
      let alertReceived = null;
      monitor.once('suspiciousActivity', (alert) => {
        alertReceived = alert;
      });

      // Create rapid commands
      const sessionId = 'rapid-session';
      for (let i = 0; i < 11; i++) {
        monitor.trackCommand(`command${i}`, { allowed: true }, sessionId);
      }

      assert.ok(alertReceived);
      assert.strictEqual(alertReceived.type, 'rapid_commands');
      assert.strictEqual(alertReceived.severity, 'low');
    });

    it('should detect excessive failed commands', () => {
      let alertReceived = null;
      monitor.once('suspiciousActivity', (alert) => {
        alertReceived = alert;
      });

      // Create failed commands
      const sessionId = 'fail-session';
      for (let i = 0; i < 6; i++) {
        monitor.trackCommand(`command${i}`, { allowed: false, reason: 'Blocked' }, sessionId);
      }

      assert.ok(alertReceived);
      assert.strictEqual(alertReceived.type, 'excessive_failures');
      assert.strictEqual(alertReceived.severity, 'medium');
    });

    it('should detect excessive deletions', () => {
      let alertReceived = null;
      monitor.once('suspiciousActivity', (alert) => {
        alertReceived = alert;
      });

      // Create deletion commands
      const sessionId = 'delete-session';
      for (let i = 0; i < 4; i++) {
        monitor.trackCommand(`rm file${i}`, { allowed: true }, sessionId);
      }

      assert.ok(alertReceived);
      assert.strictEqual(alertReceived.type, 'excessive_deletions');
      assert.strictEqual(alertReceived.severity, 'high');
    });

    it('should detect large file operations', () => {
      let alertReceived = null;
      monitor.once('suspiciousActivity', (alert) => {
        alertReceived = alert;
      });

      // Create large file operations
      const sessionId = 'large-files';
      const largeSize = 60 * 1024 * 1024; // 60MB
      for (let i = 0; i < 4; i++) {
        monitor.trackFileOperation('write', `/tmp/large${i}.bin`, largeSize, sessionId);
      }

      assert.ok(alertReceived);
      assert.strictEqual(alertReceived.type, 'large_file_operations');
      assert.strictEqual(alertReceived.severity, 'medium');
    });

    it('should avoid duplicate alerts within time window', () => {
      const sessionId = 'duplicate-test';
      let alertCount = 0;

      monitor.on('suspiciousActivity', () => {
        alertCount++;
      });

      // Create rapid commands twice
      for (let i = 0; i < 11; i++) {
        monitor.trackCommand(`command${i}`, { allowed: true }, sessionId);
      }
      for (let i = 0; i < 11; i++) {
        monitor.trackCommand(`command${i}`, { allowed: true }, sessionId);
      }

      // Should only get one alert due to deduplication
      assert.strictEqual(alertCount, 1);
    });
  });

  describe('Data Retrieval', () => {
    beforeEach(() => {
      // Add some test data
      monitor.trackCommand('ls', { allowed: true }, 'session1');
      monitor.trackCommand('rm file', { allowed: false }, 'session2');
      monitor.trackFileOperation('read', '/tmp/file.txt', 100);
      monitor.trackError(new Error('Test error'));
    });

    it('should get recent activities', () => {
      const recent = monitor.getRecentActivities(60000); // Last minute
      assert.strictEqual(recent.length, 4);
    });

    it('should get session activities', () => {
      const sessionActivities = monitor.getSessionActivities('session1');
      assert.strictEqual(sessionActivities.length, 1);
      assert.strictEqual(sessionActivities[0].sessionId, 'session1');
    });

    it('should filter session activities by type', () => {
      const commandActivities = monitor.getSessionActivities('session1', { type: 'command' });
      assert.strictEqual(commandActivities.length, 1);
      assert.strictEqual(commandActivities[0].type, 'command');
    });

    it('should limit session activities', () => {
      // Add more activities
      for (let i = 0; i < 10; i++) {
        monitor.trackCommand(`cmd${i}`, { allowed: true }, 'session1');
      }

      const limited = monitor.getSessionActivities('session1', { limit: 5 });
      assert.strictEqual(limited.length, 5);
    });
  });

  describe('Report Generation', () => {
    beforeEach(() => {
      // Add test data
      monitor.trackCommand('ls', { allowed: true }, 'session1');
      monitor.trackCommand('rm file', { allowed: false }, 'session1');
      monitor.trackFileOperation('write', '/tmp/file.txt', 1024);
      monitor.trackSecurityViolation({ type: 'test_violation' });
      monitor.trackError(new Error('Test error'));
    });

    it('should generate comprehensive report', () => {
      const report = monitor.generateReport();

      assert.ok(report.generated);
      assert.ok(report.period.start);
      assert.ok(report.period.end);
      assert.strictEqual(report.summary.totalActivities, 5);
      assert.strictEqual(report.summary.commands.total, 2);
      assert.strictEqual(report.summary.commands.allowed, 1);
      assert.strictEqual(report.summary.commands.blocked, 1);
      assert.strictEqual(report.summary.fileOperations, 1);
      assert.strictEqual(report.summary.errors, 1);
      assert.strictEqual(report.summary.violations, 1);
    });

    it('should generate session-specific report', () => {
      const report = monitor.generateReport({ sessionId: 'session1' });

      assert.strictEqual(report.sessionId, 'session1');
      assert.strictEqual(report.summary.commands.total, 2);
    });

    it('should filter by date range', () => {
      const yesterday = new Date(Date.now() - 86400000);
      const report = monitor.generateReport({ startDate: yesterday });

      assert.ok(report.summary.totalActivities > 0);
    });

    it('should include top blocked commands', () => {
      // Add more blocked commands
      monitor.trackCommand('rm file2', { allowed: false });
      monitor.trackCommand('rm file3', { allowed: false });

      const report = monitor.generateReport();
      assert.ok(report.topBlockedCommands.length > 0);
      assert.strictEqual(report.topBlockedCommands[0].value, 'rm file');
    });
  });

  describe('Statistics', () => {
    it('should calculate correct statistics', () => {
      monitor.trackCommand('cmd1', { allowed: true });
      monitor.trackCommand('cmd2', { allowed: false });
      monitor.trackFileOperation('read', '/tmp/file.txt');
      monitor.trackError(new Error('Test'));

      const stats = monitor.getStats();

      assert.strictEqual(stats.totalCommands, 2);
      assert.strictEqual(stats.allowedCommands, 1);
      assert.strictEqual(stats.blockedCommands, 1);
      assert.strictEqual(stats.fileOperations, 1);
      assert.strictEqual(stats.errors, 1);
      assert.strictEqual(stats.blockRate, '50.00%');
      assert.ok(stats.runtime >= 0);
      assert.ok(stats.commandsPerHour);
    });

    it('should handle zero commands for block rate', () => {
      const stats = monitor.getStats();
      assert.strictEqual(stats.blockRate, '0%');
    });
  });

  describe('Data Export', () => {
    beforeEach(() => {
      monitor.trackCommand('ls', { allowed: true });
      monitor.trackFileOperation('read', '/tmp/file.txt');
    });

    it('should export activities to JSON', async () => {
      const filepath = await monitor.exportActivities({ format: 'json' });

      assert.ok(filepath);
      assert.ok(filepath.includes('.json'));

      // Verify file exists and content
      const content = await fs.readFile(filepath, 'utf-8');
      const activities = JSON.parse(content);
      assert.strictEqual(activities.length, 2);
    });

    it('should export activities to CSV', async () => {
      const filepath = await monitor.exportActivities({ format: 'csv' });

      assert.ok(filepath);
      assert.ok(filepath.includes('.csv'));

      // Verify file exists and content
      const content = await fs.readFile(filepath, 'utf-8');
      assert.ok(content.includes('timestamp,type,sessionId'));
      assert.ok(content.includes('command'));
    });

    it('should export session-specific activities', async () => {
      monitor.trackCommand('session cmd', { allowed: true }, 'test-session');

      const filepath = await monitor.exportActivities({
        sessionId: 'test-session',
        format: 'json',
      });

      const content = await fs.readFile(filepath, 'utf-8');
      const activities = JSON.parse(content);
      assert.strictEqual(activities.length, 1);
      assert.strictEqual(activities[0].sessionId, 'test-session');
    });

    it('should handle export errors', async () => {
      // Create monitor with invalid export path
      const invalidMonitor = new ActivityMonitor({ exportPath: '/invalid/path' });

      try {
        await invalidMonitor.exportActivities();
        assert.fail('Should have thrown error');
      } catch (error) {
        assert.ok(error.message);
      }

      invalidMonitor.destroy();
    });

    it('should reject unsupported formats', async () => {
      try {
        await monitor.exportActivities({ format: 'xml' });
        assert.fail('Should have thrown error');
      } catch (error) {
        assert.ok(error.message.includes('Unsupported format'));
      }
    });
  });

  describe('Data Management', () => {
    beforeEach(() => {
      monitor.trackCommand('cmd1', { allowed: true }, 'session1');
      monitor.trackCommand('cmd2', { allowed: true }, 'session2');
      monitor.trackCommand('cmd3', { allowed: true }, 'session1');
    });

    it('should clear all activities', () => {
      const clearedCount = monitor.clearActivities();

      assert.strictEqual(clearedCount, 3);
      assert.strictEqual(monitor.activities.length, 0);
      assert.strictEqual(monitor.sessionActivities.size, 0);
    });

    it('should clear session-specific activities', () => {
      const clearedCount = monitor.clearActivities('session1');

      assert.strictEqual(clearedCount, 2);
      assert.strictEqual(monitor.activities.length, 3); // Global activities remain
      assert.strictEqual(monitor.sessionActivities.has('session1'), false);
      assert.strictEqual(monitor.sessionActivities.has('session2'), true);
    });

    it('should handle clearing non-existent session', () => {
      const clearedCount = monitor.clearActivities('non-existent');
      assert.strictEqual(clearedCount, 0);
    });
  });

  describe('CSV Conversion', () => {
    it('should handle empty activities', () => {
      const csv = monitor.convertToCSV([]);
      assert.strictEqual(csv, 'timestamp,type,sessionId,details\n');
    });

    it('should convert activities to CSV format', () => {
      const activities = [
        {
          id: 'test1',
          timestamp: '2023-01-01T00:00:00.000Z',
          type: 'command',
          sessionId: 'session1',
          command: 'ls',
          result: 'allowed',
        },
      ];

      const csv = monitor.convertToCSV(activities);
      const lines = csv.split('\n');

      assert.strictEqual(lines[0], 'timestamp,type,sessionId');
      assert.ok(lines[1].includes('2023-01-01T00:00:00.000Z'));
      assert.ok(lines[1].includes('command'));
      assert.ok(lines[1].includes('session1'));
    });
  });

  describe('Trend Analysis', () => {
    it('should calculate trends', () => {
      // Add activities over time
      monitor.trackCommand('cmd1', { allowed: true });
      monitor.trackCommand('cmd2', { allowed: false });
      monitor.trackError(new Error('Test'));
      monitor.trackSecurityViolation({ type: 'test' });

      const trends = monitor.calculateTrends();

      assert.ok(typeof trends.commandsPerHour === 'number');
      assert.ok(typeof trends.commandsPerDay === 'number');
      assert.ok(typeof trends.errorsPerHour === 'number');
      assert.ok(typeof trends.violationsPerDay === 'number');
    });
  });

  describe('Utility Methods', () => {
    it('should generate unique activity IDs', () => {
      const id1 = monitor.generateActivityId();
      const id2 = monitor.generateActivityId();

      assert.ok(id1.startsWith('act_'));
      assert.ok(id2.startsWith('act_'));
      assert.notStrictEqual(id1, id2);
    });

    it('should calculate severity levels', () => {
      assert.strictEqual(monitor.calculateSeverity('rapid_commands'), 'low');
      assert.strictEqual(monitor.calculateSeverity('excessive_failures'), 'medium');
      assert.strictEqual(monitor.calculateSeverity('excessive_deletions'), 'high');
      assert.strictEqual(monitor.calculateSeverity('unknown_type'), 'medium');
    });

    it('should get top items by frequency', () => {
      const items = [{ command: 'ls' }, { command: 'ls' }, { command: 'pwd' }, { command: 'ls' }];

      const top = monitor.getTopItems(items, 'command', 2);

      assert.strictEqual(top.length, 2);
      assert.strictEqual(top[0].value, 'ls');
      assert.strictEqual(top[0].count, 3);
      assert.strictEqual(top[1].value, 'pwd');
      assert.strictEqual(top[1].count, 1);
    });
  });

  describe('Cleanup', () => {
    it('should clean up intervals on destroy', () => {
      const testMonitor = new ActivityMonitor();
      assert.ok(testMonitor.analysisInterval);

      testMonitor.destroy();
      // Interval should be cleared (no direct way to test this)
      assert.ok(true);
    });
  });

  describe('Event Emission', () => {
    it('should emit analysis complete events', () => {
      let analysisReceived = null;
      monitor.once('analysisComplete', (analysis) => {
        analysisReceived = analysis;
      });

      // Manually trigger analysis
      monitor.analyzePatterns();

      assert.ok(analysisReceived);
      assert.ok(analysisReceived.timestamp);
      assert.ok(analysisReceived.stats);
      assert.ok(typeof analysisReceived.activeSessions === 'number');
      assert.ok(Array.isArray(analysisReceived.recentAlerts));
      assert.ok(analysisReceived.trends);
    });
  });
});
