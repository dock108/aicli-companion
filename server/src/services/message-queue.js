// Message queue service for persisting messages to disconnected clients
// This handles the case where long-running tasks complete after the client disconnects

export class MessageQueueService {
  constructor() {
    // In-memory storage for now, can be replaced with Redis later
    this.messageQueue = new Map(); // sessionId -> Array of queued messages
    this.messageMetadata = new Map(); // messageId -> metadata (timestamp, delivered, etc)
    this.sessionClientMap = new Map(); // sessionId -> Set of clientIds that have accessed this session

    // Cleanup old messages every hour (disabled in test environment)
    if (process.env.NODE_ENV !== 'test') {
      this.cleanupInterval = setInterval(() => {
        this.cleanupExpiredMessages();
      }, 3600000); // 1 hour
    }
  }

  /**
   * Queue a message for a session
   * @param {string} sessionId - The session ID
   * @param {Object} message - The message to queue
   * @param {Object} options - Options including TTL
   */
  queueMessage(sessionId, message, options = {}) {
    const messageId = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    const timestamp = new Date();
    const ttl = options.ttl || 86400000; // Default 24 hours
    const expiresAt = new Date(timestamp.getTime() + ttl);

    // Store message
    if (!this.messageQueue.has(sessionId)) {
      this.messageQueue.set(sessionId, []);
    }

    const queuedMessage = {
      id: messageId,
      sessionId,
      message,
      timestamp,
      expiresAt,
      delivered: false,
      deliveredAt: null,
      deliveredTo: new Set(),
    };

    this.messageQueue.get(sessionId).push(queuedMessage);
    this.messageMetadata.set(messageId, queuedMessage);

    console.log(`📥 Queued message ${messageId} for session ${sessionId}`);
    console.log(`   Message type: ${message.type}`);
    console.log(`   Expires at: ${expiresAt.toISOString()}`);
    console.log(`   Queue size for session: ${this.messageQueue.get(sessionId).length}`);

    return messageId;
  }

  /**
   * Get all undelivered messages for a session
   * @param {string} sessionId - The session ID
   * @param {string} clientId - The client ID requesting messages
   * @returns {Array} Array of undelivered messages
   */
  getUndeliveredMessages(sessionId, clientId) {
    const messages = this.messageQueue.get(sessionId) || [];
    const undelivered = [];

    for (const queuedMessage of messages) {
      // Skip if expired
      if (new Date() > queuedMessage.expiresAt) {
        continue;
      }

      // Skip if already delivered to this client
      if (queuedMessage.deliveredTo.has(clientId)) {
        continue;
      }

      undelivered.push(queuedMessage);
    }

    console.log(
      `📤 Found ${undelivered.length} undelivered messages for session ${sessionId}, client ${clientId}`
    );
    return undelivered;
  }

  /**
   * Mark messages as delivered to a specific client
   * @param {Array} messageIds - Array of message IDs
   * @param {string} clientId - The client ID
   */
  markAsDelivered(messageIds, clientId) {
    for (const messageId of messageIds) {
      const metadata = this.messageMetadata.get(messageId);
      if (metadata) {
        metadata.deliveredTo.add(clientId);
        metadata.deliveredAt = new Date();

        // Check if delivered to all clients that have accessed this session
        const sessionClients = this.sessionClientMap.get(metadata.sessionId) || new Set();
        if (sessionClients.size > 0 && metadata.deliveredTo.size >= sessionClients.size) {
          metadata.delivered = true;
        }

        console.log(`✅ Marked message ${messageId} as delivered to client ${clientId}`);
      }
    }
  }

  /**
   * Track that a client has accessed a session
   * @param {string} sessionId - The session ID
   * @param {string} clientId - The client ID
   */
  trackSessionClient(sessionId, clientId) {
    if (!this.sessionClientMap.has(sessionId)) {
      this.sessionClientMap.set(sessionId, new Set());
    }
    this.sessionClientMap.get(sessionId).add(clientId);
  }

  /**
   * Check if there are any queued messages for a session
   * @param {string} sessionId - The session ID
   * @returns {boolean} True if there are queued messages
   */
  hasQueuedMessages(sessionId) {
    const messages = this.messageQueue.get(sessionId) || [];
    return messages.some((msg) => new Date() <= msg.expiresAt && !msg.delivered);
  }

  /**
   * Get statistics about the message queue
   * @returns {Object} Queue statistics
   */
  getStatistics() {
    let totalMessages = 0;
    let undeliveredMessages = 0;
    let expiredMessages = 0;
    const now = new Date();

    for (const [, messages] of this.messageQueue) {
      totalMessages += messages.length;
      for (const msg of messages) {
        if (now > msg.expiresAt) {
          expiredMessages++;
        } else if (!msg.delivered) {
          undeliveredMessages++;
        }
      }
    }

    return {
      totalSessions: this.messageQueue.size,
      totalMessages,
      undeliveredMessages,
      expiredMessages,
      trackedClients: Array.from(this.sessionClientMap.values()).reduce(
        (sum, set) => sum + set.size,
        0
      ),
    };
  }

  /**
   * Clean up expired messages
   */
  cleanupExpiredMessages() {
    const now = new Date();
    let cleanedCount = 0;

    for (const [sessionId, messages] of this.messageQueue) {
      const validMessages = messages.filter((msg) => {
        const expired = now > msg.expiresAt;
        if (expired) {
          this.messageMetadata.delete(msg.id);
          cleanedCount++;
        }
        return !expired;
      });

      if (validMessages.length === 0) {
        this.messageQueue.delete(sessionId);
        this.sessionClientMap.delete(sessionId);
      } else {
        this.messageQueue.set(sessionId, validMessages);
      }
    }

    if (cleanedCount > 0) {
      console.log(`🧹 Cleaned up ${cleanedCount} expired messages`);
    }
  }

  /**
   * Clear all messages for a session
   * @param {string} sessionId - The session ID
   */
  clearSession(sessionId) {
    const messages = this.messageQueue.get(sessionId) || [];
    for (const msg of messages) {
      this.messageMetadata.delete(msg.id);
    }
    this.messageQueue.delete(sessionId);
    this.sessionClientMap.delete(sessionId);
    console.log(`🗑️ Cleared all messages for session ${sessionId}`);
  }

  /**
   * Shutdown the service
   */
  shutdown() {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }
    this.messageQueue.clear();
    this.messageMetadata.clear();
    this.sessionClientMap.clear();
    console.log('📭 Message queue service shut down');
  }
}

// Export singleton instance
export const messageQueueService = new MessageQueueService();
