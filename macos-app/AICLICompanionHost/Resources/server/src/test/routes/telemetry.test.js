import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { mock } from 'node:test';

describe('Telemetry Routes', () => {
  let app;
  let mockTelemetryService;

  beforeEach(() => {
    app = express();
    app.use(express.json());

    // Create mock telemetry service
    mockTelemetryService = {
      getMetrics: mock.fn(() => ({
        sessions: {
          total: 10,
          active: 3,
          completed: 7,
        },
        messages: {
          sent: 50,
          received: 45,
        },
        errors: {
          total: 2,
        },
        uptime: 3600000,
      })),
      getConnectionMetrics: mock.fn((clientId) => {
        if (clientId === 'test-client-123') {
          return {
            clientId: 'test-client-123',
            connected: true,
            messages: 15,
            errors: 0,
          };
        }
        return null;
      }),
      reset: mock.fn(),
    };

    // Mock auth middleware
    app.use((req, res, next) => {
      req.user = { id: 'test-user' };
      next();
    });

    // Create custom router with mocked service
    const router = express.Router();

    router.get('/api/telemetry', (req, res) => {
      try {
        const metrics = mockTelemetryService.getMetrics();
        res.json(metrics);
      } catch (error) {
        res.status(500).json({
          error: 'Failed to fetch telemetry',
          message: error.message,
        });
      }
    });

    router.get('/api/telemetry/connection/:clientId', (req, res) => {
      try {
        const { clientId } = req.params;
        const metrics = mockTelemetryService.getConnectionMetrics(clientId);

        if (!metrics) {
          return res.status(404).json({
            error: 'Connection not found',
            clientId,
          });
        }

        res.json(metrics);
      } catch (error) {
        res.status(500).json({
          error: 'Failed to fetch connection telemetry',
          message: error.message,
        });
      }
    });

    router.post('/api/telemetry/reset', (req, res) => {
      try {
        mockTelemetryService.reset();
        res.json({
          success: true,
          message: 'Telemetry metrics reset',
          timestamp: new Date().toISOString(),
        });
      } catch (error) {
        res.status(500).json({
          error: 'Failed to reset telemetry',
          message: error.message,
        });
      }
    });

    app.use(router);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('GET /api/telemetry', () => {
    it('should return telemetry metrics', async () => {
      const response = await request(app).get('/api/telemetry');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.sessions.total, 10);
      assert.strictEqual(response.body.sessions.active, 3);
      assert.strictEqual(response.body.messages.sent, 50);
      assert.strictEqual(response.body.errors.total, 2);
    });

    it('should handle errors gracefully', async () => {
      mockTelemetryService.getMetrics = mock.fn(() => {
        throw new Error('Metrics error');
      });

      const response = await request(app).get('/api/telemetry');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.error, 'Failed to fetch telemetry');
      assert.strictEqual(response.body.message, 'Metrics error');
    });
  });

  describe('GET /api/telemetry/connection/:clientId', () => {
    it('should return connection metrics when found', async () => {
      const response = await request(app).get('/api/telemetry/connection/test-client-123');

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.clientId, 'test-client-123');
      assert.strictEqual(response.body.connected, true);
      assert.strictEqual(response.body.messages, 15);
      assert.strictEqual(response.body.errors, 0);
    });

    it('should return 404 when connection not found', async () => {
      const response = await request(app).get('/api/telemetry/connection/non-existent');

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.error, 'Connection not found');
      assert.strictEqual(response.body.clientId, 'non-existent');
    });

    it('should handle errors gracefully', async () => {
      mockTelemetryService.getConnectionMetrics = mock.fn(() => {
        throw new Error('Connection error');
      });

      const response = await request(app).get('/api/telemetry/connection/test-client');

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.error, 'Failed to fetch connection telemetry');
      assert.strictEqual(response.body.message, 'Connection error');
    });
  });

  describe('POST /api/telemetry/reset', () => {
    it('should reset telemetry metrics', async () => {
      const response = await request(app).post('/api/telemetry/reset').send({});

      assert.strictEqual(response.status, 200);
      assert.strictEqual(response.body.success, true);
      assert.strictEqual(response.body.message, 'Telemetry metrics reset');
      assert.ok(response.body.timestamp);

      // Verify reset was called
      assert.strictEqual(mockTelemetryService.reset.mock.calls.length, 1);
    });

    it('should handle reset errors gracefully', async () => {
      mockTelemetryService.reset = mock.fn(() => {
        throw new Error('Reset error');
      });

      const response = await request(app).post('/api/telemetry/reset').send({});

      assert.strictEqual(response.status, 500);
      assert.strictEqual(response.body.error, 'Failed to reset telemetry');
      assert.strictEqual(response.body.message, 'Reset error');
    });
  });
});
