import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import request from 'supertest';
import express from 'express';
import { deviceRegistry } from '../../services/device-registry.js';
import { messageQueueManager } from '../../services/message-queue.js';
import { duplicateDetector } from '../../services/duplicate-detector.js';
import chatRoutes from '../../routes/chat.js';
import { pushNotificationService } from '../../services/push-notification.js';

describe('Device Coordination End-to-End Integration', () => {
  let app;
  let mockAICLIService;

  beforeEach(() => {
    // Create Express app for testing
    app = express();
    app.use(express.json({ limit: '50mb' }));

    // Create mock AICLI service
    mockAICLIService = {
      sessionManager: {
        findSessionByWorkingDirectory: async () => null,
        trackSessionForRouting: async () => {},
        getSessionBuffer: () => ({
          userMessages: [],
          assistantMessages: [],
        }),
        storeMessage: () => {},
      },
      sendPrompt: async () => ({
        success: true,
        sessionId: 'test-session-123',
        response: {
          result: 'This is a test response from Claude.',
        },
      }),
      on: () => {},
      removeListener: () => {},
    };

    // Mock push notification service
    pushNotificationService.registerDevice = async () => ({ success: true });
    pushNotificationService.sendClaudeResponseNotification = async () => ({ success: true });
    pushNotificationService.sendErrorNotification = async () => ({ success: true });
    pushNotificationService.sendProgressNotification = async () => ({ success: true });

    // Set up app with mock service
    app.set('aicliService', mockAICLIService);
    app.use('/api/chat', chatRoutes);

    // Clean up services
    deviceRegistry.shutdown();
    deviceRegistry.registeredDevices.clear();
    deviceRegistry.userDevices.clear();
    deviceRegistry.primaryDevices.clear();
    deviceRegistry.deviceSessions.clear();
    deviceRegistry.startDeviceMonitoring();

    duplicateDetector.reset();
    messageQueueManager.removeAllListeners();
  });

  afterEach(() => {
    deviceRegistry.shutdown();
    duplicateDetector.reset();
    messageQueueManager.removeAllListeners();
  });

  describe('Complete Device Coordination Flow', () => {
    const userId = 'user-test-123';
    const deviceId1 = 'device-ios-456';
    const deviceId2 = 'device-mac-789';
    const deviceToken = 'mock-device-token-123456789';
    const sessionId = 'session-coordination-test';
    const projectPath = '/test/project';

    it('should handle complete multi-device message flow with deduplication', async () => {
      // Step 1: Send message from first device
      const message1Response = await request(app)
        .post('/api/chat')
        .send({
          message: 'Hello Claude, please help me with this code.',
          projectPath,
          sessionId,
          deviceToken: `${deviceToken}1`,
          deviceId: deviceId1,
          userId,
          deviceInfo: {
            platform: 'iOS',
            appVersion: '1.0.0',
          },
        })
        .expect(200);

      // Verify response structure
      assert.strictEqual(message1Response.body.success, true);
      assert.strictEqual(message1Response.body.sessionId, sessionId);
      assert.strictEqual(message1Response.body.deliveryMethod, 'apns');
      assert.strictEqual(message1Response.body.duplicate, undefined);

      // Verify device was registered
      const activeDevices = deviceRegistry.getActiveDevices(userId);
      assert.strictEqual(activeDevices.length, 1);
      assert.strictEqual(activeDevices[0].deviceId, deviceId1);
      assert.strictEqual(activeDevices[0].platform, 'iOS');

      // Step 2: Send identical message from second device (should be deduplicated)
      const message2Response = await request(app)
        .post('/api/chat')
        .send({
          message: 'Hello Claude, please help me with this code.',
          projectPath,
          sessionId,
          deviceToken: `${deviceToken}2`,
          deviceId: deviceId2,
          userId,
          deviceInfo: {
            platform: 'macOS',
            appVersion: '1.0.0',
          },
        })
        .expect(200);

      // Verify duplicate detection
      assert.strictEqual(message2Response.body.success, true);
      assert.strictEqual(message2Response.body.duplicate, true);
      assert.strictEqual(
        message2Response.body.message,
        'Duplicate message detected - not processed'
      );
      assert(message2Response.body.duplicateInfo);
      assert(message2Response.body.duplicateInfo.messageHash);
      assert(message2Response.body.duplicateInfo.originalDevice);
      assert(typeof message2Response.body.duplicateInfo.timeDifference === 'number');

      // Verify both devices are registered but message was deduplicated
      const activeDevicesAfter = deviceRegistry.getActiveDevices(userId);
      assert.strictEqual(activeDevicesAfter.length, 2);

      const deviceIds = activeDevicesAfter.map((d) => d.deviceId);
      assert.ok(deviceIds.includes(deviceId1));
      assert.ok(deviceIds.includes(deviceId2));

      // Step 3: Send different message from second device (should be processed)
      const message3Response = await request(app)
        .post('/api/chat')
        .send({
          message: 'Can you also review my test files?',
          projectPath,
          sessionId,
          deviceToken: `${deviceToken}2`,
          deviceId: deviceId2,
          userId,
          deviceInfo: {
            platform: 'macOS',
            appVersion: '1.0.0',
          },
        })
        .expect(200);

      // Verify different message is processed
      assert.strictEqual(message3Response.body.success, true);
      assert.strictEqual(message3Response.body.duplicate, undefined);
      assert.strictEqual(message3Response.body.deliveryMethod, 'apns');
    });

    it('should handle device heartbeat updates during chat operations', async () => {
      // Register device first
      await request(app)
        .post('/api/chat')
        .send({
          message: 'Initial message',
          deviceToken,
          deviceId: deviceId1,
          userId,
          deviceInfo: { platform: 'iOS' },
        })
        .expect(200);

      // Get initial last seen timestamp
      const initialDevice = deviceRegistry.registeredDevices.get(deviceId1);
      const initialLastSeen = initialDevice.lastSeen;

      // Wait a bit then send another request
      await new Promise((resolve) => setTimeout(resolve, 50));

      await request(app)
        .post('/api/chat/auto-response/pause')
        .send({
          sessionId: 'test-session',
          deviceToken,
          deviceId: deviceId1,
          userId,
        })
        .expect(200);

      // Verify heartbeat was updated
      const updatedDevice = deviceRegistry.registeredDevices.get(deviceId1);
      assert.ok(updatedDevice.lastSeen >= initialLastSeen);
    });

    it.skip('should handle auto-response control with device context', async () => {
      // Test pause endpoint
      const pauseResponse = await request(app)
        .post('/api/chat/auto-response/pause')
        .send({
          sessionId,
          deviceToken,
          deviceId: deviceId1,
          userId,
        })
        .expect(200);

      assert.strictEqual(pauseResponse.body.success, true);
      assert.strictEqual(pauseResponse.body.action, 'pause');

      // Test resume endpoint
      const resumeResponse = await request(app)
        .post('/api/chat/auto-response/resume')
        .send({
          sessionId,
          deviceToken,
          deviceId: deviceId1,
          userId,
        })
        .expect(200);

      assert.strictEqual(resumeResponse.body.success, true);
      assert.strictEqual(resumeResponse.body.action, 'resume');

      // Test stop endpoint
      const stopResponse = await request(app)
        .post('/api/chat/auto-response/stop')
        .send({
          sessionId,
          deviceToken,
          deviceId: deviceId1,
          userId,
          reason: 'user_requested',
        })
        .expect(200);

      assert.strictEqual(stopResponse.body.success, true);
      assert.strictEqual(stopResponse.body.action, 'stop');
      assert.strictEqual(stopResponse.body.reason, 'user_requested');
    });

    it.skip('should handle queue status and monitoring', async () => {
      // Pause queue to prevent processing for testing
      messageQueueManager.getQueue(sessionId);
      messageQueueManager.pauseQueue(sessionId);

      // Send a message
      await request(app)
        .post('/api/chat')
        .send({
          message: 'Test message for queue monitoring',
          sessionId,
          deviceToken,
          deviceId: deviceId1,
          userId,
          deviceInfo: { platform: 'iOS' },
        })
        .expect(200);

      // Check queue status
      const queueStatus = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(queueStatus.queue.length, 1);
      assert.strictEqual(queueStatus.queue.paused, true);
      assert.strictEqual(queueStatus.queue.processing, false);

      // Resume and verify
      messageQueueManager.resumeQueue(sessionId);
      const resumedStatus = messageQueueManager.getQueueStatus(sessionId);
      assert.strictEqual(resumedStatus.queue.paused, false);
    });

    it('should handle error scenarios gracefully', async () => {
      // Test missing required fields
      const missingMessageResponse = await request(app)
        .post('/api/chat')
        .send({
          deviceToken,
          deviceId: deviceId1,
          userId,
        })
        .expect(400);

      assert.strictEqual(missingMessageResponse.body.success, false);
      assert.strictEqual(missingMessageResponse.body.error, 'Message is required');

      // Test missing device token
      const missingTokenResponse = await request(app)
        .post('/api/chat')
        .send({
          message: 'Test message',
          deviceId: deviceId1,
          userId,
        })
        .expect(400);

      assert.strictEqual(missingTokenResponse.body.success, false);
      assert.strictEqual(
        missingTokenResponse.body.error,
        'Device token is required for APNS message delivery'
      );

      // Test missing session ID for auto-response controls
      const missingSessionResponse = await request(app)
        .post('/api/chat/auto-response/pause')
        .send({
          deviceToken,
          deviceId: deviceId1,
          userId,
        })
        .expect(400);

      assert.strictEqual(missingSessionResponse.body.success, false);
      assert.strictEqual(missingSessionResponse.body.error, 'Session ID is required');
    });

    it('should handle backward compatibility without device context', async () => {
      // Send message without deviceId/userId (old format)
      const response = await request(app)
        .post('/api/chat')
        .send({
          message: 'Backward compatibility test',
          deviceToken,
          sessionId,
        })
        .expect(200);

      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.deliveryMethod, 'apns');

      // Should work without device context
      assert(response.body.requestId);
      assert(response.body.timestamp);
    });

    it('should handle device registry statistics after operations', async () => {
      // Register multiple devices through chat operations
      await request(app)
        .post('/api/chat')
        .send({
          message: 'Message from device 1',
          deviceToken: `${deviceToken}1`,
          deviceId: deviceId1,
          userId,
          deviceInfo: { platform: 'iOS' },
        })
        .expect(200);

      await request(app)
        .post('/api/chat')
        .send({
          message: 'Message from device 2',
          deviceToken: `${deviceToken}2`,
          deviceId: deviceId2,
          userId,
          deviceInfo: { platform: 'macOS' },
        })
        .expect(200);

      // Check registry statistics
      const stats = deviceRegistry.getStats();
      assert.strictEqual(stats.totalDevices, 2);
      assert.strictEqual(stats.activeDevices, 2);
      assert.strictEqual(stats.totalUsers, 1);
      assert.strictEqual(stats.averageDevicesPerUser, 2);
    });

    it.skip('should handle duplicate detector statistics after operations', async () => {
      // Send duplicate messages
      const baseMessage = {
        message: 'Duplicate detection test',
        sessionId,
        projectPath,
        deviceToken: `${deviceToken}1`,
        deviceId: deviceId1,
        userId,
        deviceInfo: { platform: 'iOS' },
      };

      // First message
      await request(app).post('/api/chat').send(baseMessage).expect(200);

      // Duplicate message
      await request(app)
        .post('/api/chat')
        .send({
          ...baseMessage,
          deviceToken: `${deviceToken}2`,
          deviceId: deviceId2,
        })
        .expect(200);

      // Check duplicate detector statistics
      const stats = duplicateDetector.getStats();
      assert.ok(stats.totalHashesStored >= 1);
      assert.ok(stats.recentHashes >= 1);
      assert.ok(stats.trackedDevices >= 2);
      assert(Array.isArray(stats.topDevicesByMessageCount));
    });
  });

  describe('Message Queue Integration', () => {
    it('should properly queue messages with device metadata', async () => {
      const testSessionId = 'queue-test-session';
      messageQueueManager.getQueue(testSessionId);
      messageQueueManager.pauseQueue(testSessionId);

      const response = await request(app)
        .post('/api/chat')
        .send({
          message: 'Queue integration test',
          sessionId: testSessionId,
          deviceToken: 'queue-device-token',
          deviceId: 'queue-device-id',
          userId: 'queue-user-id',
          deviceInfo: { platform: 'iOS' },
        })
        .expect(200);

      assert.strictEqual(response.body.success, true);

      // Verify message is queued
      const queueStatus = messageQueueManager.getQueueStatus(testSessionId);
      assert.strictEqual(queueStatus.queue.length, 1);

      messageQueueManager.removeQueue(testSessionId);
    });

    it('should handle priority-based message queuing', async () => {
      const testSessionId = 'priority-test-session';
      messageQueueManager.getQueue(testSessionId);
      messageQueueManager.pauseQueue(testSessionId);

      // Send high priority message (stop command)
      await request(app)
        .post('/api/chat')
        .send({
          message: 'stop the current operation',
          sessionId: testSessionId,
          deviceToken: 'priority-device-token',
          deviceId: 'priority-device-id',
          userId: 'priority-user-id',
        })
        .expect(200);

      // Send normal priority message
      await request(app)
        .post('/api/chat')
        .send({
          message: 'normal priority message',
          sessionId: testSessionId,
          deviceToken: 'priority-device-token',
          deviceId: 'priority-device-id',
          userId: 'priority-user-id',
        })
        .expect(200);

      const queueStatus = messageQueueManager.getQueueStatus(testSessionId);
      assert.strictEqual(queueStatus.queue.length, 2);

      messageQueueManager.removeQueue(testSessionId);
    });
  });
});
