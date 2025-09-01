/**
 * Message Queue Management Service
 * Handles per-session message queuing with priority support for auto-reply control
 */

import { EventEmitter } from 'events';
import { randomUUID } from 'crypto';
import Debug from 'debug';
import { duplicateDetector } from './duplicate-detector.js';

const debug = Debug('aicli:message-queue');

// Priority levels for message processing
export const MessagePriority = {
  HIGH: 0, // Process immediately, before auto-replies (stop commands, user interventions)
  NORMAL: 1, // Standard processing order (regular messages)
  LOW: 2, // Process after auto-replies (auto-generated follow-ups)
};

// Queue configuration
const DEFAULT_CONFIG = {
  maxQueueSize: 1000, // Maximum messages per queue
  processingTimeout: 300000, // 5 minutes timeout for processing
  retryAttempts: 3, // Number of retry attempts
  retryDelay: 1000, // Delay between retries (ms)
  allowInterruption: true, // Allow high priority to interrupt processing
  metricsInterval: 60000, // Emit metrics every minute
};

/**
 * Message wrapper with metadata
 */
class QueuedMessage {
  constructor(message, priority = MessagePriority.NORMAL, metadata = {}) {
    this.id = `msg_${randomUUID()}`;
    this.message = message;
    this.priority = priority;
    this.metadata = metadata;
    this.timestamp = Date.now();
    this.attempts = 0;
    this.status = 'pending';
    this.error = null;
  }
}

/**
 * Per-session message queue
 */
class SessionQueue extends EventEmitter {
  constructor(sessionId, config = {}) {
    super();
    this.sessionId = sessionId;
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.queue = [];
    this.processing = false;
    this.currentMessage = null;
    this.stats = {
      messagesQueued: 0,
      messagesProcessed: 0,
      messagesFailed: 0,
      averageProcessingTime: 0,
      queueDepth: 0,
      lastProcessedAt: null,
    };
    this.deadLetterQueue = [];
    this.paused = false;
  }

  /**
   * Add a message to the queue with priority
   */
  enqueue(message, priority = MessagePriority.NORMAL, metadata = {}) {
    if (this.queue.length >= this.config.maxQueueSize) {
      const error = new Error(`Queue overflow for session ${this.sessionId}`);
      this.emit('queue-overflow', { sessionId: this.sessionId, message, error });
      throw error;
    }

    // Check for duplicates if deviceId is provided in metadata
    if (metadata.deviceId && message.content) {
      const duplicateResult = duplicateDetector.processMessage(message, metadata.deviceId);
      
      if (duplicateResult.isDuplicate) {
        debug(`Duplicate message detected from device ${metadata.deviceId}: ${duplicateResult.messageHash}`);
        
        this.emit('duplicate-message', {
          sessionId: this.sessionId,
          deviceId: metadata.deviceId,
          messageHash: duplicateResult.messageHash,
          duplicateInfo: duplicateResult.duplicateInfo
        });

        // Return without enqueuing
        return {
          queued: false,
          reason: 'duplicate',
          messageHash: duplicateResult.messageHash,
          duplicateInfo: duplicateResult.duplicateInfo
        };
      }

      // Add hash to metadata for tracking
      metadata.messageHash = duplicateResult.messageHash;
    }

    const queuedMessage = new QueuedMessage(message, priority, metadata);

    // Insert based on priority
    if (priority === MessagePriority.HIGH && this.config.allowInterruption) {
      // High priority messages go to the front of their priority group
      const insertIndex = this.findInsertIndex(priority);
      this.queue.splice(insertIndex, 0, queuedMessage);
      debug(`High priority message ${queuedMessage.id} inserted at position ${insertIndex}`);

      // Emit interrupt event if currently processing a lower priority message
      if (this.processing && this.currentMessage && this.currentMessage.priority > priority) {
        this.emit('interrupt-requested', {
          currentMessage: this.currentMessage,
          interruptingMessage: queuedMessage,
        });
      }
    } else {
      // Normal and low priority messages maintain FIFO within their priority
      const insertIndex = this.findInsertIndex(priority, true);
      this.queue.splice(insertIndex, 0, queuedMessage);
      debug(
        `Message ${queuedMessage.id} with priority ${priority} queued at position ${insertIndex}`
      );
    }

    this.stats.messagesQueued++;
    this.stats.queueDepth = this.queue.length;
    this.emit('message-queued', {
      sessionId: this.sessionId,
      messageId: queuedMessage.id,
      queueDepth: this.queue.length,
    });

    // Start processing if not already processing
    if (!this.processing && !this.paused) {
      this.processNext();
    }

    return {
      queued: true,
      messageId: queuedMessage.id,
      messageHash: metadata.messageHash
    };
  }

  /**
   * Find the correct insertion index based on priority
   */
  findInsertIndex(priority, appendWithinPriority = false) {
    for (let i = 0; i < this.queue.length; i++) {
      if (this.queue[i].priority > priority) {
        return i;
      }
      if (this.queue[i].priority === priority && !appendWithinPriority) {
        return i;
      }
    }
    return this.queue.length;
  }

