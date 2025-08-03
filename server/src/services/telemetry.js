/**
 * Telemetry service for collecting performance metrics and usage statistics
 */
export class TelemetryService {
  constructor(options = {}) {
    this.metrics = {
      websocket: {
        connections: new Map(), // clientId -> connection metrics
        messages: { sent: 0, received: 0, failed: 0 },
        latency: [],
        reconnections: 0,
      },
      sessions: {
        created: 0,
        resumed: 0,
        expired: 0,
        active: 0,
        duplicatesPrevented: 0,
      },
      messages: {
        queued: 0,
        delivered: 0,
        expired: 0,
        filtered: 0,
      },
      performance: {
        messageProcessingTime: [],
        queueDeliveryTime: [],
      },
    };

    // TODO: [QUESTION] Metric retention policy
    // How long to keep metrics in memory?
    // Should we persist to disk or external service?

    this.retentionTime = options.retentionTime || 3600000; // 1 hour default
    this.maxLatencyEntries = options.maxLatencyEntries || 1000;

    // Cleanup old metrics periodically (disabled in test)
    if (process.env.NODE_ENV !== 'test') {
      this.cleanupInterval = setInterval(() => {
        this.cleanupOldMetrics();
      }, 300000); // 5 minutes
    }
  }

  /**
   * Record WebSocket connection
   */
  recordConnection(clientId, clientInfo) {
    this.metrics.websocket.connections.set(clientId, {
      connectedAt: Date.now(),
      clientInfo,
      messagesSent: 0,
      messagesReceived: 0,
      lastActivity: Date.now(),
    });
  }

  /**
   * Record WebSocket disconnection
   */
  recordDisconnection(clientId) {
    const connection = this.metrics.websocket.connections.get(clientId);
    if (connection) {
      const _duration = Date.now() - connection.connectedAt;
      // TODO: [OPTIMIZE] Store connection duration statistics
      this.metrics.websocket.connections.delete(clientId);
    }
  }

  /**
   * Record WebSocket reconnection
   */
  recordReconnection(_clientId, _previousClientId) {
    this.metrics.websocket.reconnections++;
  }

  /**
   * Record message sent
   */
  recordMessageSent(clientId, messageType, success = true) {
    if (success) {
      this.metrics.websocket.messages.sent++;
    } else {
      this.metrics.websocket.messages.failed++;
    }

    const connection = this.metrics.websocket.connections.get(clientId);
    if (connection) {
      if (success) {
        connection.messagesSent++;
      }
      connection.lastActivity = Date.now();
    }
  }

  /**
   * Record message received
   */
  recordMessageReceived(clientId, _messageType) {
    this.metrics.websocket.messages.received++;

    const connection = this.metrics.websocket.connections.get(clientId);
    if (connection) {
      connection.messagesReceived++;
      connection.lastActivity = Date.now();
    }
  }

  /**
   * Record message processing time
   */
  recordMessageProcessingTime(messageType, duration) {
    this.metrics.performance.messageProcessingTime.push({
      type: messageType,
      duration,
      timestamp: Date.now(),
    });

    // Limit array size
    if (this.metrics.performance.messageProcessingTime.length > this.maxLatencyEntries) {
      this.metrics.performance.messageProcessingTime.shift();
    }
  }

  /**
   * Record session creation
   */
  recordSessionCreated(reused = false) {
    if (reused) {
      this.metrics.sessions.resumed++;
      this.metrics.sessions.duplicatesPrevented++;
    } else {
      this.metrics.sessions.created++;
    }
    this.updateActiveSessions();
  }

  /**
   * Record session expiration
   */
  recordSessionExpired() {
    this.metrics.sessions.expired++;
    this.updateActiveSessions();
  }

  /**
   * Update active session count
   */
  updateActiveSessions(count = null) {
    if (count !== null) {
      this.metrics.sessions.active = count;
    }
  }

  /**
   * Record message queued
   */
  recordMessageQueued() {
    this.metrics.messages.queued++;
  }

  /**
   * Record message delivered
   */
  recordMessageDelivered() {
    this.metrics.messages.delivered++;
  }

