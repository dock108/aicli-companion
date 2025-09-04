import { createHash } from 'crypto';
import { getTelemetryService } from './telemetry.js';

/**
 * Detects and prevents duplicate messages across devices
 * using content hashing and temporal windows
 */
export class DuplicateDetector {
  constructor(options = {}) {
    // Configuration
    this.timeWindow = options.timeWindow || 5000; // 5 seconds
    this.maxEntries = options.maxEntries || 10000; // Maximum hash entries to store
    this.cleanupInterval = options.cleanupInterval || 60000; // 1 minute

    // Storage for message hashes with timestamps
    this.messageHashes = new Map(); // hash -> { timestamp, deviceId, sessionId }
    this.deviceMessageCount = new Map(); // deviceId -> count

    // Start periodic cleanup
    this.startCleanup();
  }

  /**
   * Generate a hash for a message to detect duplicates
   * @param {Object} message - Message object
   * @returns {string} Message hash
   */
  generateMessageHash(message) {
    // Create hash from message content, excluding timing and device-specific fields
    const hashContent = {
      content: message.content || '',
      sessionId: message.sessionId || '',
      projectPath: message.projectPath || '',
      attachments: message.attachments || [],
      // Exclude deviceId, timestamp, requestId - these should be device-specific
    };

    // Sort attachments to ensure consistent hashing
    if (hashContent.attachments && hashContent.attachments.length > 0) {
      hashContent.attachments = hashContent.attachments
        .map((att) => ({
          name: att.name || '',
          type: att.type || '',
          size: att.size || 0,
          // Exclude actual data/content for privacy and performance
        }))
        .sort((a, b) => a.name.localeCompare(b.name));
    }

    const hashInput = JSON.stringify(hashContent);
    return createHash('sha256').update(hashInput).digest('hex').substring(0, 16);
  }

  /**
   * Check if a message is a duplicate
   * @param {string} messageHash - Message hash
   * @param {string} deviceId - Device identifier
   * @param {string} sessionId - Session identifier
   * @returns {Object} Duplicate check result
   */
  isDuplicate(messageHash, deviceId, sessionId) {
    const now = Date.now();
    const telemetry = getTelemetryService();

    // Check if hash exists within time window
    const existingEntry = this.messageHashes.get(messageHash);

    if (existingEntry) {
      const timeDiff = now - existingEntry.timestamp;

      if (timeDiff <= this.timeWindow) {
        // Duplicate detected
        telemetry.trackEvent('duplicate_message_detected', {
          messageHash: `${messageHash.substring(0, 8)}...`,
          deviceId: `${deviceId.substring(0, 8)}...`,
          originalDeviceId: `${existingEntry.deviceId.substring(0, 8)}...`,
          timeDiff,
          sessionId: `${sessionId.substring(0, 8)}...`,
        });

        return {
          isDuplicate: true,
          originalDeviceId: existingEntry.deviceId,
          originalTimestamp: existingEntry.timestamp,
          timeDifference: timeDiff,
        };
      } else {
        // Hash exists but outside time window - update with new entry
        this.messageHashes.set(messageHash, {
          timestamp: now,
          deviceId,
          sessionId,
        });
      }
    } else {
      // New hash - record it
      this.messageHashes.set(messageHash, {
        timestamp: now,
        deviceId,
        sessionId,
      });
    }

    // Track device message count
    this.deviceMessageCount.set(deviceId, (this.deviceMessageCount.get(deviceId) || 0) + 1);

    return {
      isDuplicate: false,
      messageHash,
    };
  }

  /**
   * Record a message hash to prevent future duplicates
   * @param {string} messageHash - Message hash
   * @param {string} deviceId - Device identifier
   * @param {string} sessionId - Session identifier
   */
  recordMessage(messageHash, deviceId, sessionId) {
    const now = Date.now();

    this.messageHashes.set(messageHash, {
      timestamp: now,
      deviceId,
      sessionId,
    });

    // Update device count
    this.deviceMessageCount.set(deviceId, (this.deviceMessageCount.get(deviceId) || 0) + 1);

    // Cleanup if we're approaching max entries
    if (this.messageHashes.size > this.maxEntries) {
      this.performCleanup();
    }
  }

  /**
   * Check if a message would be a duplicate (without recording it)
   * @param {Object} message - Message object
   * @param {string} deviceId - Device identifier
   * @returns {Object} Duplicate check result
   */
  checkMessage(message, deviceId) {
    const messageHash = this.generateMessageHash(message);
    return this.isDuplicate(messageHash, deviceId, message.sessionId || 'unknown');
  }

