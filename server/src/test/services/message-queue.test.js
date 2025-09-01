import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { messageQueueManager, MessagePriority } from '../../services/message-queue.js';

describe('MessageQueue', () => {
  const sessionId = 'test-session-123';

  beforeEach(() => {
    // Ensure clean state
    messageQueueManager.removeQueue(sessionId);
    messageQueueManager.removeQueue('session1');
    messageQueueManager.removeQueue('session2');
  });

  afterEach(() => {
    // Clean up any active queues
    messageQueueManager.removeQueue(sessionId);
    messageQueueManager.removeQueue('session1');
    messageQueueManager.removeQueue('session2');
  });

  describe('Basic Queue Operations', () => {
    it('should add messages to queue', () => {
      // Create and pause queue before adding messages
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.queueMessage(sessionId, { id: 'msg1', content: 'test' });

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 1);
    });

    it('should add messages with different priorities', () => {
      // Create and pause queue before adding messages
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.queueMessage(sessionId, { id: '1', content: 'low' }, MessagePriority.LOW);
      messageQueueManager.queueMessage(
        sessionId,
        { id: '2', content: 'normal' },
        MessagePriority.NORMAL
      );
      messageQueueManager.queueMessage(
        sessionId,
        { id: '3', content: 'high' },
        MessagePriority.HIGH
      );

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 3);
    });

    it('should clear queue', () => {
      // Create and pause queue before adding messages
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.queueMessage(sessionId, { id: '1', content: 'test' });
      messageQueueManager.queueMessage(sessionId, { id: '2', content: 'test2' });

      messageQueueManager.clearQueue(sessionId);

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 0);
    });

    it('should pause and resume queue', () => {
      // Create and pause queue before adding messages
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.queueMessage(sessionId, { id: '1', content: 'test' });

      const pausedStatus = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(pausedStatus.queue.paused, true);

      messageQueueManager.resumeQueue(sessionId);
      const resumedStatus = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(resumedStatus.queue.paused, false);
    });

    it('should remove queue', () => {
      // Create and pause queue before adding messages
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.queueMessage(sessionId, { id: '1', content: 'test' });

      const statusBefore = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(statusBefore.queue.length, 1);

      messageQueueManager.removeQueue(sessionId);

      const statusAfter = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(statusAfter.queue.length, 0);
    });
  });

  describe('Queue Status', () => {
    it('should provide queue status', () => {
      // Create and pause queue before adding messages
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.queueMessage(sessionId, { id: '1', content: 'test' });
      messageQueueManager.queueMessage(sessionId, { id: '2', content: 'test' });

      const status = messageQueueManager.getQueueStatus(sessionId);

      assert(status);
      assert.strictEqual(status.sessionId, sessionId);
      assert.strictEqual(status.queue.length, 2);
      assert.strictEqual(status.queue.paused, true); // Queue is paused
      assert.strictEqual(status.queue.processing, false);
      assert(status.queue.stats);
      assert.strictEqual(typeof status.queue.stats.messagesQueued, 'number');
      assert.strictEqual(typeof status.queue.stats.messagesProcessed, 'number');
      assert.strictEqual(typeof status.queue.stats.messagesFailed, 'number');
    });

    it('should handle empty queue status', () => {
      const status = messageQueueManager.getQueueStatus('nonexistent');
      assert.strictEqual(status.queue.length, 0);
      assert.strictEqual(status.queue.paused, false);
      assert.strictEqual(status.queue.processing, false);
    });
  });

  describe('Global Metrics', () => {
    it('should provide global queue metrics', () => {
      // Create and pause queues before adding messages
      messageQueueManager.getQueue('session1');
      messageQueueManager.pauseQueue('session1');
      messageQueueManager.getQueue('session2');
      messageQueueManager.pauseQueue('session2');

      // Create multiple queues
      messageQueueManager.queueMessage('session1', { id: '1', content: 'test' });
      messageQueueManager.queueMessage('session1', { id: '2', content: 'test' });
      messageQueueManager.queueMessage('session2', { id: '3', content: 'test' });

      const allStatuses = messageQueueManager.getAllQueueStatuses();

      const metrics = {
        totalQueues: Object.keys(allStatuses).length,
        totalMessages: Object.values(allStatuses).reduce((sum, s) => sum + s.queue.length, 0),
        totalPaused: Object.values(allStatuses).filter((s) => s.queue.paused).length,
        queues: allStatuses,
      };

      assert.strictEqual(metrics.totalQueues, 2);
      assert.strictEqual(metrics.totalMessages, 3);
      assert.strictEqual(metrics.totalPaused, 2);
      assert(metrics.queues['session1']);
      assert(metrics.queues['session2']);
    });
  });

  describe('Queue Processing', () => {
    it('should process messages when handler is set', async () => {
      let processedMessage = null;

      // Create and pause queue first
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      // Set up handler
      messageQueueManager.setMessageHandler(sessionId, (message, callback) => {
        processedMessage = message.message;
        callback(null, { success: true });
      });

      // Add message to paused queue
      messageQueueManager.queueMessage(sessionId, { id: 'test1', content: 'hello' });

      // Start processing by resuming
      messageQueueManager.resumeQueue(sessionId);

      // Wait a bit for processing
      await new Promise((resolve) => setTimeout(resolve, 100));

      assert(processedMessage);
      assert.strictEqual(processedMessage.id, 'test1');
      assert.strictEqual(processedMessage.content, 'hello');
    });

    it('should handle processing errors gracefully', async () => {
      let attempts = 0;

      // Create queue with custom fast retry config
      const queue = messageQueueManager.getQueue(sessionId);
      queue.config.retryAttempts = 2;
      queue.config.retryDelay = 50;
      messageQueueManager.pauseQueue(sessionId);

      messageQueueManager.setMessageHandler(sessionId, (message, callback) => {
        attempts++;
        callback(new Error('Processing error'));
      });

      // Add message to paused queue
      messageQueueManager.queueMessage(sessionId, { id: 'fail1', content: 'test' });

      // Start processing by resuming
      messageQueueManager.resumeQueue(sessionId);

      // Wait for retries - with 2 attempts and 50ms base delay: 50ms + 100ms = 150ms, add buffer
      await new Promise((resolve) => setTimeout(resolve, 300));

      // Should have attempted 2 times
      assert.strictEqual(attempts, 2);

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert(status.queue.stats.messagesFailed > 0 || status.queue.deadLetterQueueSize > 0);
    });
  });
});