  /**
   * Record message expired
   */
  recordMessageExpired() {
    this.metrics.messages.expired++;
  }

  /**
   * Record message filtered
   */
  recordMessageFiltered(_reason) {
    this.metrics.messages.filtered++;
    // TODO: [OPTIMIZE] Track filter reasons
  }

  /**
   * Record queue delivery time
   */
  recordQueueDeliveryTime(duration) {
    this.metrics.performance.queueDeliveryTime.push({
      duration,
      timestamp: Date.now(),
    });

    // Limit array size
    if (this.metrics.performance.queueDeliveryTime.length > this.maxLatencyEntries) {
      this.metrics.performance.queueDeliveryTime.shift();
    }
  }

  /**
   * Get current metrics
   */
  getMetrics() {
    const now = Date.now();

    // Calculate aggregated stats
    const activeConnections = this.metrics.websocket.connections.size;

    const avgMessageProcessingTime = this.calculateAverage(
      this.metrics.performance.messageProcessingTime.map((m) => m.duration)
    );

    const avgQueueDeliveryTime = this.calculateAverage(
      this.metrics.performance.queueDeliveryTime.map((m) => m.duration)
    );

    return {
      timestamp: now,
      websocket: {
        activeConnections,
        totalMessages: {
          sent: this.metrics.websocket.messages.sent,
          received: this.metrics.websocket.messages.received,
          failed: this.metrics.websocket.messages.failed,
        },
        reconnections: this.metrics.websocket.reconnections,
      },
      sessions: { ...this.metrics.sessions },
      messages: { ...this.metrics.messages },
      performance: {
        avgMessageProcessingTime,
        avgQueueDeliveryTime,
        recentProcessingTimes: this.metrics.performance.messageProcessingTime.slice(-10),
      },
    };
  }

  /**
   * Get connection-specific metrics
   */
  getConnectionMetrics(clientId) {
    const connection = this.metrics.websocket.connections.get(clientId);
    if (!connection) return null;

    return {
      ...connection,
      connectionDuration: Date.now() - connection.connectedAt,
    };
  }

  /**
   * Calculate average
   */
  calculateAverage(values) {
    if (values.length === 0) return 0;
    return values.reduce((sum, val) => sum + val, 0) / values.length;
  }

  /**
   * Clean up old metrics
   */
  cleanupOldMetrics() {
    const cutoff = Date.now() - this.retentionTime;

    // Clean up old latency entries
    this.metrics.performance.messageProcessingTime =
      this.metrics.performance.messageProcessingTime.filter((m) => m.timestamp > cutoff);

    this.metrics.performance.queueDeliveryTime = this.metrics.performance.queueDeliveryTime.filter(
      (m) => m.timestamp > cutoff
    );

    // Clean up old latency entries
    if (this.metrics.websocket.latency.length > this.maxLatencyEntries * 2) {
      this.metrics.websocket.latency = this.metrics.websocket.latency.slice(
        -this.maxLatencyEntries
      );
    }
  }

  /**
   * Reset metrics
   */
  reset() {
    // Reset counters but keep structure
    this.metrics.websocket.messages = { sent: 0, received: 0, failed: 0 };
    this.metrics.websocket.reconnections = 0;
    this.metrics.sessions = {
      created: 0,
      resumed: 0,
      expired: 0,
      active: this.metrics.sessions.active, // Keep active count
      duplicatesPrevented: 0,
    };
    this.metrics.messages = {
      queued: 0,
      delivered: 0,
      expired: 0,
      filtered: 0,
    };
    this.metrics.performance = {
      messageProcessingTime: [],
      queueDeliveryTime: [],
    };
    this.metrics.websocket.connections.clear();
  }

  /**
   * Shutdown
   */
  shutdown() {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
    console.log('📊 Telemetry service shut down');
  }
}

// Create singleton instance lazily to avoid test issues
let _telemetryService = null;

export const getTelemetryService = () => {
  if (!_telemetryService) {
    _telemetryService = new TelemetryService();
  }
  return _telemetryService;
};

// For backward compatibility and easy access
export const telemetryService =
  process.env.NODE_ENV === 'test'
    ? null // Don't create singleton in test environment
    : getTelemetryService();
