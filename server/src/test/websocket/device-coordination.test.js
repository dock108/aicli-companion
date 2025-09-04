import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { deviceRegistry } from '../../services/device-registry.js';
import { messageQueueManager, MessagePriority } from '../../services/message-queue.js';

describe('WebSocket Device Coordination Logic', () => {
  const userId1 = 'user-123';
  const deviceId1 = 'device-abc';
  const deviceId2 = 'device-def';
  const sessionId1 = 'session-test-123';

  beforeEach(() => {
    // Clean up registries for each test
    deviceRegistry.shutdown();
    deviceRegistry.registeredDevices.clear();
    deviceRegistry.userDevices.clear();
    deviceRegistry.primaryDevices.clear();
    deviceRegistry.deviceSessions.clear();

    // Restart monitoring
    deviceRegistry.startDeviceMonitoring();

    messageQueueManager.removeAllListeners();
  });

  afterEach(() => {
    // Clean up after tests
    deviceRegistry.shutdown();
    messageQueueManager.removeAllListeners();
  });

  describe('Device Registration Flow', () => {
    it('should register device successfully', () => {
      const result = deviceRegistry.registerDevice(userId1, deviceId1, {
        platform: 'iOS',
        appVersion: '1.0.0',
      });

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.device.deviceId, deviceId1);
      assert.strictEqual(result.device.platform, 'iOS');

      // Verify device is active
      assert.ok(deviceRegistry.isDeviceActive(deviceId1));

      const activeDevices = deviceRegistry.getActiveDevices(userId1);
      assert.strictEqual(activeDevices.length, 1);
      assert.strictEqual(activeDevices[0].deviceId, deviceId1);
    });

    it('should handle multiple device registration for same user', () => {
      // Register two devices
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.registerDevice(userId1, deviceId2, { platform: 'macOS' });

      const activeDevices = deviceRegistry.getActiveDevices(userId1);
      assert.strictEqual(activeDevices.length, 2);

      const deviceIds = activeDevices.map((d) => d.deviceId);
      assert.ok(deviceIds.includes(deviceId1));
      assert.ok(deviceIds.includes(deviceId2));
    });

    it('should emit deviceRegistered event', (t, done) => {
      deviceRegistry.once('deviceRegistered', (event) => {
        assert.strictEqual(event.device.deviceId, deviceId1);
        assert.strictEqual(event.userId, userId1);
        done();
      });

      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
    });
  });

  describe('Device Heartbeat Management', () => {
    beforeEach(() => {
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
    });

    it('should update device last seen timestamp', () => {
      const initialDevice = deviceRegistry.registeredDevices.get(deviceId1);
      const initialLastSeen = initialDevice.lastSeen;

      // Wait a bit then update
      setTimeout(() => {
        deviceRegistry.updateLastSeen(deviceId1);

        const updatedDevice = deviceRegistry.registeredDevices.get(deviceId1);
        assert.ok(updatedDevice.lastSeen >= initialLastSeen);
      }, 10);
    });

    it('should maintain device as active with regular heartbeats', () => {
      assert.ok(deviceRegistry.isDeviceActive(deviceId1));

      // Update heartbeat
      deviceRegistry.updateLastSeen(deviceId1);

      // Should still be active
      assert.ok(deviceRegistry.isDeviceActive(deviceId1));
    });
  });

  describe('Primary Device Election', () => {
    beforeEach(() => {
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.registerDevice(userId1, deviceId2, { platform: 'macOS' });
    });

    it('should elect first device as primary', () => {
      const result = deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.isPrimary, true);
      assert.strictEqual(result.primaryDeviceId, deviceId1);

      // Verify primary status
      assert.ok(deviceRegistry.isPrimaryDevice(deviceId1));
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), deviceId1);
    });

    it('should reject second device when primary exists', () => {
      // First device becomes primary
      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);

      // Second device should be rejected
      const result = deviceRegistry.electPrimary(userId1, sessionId1, deviceId2);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.reason, 'primary_exists');
      assert.strictEqual(result.primaryDeviceId, deviceId1);
    });

    it('should emit primaryElected event', (t, done) => {
      deviceRegistry.once('primaryElected', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.deviceId, deviceId1);
        assert.strictEqual(event.userId, userId1);
        done();
      });

      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);
    });
  });

  describe('Primary Device Transfer', () => {
    beforeEach(() => {
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.registerDevice(userId1, deviceId2, { platform: 'macOS' });
      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should transfer primary successfully', () => {
      const result = deviceRegistry.transferPrimary(sessionId1, deviceId1, deviceId2);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.newPrimaryDeviceId, deviceId2);

      // Verify transfer
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), deviceId2);
      assert.ok(!deviceRegistry.isPrimaryDevice(deviceId1));
      assert.ok(deviceRegistry.isPrimaryDevice(deviceId2));
    });

    it('should emit primaryTransferred event', (t, done) => {
      deviceRegistry.once('primaryTransferred', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.fromDeviceId, deviceId1);
        assert.strictEqual(event.toDeviceId, deviceId2);
        done();
      });

      deviceRegistry.transferPrimary(sessionId1, deviceId1, deviceId2);
    });

    it('should reject transfer from non-primary device', () => {
      const result = deviceRegistry.transferPrimary(sessionId1, deviceId2, deviceId1);

      assert.strictEqual(result.success, false);
      assert.strictEqual(result.reason, 'not_current_primary');

      // Primary should remain unchanged
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), deviceId1);
    });
  });

  describe('Session Management', () => {
    beforeEach(() => {
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
    });

    it('should handle session state queries', () => {
      // No primary initially
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), null);
      assert.ok(!deviceRegistry.isPrimaryDevice(deviceId1));

      // Get active devices
      const activeDevices = deviceRegistry.getActiveDevices(userId1);
      assert.strictEqual(activeDevices.length, 1);
      assert.strictEqual(activeDevices[0].deviceId, deviceId1);
      assert.strictEqual(activeDevices[0].isPrimary, false);
    });

    it('should update device status in active devices list', () => {
      // Elect as primary
      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);

      const activeDevices = deviceRegistry.getActiveDevices(userId1);
      assert.strictEqual(activeDevices.length, 1);
      assert.strictEqual(activeDevices[0].isPrimary, true);
    });
  });

  describe('Device Disconnection Handling', () => {
    beforeEach(() => {
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);
    });

    it('should unregister device and remove primary status', () => {
      deviceRegistry.unregisterDevice(deviceId1);

      // Device should be removed
      assert.ok(!deviceRegistry.isDeviceActive(deviceId1));
      assert.strictEqual(deviceRegistry.getActiveDevices(userId1).length, 0);

      // Primary status should be removed
      assert.ok(!deviceRegistry.isPrimaryDevice(deviceId1));
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), null);
    });

    it('should emit deviceUnregistered event', (t, done) => {
      deviceRegistry.once('deviceUnregistered', (event) => {
        assert.strictEqual(event.deviceId, deviceId1);
        assert.strictEqual(event.userId, userId1);
        done();
      });

      deviceRegistry.unregisterDevice(deviceId1);
    });

    it('should emit primaryDeviceOffline event', (t, done) => {
      deviceRegistry.once('primaryDeviceOffline', (event) => {
        assert.strictEqual(event.sessionId, sessionId1);
        assert.strictEqual(event.deviceId, deviceId1);
        done();
      });

      deviceRegistry.unregisterDevice(deviceId1);
    });
  });

  describe('Message Queue Integration', () => {
    const sessionId = 'test-session-integration';

    beforeEach(() => {
      messageQueueManager.removeQueue(sessionId);
    });

    afterEach(() => {
      messageQueueManager.removeQueue(sessionId);
    });

    it('should queue unique messages from devices', () => {
      // Create and pause queue
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'Test message from device',
        sessionId,
        projectPath: '/test/project',
      };

      // Queue message with device context
      const result = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });

      assert.strictEqual(result.queued, true);
      assert.strictEqual(typeof result.messageId, 'string');
      assert.strictEqual(typeof result.messageHash, 'string');

      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 1);
    });

    it('should prevent duplicate messages from multiple devices', () => {
      // Create and pause queue
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      const message = {
        content: 'Duplicate test message',
        sessionId,
        projectPath: '/test/project',
      };

      // First message from device1
      const result1 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });

      // Second identical message from device2
      const result2 = messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId2,
      });

      assert.strictEqual(result1.queued, true);
      assert.strictEqual(result2.queued, false);
      assert.strictEqual(result2.reason, 'duplicate');
      assert(result2.duplicateInfo);
      assert.strictEqual(result2.duplicateInfo.originalDeviceId, deviceId1);

      // Should have only one message in queue
      const status = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(status.queue.length, 1);
    });

    it('should emit duplicate-message events', (t, done) => {
      // Create and pause queue
      const queue = messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      queue.once('duplicate-message', (event) => {
        assert.strictEqual(event.sessionId, sessionId);
        assert.strictEqual(event.deviceId, deviceId2);
        assert.strictEqual(typeof event.messageHash, 'string');
        assert(event.duplicateInfo);
        done();
      });

      const message = {
        content: 'Event test message',
        sessionId,
        projectPath: '/test/project',
      };

      // First message
      messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId1,
      });

      // Duplicate message should emit event
      messageQueueManager.queueMessage(sessionId, message, MessagePriority.NORMAL, {
        deviceId: deviceId2,
      });
    });
  });

  describe('Multi-Device Coordination Scenarios', () => {
    it('should coordinate between multiple devices for same user', () => {
      // Register multiple devices
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.registerDevice(userId1, deviceId2, { platform: 'macOS' });

      // First device attempts primary election
      const result1 = deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);
      assert.strictEqual(result1.success, true);
      assert.strictEqual(result1.isPrimary, true);

      // Second device attempts primary election (should fail)
      const result2 = deviceRegistry.electPrimary(userId1, sessionId1, deviceId2);
      assert.strictEqual(result2.success, false);
      assert.strictEqual(result2.reason, 'primary_exists');

      // Transfer primary from device1 to device2
      const transferResult = deviceRegistry.transferPrimary(sessionId1, deviceId1, deviceId2);
      assert.strictEqual(transferResult.success, true);

      // Verify final state
      assert.ok(!deviceRegistry.isPrimaryDevice(deviceId1));
      assert.ok(deviceRegistry.isPrimaryDevice(deviceId2));
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), deviceId2);
    });

    it('should handle device registry statistics correctly', () => {
      // Register multiple devices for different users
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.registerDevice(userId1, deviceId2, { platform: 'macOS' });
      deviceRegistry.registerDevice('user-456', 'device-ghi', { platform: 'Android' });

      // Elect one as primary
      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);

      const stats = deviceRegistry.getStats();
      assert.strictEqual(stats.totalDevices, 3);
      assert.strictEqual(stats.activeDevices, 3);
      assert.strictEqual(stats.inactiveDevices, 0);
      assert.strictEqual(stats.totalUsers, 2);
      assert.strictEqual(stats.primaryDevices, 1);
      assert.strictEqual(stats.averageDevicesPerUser, 1.5);
    });

    it('should handle complex session and device interactions', () => {
      // Register devices
      deviceRegistry.registerDevice(userId1, deviceId1, { platform: 'iOS' });
      deviceRegistry.registerDevice(userId1, deviceId2, { platform: 'macOS' });

      // Device1 becomes primary for session1
      deviceRegistry.electPrimary(userId1, sessionId1, deviceId1);

      // Device2 becomes primary for session2
      const sessionId2 = 'session-test-456';
      deviceRegistry.electPrimary(userId1, sessionId2, deviceId2);

      // Verify both sessions have different primary devices
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), deviceId1);
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId2), deviceId2);

      // Both devices should be considered primary (for different sessions)
      assert.ok(deviceRegistry.isPrimaryDevice(deviceId1));
      assert.ok(deviceRegistry.isPrimaryDevice(deviceId2));

      // Unregister device1 - should affect session1 only
      deviceRegistry.unregisterDevice(deviceId1);

      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId1), null);
      assert.strictEqual(deviceRegistry.getPrimaryDevice(sessionId2), deviceId2);
      assert.ok(!deviceRegistry.isPrimaryDevice(deviceId1));
      assert.ok(deviceRegistry.isPrimaryDevice(deviceId2));
    });
  });
});
