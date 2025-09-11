import { EventEmitter } from 'events';
import { getTelemetryService } from './telemetry.js';

/**
 * Manages device registration, tracking, and primary device election
 * for cross-device coordination and duplicate message prevention
 */
export class DeviceRegistry extends EventEmitter {
  constructor(options = {}) {
    super();

    // Device storage
    this.registeredDevices = new Map(); // deviceId -> device info
    this.userDevices = new Map(); // userId -> Set of deviceIds
    this.primaryDevices = new Map(); // sessionId -> deviceId
    this.deviceSessions = new Map(); // deviceId -> Set of sessionIds

    // Configuration
    this.deviceTimeout = options.deviceTimeout || 5 * 60 * 1000; // 5 minutes offline timeout
    this.heartbeatInterval = options.heartbeatInterval || 30 * 1000; // 30 seconds
    this.primaryElectionDelay = options.primaryElectionDelay || 2000; // 2 seconds

    // Start monitoring
    this.startDeviceMonitoring();
  }

  /**
   * Register a device with the registry
   * @param {string} userId - User identifier
   * @param {string} deviceId - Unique device identifier
   * @param {Object} deviceInfo - Device metadata
   * @returns {Object} Registration result
   */
  registerDevice(userId, deviceId, deviceInfo = {}) {
    const telemetry = getTelemetryService();

    const device = {
      deviceId,
      userId,
      platform: deviceInfo.platform || 'unknown',
      appVersion: deviceInfo.appVersion || 'unknown',
      registeredAt: Date.now(),
      lastSeen: Date.now(),
      isActive: true,
      metadata: deviceInfo,
    };

    this.registeredDevices.set(deviceId, device);

    // Track user devices
    if (!this.userDevices.has(userId)) {
      this.userDevices.set(userId, new Set());
    }
    this.userDevices.get(userId).add(deviceId);

    telemetry.trackEvent('device_registered', {
      deviceId: `${deviceId.substring(0, 8)}...`,
      userId: `${userId.substring(0, 8)}...`,
      platform: device.platform,
    });

    this.emit('deviceRegistered', { device, userId });

    return {
      success: true,
      device: {
        deviceId,
        platform: device.platform,
        registeredAt: device.registeredAt,
      },
    };
  }

  /**
   * Update device last seen timestamp
   * @param {string} deviceId - Device identifier
   */
  updateLastSeen(deviceId) {
    const device = this.registeredDevices.get(deviceId);
    if (device) {
      device.lastSeen = Date.now();
      device.isActive = true;
    }
  }

  /**
   * Get active devices for a user
   * @param {string} userId - User identifier
   * @returns {Array} Active devices
   */
  getActiveDevices(userId) {
    const deviceIds = this.userDevices.get(userId);
    if (!deviceIds) return [];

    const activeDevices = [];
    const now = Date.now();

    for (const deviceId of deviceIds) {
      const device = this.registeredDevices.get(deviceId);
      if (device && device.isActive && now - device.lastSeen < this.deviceTimeout) {
        activeDevices.push({
          deviceId: device.deviceId,
          platform: device.platform,
          lastSeen: device.lastSeen,
          isPrimary: this.isPrimaryDevice(deviceId),
        });
      }
    }

    return activeDevices;
  }

  /**
   * Elect primary device for a session
   * @param {string} userId - User identifier
   * @param {string} sessionId - Session identifier
   * @param {string} requestingDeviceId - Device requesting primary status
   * @returns {Object} Election result
   */
  electPrimary(userId, sessionId, requestingDeviceId) {
    const telemetry = getTelemetryService();

    // Check if device is registered and active
    const device = this.registeredDevices.get(requestingDeviceId);
    if (!device || !device.isActive) {
      return { success: false, reason: 'device_not_active' };
    }

    // Check if there's already a primary for this session
    const currentPrimary = this.primaryDevices.get(sessionId);
    if (currentPrimary && this.isDeviceActive(currentPrimary)) {
      // If requesting device is already primary, confirm
      if (currentPrimary === requestingDeviceId) {
        return {
          success: true,
          isPrimary: true,
          primaryDeviceId: requestingDeviceId,
        };
      }

      // Otherwise, another device is primary
      return {
        success: false,
        reason: 'primary_exists',
        primaryDeviceId: currentPrimary,
      };
    }

    // Elect this device as primary
    this.primaryDevices.set(sessionId, requestingDeviceId);

    // Track device sessions
    if (!this.deviceSessions.has(requestingDeviceId)) {
      this.deviceSessions.set(requestingDeviceId, new Set());
    }
    this.deviceSessions.get(requestingDeviceId).add(sessionId);

    telemetry.trackEvent('primary_device_elected', {
      sessionId: `${sessionId.substring(0, 8)}...`,
      deviceId: `${requestingDeviceId.substring(0, 8)}...`,
      userId: `${userId.substring(0, 8)}...`,
    });

    this.emit('primaryElected', {
      sessionId,
      deviceId: requestingDeviceId,
      userId,
    });

    return {
      success: true,
      isPrimary: true,
      primaryDeviceId: requestingDeviceId,
    };
  }

