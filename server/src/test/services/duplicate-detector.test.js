import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { DuplicateDetector } from '../../services/duplicate-detector.js';
import { messageQueueManager, MessagePriority } from '../../services/message-queue.js';

describe('DuplicateDetector', () => {
  let detector;
  const deviceId1 = 'device-abc-123';
  const deviceId2 = 'device-def-456';
  const sessionId = 'session-test-789';

  beforeEach(() => {
    detector = new DuplicateDetector({
      timeWindow: 1000, // 1 second for testing
      maxEntries: 100,
      cleanupInterval: 500, // 0.5 seconds for testing
    });
  });

  afterEach(() => {
    detector.shutdown();
  });

  describe('Message Hashing', () => {
    it('should generate consistent hashes for identical messages', () => {
      const message1 = {
        content: 'Hello world',
        sessionId: 'session-123',
        projectPath: '/path/to/project',
      };

      const message2 = {
        content: 'Hello world',
        sessionId: 'session-123',
        projectPath: '/path/to/project',
      };

      const hash1 = detector.generateMessageHash(message1);
      const hash2 = detector.generateMessageHash(message2);

      assert.strictEqual(hash1, hash2);
      assert.strictEqual(hash1.length, 16); // SHA-256 truncated to 16 chars
    });

    it('should generate different hashes for different messages', () => {
      const message1 = { content: 'Hello world', sessionId: 'session-123' };
      const message2 = { content: 'Goodbye world', sessionId: 'session-123' };

      const hash1 = detector.generateMessageHash(message1);
      const hash2 = detector.generateMessageHash(message2);

      assert.notStrictEqual(hash1, hash2);
    });

    it('should ignore device-specific fields in hashing', () => {
      const message1 = {
        content: 'Hello world',
        sessionId: 'session-123',
        deviceId: 'device-1',
        timestamp: Date.now(),
        requestId: 'req-1',
      };

      const message2 = {
        content: 'Hello world',
        sessionId: 'session-123',
        deviceId: 'device-2',
        timestamp: Date.now() + 1000,
        requestId: 'req-2',
      };

      const hash1 = detector.generateMessageHash(message1);
      const hash2 = detector.generateMessageHash(message2);

      assert.strictEqual(hash1, hash2);
    });

    it('should handle attachments in hashing', () => {
      const message1 = {
        content: 'Check this file',
        attachments: [
          { name: 'test.txt', type: 'text/plain', size: 100 },
          { name: 'image.png', type: 'image/png', size: 2000 },
        ],
      };

      const message2 = {
        content: 'Check this file',
        attachments: [
          { name: 'image.png', type: 'image/png', size: 2000 },
          { name: 'test.txt', type: 'text/plain', size: 100 },
        ],
      };

      const hash1 = detector.generateMessageHash(message1);
      const hash2 = detector.generateMessageHash(message2);

      // Should be same despite different attachment order (they get sorted)
      assert.strictEqual(hash1, hash2);
    });
  });

  describe('Duplicate Detection', () => {
    it('should detect duplicates within time window', () => {
      const messageHash = 'test-hash-123';

      // First message should not be duplicate
      const result1 = detector.isDuplicate(messageHash, deviceId1, sessionId);
      assert.strictEqual(result1.isDuplicate, false);

      // Second message with same hash should be duplicate
      const result2 = detector.isDuplicate(messageHash, deviceId2, sessionId);
      assert.strictEqual(result2.isDuplicate, true);
      assert.strictEqual(result2.originalDeviceId, deviceId1);
      assert.ok(result2.timeDifference < 1000);
    });

    it('should not detect duplicates outside time window', async () => {
      const messageHash = 'test-hash-456';

      // First message
      detector.isDuplicate(messageHash, deviceId1, sessionId);

      // Wait for time window to pass
      await new Promise((resolve) => setTimeout(resolve, 1100));

      // Second message should not be duplicate (outside window)
      const result = detector.isDuplicate(messageHash, deviceId2, sessionId);
      assert.strictEqual(result.isDuplicate, false);
    });

    it('should update hash timestamp when outside window', async () => {
      const messageHash = 'test-hash-789';

      // Record initial hash
      const initialResult = detector.isDuplicate(messageHash, deviceId1, sessionId);
      assert.strictEqual(initialResult.isDuplicate, false);

      // Wait for window to pass
      await new Promise((resolve) => setTimeout(resolve, 1100));

      // Hash should be updated with new timestamp
      const updateResult = detector.isDuplicate(messageHash, deviceId2, sessionId);
      assert.strictEqual(updateResult.isDuplicate, false);

      // Now within window, should be duplicate
      const duplicateResult = detector.isDuplicate(messageHash, deviceId1, sessionId);
      assert.strictEqual(duplicateResult.isDuplicate, true);
      assert.strictEqual(duplicateResult.originalDeviceId, deviceId2);
    });

    it('should track device message counts', () => {
      detector.isDuplicate('hash1', deviceId1, sessionId);
      detector.isDuplicate('hash2', deviceId1, sessionId);
      detector.isDuplicate('hash3', deviceId2, sessionId);

      const stats = detector.getStats();
      assert.strictEqual(stats.trackedDevices, 2);
      assert.strictEqual(stats.totalHashesStored, 3);
    });
  });

  describe('Message Processing', () => {
    it('should process new messages successfully', () => {
      const message = {
        content: 'New message',
        sessionId,
        projectPath: '/test/path',
      };

      const result = detector.processMessage(message, deviceId1);

      assert.strictEqual(result.isDuplicate, false);
      assert.strictEqual(result.shouldProcess, true);
      assert.strictEqual(typeof result.messageHash, 'string');
      assert.strictEqual(result.duplicateInfo, null);
    });

    it('should detect and return duplicate information', () => {
      const message = {
        content: 'Duplicate message',
        sessionId,
        projectPath: '/test/path',
      };

      // First processing
      const result1 = detector.processMessage(message, deviceId1);
      assert.strictEqual(result1.isDuplicate, false);

      // Second processing - should be duplicate
      const result2 = detector.processMessage(message, deviceId2);
      assert.strictEqual(result2.isDuplicate, true);
      assert.strictEqual(result2.shouldProcess, false);
      assert.strictEqual(result2.duplicateInfo.originalDeviceId, deviceId1);
      assert.ok(result2.duplicateInfo.timeDifference >= 0);
    });
  });

  describe('Data Management', () => {
    beforeEach(() => {
      // Add some test data
      detector.processMessage({ content: 'msg1', sessionId: 'session1' }, deviceId1);
      detector.processMessage({ content: 'msg2', sessionId: 'session1' }, deviceId1);
      detector.processMessage({ content: 'msg3', sessionId: 'session2' }, deviceId2);
    });

    it('should clear device data', () => {
      const result = detector.clearDeviceData(deviceId1);

      assert.ok(result.clearedHashes >= 2);

      const stats = detector.getStats();
      assert.strictEqual(stats.trackedDevices, 1); // Only device2 remains
    });

    it('should clear session data', () => {
      const result = detector.clearSessionData('session1');

      assert.ok(result.clearedHashes >= 2);

      // Messages from session2 should remain
      const stats = detector.getStats();
      assert.ok(stats.totalHashesStored >= 1);
    });

    it('should perform cleanup of old entries', async () => {
      const initialStats = detector.getStats();

      // Wait for entries to age out
      await new Promise((resolve) => setTimeout(resolve, 1100));

      const cleanupResult = detector.performCleanup();
      assert.ok(cleanupResult.removedEntries >= 0);

      const finalStats = detector.getStats();
      assert.ok(finalStats.totalHashesStored <= initialStats.totalHashesStored);
    });

    it('should reset all data', () => {
      detector.reset();

      const stats = detector.getStats();
      assert.strictEqual(stats.totalHashesStored, 0);
      assert.strictEqual(stats.trackedDevices, 0);
    });
  });

  describe('Statistics', () => {
    it('should provide accurate statistics', () => {
      // Add some test data
      detector.processMessage({ content: 'recent1' }, deviceId1);
      detector.processMessage({ content: 'recent2' }, deviceId1);
      detector.processMessage({ content: 'recent3' }, deviceId2);

      const stats = detector.getStats();

      assert.strictEqual(stats.totalHashesStored, 3);
      assert.strictEqual(stats.recentHashes, 3);
      assert.strictEqual(stats.oldHashes, 0);
      assert.strictEqual(stats.trackedDevices, 2);
      assert.strictEqual(stats.duplicateDetectionWindow, 1000);
      assert(Array.isArray(stats.topDevicesByMessageCount));
      assert.ok(stats.topDevicesByMessageCount.length <= 5);
    });

    it('should categorize recent vs old hashes', async () => {
      // Create a detector with no automatic cleanup for this test
      const testDetector = new DuplicateDetector({
        timeWindow: 1000,
        maxEntries: 100,
        cleanupInterval: 999999, // Very long interval to prevent auto-cleanup during test
      });

      // Add data that will become old
      testDetector.processMessage({ content: 'old1' }, deviceId1);
      testDetector.processMessage({ content: 'old2' }, deviceId1);

      // Wait for time window to pass
      await new Promise((resolve) => setTimeout(resolve, 1100));

      // Check stats - should show old hashes (no auto-cleanup happened)
      const statsBeforeCleanup = testDetector.getStats();
      assert.ok(
        statsBeforeCleanup.oldHashes >= 2,
        `Expected at least 2 old hashes, got ${statsBeforeCleanup.oldHashes}`
      );

      // Add recent data
      testDetector.processMessage({ content: 'recent1' }, deviceId2);

      // Check stats with mixed data
      const statsWithMixed = testDetector.getStats();
      assert.ok(
        statsWithMixed.oldHashes >= 2,
        `Expected at least 2 old hashes, got ${statsWithMixed.oldHashes}`
      );
      assert.ok(
        statsWithMixed.recentHashes >= 1,
        `Expected at least 1 recent hash, got ${statsWithMixed.recentHashes}`
      );

      // Manually trigger cleanup - should remove old hashes
      testDetector.performCleanup();

      // After cleanup, should only have recent hashes
      const statsAfterCleanup = testDetector.getStats();
      assert.strictEqual(
        statsAfterCleanup.oldHashes,
        0,
        `Expected 0 old hashes after cleanup, got ${statsAfterCleanup.oldHashes}`
      );
      assert.ok(
        statsAfterCleanup.recentHashes >= 1,
        `Expected at least 1 recent hash after cleanup, got ${statsAfterCleanup.recentHashes}`
      );

      testDetector.shutdown();
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty messages gracefully', () => {
      const emptyMessage = {};
      const result = detector.processMessage(emptyMessage, deviceId1);

      assert.strictEqual(result.isDuplicate, false);
      assert.strictEqual(typeof result.messageHash, 'string');
    });

    it('should handle messages without deviceId', () => {
      const message = { content: 'test message' };
      const result = detector.checkMessage(message, deviceId1);

      assert.strictEqual(result.isDuplicate, false);
    });

    it('should handle concurrent operations safely', () => {
      const message = { content: 'concurrent test' };

      // Simulate concurrent processing
      const results = [];
      for (let i = 0; i < 10; i++) {
        results.push(detector.processMessage(message, `device-${i}`));
      }

      // First should not be duplicate, rest should be
      const nonDuplicates = results.filter((r) => !r.isDuplicate);
      const duplicates = results.filter((r) => r.isDuplicate);

      assert.strictEqual(nonDuplicates.length, 1);
      assert.strictEqual(duplicates.length, 9);
    });

    it('should enforce max entries limit', () => {
      const smallDetector = new DuplicateDetector({
        timeWindow: 10000, // Long window
        maxEntries: 5,
        cleanupInterval: 100,
      });

      // Add more than max entries
      for (let i = 0; i < 10; i++) {
        smallDetector.processMessage({ content: `message ${i}` }, deviceId1);
      }

      const stats = smallDetector.getStats();
      assert.ok(stats.totalHashesStored <= 5);

      smallDetector.shutdown();
    });
  });
});

