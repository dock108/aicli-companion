import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { mock } from 'node:test';
import devicesRoutes from '../../routes/devices.js';
import { pushNotificationService } from '../../services/push-notification.js';

describe('Devices Routes', () => {
  let app;
  let originalRegisterDevice;
  let originalUnregisterDevice;
  let originalSendPush;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Store originals
    originalRegisterDevice = pushNotificationService.registerDevice;
    originalUnregisterDevice = pushNotificationService.unregisterDevice;
    originalSendPush = pushNotificationService.sendPushNotification;

    // Mock methods
    pushNotificationService.registerDevice = mock.fn(() => Promise.resolve());
    pushNotificationService.unregisterDevice = mock.fn(() => Promise.resolve());
    pushNotificationService.sendPushNotification = mock.fn(() =>
      Promise.resolve({
        success: true,
        message: 'Test notification sent',
      })
    );

    app.use('/api/devices', devicesRoutes);
  });

  afterEach(() => {
    // Restore originals
    pushNotificationService.registerDevice = originalRegisterDevice;
    pushNotificationService.unregisterDevice = originalUnregisterDevice;
    pushNotificationService.sendPushNotification = originalSendPush;
    mock.restoreAll();
  });

  describe('POST /api/devices/register', () => {
    it('should return 400 if deviceToken is missing', async () => {
      const response = await request(app).post('/api/devices/register').send({ platform: 'ios' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Device token is required');
    });

    it('should register device successfully', async () => {
      const response = await request(app)
        .post('/api/devices/register')
        .set('x-device-id', 'custom-device-123')
        .send({
          deviceToken: 'test-token-abc123',
          platform: 'ios',
          bundleId: 'com.test.app',
        });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.deviceId, 'custom-device-123');
      assert.strictEqual(response.body.message, 'Device registered for push notifications');
      assert.ok(response.body.timestamp);

      // Verify registration was called
      assert.strictEqual(pushNotificationService.registerDevice.mock.calls.length, 1);
      const [deviceId, deviceInfo] = pushNotificationService.registerDevice.mock.calls[0].arguments;
      assert.strictEqual(deviceId, 'custom-device-123');
      assert.strictEqual(deviceInfo.token, 'test-token-abc123');
      assert.strictEqual(deviceInfo.platform, 'ios');
      assert.strictEqual(deviceInfo.bundleId, 'com.test.app');
      assert.ok(deviceInfo.registeredAt);
    });

    it('should generate device ID if not provided', async () => {
      const response = await request(app).post('/api/devices/register').send({
        deviceToken: 'test-token-xyz',
      });

      assert.strictEqual(response.status, 200);
      assert.ok(response.body.deviceId);
      assert.ok(response.body.deviceId.startsWith('device_'));
    });

    it('should use default platform if not specified', async () => {
      await request(app).post('/api/devices/register').send({
        deviceToken: 'test-token',
      });

      const [, deviceInfo] = pushNotificationService.registerDevice.mock.calls[0].arguments;
      assert.strictEqual(deviceInfo.platform, 'ios');
    });

    it('should handle registration errors', async () => {
      pushNotificationService.registerDevice = mock.fn(() =>
        Promise.reject(new Error('Registration failed'))
      );

      const response = await request(app).post('/api/devices/register').send({
        deviceToken: 'bad-token',
      });

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to register device');
    });

    it('should handle different platforms', async () => {
      const response = await request(app).post('/api/devices/register').send({
        deviceToken: 'android-token',
        platform: 'android',
      });

      assert.strictEqual(response.status, 200);

      const [, deviceInfo] = pushNotificationService.registerDevice.mock.calls[0].arguments;
      assert.strictEqual(deviceInfo.platform, 'android');
    });
  });

  describe('DELETE /api/devices/:deviceId', () => {
    it('should unregister device successfully', async () => {
      const response = await request(app).delete('/api/devices/device-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Device unregistered');

      // Verify unregistration was called
      assert.strictEqual(pushNotificationService.unregisterDevice.mock.calls.length, 1);
      assert.strictEqual(
        pushNotificationService.unregisterDevice.mock.calls[0].arguments[0],
        'device-123'
      );
    });

    it('should handle unregistration errors', async () => {
      pushNotificationService.unregisterDevice = mock.fn(() =>
        Promise.reject(new Error('Unregistration failed'))
      );

      const response = await request(app).delete('/api/devices/bad-device');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to unregister device');
    });

    it('should handle special characters in device ID', async () => {
      const specialDeviceId = 'device%20with%20spaces';

      const response = await request(app).delete(`/api/devices/${specialDeviceId}`);

      assert.strictEqual(response.status, 200);

      // URL should be decoded by Express
      assert.strictEqual(
        pushNotificationService.unregisterDevice.mock.calls[0].arguments[0],
        'device with spaces'
      );
    });
  });

  describe('POST /api/devices/test-push', () => {
    it('should return 400 if deviceToken is missing', async () => {
      const response = await request(app).post('/api/devices/test-push').send({});

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Device token is required');
    });

    it('should send test notification successfully', async () => {
      const response = await request(app).post('/api/devices/test-push').send({
        deviceToken: 'test-token-123',
      });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Test notification sent');

      // Verify test notification was sent
      assert.strictEqual(pushNotificationService.sendPushNotification.mock.calls.length, 1);
      assert.strictEqual(
        pushNotificationService.sendPushNotification.mock.calls[0].arguments[0],
        'test-token-123'
      );
    });

    it('should handle test notification errors', async () => {
      pushNotificationService.sendPushNotification = mock.fn(() =>
        Promise.reject(new Error('Send failed'))
      );

      const response = await request(app).post('/api/devices/test-push').send({
        deviceToken: 'bad-token',
      });

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to send test notification');
    });

    it('should return custom test response', async () => {
      pushNotificationService.sendPushNotification = mock.fn(() =>
        Promise.resolve({
          success: true,
          message: 'Custom test response',
          details: { some: 'data' },
        })
      );

      const response = await request(app).post('/api/devices/test-push').send({
        deviceToken: 'test-token',
      });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Test notification sent');
    });
  });
});
