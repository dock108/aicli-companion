/**
 * Manages connection state persistence for WebSocket clients
 * This allows tracking client connection history across server restarts (when using persistent storage)
 */
export class ConnectionStateManager {
  constructor(options = {}) {
    // TODO: [QUESTION] Should connection state persist across server restarts?
    // Current implementation: in-memory only
    // Alternative: Redis, SQLite, or file-based persistence
    this.storage = options.storage || 'memory'; // 'memory' | 'redis' | 'file'
    this.ttl = options.ttl || 86400000; // 24 hours default

    // In-memory storage
    this.connectionStates = new Map(); // clientFingerprint -> state data

    // Cleanup interval (disabled in test)
    if (process.env.NODE_ENV !== 'test') {
      this.cleanupInterval = setInterval(() => {
        this.cleanupExpiredStates();
      }, 3600000); // 1 hour
    }
  }

  /**
   * Save connection state
   */
  async saveConnectionState(fingerprint, state) {
    const stateData = {
      ...state,
      lastUpdated: Date.now(),
      expiresAt: Date.now() + this.ttl,
    };

    this.connectionStates.set(fingerprint, stateData);

    // TODO: [OPTIMIZE] Implement Redis persistence here
    // if (this.storage === 'redis') {
    //   await this.redis.setex(
    //     `conn:${fingerprint}`,
    //     Math.floor(this.ttl / 1000),
    //     JSON.stringify(stateData)
    //   );
    // }

    console.log(`💾 Saved connection state for ${fingerprint}`);
    return true;
  }

  /**
   * Get connection state
   */
  async getConnectionState(fingerprint) {
    const state = this.connectionStates.get(fingerprint);

    if (!state) {
      // TODO: [OPTIMIZE] Check Redis if using persistent storage
      return null;
    }

    // Check if expired
    if (Date.now() > state.expiresAt) {
      this.connectionStates.delete(fingerprint);
      return null;
    }

    return state;
  }

  /**
   * Update connection sessions
   */
  async updateConnectionSessions(fingerprint, sessionIds) {
    const state = await this.getConnectionState(fingerprint);

    if (!state) {
      // Create new state
      return this.saveConnectionState(fingerprint, {
        sessionIds: new Set(sessionIds),
        firstSeen: Date.now(),
      });
    }

    // Update existing state
    state.sessionIds = new Set([...state.sessionIds, ...sessionIds]);
    return this.saveConnectionState(fingerprint, state);
  }

  /**
   * Clean up expired states
   */
  cleanupExpiredStates() {
    const now = Date.now();
    let cleaned = 0;

    for (const [fingerprint, state] of this.connectionStates) {
      if (now > state.expiresAt) {
        this.connectionStates.delete(fingerprint);
        cleaned++;
      }
    }

    if (cleaned > 0) {
      console.log(`🧹 Cleaned ${cleaned} expired connection states`);
    }
  }

  /**
   * Get statistics
   */
  getStats() {
    const now = Date.now();
    let active = 0;
    let expired = 0;

    for (const [, state] of this.connectionStates) {
      if (now > state.expiresAt) {
        expired++;
      } else {
        active++;
      }
    }

    return {
      total: this.connectionStates.size,
      active,
      expired,
      storageType: this.storage,
    };
  }

  /**
   * Shutdown
   */
  shutdown() {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
    }

    // TODO: [OPTIMIZE] Close Redis connection if using

    console.log('💾 Connection state manager shut down');
  }
}
