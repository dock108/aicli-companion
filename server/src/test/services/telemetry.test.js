import test from 'node:test';
import assert from 'node:assert';
import { TelemetryService } from '../../services/telemetry.js';

test('TelemetryService', async (t) => {
  let telemetry;

  t.beforeEach(() => {
    telemetry = new TelemetryService();
  });

  t.afterEach(() => {
    telemetry.shutdown();
  });

  await t.test('should record connection metrics', () => {
    const clientId = 'client-1';
    const clientInfo = {
      ip: '127.0.0.1',
      userAgent: 'Test Client/1.0',
      deviceId: 'test-device',
    };

    telemetry.recordConnection(clientId, clientInfo);

    const metrics = telemetry.getConnectionMetrics(clientId);
    assert.ok(metrics);
    assert.strictEqual(metrics.clientInfo.ip, '127.0.0.1');
    assert.strictEqual(metrics.messagesSent, 0);
    assert.strictEqual(metrics.messagesReceived, 0);
    assert.ok(metrics.connectedAt);
    assert.ok(metrics.connectionDuration >= 0);
  });

  await t.test('should record message metrics', () => {
    const clientId = 'client-1';
    telemetry.recordConnection(clientId, {});

    // Record sent messages
    telemetry.recordMessageSent(clientId, 'test', true);
    telemetry.recordMessageSent(clientId, 'test', true);
    telemetry.recordMessageSent(clientId, 'test', false);

    // Record received messages
    telemetry.recordMessageReceived(clientId, 'test');

    const metrics = telemetry.getMetrics();
    assert.strictEqual(metrics.websocket.totalMessages.sent, 2);
    assert.strictEqual(metrics.websocket.totalMessages.failed, 1);
    assert.strictEqual(metrics.websocket.totalMessages.received, 1);

    const connMetrics = telemetry.getConnectionMetrics(clientId);
    assert.strictEqual(connMetrics.messagesSent, 2);
    assert.strictEqual(connMetrics.messagesReceived, 1);
  });

  await t.test('should record session metrics', () => {
    // New session
    telemetry.recordSessionCreated(false);
    telemetry.recordSessionCreated(false);

    // Reused session
    telemetry.recordSessionCreated(true);

    // Expired session
    telemetry.recordSessionExpired();

    const metrics = telemetry.getMetrics();
    assert.strictEqual(metrics.sessions.created, 2);
    assert.strictEqual(metrics.sessions.resumed, 1);
    assert.strictEqual(metrics.sessions.duplicatesPrevented, 1);
    assert.strictEqual(metrics.sessions.expired, 1);
  });

  await t.test('should record message queue metrics', () => {
    telemetry.recordMessageQueued();
    telemetry.recordMessageQueued();
    telemetry.recordMessageDelivered();
    telemetry.recordMessageExpired();
    telemetry.recordMessageFiltered('empty_chunk');

    const metrics = telemetry.getMetrics();
    assert.strictEqual(metrics.messages.queued, 2);
    assert.strictEqual(metrics.messages.delivered, 1);
    assert.strictEqual(metrics.messages.expired, 1);
    assert.strictEqual(metrics.messages.filtered, 1);
  });

  await t.test('should record performance metrics', () => {
    telemetry.recordMessageProcessingTime('test', 50);
    telemetry.recordMessageProcessingTime('test', 100);
    telemetry.recordMessageProcessingTime('test', 75);

    telemetry.recordQueueDeliveryTime(200);
    telemetry.recordQueueDeliveryTime(300);

    const metrics = telemetry.getMetrics();
    assert.strictEqual(metrics.performance.avgMessageProcessingTime, 75);
    assert.strictEqual(metrics.performance.avgQueueDeliveryTime, 250);
    assert.strictEqual(metrics.performance.recentProcessingTimes.length, 3);
  });

  await t.test('should track reconnections', () => {
    telemetry.recordReconnection('client-2', 'client-1');
    telemetry.recordReconnection('client-3', 'client-2');

    const metrics = telemetry.getMetrics();
    assert.strictEqual(metrics.websocket.reconnections, 2);
  });

  await t.test('should handle metrics reset', () => {
    // Add some data
    telemetry.recordConnection('client-1', {});
    telemetry.recordMessageSent('client-1', 'test', true);
    telemetry.recordSessionCreated(false);
    telemetry.recordMessageQueued();
    telemetry.updateActiveSessions(5);

    // Reset
    telemetry.reset();

    const metrics = telemetry.getMetrics();
    assert.strictEqual(metrics.websocket.totalMessages.sent, 0);
    assert.strictEqual(metrics.sessions.created, 0);
    assert.strictEqual(metrics.sessions.active, 5); // Active count preserved
    assert.strictEqual(metrics.messages.queued, 0);
    assert.strictEqual(metrics.websocket.activeConnections, 0);
  });

  await t.test('should clean up old metrics', () => {
    const service = new TelemetryService({ retentionTime: 100 });

    // Add old metrics
    service.metrics.performance.messageProcessingTime.push({
      type: 'old',
      duration: 50,
      timestamp: Date.now() - 200,
    });

    // Add new metrics
    service.metrics.performance.messageProcessingTime.push({
      type: 'new',
      duration: 100,
      timestamp: Date.now(),
    });

    service.cleanupOldMetrics();

    assert.strictEqual(service.metrics.performance.messageProcessingTime.length, 1);
    assert.strictEqual(service.metrics.performance.messageProcessingTime[0].type, 'new');

    service.shutdown();
  });

  await t.test('should limit array sizes', () => {
    const service = new TelemetryService({ maxLatencyEntries: 5 });

    // Add more than max entries
    for (let i = 0; i < 10; i++) {
      service.recordMessageProcessingTime('test', i);
    }

    // Should only keep last 5
    assert.strictEqual(service.metrics.performance.messageProcessingTime.length, 5);
    assert.strictEqual(service.metrics.performance.messageProcessingTime[0].duration, 5);
    assert.strictEqual(service.metrics.performance.messageProcessingTime[4].duration, 9);

    service.shutdown();
  });

  await t.test('should handle missing connection gracefully', () => {
    const metrics = telemetry.getConnectionMetrics('non-existent');
    assert.strictEqual(metrics, null);
  });

  await t.test('should calculate average correctly', () => {
    assert.strictEqual(telemetry.calculateAverage([]), 0);
    assert.strictEqual(telemetry.calculateAverage([10]), 10);
    assert.strictEqual(telemetry.calculateAverage([10, 20, 30]), 20);
  });

  await t.test('should not set cleanup interval in test environment', () => {
    // Ensure NODE_ENV is set to test
    const originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'test';

    const service = new TelemetryService();
    assert.strictEqual(service.cleanupInterval, undefined);
    service.shutdown();

    process.env.NODE_ENV = originalEnv;
  });
});
