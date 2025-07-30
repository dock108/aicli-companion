import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { MessageQueueService } from '../../services/message-queue.js';

describe('MessageQueueService', () => {
  let messageQueue;

  beforeEach(() => {
    messageQueue = new MessageQueueService();
  });

  afterEach(() => {
    messageQueue.shutdown();
  });

  describe('queueMessage', () => {
    it('should queue a message for a session', () => {
      const sessionId = 'test-session-1';
      const message = { type: 'test', data: 'hello' };

      const messageId = messageQueue.queueMessage(sessionId, message);

      assert.ok(messageId);
      assert.ok(messageId.startsWith('msg_'));
      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), true);
    });

    it('should queue multiple messages for the same session', () => {
      const sessionId = 'test-session-1';

      messageQueue.queueMessage(sessionId, { type: 'test1' });
      messageQueue.queueMessage(sessionId, { type: 'test2' });
      messageQueue.queueMessage(sessionId, { type: 'test3' });

      const undelivered = messageQueue.getUndeliveredMessages(sessionId, 'client1');
      assert.strictEqual(undelivered.length, 3);
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

    it('should not return expired messages', async () => {
      const sessionId = 'test-session-1';
      const clientId = 'client1';

      // Queue a message with 1ms TTL
      messageQueue.queueMessage(sessionId, { type: 'expired' }, { ttl: 1 });

      // Wait for expiration
      await new Promise((resolve) => setTimeout(resolve, 10));

      const messages = messageQueue.getUndeliveredMessages(sessionId, clientId);
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

      // Should not appear for client1
      const messages1 = messageQueue.getUndeliveredMessages(sessionId, clientId1);
      assert.strictEqual(messages1.length, 0);

      // Should still appear for client2
      const messages2 = messageQueue.getUndeliveredMessages(sessionId, clientId2);
      assert.strictEqual(messages2.length, 1);
    });
  });

  describe('trackSessionClient', () => {
    it('should track client-session associations', () => {
      const sessionId = 'test-session-1';

      messageQueue.trackSessionClient(sessionId, 'client1');
      messageQueue.trackSessionClient(sessionId, 'client2');

      const stats = messageQueue.getStatistics();
      assert.strictEqual(stats.trackedClients, 2);
    });
  });

  describe('cleanupExpiredMessages', () => {
    it('should remove expired messages', async () => {
      const sessionId = 'test-session-1';

      // Queue messages with short TTL
      messageQueue.queueMessage(sessionId, { type: 'expired1' }, { ttl: 1 });
      messageQueue.queueMessage(sessionId, { type: 'expired2' }, { ttl: 1 });
      messageQueue.queueMessage(sessionId, { type: 'valid' }, { ttl: 60000 });

      // Wait and cleanup
      await new Promise((resolve) => setTimeout(resolve, 10));

      messageQueue.cleanupExpiredMessages();

      const messages = messageQueue.getUndeliveredMessages(sessionId, 'client1');
      assert.strictEqual(messages.length, 1);
      assert.strictEqual(messages[0].message.type, 'valid');
    });
  });

  describe('getStatistics', () => {
    it('should return correct statistics', () => {
      messageQueue.queueMessage('session1', { type: 'test1' });
      messageQueue.queueMessage('session1', { type: 'test2' });
      messageQueue.queueMessage('session2', { type: 'test3' });

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
  });

  describe('clearSession', () => {
    it('should clear all messages for a session', () => {
      const sessionId = 'test-session-1';

      messageQueue.queueMessage(sessionId, { type: 'test1' });
      messageQueue.queueMessage(sessionId, { type: 'test2' });
      messageQueue.trackSessionClient(sessionId, 'client1');

      messageQueue.clearSession(sessionId);

      assert.strictEqual(messageQueue.hasQueuedMessages(sessionId), false);
      const messages = messageQueue.getUndeliveredMessages(sessionId, 'client1');
      assert.strictEqual(messages.length, 0);
    });
  });
});
