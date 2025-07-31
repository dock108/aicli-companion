import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { WebSocketConnectionManager } from '../../services/websocket-connection-manager.js';

// Mock ID generator for testing
const mockGenerateId = mock.fn(() => 'mock-uuid-123');

describe('WebSocketConnectionManager', () => {
  let connectionManager;
  let mockWs;
  let mockRequest;

  beforeEach(() => {
    // Reset mock
    mockGenerateId.mock.resetCalls();
    mockGenerateId.mock.mockImplementation(() => 'mock-uuid-123');

    connectionManager = new WebSocketConnectionManager({
      generateId: mockGenerateId,
      healthCheckInterval: 10, // 10ms for testing
    });

    // Create mock WebSocket
    mockWs = new EventEmitter();
    Object.defineProperty(mockWs, 'isAlive', {
      writable: true,
      value: true,
    });
    mockWs.close = mock.fn();
    mockWs.terminate = mock.fn();
    mockWs.ping = mock.fn();

    // Create mock request
    mockRequest = {
      socket: {
        remoteAddress: '127.0.0.1',
        remoteFamily: 'IPv4',
      },
      headers: {
        'user-agent': 'test-client/1.0',
        host: 'localhost:3000',
      },
      url: '/',
    };
  });

  afterEach(() => {
    if (connectionManager) {
      connectionManager.stopHealthMonitoring();
      connectionManager.removeAllListeners();
    }
  });

  describe('constructor', () => {
    it('should initialize with empty clients map', () => {
      assert.ok(connectionManager instanceof EventEmitter);
      assert.ok(connectionManager.clients instanceof Map);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(connectionManager.pingInterval, null);
    });
  });

  describe('handleConnection', () => {
    it('should handle new connection without auth', () => {
      const clientId = connectionManager.handleConnection(mockWs, mockRequest, null);

      assert.strictEqual(clientId, 'mock-uuid-123');
      assert.strictEqual(connectionManager.clients.size, 1);

      const client = connectionManager.clients.get(clientId);
      assert.ok(client);
      assert.strictEqual(client.ws, mockWs);
      assert.ok(client.sessionIds instanceof Set);
      assert.strictEqual(client.sessionIds.size, 0);
      assert.strictEqual(client.isAlive, true);
      assert.ok(client.connectedAt instanceof Date);
      assert.ok(client.lastActivity instanceof Date);
    });

    it('should handle new connection with valid auth token', () => {
      mockRequest.url = '/?token=valid-token';

      const clientId = connectionManager.handleConnection(mockWs, mockRequest, 'valid-token');

      assert.strictEqual(clientId, 'mock-uuid-123');
      assert.strictEqual(connectionManager.clients.size, 1);
    });

    it('should reject connection with invalid auth token', () => {
      mockRequest.url = '/?token=invalid-token';

      const clientId = connectionManager.handleConnection(mockWs, mockRequest, 'valid-token');

      assert.strictEqual(clientId, null);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(mockWs.close.mock.calls.length, 1);
      assert.strictEqual(mockWs.close.mock.calls[0].arguments[0], 1008);
    });

    it('should reject connection with missing auth token when required', () => {
      const clientId = connectionManager.handleConnection(mockWs, mockRequest, 'required-token');

      assert.strictEqual(clientId, null);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(mockWs.close.mock.calls.length, 1);
    });

    it('should handle auth token from authorization header', () => {
      mockRequest.headers.authorization = 'Bearer valid-token';

      const clientId = connectionManager.handleConnection(mockWs, mockRequest, 'valid-token');

      assert.strictEqual(clientId, 'mock-uuid-123');
      assert.strictEqual(connectionManager.clients.size, 1);
    });

    it('should emit clientConnected event', async () => {
      const eventPromise = new Promise((resolve) => {
        connectionManager.once('clientConnected', (event) => {
          assert.strictEqual(event.clientId, 'mock-uuid-123');
          assert.ok(event.client);
          assert.ok(event.connectionInfo);
          assert.strictEqual(event.connectionInfo.ip, '127.0.0.1');
          assert.strictEqual(event.connectionInfo.family, 'IPv4');
          assert.strictEqual(event.connectionInfo.userAgent, 'test-client/1.0');
          resolve();
        });
      });

      connectionManager.handleConnection(mockWs, mockRequest, null);

      await eventPromise;
    });

    it('should set up pong handler', async () => {
      const clientId = connectionManager.handleConnection(mockWs, mockRequest, null);
      const client = connectionManager.clients.get(clientId);
      const connectedAt = client.connectedAt.getTime();

      // Wait a bit to ensure time difference
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Trigger pong event
      mockWs.emit('pong');

      // Should update client activity
      assert.ok(client.lastActivity.getTime() > connectedAt);
    });

    it('should set up close handler', () => {
      let disconnectionEvent = null;
      connectionManager.once('clientDisconnected', (event) => {
        disconnectionEvent = event;
      });

      const clientId = connectionManager.handleConnection(mockWs, mockRequest, null);

      // Trigger close event
      mockWs.emit('close', 1000, 'Normal closure');

      // Should clean up client
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.ok(disconnectionEvent);
      assert.strictEqual(disconnectionEvent.clientId, clientId);
    });

    it('should set up error handler', () => {
      let disconnectionEvent = null;
      connectionManager.once('clientDisconnected', (event) => {
        disconnectionEvent = event;
      });

      const _clientId = connectionManager.handleConnection(mockWs, mockRequest, null);

      // Trigger error event
      mockWs.emit('error', new Error('Test error'));

      // Should clean up client
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.ok(disconnectionEvent);
      assert.strictEqual(disconnectionEvent.closeCode, 1011);
    });
  });

  describe('handleDisconnection', () => {
    let clientId;

    beforeEach(() => {
      clientId = connectionManager.handleConnection(mockWs, mockRequest, null);
    });

    it('should handle disconnection and emit event', async () => {
      const eventPromise = new Promise((resolve) => {
        connectionManager.once('clientDisconnected', (event) => {
          assert.strictEqual(event.clientId, clientId);
          assert.strictEqual(event.closeCode, 1000);
          assert.strictEqual(event.reason, 'Normal closure');
          assert.strictEqual(event.sessionCount, 0);
          resolve();
        });
      });

      connectionManager.handleDisconnection(clientId, 1000, 'Normal closure');

      await eventPromise;

      // Should remove client
      assert.strictEqual(connectionManager.clients.size, 0);
    });

    it('should handle disconnection of non-existent client gracefully', () => {
      connectionManager.handleDisconnection('non-existent', 1000, 'Test');

      // Should not affect existing clients
      assert.strictEqual(connectionManager.clients.size, 1);
    });

    it('should include session count in disconnection event', async () => {
      // Add sessions to client
      const client = connectionManager.clients.get(clientId);
      client.sessionIds.add('session1');
      client.sessionIds.add('session2');

      const eventPromise = new Promise((resolve) => {
        connectionManager.once('clientDisconnected', (event) => {
          assert.strictEqual(event.sessionCount, 2);
          resolve();
        });
      });

      connectionManager.handleDisconnection(clientId, 1000, 'Test');

      await eventPromise;
    });
  });

  describe('health monitoring', () => {
    let _clientId;

    beforeEach(() => {
      _clientId = connectionManager.handleConnection(mockWs, mockRequest, null);
    });

    it('should start health monitoring', () => {
      connectionManager.startHealthMonitoring();
      assert.ok(connectionManager.pingInterval);
    });

    it('should not start multiple health monitoring intervals', () => {
      connectionManager.startHealthMonitoring();
      const firstInterval = connectionManager.pingInterval;

      connectionManager.startHealthMonitoring();
      assert.strictEqual(connectionManager.pingInterval, firstInterval);
    });

    it('should stop health monitoring', () => {
      connectionManager.startHealthMonitoring();
      assert.ok(connectionManager.pingInterval);

      connectionManager.stopHealthMonitoring();
      assert.strictEqual(connectionManager.pingInterval, null);
    });

    it('should ping clients during health check', async () => {
      // First establish a connection
      const innerClientId = connectionManager.handleConnection(mockWs, mockRequest, null);
      assert.ok(innerClientId);

      connectionManager.startHealthMonitoring();

      // Wait for first ping cycle (health monitoring runs every 10ms in test)
      await new Promise((resolve) => setTimeout(resolve, 20));

      assert.strictEqual(mockWs.ping.mock.calls.length, 1);
      assert.strictEqual(mockWs.isAlive, false); // Should be set to false after ping
      connectionManager.stopHealthMonitoring();
    });

    it('should terminate dead connections', async () => {
      // First establish a connection
      const innerClientId2 = connectionManager.handleConnection(mockWs, mockRequest, null);
      assert.ok(innerClientId2);

      // Mark client as dead
      mockWs.isAlive = false;

      connectionManager.startHealthMonitoring();

      let disconnectionEvent = null;
      connectionManager.once('clientDisconnected', (event) => {
        disconnectionEvent = event;
      });

      // Wait for health check cycle
      await new Promise((resolve) => setTimeout(resolve, 20));

      assert.strictEqual(mockWs.terminate.mock.calls.length, 1);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.ok(disconnectionEvent);
      assert.strictEqual(disconnectionEvent.reason, 'Connection lost - no pong received');
      connectionManager.stopHealthMonitoring();
    });

    it('should handle ping errors', async () => {
      // First establish a connection
      const innerClientId3 = connectionManager.handleConnection(mockWs, mockRequest, null);
      assert.ok(innerClientId3);

      mockWs.ping.mock.mockImplementation(() => {
        throw new Error('Ping failed');
      });

      connectionManager.startHealthMonitoring();

      let disconnectionEvent = null;
      connectionManager.once('clientDisconnected', (event) => {
        disconnectionEvent = event;
      });

      // Wait for health check cycle
      await new Promise((resolve) => setTimeout(resolve, 20));

      assert.strictEqual(mockWs.terminate.mock.calls.length, 1);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.ok(disconnectionEvent);
      connectionManager.stopHealthMonitoring();
    });
  });

  describe('client management', () => {
    let clientId;

    beforeEach(() => {
      clientId = connectionManager.handleConnection(mockWs, mockRequest, null);
    });

    it('should get client by ID', () => {
      const client = connectionManager.getClient(clientId);
      assert.ok(client);
      assert.strictEqual(client.ws, mockWs);
    });

    it('should return undefined for non-existent client', () => {
      const client = connectionManager.getClient('non-existent');
      assert.strictEqual(client, undefined);
    });

    it('should get all clients', () => {
      const allClients = connectionManager.getAllClients();
      assert.ok(allClients instanceof Map);
      assert.strictEqual(allClients.size, 1);
      assert.ok(allClients.has(clientId));
    });

    it('should add session to client', () => {
      connectionManager.addSessionToClient(clientId, 'session1');

      const client = connectionManager.getClient(clientId);
      assert.ok(client.sessionIds.has('session1'));
      assert.strictEqual(client.sessionIds.size, 1);
    });

    it('should remove session from client', () => {
      connectionManager.addSessionToClient(clientId, 'session1');
      connectionManager.addSessionToClient(clientId, 'session2');

      connectionManager.removeSessionFromClient(clientId, 'session1');

      const client = connectionManager.getClient(clientId);
      assert.ok(!client.sessionIds.has('session1'));
      assert.ok(client.sessionIds.has('session2'));
      assert.strictEqual(client.sessionIds.size, 1);
    });

    it('should handle session operations on non-existent client gracefully', () => {
      assert.doesNotThrow(() => {
        connectionManager.addSessionToClient('non-existent', 'session1');
        connectionManager.removeSessionFromClient('non-existent', 'session1');
      });
    });

    it('should subscribe client to events', () => {
      connectionManager.subscribeClient(clientId, 'event1');

      const client = connectionManager.getClient(clientId);
      assert.ok(client.subscribedEvents.has('event1'));
    });

    it('should subscribe client to multiple events', () => {
      connectionManager.subscribeClient(clientId, ['event1', 'event2']);

      const client = connectionManager.getClient(clientId);
      assert.ok(client.subscribedEvents.has('event1'));
      assert.ok(client.subscribedEvents.has('event2'));
    });

    it('should update client activity', async () => {
      const client = connectionManager.getClient(clientId);
      const originalActivity = client.lastActivity.getTime();

      // Wait a bit to ensure time difference
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Update activity
      connectionManager.updateClientActivity(clientId);

      // Check that activity was updated
      assert.ok(client.lastActivity.getTime() > originalActivity);
    });

    it('should get clients by session ID', () => {
      // Create another client
      const mockWs2 = new EventEmitter();
      Object.defineProperty(mockWs2, 'isAlive', {
        writable: true,
        value: true,
      });
      mockWs2.close = mock.fn();
      mockWs2.terminate = mock.fn();
      mockWs2.ping = mock.fn();

      mockGenerateId.mock.mockImplementation(() => 'client2');
      const clientId2 = connectionManager.handleConnection(mockWs2, mockRequest, null);

      // Add sessions to clients
      connectionManager.addSessionToClient(clientId, 'session1');
      connectionManager.addSessionToClient(clientId, 'session2');
      connectionManager.addSessionToClient(clientId2, 'session1');

      const sessionClients = connectionManager.getClientsBySession('session1');

      assert.strictEqual(sessionClients.length, 2);
      const clientIds = sessionClients.map((sc) => sc.clientId);
      assert.ok(clientIds.includes(clientId));
      assert.ok(clientIds.includes(clientId2));
    });
  });

  describe('shutdown', () => {
    it('should shutdown and close all connections', () => {
      const _clientId = connectionManager.handleConnection(mockWs, mockRequest, null);
      connectionManager.startHealthMonitoring();

      connectionManager.shutdown();

      assert.strictEqual(mockWs.close.mock.calls.length, 1);
      assert.strictEqual(mockWs.close.mock.calls[0].arguments[0], 1001);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(connectionManager.pingInterval, null);
    });

    it('should handle close errors gracefully', () => {
      mockWs.close.mock.mockImplementation(() => {
        throw new Error('Close failed');
      });

      const _clientId2 = connectionManager.handleConnection(mockWs, mockRequest, null);

      assert.doesNotThrow(() => {
        connectionManager.shutdown();
      });

      assert.strictEqual(connectionManager.clients.size, 0);
    });
  });

  describe('getStats', () => {
    it('should return correct statistics', () => {
      // Create clients with sessions and subscriptions
      const clientId1 = connectionManager.handleConnection(mockWs, mockRequest, null);

      const mockWs2 = new EventEmitter();
      Object.defineProperty(mockWs2, 'isAlive', {
        writable: true,
        value: true,
      });
      mockWs2.close = mock.fn();
      mockWs2.terminate = mock.fn();
      mockWs2.ping = mock.fn();

      mockGenerateId.mock.mockImplementation(() => 'client2');
      const clientId2 = connectionManager.handleConnection(mockWs2, mockRequest, null);

      // Add sessions and subscriptions
      connectionManager.addSessionToClient(clientId1, 'session1');
      connectionManager.addSessionToClient(clientId1, 'session2');
      connectionManager.addSessionToClient(clientId2, 'session3');

      connectionManager.subscribeClient(clientId1, ['event1', 'event2']);
      connectionManager.subscribeClient(clientId2, 'event3');

      connectionManager.startHealthMonitoring();

      const stats = connectionManager.getStats();

      assert.strictEqual(stats.connectedClients, 2);
      assert.strictEqual(stats.totalSessions, 3);
      assert.strictEqual(stats.totalSubscriptions, 3);
      assert.strictEqual(stats.healthMonitoring, true);

      connectionManager.stopHealthMonitoring();
    });

    it('should return zero stats for no clients', () => {
      const stats = connectionManager.getStats();

      assert.strictEqual(stats.connectedClients, 0);
      assert.strictEqual(stats.totalSessions, 0);
      assert.strictEqual(stats.totalSubscriptions, 0);
      assert.strictEqual(stats.healthMonitoring, false);
    });
  });
});
