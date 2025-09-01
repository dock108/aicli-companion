import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { DeviceRegistry } from '../../services/device-registry.js';

describe('DeviceRegistry', () => {
  let registry;
  const userId1 = 'user-123';
  const userId2 = 'user-456';
  const deviceId1 = 'device-abc';
  const deviceId2 = 'device-def';
  const sessionId1 = 'session-123';
  const sessionId2 = 'session-456';

  beforeEach(() => {
    registry = new DeviceRegistry({ 
      deviceTimeout: 1000, // 1 second for testing
      heartbeatInterval: 100 // 100ms for testing
    });
  });

  afterEach(() => {
    registry.shutdown();
  });

  describe('Device Registration', () => {
    it('should register a device successfully', () => {
      const result = registry.registerDevice(userId1, deviceId1, {
        platform: 'iOS',
        appVersion: '1.0.0'
      });

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.device.deviceId, deviceId1);
      assert.strictEqual(result.device.platform, 'iOS');
      
      // Verify device is stored
      const activeDevices = registry.getActiveDevices(userId1);
      assert.strictEqual(activeDevices.length, 1);
      assert.strictEqual(activeDevices[0].deviceId, deviceId1);
    });

    it('should handle multiple devices for same user', () => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.registerDevice(userId1, deviceId2, { platform: 'macOS' });

      const activeDevices = registry.getActiveDevices(userId1);
      assert.strictEqual(activeDevices.length, 2);
      
      const deviceIds = activeDevices.map(d => d.deviceId);
      assert.ok(deviceIds.includes(deviceId1));
      assert.ok(deviceIds.includes(deviceId2));
    });

    it('should handle devices for different users', () => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.registerDevice(userId2, deviceId2, { platform: 'Android' });

      const user1Devices = registry.getActiveDevices(userId1);
      const user2Devices = registry.getActiveDevices(userId2);

      assert.strictEqual(user1Devices.length, 1);
      assert.strictEqual(user2Devices.length, 1);
      assert.strictEqual(user1Devices[0].deviceId, deviceId1);
      assert.strictEqual(user2Devices[0].deviceId, deviceId2);
    });

    it('should emit deviceRegistered event', (t, done) => {
      registry.once('deviceRegistered', (event) => {
        assert.strictEqual(event.device.deviceId, deviceId1);
        assert.strictEqual(event.userId, userId1);
        done();
      });

      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
    });
  });

  describe('Device Activity Tracking', () => {
    beforeEach(() => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
    });

    it('should update last seen timestamp', () => {
      const initialDevice = registry.registeredDevices.get(deviceId1);
      const initialLastSeen = initialDevice.lastSeen;

      // Wait a bit then update
      setTimeout(() => {
        registry.updateLastSeen(deviceId1);
        
        const updatedDevice = registry.registeredDevices.get(deviceId1);
        assert.ok(updatedDevice.lastSeen > initialLastSeen);
      }, 10);
    });

    it('should check device active status', () => {
      assert.ok(registry.isDeviceActive(deviceId1));
      
      // Should be inactive for non-existent device
      assert.ok(!registry.isDeviceActive('non-existent'));
    });

    it('should detect inactive devices after timeout', (t, done) => {
      // Device should timeout after 1 second (configured in beforeEach)
      setTimeout(() => {
        assert.ok(!registry.isDeviceActive(deviceId1));
        
        const activeDevices = registry.getActiveDevices(userId1);
        assert.strictEqual(activeDevices.length, 0);
        done();
      }, 1100);
    });
  });

  describe('Primary Device Election', () => {
    beforeEach(() => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.registerDevice(userId1, deviceId2, { platform: 'macOS' });
    });

    it('should elect first device as primary', () => {
      const result = registry.electPrimary(userId1, sessionId1, deviceId1);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.isPrimary, true);
      assert.strictEqual(result.primaryDeviceId, deviceId1);
      
      // Verify primary status
      assert.ok(registry.isPrimaryDevice(deviceId1));
      assert.strictEqual(registry.getPrimaryDevice(sessionId1), deviceId1);
    });

    it('should reject second device when primary exists', () => {
      // First device becomes primary
      registry.electPrimary(userId1, sessionId1, deviceId1);
      
      // Second device should be rejected
      const result = registry.electPrimary(userId1, sessionId1, deviceId2);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.reason, 'primary_exists');
      assert.strictEqual(result.primaryDeviceId, deviceId1);
    });

    it('should confirm existing primary device', () => {
      // First device becomes primary
      registry.electPrimary(userId1, sessionId1, deviceId1);
      
      // Same device requests primary again
      const result = registry.electPrimary(userId1, sessionId1, deviceId1);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.isPrimary, true);
      assert.strictEqual(result.primaryDeviceId, deviceId1);
    });

    it('should emit primaryElected event', (t, done) => {
      registry.once('primaryElected', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.deviceId, deviceId1);
        assert.strictEqual(event.userId, userId1);
        done();
      });

      registry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should handle multiple sessions per device', () => {
      registry.electPrimary(userId1, sessionId1, deviceId1);
      registry.electPrimary(userId1, sessionId2, deviceId1);

      assert.strictEqual(registry.getPrimaryDevice(sessionId1), deviceId1);
      assert.strictEqual(registry.getPrimaryDevice(sessionId2), deviceId1);
      assert.ok(registry.isPrimaryDevice(deviceId1));
    });

    it('should reject election for inactive device', () => {
      // Mark device as inactive by not updating last seen and waiting
      setTimeout(() => {
        const result = registry.electPrimary(userId1, sessionId1, deviceId1);
        assert.strictEqual(result.success, false);
        assert.strictEqual(result.reason, 'device_not_active');
      }, 1100);
    });
  });

  describe('Primary Device Transfer', () => {
    beforeEach(() => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.registerDevice(userId1, deviceId2, { platform: 'macOS' });
      registry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should transfer primary successfully', () => {
      const result = registry.transferPrimary(sessionId1, deviceId1, deviceId2);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.newPrimaryDeviceId, deviceId2);
      
      // Verify transfer
      assert.strictEqual(registry.getPrimaryDevice(sessionId1), deviceId2);
      assert.ok(!registry.isPrimaryDevice(deviceId1));
      assert.ok(registry.isPrimaryDevice(deviceId2));
    });

    it('should reject transfer from non-primary device', () => {
      const result = registry.transferPrimary(sessionId1, deviceId2, deviceId1);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.reason, 'not_current_primary');
      
      // Primary should remain unchanged
      assert.strictEqual(registry.getPrimaryDevice(sessionId1), deviceId1);
    });

    it('should reject transfer to inactive device', () => {
      // Make device2 inactive by waiting for timeout
      setTimeout(() => {
        const result = registry.transferPrimary(sessionId1, deviceId1, deviceId2);
        
        assert.strictEqual(result.success, false);
        assert.strictEqual(result.reason, 'target_device_inactive');
      }, 1100);
    });

    it('should emit primaryTransferred event', (t, done) => {
      registry.once('primaryTransferred', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.fromDeviceId, deviceId1);
        assert.strictEqual(event.toDeviceId, deviceId2);
        done();
      });

      registry.transferPrimary(sessionId1, deviceId1, deviceId2);
    });
  });

  describe('Device Unregistration', () => {
    beforeEach(() => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should unregister device and remove primary status', () => {
      registry.unregisterDevice(deviceId1);

      // Device should be removed
      assert.ok(!registry.isDeviceActive(deviceId1));
      assert.strictEqual(registry.getActiveDevices(userId1).length, 0);
      
      // Primary status should be removed
      assert.ok(!registry.isPrimaryDevice(deviceId1));
      assert.strictEqual(registry.getPrimaryDevice(sessionId1), null);
    });

    it('should emit deviceUnregistered event', (t, done) => {
      registry.once('deviceUnregistered', (event) => {
        assert.strictEqual(event.deviceId, deviceId1);
        assert.strictEqual(event.userId, userId1);
        done();
      });

      registry.unregisterDevice(deviceId1);
    });

    it('should emit primaryDeviceOffline event for sessions', (t, done) => {
      registry.once('primaryDeviceOffline', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.deviceId, deviceId1);
        done();
      });

      registry.unregisterDevice(deviceId1);
    });
  });

  describe('Device Timeout Monitoring', () => {
    beforeEach(() => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should detect timed out devices and remove primary status', (t, done) => {
      registry.once('primaryDeviceTimeout', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.deviceId, deviceId1);
        
        // Primary status should be removed
        assert.ok(!registry.isPrimaryDevice(deviceId1));
        assert.strictEqual(registry.getPrimaryDevice(sessionId1), null);
        done();
      });

      // Wait for timeout monitoring to kick in
      // Device timeout is 1000ms, monitoring runs every 100ms
    });
  });

  describe('Registry Statistics', () => {
    beforeEach(() => {
      registry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      registry.registerDevice(userId1, deviceId2, { platform: 'macOS' });
      registry.registerDevice(userId2, 'device-ghi', { platform: 'Android' });
      
      registry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should return accurate statistics', () => {
      const stats = registry.getStats();

      assert.strictEqual(stats.totalDevices, 3);
      assert.strictEqual(stats.activeDevices, 3);
      assert.strictEqual(stats.inactiveDevices, 0);
      assert.strictEqual(stats.totalUsers, 2);
      assert.strictEqual(stats.primaryDevices, 1);
      assert.strictEqual(stats.averageDevicesPerUser, 1.5);
    });

    it('should track inactive devices in stats', (t, done) => {
      // Wait for devices to timeout
      setTimeout(() => {
        const stats = registry.getStats();
        
        assert.strictEqual(stats.totalDevices, 3);
        assert.strictEqual(stats.activeDevices, 0);
        assert.strictEqual(stats.inactiveDevices, 3);
        done();
      }, 1100);
    });
  });

  describe('Edge Cases', () => {
    it('should handle operations on non-existent devices gracefully', () => {
      registry.updateLastSeen('non-existent');
      registry.unregisterDevice('non-existent');
      
      assert.strictEqual(registry.getActiveDevices('non-existent-user').length, 0);
      assert.ok(!registry.isDeviceActive('non-existent'));
      assert.ok(!registry.isPrimaryDevice('non-existent'));
    });

    it('should handle empty device info gracefully', () => {
      const result = registry.registerDevice(userId1, deviceId1);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.device.platform, 'unknown');
    });

    it('should maintain consistency during concurrent operations', () => {
      // Register multiple devices rapidly
      registry.registerDevice(userId1, 'device-1', { platform: 'iOS' });
      registry.registerDevice(userId1, 'device-2', { platform: 'macOS' });
      registry.registerDevice(userId1, 'device-3', { platform: 'iPad' });

      // Try to elect primary for same session from multiple devices
      const result1 = registry.electPrimary(userId1, sessionId1, 'device-1');
      const result2 = registry.electPrimary(userId1, sessionId1, 'device-2');
      const result3 = registry.electPrimary(userId1, sessionId1, 'device-3');

      // Only one should succeed
      const successes = [result1, result2, result3].filter(r => r.success);
      assert.strictEqual(successes.length, 1);

      // Should have exactly one primary device for the session
      const primaryDevice = registry.getPrimaryDevice(sessionId1);
      assert.ok(['device-1', 'device-2', 'device-3'].includes(primaryDevice));
    });
  });
});