  /**
   * Process and record a message, checking for duplicates
   * @param {Object} message - Message object
   * @param {string} deviceId - Device identifier
   * @returns {Object} Processing result
   */
  processMessage(message, deviceId) {
    const messageHash = this.generateMessageHash(message);
    const duplicateCheck = this.isDuplicate(messageHash, deviceId, message.sessionId || 'unknown');

    if (!duplicateCheck.isDuplicate) {
      // Record the message hash
      this.recordMessage(messageHash, deviceId, message.sessionId || 'unknown');
    }

    return {
      messageHash,
      isDuplicate: duplicateCheck.isDuplicate,
      shouldProcess: !duplicateCheck.isDuplicate,
      duplicateInfo: duplicateCheck.isDuplicate
        ? {
            originalDeviceId: duplicateCheck.originalDeviceId,
            originalTimestamp: duplicateCheck.originalTimestamp,
            timeDifference: duplicateCheck.timeDifference,
          }
        : null,
    };
  }

  /**
   * Get duplicate statistics
   * @returns {Object} Statistics
   */
  getStats() {
    const now = Date.now();
    let recentHashes = 0;
    let oldHashes = 0;

    for (const entry of this.messageHashes.values()) {
      if (now - entry.timestamp <= this.timeWindow) {
        recentHashes++;
      } else {
        oldHashes++;
      }
    }

    const topDevices = Array.from(this.deviceMessageCount.entries())
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([deviceId, count]) => ({
        deviceId: `${deviceId.substring(0, 8)}...`,
        messageCount: count,
      }));

    return {
      totalHashesStored: this.messageHashes.size,
      recentHashes,
      oldHashes,
      duplicateDetectionWindow: this.timeWindow,
      trackedDevices: this.deviceMessageCount.size,
      topDevicesByMessageCount: topDevices,
    };
  }

  /**
   * Clear duplicate detection data for a specific device
   * @param {string} deviceId - Device identifier
   */
  clearDeviceData(deviceId) {
    const telemetry = getTelemetryService();
    let cleared = 0;

    // Remove hashes from this device
    for (const [hash, entry] of this.messageHashes.entries()) {
      if (entry.deviceId === deviceId) {
        this.messageHashes.delete(hash);
        cleared++;
      }
    }

    // Clear device count
    this.deviceMessageCount.delete(deviceId);

    if (cleared > 0) {
      telemetry.trackEvent('device_data_cleared', {
        deviceId: `${deviceId.substring(0, 8)}...`,
        clearedHashes: cleared,
      });
    }

    return { clearedHashes: cleared };
  }

  /**
   * Clear duplicate detection data for a specific session
   * @param {string} sessionId - Session identifier
   */
  clearSessionData(sessionId) {
    let cleared = 0;

    // Remove hashes from this session
    for (const [hash, entry] of this.messageHashes.entries()) {
      if (entry.sessionId === sessionId) {
        this.messageHashes.delete(hash);
        cleared++;
      }
    }

    return { clearedHashes: cleared };
  }

  /**
   * Start periodic cleanup of old entries
   */
  startCleanup() {
    this.cleanupIntervalId = setInterval(() => {
      this.performCleanup();
    }, this.cleanupInterval);
  }

  /**
   * Perform cleanup of old message hashes
   */
  performCleanup() {
    const now = Date.now();
    const beforeSize = this.messageHashes.size;
    let removed = 0;

    // Remove entries older than the time window
    for (const [hash, entry] of this.messageHashes.entries()) {
      if (now - entry.timestamp > this.timeWindow) {
        this.messageHashes.delete(hash);
        removed++;
      }
    }

    // If still too many entries, remove oldest ones
    if (this.messageHashes.size > this.maxEntries) {
      const entries = Array.from(this.messageHashes.entries());
      entries.sort((a, b) => a[1].timestamp - b[1].timestamp);

      const toRemove = this.messageHashes.size - this.maxEntries;
      for (let i = 0; i < toRemove; i++) {
        this.messageHashes.delete(entries[i][0]);
        removed++;
      }
    }

    if (removed > 0) {
      const telemetry = getTelemetryService();
      telemetry.trackEvent('duplicate_detector_cleanup', {
        removedEntries: removed,
        beforeSize,
        afterSize: this.messageHashes.size,
      });
    }

    return {
      removedEntries: removed,
      remainingEntries: this.messageHashes.size,
    };
  }

  /**
   * Force cleanup and reset
   */
  reset() {
    this.messageHashes.clear();
    this.deviceMessageCount.clear();

    const telemetry = getTelemetryService();
    telemetry.trackEvent('duplicate_detector_reset');
  }

  /**
   * Test helper: inject a message hash for testing
   * @param {string} messageHash - Hash to inject
   * @param {string} deviceId - Device ID
   * @param {string} sessionId - Session ID
   * @param {number} timestamp - Custom timestamp
   */
  injectHash(messageHash, deviceId, sessionId, timestamp = Date.now()) {
    this.messageHashes.set(messageHash, {
      timestamp,
      deviceId,
      sessionId,
    });
  }

  /**
   * Shutdown the duplicate detector
   */
  shutdown() {
    if (this.cleanupIntervalId) {
      clearInterval(this.cleanupIntervalId);
    }

    this.messageHashes.clear();
    this.deviceMessageCount.clear();
  }
}

// Export singleton instance
export const duplicateDetector = new DuplicateDetector();
