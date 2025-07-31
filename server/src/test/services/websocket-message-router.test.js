import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { WebSocketMessageRouter } from '../../services/websocket-message-router.js';
import { WebSocketUtilities } from '../../services/websocket-utilities.js';

// Store original methods for restoration
const originalSendErrorMessage = WebSocketUtilities.sendErrorMessage;
const originalSafeParse = WebSocketUtilities.safeParse;
const originalValidateMessage = WebSocketUtilities.validateMessage;

describe('WebSocketMessageRouter', () => {
  let router;
  let mockHandler;
  let mockAicliService;
  let mockConnectionManager;
  let mockClients;

  beforeEach(() => {
    // Mock WebSocketUtilities methods
    WebSocketUtilities.sendErrorMessage = mock.fn();
    WebSocketUtilities.safeParse = mock.fn((data) => {
      try {
        return JSON.parse(data);
      } catch {
        return null;
      }
    });
    WebSocketUtilities.validateMessage = mock.fn((message) => ({
      valid: !!(message && message.type),
      error: !message ? 'No message' : !message.type ? 'No message type' : null,
    }));

    router = new WebSocketMessageRouter();

    mockHandler = mock.fn((_clientId, _requestId, _data, ..._args) => {
      return Promise.resolve({ success: true });
    });

    mockAicliService = {
      someMethod: mock.fn(),
    };

    mockClients = new Map();
    mockClients.set('client1', {
      ws: { readyState: 1 },
      lastActivity: new Date(),
    });

    mockConnectionManager = {
      updateClientActivity: mock.fn(),
      getAllClients: mock.fn(() => mockClients),
    };
  });

  afterEach(async () => {
    // Shutdown router to clean up any intervals/timers
    if (router) {
      await router.shutdown();
    }

    // Restore original methods
    WebSocketUtilities.sendErrorMessage = originalSendErrorMessage;
    WebSocketUtilities.safeParse = originalSafeParse;
    WebSocketUtilities.validateMessage = originalValidateMessage;
  });

  describe('constructor', () => {
    it('should initialize with empty handlers and message queue', () => {
      const newRouter = new WebSocketMessageRouter();
      assert.ok(newRouter.handlers instanceof Map);
      assert.strictEqual(newRouter.handlers.size, 0);
      assert.ok(Array.isArray(newRouter.messageQueue));
      assert.strictEqual(newRouter.messageQueue.length, 0);
    });
  });

  describe('registerHandler', () => {
    it('should register a handler for a message type', () => {
      router.registerHandler('test', mockHandler);
      assert.strictEqual(router.handlers.get('test'), mockHandler);
    });

    it('should throw error for non-function handler', () => {
      assert.throws(() => {
        router.registerHandler('test', 'not-a-function');
      }, /must be a function/);
    });

    it('should override existing handler', () => {
      const handler1 = mock.fn();
      const handler2 = mock.fn();

      router.registerHandler('test', handler1);
      router.registerHandler('test', handler2);

      assert.strictEqual(router.handlers.get('test'), handler2);
    });
  });

  describe('registerHandlers', () => {
    it('should register multiple handlers at once', () => {
      const handlers = {
        type1: mock.fn(),
        type2: mock.fn(),
        type3: mock.fn(),
      };

      router.registerHandlers(handlers);

      assert.strictEqual(router.handlers.size, 3);
      assert.strictEqual(router.handlers.get('type1'), handlers.type1);
      assert.strictEqual(router.handlers.get('type2'), handlers.type2);
      assert.strictEqual(router.handlers.get('type3'), handlers.type3);
    });

    it('should handle empty handlers object', () => {
      router.registerHandlers({});
      assert.strictEqual(router.handlers.size, 0);
    });
  });

  describe('unregisterHandler', () => {
    it('should unregister a handler', () => {
      router.registerHandler('test', mockHandler);
      assert.strictEqual(router.handlers.get('test'), mockHandler);

      const removed = router.unregisterHandler('test');
      assert.strictEqual(removed, true);
      assert.strictEqual(router.handlers.get('test'), undefined);
    });

    it('should return false when unregistering non-existent handler', () => {
      const removed = router.unregisterHandler('nonexistent');
      assert.strictEqual(removed, false);
    });
  });

  describe('getRegisteredTypes', () => {
    it('should return empty array when no handlers registered', () => {
      const types = router.getRegisteredTypes();
      assert.ok(Array.isArray(types));
      assert.strictEqual(types.length, 0);
    });

    it('should return registered message types', () => {
      router.registerHandler('type1', mock.fn());
      router.registerHandler('type2', mock.fn());
      router.registerHandler('type3', mock.fn());

      const types = router.getRegisteredTypes();
      assert.strictEqual(types.length, 3);
      assert.ok(types.includes('type1'));
      assert.ok(types.includes('type2'));
      assert.ok(types.includes('type3'));
    });
  });

  describe('routeMessage', () => {
    it('should route message to registered handler', async () => {
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: { value: 'test-data' },
      };

      // Pass as JSON string as expected by the actual implementation
      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(mockHandler.mock.calls.length, 1);
      assert.strictEqual(mockHandler.mock.calls[0].arguments[0], 'client1');
      assert.strictEqual(mockHandler.mock.calls[0].arguments[1], 'req123');
      assert.deepStrictEqual(mockHandler.mock.calls[0].arguments[2], { value: 'test-data' });
    });

    it('should pass services to handler in correct order', async () => {
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      const handlerArgs = mockHandler.mock.calls[0].arguments;
      assert.strictEqual(handlerArgs[3], mockAicliService);
      assert.strictEqual(handlerArgs[4], mockClients); // clients from connectionManager.getAllClients()
      assert.strictEqual(handlerArgs[5], mockConnectionManager);
    });

    it('should handle unknown message type', async () => {
      const message = {
        type: 'unknown',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[0], 'client1');
      assert.strictEqual(errorCall.arguments[1], 'req123');
      assert.strictEqual(errorCall.arguments[2], 'ROUTING_ERROR');
      assert.ok(errorCall.arguments[3].includes('No handler registered'));
    });

    it('should handle invalid JSON', async () => {
      await router.routeMessage(
        'client1',
        'invalid-json{',
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'ROUTING_ERROR');
      assert.ok(errorCall.arguments[3].includes('Failed to parse'));
    });

    it('should handle missing message type', async () => {
      const message = {
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'ROUTING_ERROR');
    });

    it('should handle handler errors', async () => {
      const errorHandler = mock.fn(() => {
        throw new Error('Handler error');
      });

      router.registerHandler('test', errorHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      // Handler error is caught in both dispatchMessage and routeMessage, resulting in 2 error messages
      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 2);

      // Check the handler-specific error (first call)
      const handlerErrorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(handlerErrorCall.arguments[2], 'HANDLER_ERROR');
      assert.ok(handlerErrorCall.arguments[3].includes('Handler error'));

      // Check the routing error (second call)
      const routingErrorCall = WebSocketUtilities.sendErrorMessage.mock.calls[1];
      assert.strictEqual(routingErrorCall.arguments[2], 'ROUTING_ERROR');
      assert.ok(routingErrorCall.arguments[3].includes('Handler error'));
    });

    it('should update client activity', async () => {
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(mockConnectionManager.updateClientActivity.mock.calls.length, 1);
      assert.strictEqual(
        mockConnectionManager.updateClientActivity.mock.calls[0].arguments[0],
        'client1'
      );
    });

    it('should emit events for monitoring', async () => {
      let receivedEvent = null;
      let dispatchedEvent = null;

      router.on('messageReceived', (event) => {
        receivedEvent = event;
      });

      router.on('messageDispatched', (event) => {
        dispatchedEvent = event;
      });

      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.ok(receivedEvent);
      assert.strictEqual(receivedEvent.clientId, 'client1');
      assert.strictEqual(receivedEvent.messageType, 'test');
      assert.strictEqual(receivedEvent.requestId, 'req123');

      assert.ok(dispatchedEvent);
      assert.strictEqual(dispatchedEvent.clientId, 'client1');
      assert.strictEqual(dispatchedEvent.messageType, 'test');
    });
  });

  describe('dispatchMessage', () => {
    it('should dispatch to correct handler', async () => {
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: { test: true },
      };

      await router.dispatchMessage('client1', message, mockAicliService, mockConnectionManager);

      assert.strictEqual(mockHandler.mock.calls.length, 1);
      assert.deepStrictEqual(mockHandler.mock.calls[0].arguments[2], { test: true });
    });

    it('should handle handler errors and emit events', async () => {
      let errorEvent = null;
      router.on('handlerError', (event) => {
        errorEvent = event;
      });

      const errorHandler = mock.fn(() => {
        throw new Error('Test handler error');
      });

      router.registerHandler('error', errorHandler);

      const message = {
        type: 'error',
        requestId: 'req123',
        data: {},
      };

      await assert.rejects(async () => {
        await router.dispatchMessage('client1', message, mockAicliService, mockConnectionManager);
      }, /Test handler error/);

      assert.ok(errorEvent);
      assert.strictEqual(errorEvent.messageType, 'error');
      assert.strictEqual(errorEvent.error, 'Test handler error');
    });
  });

  describe('setupMessageListener', () => {
    it('should set up message listener on WebSocket', () => {
      const mockWs = {
        on: mock.fn(),
      };

      router.setupMessageListener(mockWs, 'client1', mockAicliService, mockConnectionManager);

      assert.strictEqual(mockWs.on.mock.calls.length, 1);
      assert.strictEqual(mockWs.on.mock.calls[0].arguments[0], 'message');
      assert.strictEqual(typeof mockWs.on.mock.calls[0].arguments[1], 'function');
    });

    it('should route messages received through listener', async () => {
      let messageHandler;
      const mockWs = {
        on: mock.fn((event, handler) => {
          if (event === 'message') {
            messageHandler = handler;
          }
        }),
      };

      router.registerHandler('test', mockHandler);
      router.setupMessageListener(mockWs, 'client1', mockAicliService, mockConnectionManager);

      // Simulate receiving a message
      const message = { type: 'test', requestId: 'req123', data: {} };
      await messageHandler(JSON.stringify(message));

      assert.strictEqual(mockHandler.mock.calls.length, 1);
    });
  });

  describe('createMiddleware', () => {
    it('should intercept messages with middleware', async () => {
      let middlewareCalled = false;
      const middlewareFunction = mock.fn(
        async (_clientId, _message, _aicliService, _connectionManager) => {
          middlewareCalled = true;
          return true; // Continue to handler
        }
      );

      router.createMiddleware(middlewareFunction);
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(middlewareCalled, true);
      assert.strictEqual(mockHandler.mock.calls.length, 1);
    });

    it('should allow middleware to block message processing', async () => {
      const blockingMiddleware = mock.fn(async () => false); // Block message

      router.createMiddleware(blockingMiddleware);
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(blockingMiddleware.mock.calls.length, 1);
      assert.strictEqual(mockHandler.mock.calls.length, 0); // Handler should not be called
    });

    it('should continue on middleware error', async () => {
      const errorMiddleware = mock.fn(async () => {
        throw new Error('Middleware error');
      });

      router.createMiddleware(errorMiddleware);
      router.registerHandler('test', mockHandler);

      const message = {
        type: 'test',
        requestId: 'req123',
        data: {},
      };

      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      assert.strictEqual(mockHandler.mock.calls.length, 1); // Handler should still be called
    });
  });

  describe('enableMessageQueueing', () => {
    it('should enable message queueing', () => {
      router.enableMessageQueueing({ batchSize: 5, flushInterval: 50 });

      assert.ok(router.queueFlushInterval);
      assert.strictEqual(router.messageQueue.length, 0);
    });

    it('should queue messages instead of processing immediately', async () => {
      router.registerHandler('test', mockHandler);
      router.enableMessageQueueing({ batchSize: 3 });

      const message = { type: 'test', requestId: 'req123', data: {} };

      // Send 2 messages - should be queued
      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );
      await router.routeMessage(
        'client2',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      // Handler should not be called yet
      assert.strictEqual(mockHandler.mock.calls.length, 0);
    });
  });

  describe('disableMessageQueueing', () => {
    it('should disable message queueing and flush remaining messages', async () => {
      router.registerHandler('test', mockHandler);
      router.enableMessageQueueing({ batchSize: 10 });

      const message = { type: 'test', requestId: 'req123', data: {} };

      // Queue a message
      await router.routeMessage(
        'client1',
        JSON.stringify(message),
        mockAicliService,
        mockConnectionManager
      );

      // Disable queueing
      await router.disableMessageQueueing();

      // Interval should be cleared
      assert.strictEqual(router.queueFlushInterval, null);
    });
  });

  describe('getStats', () => {
    it('should return router statistics', () => {
      router.registerHandler('type1', mock.fn());
      router.registerHandler('type2', mock.fn());

      const stats = router.getStats();

      assert.strictEqual(stats.registeredHandlers, 2);
      assert.deepStrictEqual(stats.handlerTypes, ['type1', 'type2']);
      assert.strictEqual(stats.queueEnabled, false);
      assert.strictEqual(stats.queueSize, 0);
    });

    it('should show queue statistics when enabled', () => {
      router.enableMessageQueueing();

      const stats = router.getStats();

      assert.strictEqual(stats.queueEnabled, true);
      assert.strictEqual(typeof stats.queueSize, 'number');
    });
  });

  describe('shutdown', () => {
    it('should clean up all resources', async () => {
      router.registerHandler('test1', mock.fn());
      router.registerHandler('test2', mock.fn());
      router.enableMessageQueueing();

      // Add event listener
      const listener = mock.fn();
      router.on('test', listener);

      await router.shutdown();

      assert.strictEqual(router.handlers.size, 0);
      assert.strictEqual(router.queueFlushInterval, null);
      assert.strictEqual(router.listenerCount('test'), 0);
    });
  });
});
