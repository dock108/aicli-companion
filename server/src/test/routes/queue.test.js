import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import express from 'express';
import queueRouter from '../../routes/queue.js';
import { messageQueueManager, MessagePriority } from '../../services/message-queue.js';

describe('Queue Routes', () => {
  let app;
  let originalGetQueueStatus;
  let originalGetQueue;
  let originalPauseQueue;
  let originalResumeQueue;
  let originalClearQueue;
  let originalRemoveQueue;
  let originalGetAllQueueStatuses;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/api/queue', queueRouter);

    // Store original methods
    originalGetQueueStatus = messageQueueManager.getQueueStatus;
    originalGetQueue = messageQueueManager.getQueue;
    originalPauseQueue = messageQueueManager.pauseQueue;
    originalResumeQueue = messageQueueManager.resumeQueue;
    originalClearQueue = messageQueueManager.clearQueue;
    originalRemoveQueue = messageQueueManager.removeQueue;
    originalGetAllQueueStatuses = messageQueueManager.getAllQueueStatuses;

    // Clear any existing queues
    const statuses = messageQueueManager.getAllQueueStatuses();
    for (const sessionId of Object.keys(statuses)) {
      messageQueueManager.removeQueue(sessionId);
    }
  });

  afterEach(() => {
    // Restore original methods
    messageQueueManager.getQueueStatus = originalGetQueueStatus;
    messageQueueManager.getQueue = originalGetQueue;
    messageQueueManager.pauseQueue = originalPauseQueue;
    messageQueueManager.resumeQueue = originalResumeQueue;
    messageQueueManager.clearQueue = originalClearQueue;
    messageQueueManager.removeQueue = originalRemoveQueue;
    messageQueueManager.getAllQueueStatuses = originalGetAllQueueStatuses;
    mock.restoreAll();
  });

  describe('GET /:sessionId/status', () => {
    it('should return queue status for existing session', async () => {
      // Create a queue and add a message
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause(); // Pause to prevent auto-processing
      queue.enqueue({ message: 'test' }, MessagePriority.NORMAL, { test: true });

      const response = await request(app)
        .get('/api/queue/test-session/status')
        .set('x-request-id', 'test-req-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.sessionId, 'test-session');
      assert.ok(response.body.queue);
      assert.strictEqual(response.body.queue.length, 1);
      assert.strictEqual(response.body.requestId, 'test-req-123');
    });

    it('should return 404 for non-existent session', async () => {
      // Mock getQueueStatus to return null for non-existent queue
      messageQueueManager.getQueueStatus = mock.fn((sessionId) => {
        if (sessionId === 'non-existent') return null;
        return originalGetQueueStatus.call(messageQueueManager, sessionId);
      });

      const response = await request(app).get('/api/queue/non-existent/status');

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Queue not found for session');
    });

    it('should generate request ID if not provided', async () => {
      messageQueueManager.getQueue('test-session');

      const response = await request(app).get('/api/queue/test-session/status');

      assert.strictEqual(response.status, 200);
      assert.ok(response.body.requestId);
      assert.ok(response.body.requestId.startsWith('REQ_'));
    });
  });

  describe('GET /:sessionId/messages', () => {
    it('should return messages for existing queue', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause(); // Pause to prevent auto-processing
      queue.enqueue({ message: 'msg1' }, MessagePriority.HIGH, { tag: 'high' });
      queue.enqueue({ message: 'msg2' }, MessagePriority.NORMAL, { tag: 'normal' });
      queue.enqueue({ message: 'msg3' }, MessagePriority.LOW, { tag: 'low' });

      const response = await request(app).get('/api/queue/test-session/messages');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.ok(response.body.messages);
      assert.ok(Array.isArray(response.body.messages.pending));
      assert.strictEqual(response.body.messages.pending.length, 3);

      // Check priority ordering (HIGH should be first)
      assert.strictEqual(response.body.messages.pending[0].priority, MessagePriority.HIGH);
      assert.strictEqual(response.body.messages.pending[0].priorityName, 'HIGH');
    });

    it('should return 404 for non-existent queue', async () => {
      // Don't create the queue - it shouldn't exist
      const response = await request(app).get('/api/queue/non-existent-session/messages');

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Queue not found for session');
    });

    it('should include dead letter messages', async () => {
      const queue = messageQueueManager.getQueue('test-session');

      // Add a message to dead letter queue
      const failedMessage = {
        id: 'msg_failed',
        message: { text: 'failed' },
        priority: MessagePriority.NORMAL,
        metadata: {},
        timestamp: Date.now(),
        attempts: 3,
        status: 'failed',
        error: 'Max retries exceeded',
      };
      queue.deadLetterQueue.push(failedMessage);

      const response = await request(app).get('/api/queue/test-session/messages');

      assert.strictEqual(response.status, 200);
      assert.ok(response.body.messages.deadLetter);
      assert.strictEqual(response.body.messages.deadLetter.length, 1);
      assert.strictEqual(response.body.messages.deadLetter[0].id, 'msg_failed');
      assert.strictEqual(response.body.messages.deadLetter[0].error, 'Max retries exceeded');
    });

    it('should include currently processing message', async () => {
      const queue = messageQueueManager.getQueue('test-session');

      // Simulate a processing message
      queue.currentMessage = {
        id: 'msg_processing',
        priority: MessagePriority.NORMAL,
        timestamp: Date.now(),
      };

      const response = await request(app).get('/api/queue/test-session/messages');

      assert.strictEqual(response.status, 200);
      assert.ok(response.body.messages.processing);
      assert.strictEqual(response.body.messages.processing.id, 'msg_processing');
    });
  });

  describe('POST /:sessionId/pause', () => {
    it('should pause queue processing', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause(); // Start paused
      queue.enqueue({ message: 'test' });

      const response = await request(app)
        .post('/api/queue/test-session/pause')
        .set('x-request-id', 'pause-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.action, 'pause');
      assert.strictEqual(response.body.paused, true);
      assert.strictEqual(response.body.requestId, 'pause-123');

      // Verify queue is actually paused
      const status = messageQueueManager.getQueueStatus('test-session');
      assert.strictEqual(status.queue.paused, true);
    });

    it('should handle pause for non-existent queue', async () => {
      const response = await request(app).post('/api/queue/non-existent/pause');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.paused, true);
    });
  });

  describe('POST /:sessionId/resume', () => {
    it('should resume queue processing', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause();
      queue.enqueue({ message: 'test' });

      const response = await request(app)
        .post('/api/queue/test-session/resume')
        .set('x-request-id', 'resume-456');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.action, 'resume');
      assert.strictEqual(response.body.paused, false);
      assert.strictEqual(response.body.requestId, 'resume-456');

      // Verify queue is actually resumed
      const status = messageQueueManager.getQueueStatus('test-session');
      assert.strictEqual(status.queue.paused, false);
    });

    it('should handle resume for non-existent queue', async () => {
      const response = await request(app).post('/api/queue/non-existent/resume');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.paused, false);
    });
  });

  describe('POST /:sessionId/clear', () => {
    it('should clear all queued messages', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause(); // Pause to prevent auto-processing
      queue.enqueue({ message: 'msg1' });
      queue.enqueue({ message: 'msg2' });
      queue.enqueue({ message: 'msg3' });

      const response = await request(app)
        .post('/api/queue/test-session/clear')
        .set('x-request-id', 'clear-789');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.action, 'clear');
      assert.strictEqual(response.body.messagesCleared, 3);
      assert.strictEqual(response.body.requestId, 'clear-789');

      // Verify queue is actually cleared
      const status = messageQueueManager.getQueueStatus('test-session');
      assert.strictEqual(status.queue.length, 0);
    });

    it('should handle clear for empty queue', async () => {
      messageQueueManager.getQueue('test-session');

      const response = await request(app).post('/api/queue/test-session/clear');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.messagesCleared, 0);
    });

    it('should handle clear for non-existent queue', async () => {
      const response = await request(app).post('/api/queue/non-existent/clear');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.messagesCleared, 0);
    });
  });

  describe('DELETE /:sessionId', () => {
    it('should remove entire queue', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.enqueue({ message: 'test' });

      const response = await request(app)
        .delete('/api/queue/test-session')
        .set('x-request-id', 'delete-999');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.action, 'remove');
      assert.strictEqual(response.body.requestId, 'delete-999');

      // Verify queue is actually removed
      const status = messageQueueManager.getQueueStatus('test-session');
      // Should return default status for non-existent queue
      assert.strictEqual(status.queue.length, 0);
      assert.strictEqual(status.queue.stats.messagesQueued, 0);
    });

    it('should return 404 for non-existent queue', async () => {
      // Mock to ensure queue doesn't exist
      messageQueueManager.getQueueStatus = mock.fn(() => null);

      const response = await request(app).delete('/api/queue/non-existent');

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Queue not found for session');
    });
  });

  describe('GET /metrics', () => {
    it('should return global queue metrics', async () => {
      // Create multiple queues with different states
      const queue1 = messageQueueManager.getQueue('session1');
      queue1.pause();
      queue1.enqueue({ message: 'msg1' });
      queue1.enqueue({ message: 'msg2' });

      const queue2 = messageQueueManager.getQueue('session2');
      queue2.pause(); // Pause to prevent auto-processing
      queue2.enqueue({ message: 'msg3' });

      // Add a message to dead letter queue
      queue2.deadLetterQueue.push({
        id: 'dead_msg',
        status: 'failed',
      });

      const response = await request(app)
        .get('/api/queue/metrics')
        .set('x-request-id', 'metrics-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.ok(response.body.metrics);
      assert.strictEqual(response.body.metrics.totalQueues, 2);
      assert.strictEqual(response.body.metrics.totalMessages, 3);
      assert.strictEqual(response.body.metrics.totalPaused, 2); // Both queues are paused
      assert.strictEqual(response.body.metrics.totalDeadLetter, 1);
      assert.strictEqual(response.body.requestId, 'metrics-123');
      assert.ok(response.body.metrics.queues.session1);
      assert.ok(response.body.metrics.queues.session2);
    });

    it('should return empty metrics when no queues exist', async () => {
      const response = await request(app).get('/api/queue/metrics');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.metrics.totalQueues, 0);
      assert.strictEqual(response.body.metrics.totalMessages, 0);
      assert.deepStrictEqual(response.body.metrics.queues, {});
    });
  });

  describe('PUT /:sessionId/message/:messageId/priority', () => {
    it('should update message priority', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause(); // Pause to prevent auto-processing

      // Add messages with different priorities
      queue.enqueue({ message: 'msg1' }, MessagePriority.NORMAL, { id: '1' });
      queue.enqueue({ message: 'msg2' }, MessagePriority.LOW, { id: '2' });

      // Get the message ID from the queue
      const messageId = queue.queue[0].id;

      const response = await request(app)
        .put(`/api/queue/test-session/message/${messageId}/priority`)
        .send({ priority: MessagePriority.HIGH })
        .set('x-request-id', 'priority-update-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.newPriority, MessagePriority.HIGH);
      assert.strictEqual(response.body.priorityName, 'HIGH');
      assert.strictEqual(response.body.requestId, 'priority-update-123');

      // Verify message was reordered (HIGH priority should be first)
      assert.strictEqual(queue.queue[0].id, messageId);
      assert.strictEqual(queue.queue[0].priority, MessagePriority.HIGH);
    });

    it('should return 400 for invalid priority', async () => {
      messageQueueManager.getQueue('test-session');

      const response = await request(app)
        .put('/api/queue/test-session/message/msg123/priority')
        .send({ priority: 99 }); // Invalid priority

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
      assert.ok(response.body.error.includes('Invalid priority'));
    });

    it('should return 404 for non-existent queue', async () => {
      // Don't create the queue - it shouldn't exist
      const response = await request(app)
        .put('/api/queue/non-existent-queue-session/message/msg123/priority')
        .send({ priority: MessagePriority.HIGH });

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Queue not found for session');
    });

    it('should return 404 for non-existent message', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.enqueue({ message: 'test' });

      const response = await request(app)
        .put('/api/queue/test-session/message/non-existent-msg/priority')
        .send({ priority: MessagePriority.HIGH });

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Message not found in queue');
    });

    it('should handle numeric priority values', async () => {
      const queue = messageQueueManager.getQueue('test-session');
      queue.pause();
      queue.enqueue({ message: 'test' });

      const messageId = queue.queue[0].id;

      const response = await request(app)
        .put(`/api/queue/test-session/message/${messageId}/priority`)
        .send({ priority: 0 }); // HIGH priority as number

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.newPriority, 0);
      assert.strictEqual(response.body.priorityName, 'HIGH');
    });
  });
});