  /**
   * Process the next message in the queue
   */
  async processNext() {
    if (this.processing || this.paused || this.queue.length === 0) {
      return;
    }

    this.processing = true;
    this.currentMessage = this.queue.shift();
    const startTime = Date.now();

    try {
      debug(`Processing message ${this.currentMessage.id} for session ${this.sessionId}`);
      this.currentMessage.status = 'processing';
      this.emit('message-processing', {
        sessionId: this.sessionId,
        messageId: this.currentMessage.id,
        priority: this.currentMessage.priority,
      });

      // Set a timeout for processing
      const timeoutPromise = new Promise((_, reject) => {
        setTimeout(() => reject(new Error('Processing timeout')), this.config.processingTimeout);
      });

      // Emit the message for processing
      const processingPromise = new Promise((resolve, reject) => {
        this.emit('process-message', this.currentMessage, (error, result) => {
          if (error) reject(error);
          else resolve(result);
        });
      });

      await Promise.race([processingPromise, timeoutPromise]);

      // Success
      this.currentMessage.status = 'completed';
      this.stats.messagesProcessed++;
      this.stats.lastProcessedAt = Date.now();

      const processingTime = Date.now() - startTime;
      this.stats.averageProcessingTime =
        (this.stats.averageProcessingTime * (this.stats.messagesProcessed - 1) + processingTime) /
        this.stats.messagesProcessed;

      this.emit('message-processed', {
        sessionId: this.sessionId,
        messageId: this.currentMessage.id,
        processingTime,
      });
    } catch (error) {
      debug(`Error processing message ${this.currentMessage.id}: ${error.message}`);
      this.currentMessage.attempts++;
      this.currentMessage.error = error.message;

      if (this.currentMessage.attempts < this.config.retryAttempts) {
        // Retry with exponential backoff
        const delay = this.config.retryDelay * Math.pow(2, this.currentMessage.attempts - 1);
        debug(
          `Retrying message ${this.currentMessage.id} after ${delay}ms (attempt ${this.currentMessage.attempts})`
        );

        // Save message for retry since currentMessage will be cleared
        const messageToRetry = this.currentMessage;
        setTimeout(() => {
          this.queue.unshift(messageToRetry);
          if (!this.processing && !this.paused) {
            this.processNext();
          }
        }, delay);
      } else {
        // Move to dead letter queue
        this.currentMessage.status = 'failed';
        this.deadLetterQueue.push(this.currentMessage);
        this.stats.messagesFailed++;

        this.emit('message-failed', {
          sessionId: this.sessionId,
          messageId: this.currentMessage.id,
          error: error.message,
          attempts: this.currentMessage.attempts,
        });
      }
    } finally {
      this.processing = false;
      this.currentMessage = null;
      this.stats.queueDepth = this.queue.length;

      // Process next message if available
      if (this.queue.length > 0 && !this.paused) {
        setImmediate(() => this.processNext());
      }
    }
  }

  /**
   * Pause queue processing
   */
  pause() {
    this.paused = true;
    this.emit('queue-paused', { sessionId: this.sessionId });
  }

  /**
   * Resume queue processing
   */
  resume() {
    this.paused = false;
    this.emit('queue-resumed', { sessionId: this.sessionId });
    if (this.queue.length > 0 && !this.processing) {
      this.processNext();
    }
  }

  /**
   * Clear the queue
   */
  clear() {
    const clearedCount = this.queue.length;
    this.queue = [];
    this.stats.queueDepth = 0;
    this.emit('queue-cleared', { sessionId: this.sessionId, clearedCount });
  }

  /**
   * Get queue status
   */
  getStatus() {
    return {
      sessionId: this.sessionId,
      queueLength: this.queue.length,
      processing: this.processing,
      paused: this.paused,
      currentMessage: this.currentMessage
        ? {
            id: this.currentMessage.id,
            priority: this.currentMessage.priority,
            timestamp: this.currentMessage.timestamp,
          }
        : null,
      stats: { ...this.stats },
      deadLetterQueueSize: this.deadLetterQueue.length,
    };
  }

  /**
   * Get messages by priority
   */
  getMessagesByPriority(priority) {
    return this.queue.filter((msg) => msg.priority === priority);
  }

  /**
   * Reorder queue based on new priorities
   */
  reorderQueue() {
    this.queue.sort((a, b) => {
      if (a.priority !== b.priority) {
        return a.priority - b.priority;
      }
      return a.timestamp - b.timestamp; // FIFO within same priority
    });
  }

  /**
   * Clean up resources
   */
  destroy() {
    this.clear();
    this.removeAllListeners();
  }
}

/**
 * Message Queue Manager - manages queues for all sessions
 */
