import express from 'express';
import { createLogger } from '../utils/logger.js';
import { messageQueueManager, MessagePriority } from '../services/message-queue.js';

const logger = createLogger('QueueAPI');
const router = express.Router();

/**
 * GET /api/queue/:sessionId/status - Get queue status for a session
 */
router.get('/:sessionId/status', (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Getting queue status', { sessionId, requestId });

  const status = messageQueueManager.getQueueStatus(sessionId);

  if (!status) {
    return res.status(404).json({
      success: false,
      error: 'Queue not found for session',
      sessionId,
      requestId,
    });
  }

  res.json({
    success: true,
    sessionId,
    queue: {
      length: status.queueLength,
      processing: status.processing,
      paused: status.paused,
      currentMessage: status.currentMessage,
      stats: status.stats,
      deadLetterQueueSize: status.deadLetterQueueSize,
    },
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /api/queue/:sessionId/messages - Get queued messages for a session
 */
router.get('/:sessionId/messages', (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Getting queued messages', { sessionId, requestId });

  const queue = messageQueueManager.getQueue(sessionId);

  if (!queue) {
    return res.status(404).json({
      success: false,
      error: 'Queue not found for session',
      sessionId,
      requestId,
    });
  }

  const messages = queue.queue.map((msg) => ({
    id: msg.id,
    priority: msg.priority,
    priorityName: Object.keys(MessagePriority).find((key) => MessagePriority[key] === msg.priority),
    timestamp: msg.timestamp,
    status: msg.status,
    attempts: msg.attempts,
    error: msg.error,
    metadata: msg.metadata,
  }));

  const deadLetterMessages = queue.deadLetterQueue.map((msg) => ({
    id: msg.id,
    priority: msg.priority,
    priorityName: Object.keys(MessagePriority).find((key) => MessagePriority[key] === msg.priority),
    timestamp: msg.timestamp,
    status: msg.status,
    attempts: msg.attempts,
    error: msg.error,
    metadata: msg.metadata,
  }));

  res.json({
    success: true,
    sessionId,
    messages: {
      pending: messages,
      deadLetter: deadLetterMessages,
      processing: queue.currentMessage
        ? {
            id: queue.currentMessage.id,
            priority: queue.currentMessage.priority,
            timestamp: queue.currentMessage.timestamp,
          }
        : null,
    },
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/queue/:sessionId/pause - Pause queue processing
 */
router.post('/:sessionId/pause', (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Pausing queue', { sessionId, requestId });

  messageQueueManager.pauseQueue(sessionId);

  const status = messageQueueManager.getQueueStatus(sessionId);

  res.json({
    success: true,
    sessionId,
    action: 'pause',
    paused: status?.paused || true,
    queueLength: status?.queueLength || 0,
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/queue/:sessionId/resume - Resume queue processing
 */
router.post('/:sessionId/resume', (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Resuming queue', { sessionId, requestId });

  messageQueueManager.resumeQueue(sessionId);

  const status = messageQueueManager.getQueueStatus(sessionId);

  res.json({
    success: true,
    sessionId,
    action: 'resume',
    paused: status?.paused || false,
    queueLength: status?.queueLength || 0,
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * POST /api/queue/:sessionId/clear - Clear all queued messages
 */
router.post('/:sessionId/clear', (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Clearing queue', { sessionId, requestId });

  const statusBefore = messageQueueManager.getQueueStatus(sessionId);
  const clearedCount = statusBefore?.queueLength || 0;

  messageQueueManager.clearQueue(sessionId);

  res.json({
    success: true,
    sessionId,
    action: 'clear',
    messagesCleared: clearedCount,
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * DELETE /api/queue/:sessionId - Remove entire queue for a session
 */
router.delete('/:sessionId', (req, res) => {
  const { sessionId } = req.params;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Removing queue', { sessionId, requestId });

  const statusBefore = messageQueueManager.getQueueStatus(sessionId);

  if (!statusBefore) {
    return res.status(404).json({
      success: false,
      error: 'Queue not found for session',
      sessionId,
      requestId,
    });
  }

  messageQueueManager.removeQueue(sessionId);

  res.json({
    success: true,
    sessionId,
    action: 'remove',
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * GET /api/queue/metrics - Get global queue metrics
 */
router.get('/metrics', (req, res) => {
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Getting queue metrics', { requestId });

  const allStatuses = messageQueueManager.getAllQueueStatuses();

  const metrics = {
    totalQueues: Object.keys(allStatuses).length,
    totalMessages: 0,
    totalProcessing: 0,
    totalPaused: 0,
    totalDeadLetter: 0,
    queues: {},
  };

  for (const [sessionId, status] of Object.entries(allStatuses)) {
    metrics.totalMessages += status.queueLength;
    if (status.processing) metrics.totalProcessing++;
    if (status.paused) metrics.totalPaused++;
    metrics.totalDeadLetter += status.deadLetterQueueSize;

    metrics.queues[sessionId] = {
      queueLength: status.queueLength,
      processing: status.processing,
      paused: status.paused,
      stats: status.stats,
    };
  }

  res.json({
    success: true,
    metrics,
    requestId,
    timestamp: new Date().toISOString(),
  });
});

/**
 * PUT /api/queue/:sessionId/message/:messageId/priority - Update message priority
 */
router.put('/:sessionId/message/:messageId/priority', (req, res) => {
  const { sessionId, messageId } = req.params;
  const { priority } = req.body;
  const requestId =
    req.headers['x-request-id'] || `REQ_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

  logger.info('Updating message priority', { sessionId, messageId, priority, requestId });

  // Validate priority
  const validPriorities = Object.values(MessagePriority);
  if (!validPriorities.includes(priority)) {
    return res.status(400).json({
      success: false,
      error: 'Invalid priority. Must be 0 (HIGH), 1 (NORMAL), or 2 (LOW)',
      requestId,
    });
  }

  const queue = messageQueueManager.getQueue(sessionId);

  if (!queue) {
    return res.status(404).json({
      success: false,
      error: 'Queue not found for session',
      sessionId,
      requestId,
    });
  }

  // Find and update message priority
  const messageIndex = queue.queue.findIndex((msg) => msg.id === messageId);

  if (messageIndex === -1) {
    return res.status(404).json({
      success: false,
      error: 'Message not found in queue',
      messageId,
      requestId,
    });
  }

  // Update priority and reorder queue
  queue.queue[messageIndex].priority = priority;
  queue.reorderQueue();

  res.json({
    success: true,
    sessionId,
    messageId,
    newPriority: priority,
    priorityName: Object.keys(MessagePriority).find((key) => MessagePriority[key] === priority),
    requestId,
    timestamp: new Date().toISOString(),
  });
});

export default router;
