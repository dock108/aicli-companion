import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { mock } from 'node:test';
import pushNotificationRoutes from '../../routes/push-notifications.js';
import { pushNotificationService } from '../../services/push-notification.js';

describe('Push Notifications Routes', () => {
  let app;
  let originalSendClaudeResponse;
  let originalGetStats;
  let originalBadTokens;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Store originals
    originalSendClaudeResponse = pushNotificationService.sendClaudeResponseNotification;
    originalGetStats = pushNotificationService.getStats;
    originalBadTokens = pushNotificationService.badTokens;

    // Mock methods
    pushNotificationService.sendClaudeResponseNotification = mock.fn(() =>
      Promise.resolve({
        success: true,
        messageId: 'claude-msg-456',
      })
    );

    pushNotificationService.getStats = mock.fn(() => ({
      sent: 100,
      failed: 5,
      badTokens: 2,
      devices: 10,
    }));

    pushNotificationService.badTokens = new Set(['bad-token-1', 'bad-token-2']);

    // Mock auth middleware
    app.use((req, res, next) => {
      req.user = { id: 'test-user' };
      next();
    });

    app.use(pushNotificationRoutes);
  });

  afterEach(() => {
    // Restore originals
    pushNotificationService.sendClaudeResponseNotification = originalSendClaudeResponse;
    pushNotificationService.getStats = originalGetStats;
    pushNotificationService.badTokens = originalBadTokens;
    mock.restoreAll();
  });

  describe('GET /api/push-notifications/stats', () => {
    it('should return push notification statistics', async () => {
      const response = await request(app).get('/api/push-notifications/stats');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.sent, 100);
      assert.strictEqual(response.body.failed, 5);
      assert.strictEqual(response.body.badTokens, 2);
      assert.strictEqual(response.body.devices, 10);
    });

    it('should handle errors gracefully', async () => {
      pushNotificationService.getStats = mock.fn(() => {
        throw new Error('Stats error');
      });

      const response = await request(app).get('/api/push-notifications/stats');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.error, 'Failed to fetch push notification statistics');
      assert.strictEqual(response.body.message, 'Stats error');
    });
  });

  describe('POST /api/push-notifications/test', () => {
    it('should return 400 if clientId is missing', async () => {
      const response = await request(app)
        .post('/api/push-notifications/test')
        .send({ message: 'Test message' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.error, 'Missing clientId');
    });

    it('should send test notification successfully', async () => {
      const response = await request(app).post('/api/push-notifications/test').send({
        clientId: 'test-client-123',
        message: 'Custom test message',
      });

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Test notification sent');
      assert.strictEqual(response.body.clientId, 'test-client-123');

      // Verify notification was sent
      assert.strictEqual(
        pushNotificationService.sendClaudeResponseNotification.mock.calls.length,
        1
      );
      const [clientId, testData] =
        pushNotificationService.sendClaudeResponseNotification.mock.calls[0].arguments;
      assert.strictEqual(clientId, 'test-client-123');
      assert.strictEqual(testData.message, 'Custom test message');
      assert.strictEqual(testData.sessionId, 'test-session');
    });

    it('should use default message if not provided', async () => {
      const response = await request(app).post('/api/push-notifications/test').send({
        clientId: 'test-client-123',
      });

      assert.strictEqual(response.status, 200);

      // Verify default message was used
      const [, testData] =
        pushNotificationService.sendClaudeResponseNotification.mock.calls[0].arguments;
      assert.strictEqual(testData.message, 'Test notification from AICLI Companion');
    });

    it('should handle send errors', async () => {
      pushNotificationService.sendClaudeResponseNotification = mock.fn(() =>
        Promise.reject(new Error('Send failed'))
      );

      const response = await request(app).post('/api/push-notifications/test').send({
        clientId: 'bad-client',
        message: 'Test message',
      });

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.error, 'Failed to send test notification');
      assert.strictEqual(response.body.message, 'Send failed');
    });
  });

  describe('DELETE /api/push-notifications/bad-tokens', () => {
    it('should clear bad tokens cache', async () => {
      const response = await request(app).delete('/api/push-notifications/bad-tokens');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Bad tokens cache cleared');
      assert.strictEqual(response.body.tokensCleared, 2);

      // Verify cache was cleared
      assert.strictEqual(pushNotificationService.badTokens.size, 0);
    });

    it('should handle errors gracefully', async () => {
      // Create a mock that throws when accessing size
      Object.defineProperty(pushNotificationService.badTokens, 'size', {
        get: () => {
          throw new Error('Cache error');
        },
        configurable: true,
      });

      const response = await request(app).delete('/api/push-notifications/bad-tokens');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.error, 'Failed to clear bad tokens');
      assert.strictEqual(response.body.message, 'Cache error');

      // Clean up the property descriptor
      delete pushNotificationService.badTokens.size;
    });
  });
});
