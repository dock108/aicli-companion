import test from 'node:test';
import assert from 'node:assert';
import { getTelemetryService } from '../../services/telemetry.js';

test('Telemetry Routes', async (t) => {
  let telemetryService;

  t.beforeEach(() => {
    telemetryService = getTelemetryService();
    telemetryService.reset();
  });

  await t.test('getTelemetryService returns metrics', async () => {
    // Add some test data
    telemetryService.recordConnection('client-1', { ip: '127.0.0.1' });
    telemetryService.recordMessageSent('client-1', 'test', true);
    telemetryService.recordSessionCreated(false);

    const metrics = telemetryService.getMetrics();

    assert.ok(metrics);
    assert.ok(metrics.websocket);
    assert.ok(metrics.sessions);
    assert.ok(metrics.messages);
    assert.strictEqual(metrics.websocket.totalMessages.sent, 1);
    assert.strictEqual(metrics.sessions.created, 1);
  });

  await t.test('getConnectionMetrics returns connection-specific data', async () => {
    const clientId = 'client-1';
    telemetryService.recordConnection(clientId, { ip: '127.0.0.1' });
    telemetryService.recordMessageSent(clientId, 'test', true);

    const connectionMetrics = telemetryService.getConnectionMetrics(clientId);

    assert.ok(connectionMetrics);
    assert.strictEqual(connectionMetrics.clientInfo.ip, '127.0.0.1');
    assert.strictEqual(connectionMetrics.messagesSent, 1);
  });

  await t.test('getConnectionMetrics returns null for unknown client', async () => {
    const connectionMetrics = telemetryService.getConnectionMetrics('unknown');
    assert.strictEqual(connectionMetrics, null);
  });

  await t.test('reset clears all metrics', async () => {
    // Add some data
    telemetryService.recordConnection('client-1', {});
    telemetryService.recordSessionCreated(false);
    telemetryService.recordMessageQueued();

    // Reset
    telemetryService.reset();

    const metrics = telemetryService.getMetrics();
    assert.strictEqual(metrics.websocket.totalMessages.sent, 0);
    assert.strictEqual(metrics.sessions.created, 0);
    assert.strictEqual(metrics.messages.queued, 0);
  });
});