describe('DuplicateDetector Integration with MessageQueue', () => {
  const sessionId = 'integration-test-session';
  const deviceId1 = 'device-integration-1';
  const deviceId2 = 'device-integration-2';

  beforeEach(() => {
    // Clean up any existing queues
    messageQueueManager.removeQueue(sessionId);
  });

  afterEach(() => {
    messageQueueManager.removeQueue(sessionId);
  });

  describe('Message Queue Deduplication', () => {
    it('should queue unique messages successfully', () => {
      // Create and pause queue to prevent processing
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'Unique message',
        sessionId,
        projectPath: '/test/project',
      };

      const result = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });

      assert.strictEqual(result.queued, true);
      assert.strictEqual(typeof result.messageId, 'string');
      assert.strictEqual(typeof result.messageHash, 'string');

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 1);
    });

    it('should reject duplicate messages', () => {
      // Create and pause queue
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'Duplicate test message',
        sessionId,
        projectPath: '/test/project',
      };

      // First message should be queued
      const result1 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });

      assert.strictEqual(result1.queued, true);

      // Second identical message should be rejected
      const result2 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId2,
      });

      assert.strictEqual(result2.queued, false);
      assert.strictEqual(result2.reason, 'duplicate');
      assert.strictEqual(typeof result2.messageHash, 'string');
      assert(result2.duplicateInfo);
      assert.strictEqual(result2.duplicateInfo.originalDeviceId, deviceId1);

      // Queue should still have only one message
      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 1);
    });

    it('should handle messages without deviceId (no deduplication)', () => {
      // Create and pause queue
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'No device ID message',
        sessionId,
      };

      // Both messages should be queued (no deduplication without deviceId)
      const result1 = messageQueueManager.queueMessage(sessionId, message);
      const result2 = messageQueueManager.queueMessage(sessionId, message);

      assert.strictEqual(result1.queued, true);
      assert.strictEqual(result2.queued, true);

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 2);
    });

    it('should emit duplicate-message event', (t, done) => {
      // Create and pause queue
      const queue = messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      queue.once('duplicate-message', (event) => {
        assert.strictEqual(event.sessionId, sessionId);
        assert.strictEqual(event.deviceId, deviceId2);
        assert.strictEqual(typeof event.messageHash, 'string');
        assert(event.duplicateInfo);
        done();
      });

      const message = {
        content: 'Event test message',
        sessionId,
        projectPath: '/test/project',
      };

      // First message
      messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });

      // Second duplicate message should emit event
      messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId2,
      });
    });

    it('should allow duplicate messages after time window expires', async () => {
      // Create and pause queue
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'Time window test message',
        sessionId,
        projectPath: '/test/project',
      };

      // First message
      const result1 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });
      assert.strictEqual(result1.queued, true);

      // Wait for duplicate detection window to expire (5 seconds default)
      await new Promise((resolve) => setTimeout(resolve, 5100));

      // Second message should now be allowed
      const result2 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId2,
      });

      assert.strictEqual(result2.queued, true);

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 2);
    });

    it('should preserve message priority despite deduplication', () => {
      // Create and pause queue
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'Priority test message',
        sessionId,
      };

      // Queue high priority message first
      const result1 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.HIGH, {
        deviceId: deviceId1,
      });

      // Try to queue same message with low priority - should be rejected
      const result2 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.LOW, {
        deviceId: deviceId2,
      });

      assert.strictEqual(result1.queued, true);
      assert.strictEqual(result2.queued, false);
      assert.strictEqual(result2.reason, 'duplicate');

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 1);
    });
  });
});
