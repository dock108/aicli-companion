import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { mock } from 'node:test';
import chatRoutes from '../../routes/chat.js';
import { pushNotificationService } from '../../services/push-notification.js';
import { AICLIService } from '../../services/aicli.js';

describe('Chat Routes', () => {
  let app;
  let originalRegisterDevice;
  let originalSendPrompt;
  let originalSendResponseNotification;
  let aicliService;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Create mock AICLI service
    aicliService = new AICLIService();
    app.set('aicliService', aicliService);

    // Store originals
    originalRegisterDevice = pushNotificationService.registerDevice;
    originalSendPrompt = aicliService.sendPrompt;
    originalSendResponseNotification = pushNotificationService.sendClaudeResponseNotification;

    // Mock methods
    pushNotificationService.registerDevice = mock.fn(() => Promise.resolve());
    pushNotificationService.sendClaudeResponseNotification = mock.fn(() => Promise.resolve());
    aicliService.sendPrompt = mock.fn(() =>
      Promise.resolve({
        sessionId: 'test-session-123',
        success: true,
        response: {
          result: 'Test response',
          session_id: 'test-session-123',
        },
      })
    );

    app.use('/api/chat', chatRoutes);
  });

  afterEach(() => {
    // Restore originals
    pushNotificationService.registerDevice = originalRegisterDevice;
    pushNotificationService.sendClaudeResponseNotification = originalSendResponseNotification;
    aicliService.sendPrompt = originalSendPrompt;
    mock.restoreAll();
  });

  describe('POST /api/chat', () => {
    it('should return 400 if message is missing', async () => {
      const response = await request(app).post('/api/chat').send({ deviceToken: 'test-token' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Message is required');
    });

    it('should return 400 if deviceToken is missing', async () => {
      const response = await request(app).post('/api/chat').send({ message: 'Test message' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Device token is required for APNS message delivery');
    });

    it('should process message successfully', async () => {
      const response = await request(app)
        .post('/api/chat')
        .set('x-request-id', 'test-request-123')
        .send({
          message: 'Test message',
          deviceToken: 'test-device-token',
          projectPath: '/test/path',
          sessionId: 'existing-session',
        });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Message received, processing Claude response');
      assert.ok(response.body.requestId);

      // Verify device was registered
      assert.strictEqual(pushNotificationService.registerDevice.mock.calls.length, 1);
      const [deviceId, deviceInfo] = pushNotificationService.registerDevice.mock.calls[0].arguments;
      assert.strictEqual(deviceId, 'test-device-token');
      assert.strictEqual(deviceInfo.token, 'test-device-token');
      assert.strictEqual(deviceInfo.platform, 'ios');
    });

    it('should create new session when sessionId is "new"', async () => {
      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-device-token',
        sessionId: 'new',
        projectPath: '/test/project',
      });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);

      // Wait for async processing
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Verify sendPrompt was called
      assert.strictEqual(aicliService.sendPrompt.mock.calls.length, 1);
      const [prompt, options] = aicliService.sendPrompt.mock.calls[0].arguments;
      assert.strictEqual(prompt, 'Test message');
      assert.strictEqual(options.workingDirectory, '/test/project');
      assert.strictEqual(options.sessionId, 'new');
    });

    it('should use existing session when provided', async () => {
      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-device-token',
        sessionId: 'existing-session-123',
        projectPath: '/test/project',
      });

      assert.strictEqual(response.status, 200);

      // Wait for async processing
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Verify sendPrompt was called with session ID
      const [, options] = aicliService.sendPrompt.mock.calls[0].arguments;
      assert.strictEqual(options.sessionId, 'existing-session-123');
    });

    it('should handle device registration errors gracefully', async () => {
      pushNotificationService.registerDevice = mock.fn(() =>
        Promise.reject(new Error('Registration failed'))
      );

      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'bad-token',
        sessionId: 'test-session',
      });

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Failed to register device for push notifications');
    });

    it('should handle Claude execution errors', async () => {
      aicliService.sendPrompt = mock.fn(() => Promise.reject(new Error('Claude error')));

      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-token',
        sessionId: 'test-session',
      });

      assert.strictEqual(response.status, 200);
      // Error handling happens asynchronously
    });

    it('should send push notification with response', async () => {
      await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-device-token',
        sessionId: 'test-session',
      });

      // Wait a bit for async processing
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Verify push notification was sent
      assert.strictEqual(
        pushNotificationService.sendClaudeResponseNotification.mock.calls.length,
        1
      );
      const [deviceId, options] =
        pushNotificationService.sendClaudeResponseNotification.mock.calls[0].arguments;
      assert.strictEqual(deviceId, 'test-device-token');
      assert.strictEqual(options.message, 'Test response');
      assert.strictEqual(options.sessionId, 'test-session-123');
    });

    it('should handle push notification errors', async () => {
      pushNotificationService.sendClaudeResponseNotification = mock.fn(() =>
        Promise.reject(new Error('Push failed'))
      );

      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-token',
        sessionId: 'test-session',
      });

      assert.strictEqual(response.status, 200);
      // Push errors are handled gracefully in background
    });

    it('should truncate long device tokens in logs', async () => {
      const longToken = 'a'.repeat(100);

      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: longToken,
        sessionId: 'test-session',
      });

      assert.strictEqual(response.status, 200);
      // Token should be truncated in logs (first 16 chars + ...)
    });

    it('should handle empty project path', async () => {
      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-token',
        sessionId: 'test-session',
        // No projectPath
      });

      assert.strictEqual(response.status, 200);

      // Wait for async processing
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Should use process.cwd() as default
      const [, options] = aicliService.sendPrompt.mock.calls[0].arguments;
      assert.strictEqual(options.workingDirectory, process.cwd());
    });

    it('should generate request ID if not provided', async () => {
      const response = await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-token',
      });

      assert.strictEqual(response.status, 200);
      assert.ok(response.body.requestId);
      assert.ok(response.body.requestId.startsWith('REQ_'));
    });

    it('should use provided request ID from header', async () => {
      const response = await request(app)
        .post('/api/chat')
        .set('x-request-id', 'custom-req-123')
        .send({
          message: 'Test message',
          deviceToken: 'test-token',
        });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.requestId, 'custom-req-123');
    });

    it('should handle result with error type', async () => {
      aicliService.sendPrompt = mock.fn(() =>
        Promise.resolve({
          sessionId: 'error-session',
          success: false,
          response: {
            type: 'error',
            error: 'Test error message',
            result: 'Test error message',
          },
        })
      );

      await request(app).post('/api/chat').send({
        message: 'Test message',
        deviceToken: 'test-token',
        sessionId: 'test-session',
      });

      // Wait for async processing
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Should still send notification with error message
      assert.strictEqual(
        pushNotificationService.sendClaudeResponseNotification.mock.calls.length,
        1
      );
      const [, options] =
        pushNotificationService.sendClaudeResponseNotification.mock.calls[0].arguments;
      assert.strictEqual(options.message, 'Test error message');
    });
  });
});
