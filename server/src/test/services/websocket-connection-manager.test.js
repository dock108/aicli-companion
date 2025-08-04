import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { WebSocketConnectionManager } from '../../services/websocket-connection-manager.js';

describe('WebSocketConnectionManager', () => {
  let connectionManager;
  let mockWs;
  let mockRequest;
  let mockGenerateId;

  beforeEach(() => {
    // Create fresh mock for each test
    let idCounter = 0;
    mockGenerateId = () => `mock-uuid-${++idCounter}`;

    connectionManager = new WebSocketConnectionManager({
      generateId: mockGenerateId,
      healthCheckInterval: 10, // 10ms for testing
    });

    // Create mock WebSocket with mock function tracking
    mockWs = new EventEmitter();
    Object.defineProperty(mockWs, 'isAlive', {
      writable: true,
      value: true,
    });

    // Create mock functions with call tracking
    const createMockFunction = () => {
      const fn = function (..._args) {};
      fn.mock = { calls: [] };
      const originalFn = fn;
      const mockFn = function (...args) {
        mockFn.mock.calls.push({ arguments: args });
        return originalFn.apply(this, args);
      };
      mockFn.mock = { calls: [] };
      return mockFn;
    };
    mockWs.close = createMockFunction();
    mockWs.terminate = createMockFunction();
    mockWs.ping = createMockFunction();

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
      connectionManager.shutdown();
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
    it('should handle new connection without auth', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      assert.strictEqual(clientId, 'mock-uuid-1');
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

    it('should handle new connection with valid auth token', async () => {
      mockRequest.url = '/?token=valid-token';

      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, 'valid-token');

      assert.strictEqual(clientId, 'mock-uuid-1');
      assert.strictEqual(connectionManager.clients.size, 1);
    });

    it('should reject connection with invalid auth token', async () => {
      mockRequest.url = '/?token=invalid-token';

      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, 'valid-token');

      assert.strictEqual(clientId, null);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(mockWs.close.mock.calls.length, 1);
      assert.strictEqual(mockWs.close.mock.calls[0].arguments[0], 1008);
    });

    it('should reject connection with missing auth token when required', async () => {
      const clientId = await connectionManager.handleConnection(
        mockWs,
        mockRequest,
        'required-token'
      );

      assert.strictEqual(clientId, null);
      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(mockWs.close.mock.calls.length, 1);
    });

    it('should handle auth token from authorization header', async () => {
      mockRequest.headers.authorization = 'Bearer valid-token';

      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, 'valid-token');

      assert.strictEqual(clientId, 'mock-uuid-1');
      assert.strictEqual(connectionManager.clients.size, 1);
    });

    it('should emit clientConnected event', async () => {
      const eventPromise = new Promise((resolve) => {
        connectionManager.once('clientConnected', (event) => {
          assert.strictEqual(event.clientId, 'mock-uuid-1');
          assert.ok(event.client);
          assert.ok(event.connectionInfo);
          resolve();
        });
      });

      await connectionManager.handleConnection(mockWs, mockRequest, null);
      await eventPromise;
    });

    it('should set up pong handler', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Trigger pong event
      mockWs.emit('pong');

      const client = connectionManager.clients.get(clientId);
      const initialActivity = client.lastActivity;

      // Wait a bit and trigger pong again
      await new Promise((resolve) => setTimeout(resolve, 10));
      mockWs.emit('pong');
      const updatedActivity = connectionManager.clients.get(clientId).lastActivity;
      assert.ok(updatedActivity > initialActivity);
    });

    it('should set up close handler', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Mock handleDisconnection
      const originalHandleDisconnection = connectionManager.handleDisconnection;
      let disconnectionCalled = false;
      connectionManager.handleDisconnection = (id, code, reason) => {
        disconnectionCalled = true;
        assert.strictEqual(id, clientId);
        assert.strictEqual(code, 1000);
        assert.strictEqual(reason, 'Normal closure');
      };

      // Trigger close event
      mockWs.emit('close', 1000, 'Normal closure');

      assert.ok(disconnectionCalled);
      connectionManager.handleDisconnection = originalHandleDisconnection;
    });

    it('should set up error handler', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Mock console.error
      const originalConsoleError = console.error;
      let errorLogged = false;
      console.error = (...args) => {
        errorLogged = true;
        assert.strictEqual(args[0], `WebSocket error for client ${clientId}:`);
      };

      // Trigger error event
      mockWs.emit('error', new Error('Test error'));

      assert.ok(errorLogged);
      console.error = originalConsoleError;
    });
  });

  describe('handleDisconnection', () => {
    it('should handle disconnection and emit event', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      let eventEmitted = false;
      connectionManager.once('clientDisconnected', (event) => {
        eventEmitted = true;
        assert.strictEqual(event.clientId, clientId);
        assert.ok(event.client);
        assert.strictEqual(event.closeCode, 1000);
        assert.strictEqual(event.reason, 'Normal closure');
        assert.strictEqual(event.sessionCount, 0);
      });

      connectionManager.handleDisconnection(clientId, 1000, 'Normal closure');

      assert.ok(eventEmitted);
      assert.strictEqual(connectionManager.clients.size, 0);
    });

    it('should handle disconnection of non-existent client gracefully', () => {
      // Should not throw
      assert.doesNotThrow(() => {
        connectionManager.handleDisconnection('non-existent', 1000, 'Test');
      });
    });

    it('should include session count in disconnection event', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Add some sessions
      connectionManager.addSessionToClient(clientId, 'session-1');
      connectionManager.addSessionToClient(clientId, 'session-2');

      let eventEmitted = false;
      connectionManager.once('clientDisconnected', (event) => {
        eventEmitted = true;
        assert.strictEqual(event.sessionCount, 2);
      });

      connectionManager.handleDisconnection(clientId, 1000, 'Test');
      assert.ok(eventEmitted);
    });
  });

  describe('health monitoring', () => {
    it('should start health monitoring', () => {
      connectionManager.startHealthMonitoring();
      assert.ok(connectionManager.pingInterval);
    });

    it('should not start multiple health monitoring intervals', () => {
      connectionManager.startHealthMonitoring();
      const interval1 = connectionManager.pingInterval;

      connectionManager.startHealthMonitoring();
      const interval2 = connectionManager.pingInterval;

      assert.strictEqual(interval1, interval2);
    });

    it('should stop health monitoring', () => {
      connectionManager.startHealthMonitoring();
      assert.ok(connectionManager.pingInterval);

      connectionManager.stopHealthMonitoring();
      assert.strictEqual(connectionManager.pingInterval, null);
    });

    it('should ping clients during health check', async () => {
      const _clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      connectionManager.startHealthMonitoring();

      // Wait for ping interval
      await new Promise((resolve) => setTimeout(resolve, 15));

      assert.ok(mockWs.ping.mock.calls.length > 0);
      connectionManager.stopHealthMonitoring();
    });

    it('should terminate dead connections', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Mark connection as dead
      mockWs.isAlive = false;
      const client = connectionManager.clients.get(clientId);
      client.ws.isAlive = false;

      connectionManager.startHealthMonitoring();

      // Wait for health check
      await new Promise((resolve) => setTimeout(resolve, 15));

      assert.ok(mockWs.terminate.mock.calls.length > 0);
      assert.strictEqual(connectionManager.clients.size, 0);

      connectionManager.stopHealthMonitoring();
    });

    it('should handle ping errors', async () => {
      const _clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Make ping throw error
      mockWs.ping = () => {
        throw new Error('Ping failed');
      };

      connectionManager.startHealthMonitoring();

      // Wait for health check
      await new Promise((resolve) => setTimeout(resolve, 15));

      assert.ok(mockWs.terminate.mock.calls.length > 0);
      assert.strictEqual(connectionManager.clients.size, 0);

      connectionManager.stopHealthMonitoring();
    });
  });

  describe('client management', () => {
    it('should get client by ID', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      const client = connectionManager.getClient(clientId);
      assert.ok(client);
      assert.strictEqual(client.ws, mockWs);
    });

    it('should return undefined for non-existent client', () => {
      const client = connectionManager.getClient('non-existent');
      assert.strictEqual(client, undefined);
    });

    it('should get all clients', async () => {
      await connectionManager.handleConnection(mockWs, mockRequest, null);

      const clients = connectionManager.getAllClients();
      assert.ok(clients instanceof Map);
      assert.strictEqual(clients.size, 1);
    });

    it('should add session to client', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      connectionManager.addSessionToClient(clientId, 'session-1');

      const client = connectionManager.getClient(clientId);
      assert.ok(client.sessionIds.has('session-1'));
    });

    it('should remove session from client', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      connectionManager.addSessionToClient(clientId, 'session-1');
      connectionManager.removeSessionFromClient(clientId, 'session-1');

      const client = connectionManager.getClient(clientId);
      assert.ok(!client.sessionIds.has('session-1'));
    });

    it('should handle session operations on non-existent client gracefully', () => {
      // Should not throw
      assert.doesNotThrow(() => {
        connectionManager.addSessionToClient('non-existent', 'session-1');
        connectionManager.removeSessionFromClient('non-existent', 'session-1');
      });
    });

    it('should subscribe client to events', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      connectionManager.subscribeClient(clientId, 'event1');

      const client = connectionManager.getClient(clientId);
      assert.ok(client.subscribedEvents.has('event1'));
    });

    it('should subscribe client to multiple events', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      connectionManager.subscribeClient(clientId, ['event1', 'event2']);

      const client = connectionManager.getClient(clientId);
      assert.ok(client.subscribedEvents.has('event1'));
      assert.ok(client.subscribedEvents.has('event2'));
    });

    it('should update client activity', async () => {
      const clientId = await connectionManager.handleConnection(mockWs, mockRequest, null);

      const client = connectionManager.getClient(clientId);
      const initialActivity = client.lastActivity;

      await new Promise((resolve) => setTimeout(resolve, 10));

      connectionManager.updateClientActivity(clientId);

      const updatedActivity = connectionManager.getClient(clientId).lastActivity;
      assert.ok(updatedActivity > initialActivity);
    });

    it('should get clients by session ID', async () => {
      const clientId1 = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Create second client
      const mockWs2 = new EventEmitter();
      Object.defineProperty(mockWs2, 'isAlive', {
        writable: true,
        value: true,
      });

      const createMockFunction = () => {
        const mockFn = function (...args) {
          mockFn.mock.calls.push({ arguments: args });
        };
        mockFn.mock = { calls: [] };
        return mockFn;
      };
      mockWs2.close = createMockFunction();
      mockWs2.terminate = createMockFunction();
      mockWs2.ping = createMockFunction();
      const clientId2 = await connectionManager.handleConnection(mockWs2, mockRequest, null);

      // Add same session to both clients
      connectionManager.addSessionToClient(clientId1, 'session-1');
      connectionManager.addSessionToClient(clientId2, 'session-1');

      // Add different session to second client
      connectionManager.addSessionToClient(clientId2, 'session-2');

      const session1Clients = connectionManager.getClientsBySession('session-1');
      assert.strictEqual(session1Clients.length, 2);

      const session2Clients = connectionManager.getClientsBySession('session-2');
      assert.strictEqual(session2Clients.length, 1);
      assert.strictEqual(session2Clients[0].clientId, clientId2);
    });
  });

  describe('shutdown', () => {
    it('should shutdown and close all connections', async () => {
      await connectionManager.handleConnection(mockWs, mockRequest, null);
      connectionManager.startHealthMonitoring();

      connectionManager.shutdown();

      assert.strictEqual(connectionManager.clients.size, 0);
      assert.strictEqual(connectionManager.pingInterval, null);
      assert.strictEqual(mockWs.close.mock.calls.length, 1);
      assert.strictEqual(mockWs.close.mock.calls[0].arguments[0], 1001);
      assert.strictEqual(mockWs.close.mock.calls[0].arguments[1], 'Server shutting down');
    });

    it('should handle close errors gracefully', async () => {
      await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Make close throw error
      mockWs.close = () => {
        throw new Error('Close failed');
      };

      // Should not throw
      assert.doesNotThrow(() => {
        connectionManager.shutdown();
      });
    });
  });

  describe('getStats', () => {
    it('should return correct statistics', async () => {
      const clientId1 = await connectionManager.handleConnection(mockWs, mockRequest, null);

      // Create second client
      const mockWs2 = new EventEmitter();
      Object.defineProperty(mockWs2, 'isAlive', {
        writable: true,
        value: true,
      });

      const createMockFunction = () => {
        const mockFn = function (...args) {
          mockFn.mock.calls.push({ arguments: args });
        };
        mockFn.mock = { calls: [] };
        return mockFn;
      };
      mockWs2.close = createMockFunction();
      mockWs2.terminate = createMockFunction();
      mockWs2.ping = createMockFunction();
      const clientId2 = await connectionManager.handleConnection(mockWs2, mockRequest, null);

      // Add sessions and subscriptions
      connectionManager.addSessionToClient(clientId1, 'session-1');
      connectionManager.addSessionToClient(clientId1, 'session-2');
      connectionManager.addSessionToClient(clientId2, 'session-3');

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
