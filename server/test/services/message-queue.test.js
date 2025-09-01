import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { MessageQueueManager, MessagePriority } from '../../src/services/message-queue.js';

describe('MessageQueueManager', () => {
  let queueManager;

  beforeEach(() => {
    queueManager = new MessageQueueManager({
      metricsInterval: 0, // Disable metrics timer in tests
      maxQueueSize: 10,
      processingTimeout: 1000,
      retryAttempts: 2,
      retryDelay: 50,
    });
  });

  afterEach(() => {
    queueManager.destroy();
  });

  describe('Queue Creation', () => {
    it('should create a new queue for a session', () => {
      const queue = queueManager.getQueue('session1');
      assert.ok(queue);
      assert.strictEqual(queue.sessionId, 'session1');
    });

    it('should return the same queue for the same session', () => {
      const queue1 = queueManager.getQueue('session1');
      const queue2 = queueManager.getQueue('session1');
      assert.strictEqual(queue1, queue2);
    });

    it('should track multiple queues', () => {
      queueManager.getQueue('session1');
      queueManager.getQueue('session2');
      queueManager.getQueue('session3');
      
      const statuses = queueManager.getAllQueueStatuses();
      assert.strictEqual(Object.keys(statuses).length, 3);
    });
  });

  describe('Message Queueing', () => {
    it('should queue messages with normal priority by default', () => {
      const messageId = queueManager.queueMessage('session1', { text: 'test' });
      assert.ok(messageId);
      
      const status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.queueLength, 1);
    });

    it('should queue messages with different priorities', () => {
      queueManager.queueMessage('session1', { text: 'low' }, MessagePriority.LOW);
      queueManager.queueMessage('session1', { text: 'high' }, MessagePriority.HIGH);
      queueManager.queueMessage('session1', { text: 'normal' }, MessagePriority.NORMAL);
      
      const queue = queueManager.getQueue('session1');
      assert.strictEqual(queue.queue[0].priority, MessagePriority.HIGH);
      assert.strictEqual(queue.queue[1].priority, MessagePriority.NORMAL);
      assert.strictEqual(queue.queue[2].priority, MessagePriority.LOW);
    });

    it('should maintain FIFO order within same priority', () => {
      queueManager.queueMessage('session1', { text: 'first' }, MessagePriority.NORMAL);
      queueManager.queueMessage('session1', { text: 'second' }, MessagePriority.NORMAL);
      queueManager.queueMessage('session1', { text: 'third' }, MessagePriority.NORMAL);
      
      const queue = queueManager.getQueue('session1');
      assert.strictEqual(queue.queue[0].message.text, 'first');
      assert.strictEqual(queue.queue[1].message.text, 'second');
      assert.strictEqual(queue.queue[2].message.text, 'third');
    });

    it('should throw error on queue overflow', () => {
      const queue = queueManager.getQueue('session1');
      
      // Fill the queue to max
      for (let i = 0; i < 10; i++) {
        queueManager.queueMessage('session1', { text: `msg${i}` });
      }
      
      // Should throw on overflow
      assert.throws(() => {
        queueManager.queueMessage('session1', { text: 'overflow' });
      }, /Queue overflow/);
    });
  });

  describe('Message Processing', () => {
    it('should process messages in priority order', async () => {
      const processed = [];
      const queue = queueManager.getQueue('session1');
      
      // Set up handler
      queueManager.setMessageHandler('session1', (message, callback) => {
        processed.push(message.message.text);
        callback(null, { success: true });
      });
      
      // Queue messages in reverse priority order
      queueManager.queueMessage('session1', { text: 'low' }, MessagePriority.LOW);
      queueManager.queueMessage('session1', { text: 'normal' }, MessagePriority.NORMAL);
      queueManager.queueMessage('session1', { text: 'high' }, MessagePriority.HIGH);
      
      // Wait for processing
      await new Promise(resolve => setTimeout(resolve, 100));
      
      assert.deepStrictEqual(processed, ['high', 'normal', 'low']);
    });

    it('should handle processing errors and retry', async () => {
      let attempts = 0;
      const queue = queueManager.getQueue('session1');
      
      queueManager.setMessageHandler('session1', (message, callback) => {
        attempts++;
        if (attempts < 2) {
          callback(new Error('Processing failed'));
        } else {
          callback(null, { success: true });
        }
      });
      
      queueManager.queueMessage('session1', { text: 'retry-test' });
      
      // Wait for retries
      await new Promise(resolve => setTimeout(resolve, 200));
      
      assert.strictEqual(attempts, 2);
      const status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.stats.messagesProcessed, 1);
    });

    it('should move failed messages to dead letter queue', async () => {
      const queue = queueManager.getQueue('session1');
      
      queueManager.setMessageHandler('session1', (message, callback) => {
        callback(new Error('Always fails'));
      });
      
      queueManager.queueMessage('session1', { text: 'doomed' });
      
      // Wait for retries to exhaust
      await new Promise(resolve => setTimeout(resolve, 300));
      
      const status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.deadLetterQueueSize, 1);
      assert.strictEqual(status.stats.messagesFailed, 1);
    });

    it('should timeout long-running messages', async () => {
      const queue = queueManager.getQueue('session1');
      
      queueManager.setMessageHandler('session1', async (message, callback) => {
        // Never call callback - simulate hanging
        await new Promise(resolve => setTimeout(resolve, 5000));
      });
      
      queueManager.queueMessage('session1', { text: 'hang' });
      
      // Wait for timeout
      await new Promise(resolve => setTimeout(resolve, 1500));
      
      const status = queueManager.getQueueStatus('session1');
      assert.ok(status.deadLetterQueueSize > 0);
    });
  });

  describe('Queue Control', () => {
    it('should pause and resume queue processing', async () => {
      let processedCount = 0;
      
      queueManager.setMessageHandler('session1', (message, callback) => {
        processedCount++;
        callback(null, { success: true });
      });
      
      // Queue messages
      queueManager.queueMessage('session1', { text: 'msg1' });
      queueManager.queueMessage('session1', { text: 'msg2' });
      
      // Pause immediately
      queueManager.pauseQueue('session1');
      
      // Wait a bit
      await new Promise(resolve => setTimeout(resolve, 100));
      
      // Should have processed at most 1 (the one that started before pause)
      assert.ok(processedCount <= 1);
      
      // Resume
      queueManager.resumeQueue('session1');
      
      // Wait for processing
      await new Promise(resolve => setTimeout(resolve, 100));
      
      assert.strictEqual(processedCount, 2);
    });

    it('should clear queue', () => {
      queueManager.queueMessage('session1', { text: 'msg1' });
      queueManager.queueMessage('session1', { text: 'msg2' });
      queueManager.queueMessage('session1', { text: 'msg3' });
      
      let status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.queueLength, 3);
      
      queueManager.clearQueue('session1');
      
      status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.queueLength, 0);
    });

    it('should remove queue completely', () => {
      queueManager.queueMessage('session1', { text: 'msg1' });
      
      assert.ok(queueManager.getQueueStatus('session1'));
      
      queueManager.removeQueue('session1');
      
      assert.strictEqual(queueManager.getQueueStatus('session1'), null);
    });
  });

  describe('High Priority Interruption', () => {
    it('should emit interrupt event for high priority messages', async () => {
      let interruptEmitted = false;
      const queue = queueManager.getQueue('session1');
      
      queue.on('interrupt-requested', () => {
        interruptEmitted = true;
      });
      
      // Set up slow handler
      queueManager.setMessageHandler('session1', async (message, callback) => {
        await new Promise(resolve => setTimeout(resolve, 200));
        callback(null, { success: true });
      });
      
      // Queue normal priority message
      queueManager.queueMessage('session1', { text: 'normal' }, MessagePriority.NORMAL);
      
      // Wait for processing to start
      await new Promise(resolve => setTimeout(resolve, 50));
      
      // Queue high priority message
      queueManager.queueMessage('session1', { text: 'urgent' }, MessagePriority.HIGH);
      
      assert.ok(interruptEmitted);
    });

    it('should process high priority messages before low priority', async () => {
      const processed = [];
      
      queueManager.setMessageHandler('session1', (message, callback) => {
        processed.push(message.message.text);
        callback(null, { success: true });
      });
      
      // Queue in specific order
      queueManager.queueMessage('session1', { text: 'low1' }, MessagePriority.LOW);
      queueManager.queueMessage('session1', { text: 'normal1' }, MessagePriority.NORMAL);
      queueManager.queueMessage('session1', { text: 'low2' }, MessagePriority.LOW);
      queueManager.queueMessage('session1', { text: 'high1' }, MessagePriority.HIGH);
      queueManager.queueMessage('session1', { text: 'normal2' }, MessagePriority.NORMAL);
      queueManager.queueMessage('session1', { text: 'high2' }, MessagePriority.HIGH);
      
      // Wait for all to process
      await new Promise(resolve => setTimeout(resolve, 200));
      
      // High priority should be first, then normal, then low
      assert.strictEqual(processed[0], 'high1');
      assert.strictEqual(processed[1], 'high2');
      assert.strictEqual(processed[2], 'normal1');
      assert.strictEqual(processed[3], 'normal2');
      assert.strictEqual(processed[4], 'low1');
      assert.strictEqual(processed[5], 'low2');
    });
  });

  describe('Metrics and Monitoring', () => {
    it('should track queue statistics', async () => {
      const queue = queueManager.getQueue('session1');
      
      queueManager.setMessageHandler('session1', (message, callback) => {
        callback(null, { success: true });
      });
      
      queueManager.queueMessage('session1', { text: 'msg1' });
      queueManager.queueMessage('session1', { text: 'msg2' });
      
      await new Promise(resolve => setTimeout(resolve, 100));
      
      const status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.stats.messagesQueued, 2);
      assert.strictEqual(status.stats.messagesProcessed, 2);
      assert.ok(status.stats.averageProcessingTime > 0);
    });

    it('should emit events for queue lifecycle', async () => {
      const events = [];
      
      queueManager.on('message-queued', (data) => events.push({ type: 'queued', ...data }));
      queueManager.on('message-processing', (data) => events.push({ type: 'processing', ...data }));
      queueManager.on('message-processed', (data) => events.push({ type: 'processed', ...data }));
      
      queueManager.setMessageHandler('session1', (message, callback) => {
        callback(null, { success: true });
      });
      
      queueManager.queueMessage('session1', { text: 'test' });
      
      await new Promise(resolve => setTimeout(resolve, 100));
      
      assert.ok(events.some(e => e.type === 'queued'));
      assert.ok(events.some(e => e.type === 'processing'));
      assert.ok(events.some(e => e.type === 'processed'));
    });
  });

  describe('Edge Cases', () => {
    it('should handle empty message gracefully', () => {
      const messageId = queueManager.queueMessage('session1', null);
      assert.ok(messageId);
      
      const status = queueManager.getQueueStatus('session1');
      assert.strictEqual(status.queueLength, 1);
    });

    it('should handle concurrent operations on same session', async () => {
      const processed = [];
      
      queueManager.setMessageHandler('session1', async (message, callback) => {
        await new Promise(resolve => setTimeout(resolve, 10));
        processed.push(message.message.text);
        callback(null, { success: true });
      });
      
      // Queue many messages rapidly
      const promises = [];
      for (let i = 0; i < 5; i++) {
        promises.push(
          Promise.resolve(queueManager.queueMessage('session1', { text: `msg${i}` }))
        );
      }
      
      await Promise.all(promises);
      await new Promise(resolve => setTimeout(resolve, 200));
      
      assert.strictEqual(processed.length, 5);
      // Check messages were processed in order
      for (let i = 0; i < 5; i++) {
        assert.strictEqual(processed[i], `msg${i}`);
      }
    });

    it('should handle queue removal during processing', async () => {
      let processStarted = false;
      
      queueManager.setMessageHandler('session1', async (message, callback) => {
        processStarted = true;
        await new Promise(resolve => setTimeout(resolve, 100));
        callback(null, { success: true });
      });
      
      queueManager.queueMessage('session1', { text: 'test' });
      
      // Wait for processing to start
      await new Promise(resolve => setTimeout(resolve, 20));
      assert.ok(processStarted);
      
      // Remove queue while processing
      queueManager.removeQueue('session1');
      
      // Should not throw
      assert.strictEqual(queueManager.getQueueStatus('session1'), null);
    });
  });
});

describe('MessagePriority', () => {
  it('should have correct priority values', () => {
    assert.strictEqual(MessagePriority.HIGH, 0);
    assert.strictEqual(MessagePriority.NORMAL, 1);
    assert.strictEqual(MessagePriority.LOW, 2);
    assert.ok(MessagePriority.HIGH < MessagePriority.NORMAL);
    assert.ok(MessagePriority.NORMAL < MessagePriority.LOW);
  });
});