  /**
   * Transfer primary status from one device to another
   * @param {string} sessionId - Session identifier
   * @param {string} fromDeviceId - Current primary device
   * @param {string} toDeviceId - New primary device
   * @returns {Object} Transfer result
   */
  transferPrimary(sessionId, fromDeviceId, toDeviceId) {
    const telemetry = getTelemetryService();

    // Validate current primary
    const currentPrimary = this.primaryDevices.get(sessionId);
    if (currentPrimary !== fromDeviceId) {
      return { success: false, reason: 'not_current_primary' };
    }

    // Validate target device
    const targetDevice = this.registeredDevices.get(toDeviceId);
    if (!targetDevice || !targetDevice.isActive) {
      return { success: false, reason: 'target_device_inactive' };
    }

    // Transfer primary status
    this.primaryDevices.set(sessionId, toDeviceId);

    // Update device sessions tracking
    if (this.deviceSessions.has(fromDeviceId)) {
      this.deviceSessions.get(fromDeviceId).delete(sessionId);
    }
    if (!this.deviceSessions.has(toDeviceId)) {
      this.deviceSessions.set(toDeviceId, new Set());
    }
    this.deviceSessions.get(toDeviceId).add(sessionId);

    telemetry.trackEvent('primary_device_transferred', {
      sessionId: `${sessionId.substring(0, 8)}...`,
      fromDeviceId: `${fromDeviceId.substring(0, 8)}...`,
      toDeviceId: `${toDeviceId.substring(0, 8)}...`,
    });

    this.emit('primaryTransferred', {
      sessionId,
      fromDeviceId,
      toDeviceId,
    });

    return { success: true, newPrimaryDeviceId: toDeviceId };
  }

  /**
   * Check if device is primary for any session
   * @param {string} deviceId - Device identifier
   * @returns {boolean} True if device is primary
   */
  isPrimaryDevice(deviceId) {
    for (const [_sessionId, primaryDeviceId] of this.primaryDevices) {
      if (primaryDeviceId === deviceId) return true;
    }
    return false;
  }

  /**
   * Get primary device for a session
   * @param {string} sessionId - Session identifier
   * @returns {string|null} Primary device ID or null
   */
  getPrimaryDevice(sessionId) {
    return this.primaryDevices.get(sessionId) || null;
  }

  /**
   * Check if device is active (within timeout window)
   * @param {string} deviceId - Device identifier
   * @returns {boolean} True if device is active
   */
  isDeviceActive(deviceId) {
    const device = this.registeredDevices.get(deviceId);
    if (!device) return false;

    const now = Date.now();
    return device.isActive && now - device.lastSeen < this.deviceTimeout;
  }

  /**
   * Unregister a device
   * @param {string} deviceId - Device identifier
   */
  unregisterDevice(deviceId) {
    const device = this.registeredDevices.get(deviceId);
    if (!device) return;

    const telemetry = getTelemetryService();

    // Remove from user devices
    const userDeviceSet = this.userDevices.get(device.userId);
    if (userDeviceSet) {
      userDeviceSet.delete(deviceId);
      if (userDeviceSet.size === 0) {
        this.userDevices.delete(device.userId);
      }
    }

    // Remove primary status for all sessions
    const deviceSessionSet = this.deviceSessions.get(deviceId);
    if (deviceSessionSet) {
      for (const sessionId of deviceSessionSet) {
        this.primaryDevices.delete(sessionId);
        // Trigger re-election if needed
        this.emit('primaryDeviceOffline', { sessionId, deviceId });
      }
      this.deviceSessions.delete(deviceId);
    }

    // Remove device
    this.registeredDevices.delete(deviceId);

    telemetry.trackEvent('device_unregistered', {
      deviceId: `${deviceId.substring(0, 8)}...`,
      userId: `${device.userId.substring(0, 8)}...`,
    });

    this.emit('deviceUnregistered', { deviceId, userId: device.userId });
  }

  /**
   * Start monitoring devices for timeouts
   */
  startDeviceMonitoring() {
    this.monitoringInterval = setInterval(() => {
      this.checkDeviceTimeouts();
    }, this.heartbeatInterval);
  }

  /**
   * Check for timed-out devices and mark them inactive
   */
  checkDeviceTimeouts() {
    const now = Date.now();
    const timedOutDevices = [];

    for (const [deviceId, device] of this.registeredDevices) {
      if (device.isActive && now - device.lastSeen > this.deviceTimeout) {
        device.isActive = false;
        timedOutDevices.push(deviceId);

        // Remove primary status for timed-out devices
        const deviceSessionSet = this.deviceSessions.get(deviceId);
        if (deviceSessionSet) {
          for (const sessionId of deviceSessionSet) {
            const primaryDevice = this.primaryDevices.get(sessionId);
            if (primaryDevice === deviceId) {
              this.primaryDevices.delete(sessionId);
              this.emit('primaryDeviceTimeout', { sessionId, deviceId });
            }
          }
        }
      }
    }

    if (timedOutDevices.length > 0) {
      const telemetry = getTelemetryService();
      telemetry.trackEvent('devices_timed_out', {
        count: timedOutDevices.length,
      });
    }
  }

  /**
   * Get registry statistics
   * @returns {Object} Registry statistics
   */
  getStats() {
    const now = Date.now();
    let activeCount = 0;
    let inactiveCount = 0;

    for (const device of this.registeredDevices.values()) {
      if (device.isActive && now - device.lastSeen < this.deviceTimeout) {
        activeCount++;
      } else {
        inactiveCount++;
      }
    }

    return {
      totalDevices: this.registeredDevices.size,
      activeDevices: activeCount,
      inactiveDevices: inactiveCount,
      totalUsers: this.userDevices.size,
      primaryDevices: this.primaryDevices.size,
      averageDevicesPerUser:
        this.userDevices.size > 0 ? this.registeredDevices.size / this.userDevices.size : 0,
    };
  }

  /**
   * Cleanup method
   */
  shutdown() {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
    }

    this.registeredDevices.clear();
    this.userDevices.clear();
    this.primaryDevices.clear();
    this.deviceSessions.clear();

    this.emit('shutdown');
  }
}

// Export singleton instance
export const deviceRegistry = new DeviceRegistry();