export class MessageQueueManager extends EventEmitter {
  constructor(config = {}) {
    super();
    this.config = { ...DEFAULT_CONFIG, ...config };
    this.queues = new Map();
    this.globalStats = {
      totalQueues: 0,
      totalMessagesQueued: 0,
      totalMessagesProcessed: 0,
      totalMessagesFailed: 0,
    };

    // Start metrics reporting
    if (this.config.metricsInterval > 0) {
      this.metricsTimer = setInterval(() => this.emitMetrics(), this.config.metricsInterval);
    }
  }

  /**
   * Get or create a queue for a session
   */
  getQueue(sessionId) {
    if (!this.queues.has(sessionId)) {
      const queue = new SessionQueue(sessionId, this.config);

      // Forward events from session queue
      queue.on('message-queued', (data) => this.emit('message-queued', data));
      queue.on('message-processing', (data) => this.emit('message-processing', data));
      queue.on('message-processed', (data) => {
        this.globalStats.totalMessagesProcessed++;
        this.emit('message-processed', data);
      });
      queue.on('message-failed', (data) => {
        this.globalStats.totalMessagesFailed++;
        this.emit('message-failed', data);
      });
      queue.on('queue-overflow', (data) => this.emit('queue-overflow', data));
      queue.on('interrupt-requested', (data) => this.emit('interrupt-requested', data));

      this.queues.set(sessionId, queue);
      this.globalStats.totalQueues++;
      debug(`Created queue for session ${sessionId}`);
    }
    return this.queues.get(sessionId);
  }

  /**
   * Queue a message for a session
   */
  queueMessage(sessionId, message, priority = MessagePriority.NORMAL, metadata = {}) {
    const queue = this.getQueue(sessionId);
    this.globalStats.totalMessagesQueued++;
    return queue.enqueue(message, priority, metadata);
  }

  /**
   * Process a message handler for a session
   */
  setMessageHandler(sessionId, handler) {
    const queue = this.getQueue(sessionId);
    queue.removeAllListeners('process-message');
    queue.on('process-message', handler);
  }

  /**
   * Pause a session's queue
   */
  pauseQueue(sessionId) {
    const queue = this.queues.get(sessionId);
    if (queue) {
      queue.pause();
    }
  }

  /**
   * Resume a session's queue
   */
  resumeQueue(sessionId) {
    const queue = this.queues.get(sessionId);
    if (queue) {
      queue.resume();
    }
  }

  /**
   * Clear a session's queue
   */
  clearQueue(sessionId) {
    const queue = this.queues.get(sessionId);
    if (queue) {
      queue.clear();
    }
  }

  /**
   * Get status for a session's queue
   */
  getQueueStatus(sessionId) {
    const queue = this.queues.get(sessionId);
    if (queue) {
      const status = queue.getStatus();
      // Transform to API format
      return {
        sessionId: status.sessionId,
        queue: {
          length: status.queueLength,
          processing: status.processing,
          paused: status.paused,
          currentMessage: status.currentMessage,
          stats: status.stats,
          deadLetterQueueSize: status.deadLetterQueueSize,
        },
      };
    }
    // Return default status for non-existent queue
    return {
      sessionId,
      queue: {
        length: 0,
        processing: false,
        paused: false,
        currentMessage: null,
        stats: {
          messagesQueued: 0,
          messagesProcessed: 0,
          messagesFailed: 0,
          averageProcessingTime: 0,
          queueDepth: 0,
          lastProcessedAt: null,
        },
        deadLetterQueueSize: 0,
      },
    };
  }

  /**
   * Get status for all queues
   */
  getAllQueueStatuses() {
    const statuses = {};
    for (const [sessionId, queue] of this.queues) {
      const status = queue.getStatus();
      statuses[sessionId] = {
        sessionId: status.sessionId,
        queue: {
          length: status.queueLength,
          processing: status.processing,
          paused: status.paused,
          currentMessage: status.currentMessage,
          stats: status.stats,
          deadLetterQueueSize: status.deadLetterQueueSize,
        },
      };
    }
    return statuses;
  }

  /**
   * Remove a session's queue
   */
  removeQueue(sessionId) {
    const queue = this.queues.get(sessionId);
    if (queue) {
      queue.destroy();
      this.queues.delete(sessionId);
      this.globalStats.totalQueues--;
      debug(`Removed queue for session ${sessionId}`);
    }
  }

  /**
   * Emit metrics for monitoring
   */
  emitMetrics() {
    const metrics = {
      ...this.globalStats,
      activeQueues: this.queues.size,
      queueStatuses: {},
    };

    for (const [sessionId, queue] of this.queues) {
      metrics.queueStatuses[sessionId] = {
        queueDepth: queue.queue.length,
        processing: queue.processing,
        stats: queue.stats,
      };
    }

    this.emit('metrics', metrics);
    debug('Metrics emitted:', metrics);
  }

  /**
   * Clean up all resources
   */
  destroy() {
    if (this.metricsTimer) {
      clearInterval(this.metricsTimer);
    }
    for (const queue of this.queues.values()) {
      queue.destroy();
    }
    this.queues.clear();
    this.removeAllListeners();
  }
}

// Export singleton instance
export const messageQueueManager = new MessageQueueManager();
export default messageQueueManager;
