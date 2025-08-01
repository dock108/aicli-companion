import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { MessageQueueService } from '../../services/message-queue.js';

describe('MessageQueueService', () => {
  let messageQueue;
  let consoleLogSpy;
  let clearIntervalSpy;

  beforeEach(() => {
    // Set test environment
    process.env.NODE_ENV = 'test';

    // Create fresh instance
    messageQueue = new MessageQueueService();

    // Mock console.log to verify output
    consoleLogSpy = mock.method(console, 'log');

    // Mock clearInterval
    clearIntervalSpy = mock.method(global, 'clearInterval');
  });

  afterEach(() => {
    // Clean up
    messageQueue.shutdown();

    // Restore mocks
    mock.restoreAll();
  });

  describe('constructor', () => {
    it('should initialize empty maps', () => {
      const mq = new MessageQueueService();
      assert.strictEqual(mq.messageQueue.size, 0);
      assert.strictEqual(mq.messageMetadata.size, 0);
      assert.strictEqual(mq.sessionClientMap.size, 0);
    });

    it('should not set cleanup interval in test environment', () => {
      const mq = new MessageQueueService();
      assert.strictEqual(mq.cleanupInterval, undefined);
    });

    it('should set cleanup interval in non-test environment', () => {
      const originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';

      const setIntervalSpy = mock.method(global, 'setInterval');
      const mq = new MessageQueueService();

      assert.strictEqual(setIntervalSpy.mock.calls.length, 1);
      assert.strictEqual(setIntervalSpy.mock.calls[0].arguments[1], 3600000);

      // Cleanup
      if (mq.cleanupInterval) {
        clearInterval(mq.cleanupInterval);
      }
      process.env.NODE_ENV = originalEnv;
    });
  });

  describe('queueMessage', () => {
    it('should queue a message for a session', () => {
      const sessionId = 'test-session-1';
      const message = { type: 'test', data: 'hello' };

      const messageId = messageQueue.queueMessage(sessionId, message);

      assert.ok(messageId);
      assert.ok(messageId.startsWith('msg_'));
      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), true);
      assert.strictEqual(messageQueue.messageQueue.get(sessionId).length, 1);
      assert.strictEqual(messageQueue.messageMetadata.has(messageId), true);

      // Verify console output
      assert.strictEqual(consoleLogSpy.mock.calls.length, 4);
    });

    it('should queue multiple messages for the same session', () => {
      const sessionId = 'test-session-1';

      messageQueue.queueMessage(sessionId, { type: 'test1' });
      messageQueue.queueMessage(sessionId, { type: 'test2' });
      messageQueue.queueMessage(sessionId, { type: 'test3' });

      const messages = messageQueue.messageQueue.get(sessionId);
      assert.strictEqual(messages.length, 3);
    });

    it('should use custom TTL when provided', () => {
      const sessionId = 'test-session-1';
      const customTTL = 60000; // 1 minute

      const messageId = messageQueue.queueMessage(sessionId, { type: 'test' }, { ttl: customTTL });
      const metadata = messageQueue.messageMetadata.get(messageId);

      const expectedExpiry = metadata.timestamp.getTime() + customTTL;
      assert.strictEqual(metadata.expiresAt.getTime(), expectedExpiry);
    });
  });

  describe('getUndeliveredMessages', () => {
    it('should return undelivered messages for a client', () => {
      const sessionId = 'test-session-1';
      const clientId = 'client1';

      messageQueue.queueMessage(sessionId, { type: 'test1' });
      messageQueue.queueMessage(sessionId, { type: 'test2' });

      const messages = messageQueue.getUndeliveredMessages(sessionId, clientId);
      assert.strictEqual(messages.length, 2);
      assert.strictEqual(messages[0].message.type, 'test1');
      assert.strictEqual(messages[1].message.type, 'test2');
    });

    it('should not return messages already delivered to the client', () => {
      const sessionId = 'test-session-1';
      const clientId = 'client1';

      const msgId1 = messageQueue.queueMessage(sessionId, { type: 'test1' });
      messageQueue.queueMessage(sessionId, { type: 'test2' });

      // Mark first message as delivered
      messageQueue.markAsDelivered([msgId1], clientId);

      const messages = messageQueue.getUndeliveredMessages(sessionId, clientId);
      assert.strictEqual(messages.length, 1);
      assert.strictEqual(messages[0].message.type, 'test2');
    });

    it('should not return expired messages', () => {
      const sessionId = 'test-session-1';
      const clientId = 'client1';

      // Queue a message with 1ms TTL
      const msgId = messageQueue.queueMessage(sessionId, { type: 'expired' }, { ttl: 1 });

      // Manually expire the message
      const metadata = messageQueue.messageMetadata.get(msgId);
      metadata.expiresAt = new Date(Date.now() - 1000);

      const messages = messageQueue.getUndeliveredMessages(sessionId, clientId);
      assert.strictEqual(messages.length, 0);
    });

    it('should return empty array for non-existent session', () => {
      const messages = messageQueue.getUndeliveredMessages('non-existent', 'client1');
      assert.strictEqual(messages.length, 0);
    });
  });

  describe('markAsDelivered', () => {
    it('should mark messages as delivered to a specific client', () => {
      const sessionId = 'test-session-1';
      const clientId1 = 'client1';
      const clientId2 = 'client2';

      const msgId = messageQueue.queueMessage(sessionId, { type: 'test' });

      // Mark as delivered to client1
      messageQueue.markAsDelivered([msgId], clientId1);

      const metadata = messageQueue.messageMetadata.get(msgId);
      assert.ok(metadata.deliveredTo.has(clientId1));
      assert.ok(metadata.deliveredAt);

      // Should not appear for client1
      const messages1 = messageQueue.getUndeliveredMessages(sessionId, clientId1);
      assert.strictEqual(messages1.length, 0);

      // Should still appear for client2
      const messages2 = messageQueue.getUndeliveredMessages(sessionId, clientId2);
      assert.strictEqual(messages2.length, 1);
    });

    it('should mark message as fully delivered when all tracked clients received it', () => {
      const sessionId = 'test-session-1';
      const clientId1 = 'client1';
      const clientId2 = 'client2';

      // Track both clients
      messageQueue.trackSessionClient(sessionId, clientId1);
      messageQueue.trackSessionClient(sessionId, clientId2);

      const msgId = messageQueue.queueMessage(sessionId, { type: 'test' });

      // Deliver to first client
      messageQueue.markAsDelivered([msgId], clientId1);
      let metadata = messageQueue.messageMetadata.get(msgId);
      assert.strictEqual(metadata.delivered, false);

      // Deliver to second client
      messageQueue.markAsDelivered([msgId], clientId2);
      metadata = messageQueue.messageMetadata.get(msgId);
      assert.strictEqual(metadata.delivered, true);
    });

    it('should handle non-existent message IDs gracefully', () => {
      // Should not throw
      messageQueue.markAsDelivered(['non-existent-id'], 'client1');
      assert.ok(true); // If we got here, no error was thrown
    });
  });

  describe('trackSessionClient', () => {
    it('should track client-session associations', () => {
      const sessionId = 'test-session-1';

      messageQueue.trackSessionClient(sessionId, 'client1');
      messageQueue.trackSessionClient(sessionId, 'client2');

      const clients = messageQueue.sessionClientMap.get(sessionId);
      assert.strictEqual(clients.size, 2);
      assert.ok(clients.has('client1'));
      assert.ok(clients.has('client2'));
    });

    it('should not duplicate client entries', () => {
      const sessionId = 'test-session-1';

      messageQueue.trackSessionClient(sessionId, 'client1');
      messageQueue.trackSessionClient(sessionId, 'client1');

      const clients = messageQueue.sessionClientMap.get(sessionId);
      assert.strictEqual(clients.size, 1);
    });
  });

  describe('hasQueuedMessages', () => {
    it('should return true when session has undelivered messages', () => {
      const sessionId = 'test-session-1';
      messageQueue.queueMessage(sessionId, { type: 'test' });

      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), true);
    });

    it('should return false when all messages are delivered', () => {
      const sessionId = 'test-session-1';
      const msgId = messageQueue.queueMessage(sessionId, { type: 'test' });

      // Mark as fully delivered
      const metadata = messageQueue.messageMetadata.get(msgId);
      metadata.delivered = true;

      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), false);
    });

    it('should return false when all messages are expired', () => {
      const sessionId = 'test-session-1';
      const msgId = messageQueue.queueMessage(sessionId, { type: 'test' });

      // Expire the message
      const metadata = messageQueue.messageMetadata.get(msgId);
      metadata.expiresAt = new Date(Date.now() - 1000);

      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), false);
    });

    it('should return false for non-existent session', () => {
      assert.strictEqual(messageQueue.hasQueuedMessages('non-existent'), false);
    });
  });

  describe('getStatistics', () => {
    it('should return correct statistics', () => {
      // Queue messages for different sessions
      messageQueue.queueMessage('session1', { type: 'test1' });
      messageQueue.queueMessage('session1', { type: 'test2' });
      messageQueue.queueMessage('session2', { type: 'test3' });

      // Track clients
      messageQueue.trackSessionClient('session1', 'client1');
      messageQueue.trackSessionClient('session1', 'client2');
      messageQueue.trackSessionClient('session2', 'client3');

      const stats = messageQueue.getStatistics();
      assert.strictEqual(stats.totalSessions, 2);
      assert.strictEqual(stats.totalMessages, 3);
      assert.strictEqual(stats.undeliveredMessages, 3);
      assert.strictEqual(stats.expiredMessages, 0);
      assert.strictEqual(stats.trackedClients, 3);
    });

    it('should count delivered and expired messages correctly', () => {
      const sessionId = 'test-session';

      // Add messages
      const msgId1 = messageQueue.queueMessage(sessionId, { type: 'delivered' });
      const msgId2 = messageQueue.queueMessage(sessionId, { type: 'expired' });
      messageQueue.queueMessage(sessionId, { type: 'undelivered' });

      // Mark first as delivered
      const metadata1 = messageQueue.messageMetadata.get(msgId1);
      metadata1.delivered = true;

      // Expire second
      const metadata2 = messageQueue.messageMetadata.get(msgId2);
      metadata2.expiresAt = new Date(Date.now() - 1000);

      const stats = messageQueue.getStatistics();
      assert.strictEqual(stats.totalMessages, 3);
      assert.strictEqual(stats.undeliveredMessages, 1);
      assert.strictEqual(stats.expiredMessages, 1);
    });
  });

  describe('cleanupExpiredMessages', () => {
    it('should remove expired messages', () => {
      const sessionId = 'test-session-1';

      // Queue messages with different expiration
      const msgId1 = messageQueue.queueMessage(sessionId, { type: 'expired1' }, { ttl: 1 });
      const msgId2 = messageQueue.queueMessage(sessionId, { type: 'expired2' }, { ttl: 1 });
      messageQueue.queueMessage(sessionId, { type: 'valid' }, { ttl: 60000 });

      // Manually expire first two messages
      messageQueue.messageMetadata.get(msgId1).expiresAt = new Date(Date.now() - 1000);
      messageQueue.messageMetadata.get(msgId2).expiresAt = new Date(Date.now() - 1000);

      // Reset console spy to check cleanup output
      consoleLogSpy.mock.resetCalls();

      messageQueue.cleanupExpiredMessages();

      // Check results
      const messages = messageQueue.messageQueue.get(sessionId);
      assert.strictEqual(messages.length, 1);
      assert.strictEqual(messages[0].message.type, 'valid');

      // Check metadata was cleaned
      assert.strictEqual(messageQueue.messageMetadata.has(msgId1), false);
      assert.strictEqual(messageQueue.messageMetadata.has(msgId2), false);

      // Check console output
      assert.strictEqual(consoleLogSpy.mock.calls.length, 1);
      assert.ok(consoleLogSpy.mock.calls[0].arguments[0].includes('Cleaned up 2 expired messages'));
    });

    it('should remove sessions with no valid messages', () => {
      const sessionId = 'test-session-1';

      // Track a client
      messageQueue.trackSessionClient(sessionId, 'client1');

      // Queue an expired message
      const msgId = messageQueue.queueMessage(sessionId, { type: 'expired' });
      messageQueue.messageMetadata.get(msgId).expiresAt = new Date(Date.now() - 1000);

      messageQueue.cleanupExpiredMessages();

      // Session should be removed
      assert.strictEqual(messageQueue.messageQueue.has(sessionId), false);
      assert.strictEqual(messageQueue.sessionClientMap.has(sessionId), false);
    });

    it('should not log when no messages are cleaned', () => {
      messageQueue.queueMessage('session1', { type: 'valid' });

      consoleLogSpy.mock.resetCalls();
      messageQueue.cleanupExpiredMessages();

      // Should not log anything
      assert.strictEqual(consoleLogSpy.mock.calls.length, 0);
    });
  });

  describe('clearSession', () => {
    it('should clear all messages for a session', () => {
      const sessionId = 'test-session-1';

      // Queue messages
      const msgId1 = messageQueue.queueMessage(sessionId, { type: 'test1' });
      const msgId2 = messageQueue.queueMessage(sessionId, { type: 'test2' });

      // Track client
      messageQueue.trackSessionClient(sessionId, 'client1');

      consoleLogSpy.mock.resetCalls();
      messageQueue.clearSession(sessionId);

      // Check everything is cleared
      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), false);
      assert.strictEqual(messageQueue.messageQueue.has(sessionId), false);
      assert.strictEqual(messageQueue.sessionClientMap.has(sessionId), false);
      assert.strictEqual(messageQueue.messageMetadata.has(msgId1), false);
      assert.strictEqual(messageQueue.messageMetadata.has(msgId2), false);

      // Check console output
      assert.strictEqual(consoleLogSpy.mock.calls.length, 1);
      assert.ok(
        consoleLogSpy.mock.calls[0].arguments[0].includes('Cleared all messages for session')
      );
    });

    it('should handle clearing non-existent session', () => {
      // Should not throw
      messageQueue.clearSession('non-existent');
      assert.ok(true);
    });
  });

  describe('shutdown', () => {
    it('should clear all data structures', () => {
      // Add some data
      messageQueue.queueMessage('session1', { type: 'test' });
      messageQueue.trackSessionClient('session1', 'client1');

      consoleLogSpy.mock.resetCalls();
      messageQueue.shutdown();

      // Check everything is cleared
      assert.strictEqual(messageQueue.messageQueue.size, 0);
      assert.strictEqual(messageQueue.messageMetadata.size, 0);
      assert.strictEqual(messageQueue.sessionClientMap.size, 0);

      // Check console output
      assert.strictEqual(consoleLogSpy.mock.calls.length, 1);
      assert.ok(
        consoleLogSpy.mock.calls[0].arguments[0].includes('Message queue service shut down')
      );
    });

    it('should clear interval if present', () => {
      // Create instance with interval
      const originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';

      const mq = new MessageQueueService();
      assert.ok(mq.cleanupInterval);

      clearIntervalSpy.mock.resetCalls();
      mq.shutdown();

      // Check interval was cleared
      assert.strictEqual(clearIntervalSpy.mock.calls.length, 1);

      process.env.NODE_ENV = originalEnv;
    });

    it('should handle shutdown when no interval exists', () => {
      // Test environment - no interval
      assert.strictEqual(messageQueue.cleanupInterval, undefined);

      // Should not throw
      messageQueue.shutdown();
      assert.ok(true);
    });
  });
});
