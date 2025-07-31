import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { WebSocketMessageRouter } from '../../services/websocket-message-router.js';

// Mock WebSocketUtilities
const mockWebSocketUtilities = {
  safeParse: mock.fn(),
  validateMessage: mock.fn(),
  sendErrorMessage: mock.fn()
};

const mockUtilities = mock.module('../../services/websocket-utilities.js', {
  WebSocketUtilities: mockWebSocketUtilities
});

describe('WebSocketMessageRouter', () => {
  let router;
  let mockAicliService;
  let mockConnectionManager;
  let mockClients;

  beforeEach(() => {
    router = new WebSocketMessageRouter();
    
    mockAicliService = {
      sendPrompt: mock.fn(() => Promise.resolve({ result: 'test' }))
    };
    
    mockClients = new Map();
    
    mockConnectionManager = {
      updateClientActivity: mock.fn(),
      getAllClients: mock.fn(() => mockClients)
    };

    // Reset mocks
    mockWebSocketUtilities.safeParse.mock.resetCalls();
    mockWebSocketUtilities.validateMessage.mock.resetCalls();
    mockWebSocketUtilities.sendErrorMessage.mock.resetCalls();
  });

  afterEach(() => {
    if (router) {
      router.shutdown();
    }
  });

  describe('constructor', () => {
    it('should initialize with empty handlers and message queue', () => {
      assert.ok(router instanceof EventEmitter);
      assert.ok(router.handlers instanceof Map);
      assert.strictEqual(router.handlers.size, 0);
      assert.ok(Array.isArray(router.messageQueue));
      assert.strictEqual(router.messageQueue.length, 0);
    });
  });

  describe('handler registration', () => {
    it('should register a single handler', () => {
      const handler = mock.fn();
      router.registerHandler('test', handler);
      
      assert.strictEqual(router.handlers.size, 1);
      assert.strictEqual(router.handlers.get('test'), handler);
    });

    it('should reject non-function handler', () => {
      assert.throws(
        () => router.registerHandler('test', 'not-a-function'),
        /must be a function/
      );
    });

    it('should register multiple handlers', () => {
      const handlers = {
        ping: mock.fn(),
        pong: mock.fn(),
        message: mock.fn()
      };
      
      router.registerHandlers(handlers);
      
      assert.strictEqual(router.handlers.size, 3);
      assert.strictEqual(router.handlers.get('ping'), handlers.ping);
      assert.strictEqual(router.handlers.get('pong'), handlers.pong);
      assert.strictEqual(router.handlers.get('message'), handlers.message);
    });

    it('should unregister handlers', () => {
      const handler = mock.fn();
      router.registerHandler('test', handler);
      
      const removed = router.unregisterHandler('test');
      
      assert.strictEqual(removed, true);
      assert.strictEqual(router.handlers.size, 0);
    });

    it('should return false when unregistering non-existent handler', () => {
      const removed = router.unregisterHandler('non-existent');
      assert.strictEqual(removed, false);
    });

    it('should get registered message types', () => {
      router.registerHandler('ping', mock.fn());
      router.registerHandler('message', mock.fn());
      
      const types = router.getRegisteredTypes();
      
      assert.strictEqual(types.length, 2);
      assert.ok(types.includes('ping'));
      assert.ok(types.includes('message'));
    });
  });

  describe('message routing', () => {
    const mockMessage = {
      type: 'test',
      requestId: 'req123',
      data: { content: 'hello' }
    };

    beforeEach(() => {
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => mockMessage);
      mockWebSocketUtilities.validateMessage.mock.mockImplementation(() => ({ valid: true }));
    });

    it('should route valid message to handler', async () => {
      const handler = mock.fn();
      router.registerHandler('test', handler);
      
      let messageReceivedEvent = null;
      router.once('messageReceived', (event) => {
        messageReceivedEvent = event;
      });

      await router.routeMessage('client1', Buffer.from(JSON.stringify(mockMessage)), mockAicliService, mockConnectionManager);
      
      assert.strictEqual(handler.mock.calls.length, 1);
      assert.strictEqual(mockConnectionManager.updateClientActivity.mock.calls.length, 1);
      assert.strictEqual(mockConnectionManager.updateClientActivity.mock.calls[0].arguments[0], 'client1');
      
      assert.ok(messageReceivedEvent);
      assert.strictEqual(messageReceivedEvent.clientId, 'client1');
      assert.strictEqual(messageReceivedEvent.messageType, 'test');
      assert.strictEqual(messageReceivedEvent.requestId, 'req123');
    });

    it('should handle JSON parse errors', async () => {
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => null);
      
      let errorEvent = null;
      router.once('routingError', (event) => {
        errorEvent = event;
      });

      await router.routeMessage('client1', Buffer.from('invalid json'), mockAicliService, mockConnectionManager);
      
      assert.strictEqual(mockWebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      assert.ok(errorEvent);
      assert.strictEqual(errorEvent.clientId, 'client1');
      assert.ok(errorEvent.error.includes('Failed to parse'));
    });

    it('should handle message validation errors', async () => {
      mockWebSocketUtilities.validateMessage.mock.mockImplementation(() => ({ 
        valid: false, 
        error: 'Missing required field' 
      }));
      
      await router.routeMessage('client1', Buffer.from(JSON.stringify(mockMessage)), mockAicliService, mockConnectionManager);
      
      assert.strictEqual(mockWebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = mockWebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'ROUTING_ERROR');
      assert.ok(errorCall.arguments[3].includes('Missing required field'));
    });

    it('should handle missing handler error', async () => {
      // Don't register handler for 'test' type
      
      await router.routeMessage('client1', Buffer.from(JSON.stringify(mockMessage)), mockAicliService, mockConnectionManager);
      
      assert.strictEqual(mockWebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = mockWebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.ok(errorCall.arguments[3].includes('No handler registered'));
    });

    it('should not log ping messages', async () => {
      const pingMessage = { type: 'ping', requestId: 'ping1' };
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => pingMessage);
      
      const handler = mock.fn();
      router.registerHandler('ping', handler);
      
      // This test mainly verifies that ping messages don't cause excessive logging
      // We can't easily test console.log output, but we can verify the handler is called
      await router.routeMessage('client1', Buffer.from(JSON.stringify(pingMessage)), mockAicliService, mockConnectionManager);
      
      assert.strictEqual(handler.mock.calls.length, 1);
    });
  });

  describe('message dispatching', () => {
    const mockMessage = {
      type: 'test',
      requestId: 'req123',
      data: { content: 'hello' }
    };

    it('should dispatch message with correct parameters', async () => {
      const handler = mock.fn();
      router.registerHandler('test', handler);
      
      let dispatchedEvent = null;
      router.once('messageDispatched', (event) => {
        dispatchedEvent = event;
      });

      await router.dispatchMessage('client1', mockMessage, mockAicliService, mockConnectionManager);
      
      assert.strictEqual(handler.mock.calls.length, 1);
      const [clientId, requestId, data, aicliService, clients, connectionManager] = handler.mock.calls[0].arguments;
      
      assert.strictEqual(clientId, 'client1');
      assert.strictEqual(requestId, 'req123');
      assert.deepStrictEqual(data, { content: 'hello' });
      assert.strictEqual(aicliService, mockAicliService);
      assert.strictEqual(clients, mockClients);
      assert.strictEqual(connectionManager, mockConnectionManager);
      
      assert.ok(dispatchedEvent);
      assert.strictEqual(dispatchedEvent.messageType, 'test');
    });

    it('should handle handler errors', async () => {
      const handler = mock.fn(() => {
        throw new Error('Handler failed');
      });
      router.registerHandler('test', handler);
      
      let handlerErrorEvent = null;
      router.once('handlerError', (event) => {
        handlerErrorEvent = event;
      });

      await assert.rejects(
        router.dispatchMessage('client1', mockMessage, mockAicliService, mockConnectionManager),
        /Handler failed/
      );
      
      assert.strictEqual(mockWebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = mockWebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'HANDLER_ERROR');
      
      assert.ok(handlerErrorEvent);
      assert.strictEqual(handlerErrorEvent.messageType, 'test');
      assert.strictEqual(handlerErrorEvent.error, 'Handler failed');
    });
  });

  describe('message listener setup', () => {
    it('should set up message listener on WebSocket', () => {
      const mockWs = new EventEmitter();
      
      router.setupMessageListener(mockWs, 'client1', mockAicliService, mockConnectionManager);
      
      // Verify listener was added
      assert.strictEqual(mockWs.listenerCount('message'), 1);
    });

    it('should handle messages through listener', async () => {
      const mockWs = new EventEmitter();
      const handler = mock.fn();
      
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => ({
        type: 'test',
        requestId: 'req123'
      }));
      mockWebSocketUtilities.validateMessage.mock.mockImplementation(() => ({ valid: true }));
      
      router.registerHandler('test', handler);
      router.setupMessageListener(mockWs, 'client1', mockAicliService, mockConnectionManager);
      
      // Emit message
      mockWs.emit('message', Buffer.from('{"type":"test","requestId":"req123"}'));
      
      // Wait for async processing
      await new Promise(resolve => setTimeout(resolve, 10));
      
      assert.strictEqual(handler.mock.calls.length, 1);
    });
  });

  describe('middleware', () => {
    it('should create and apply middleware', async () => {
      const middleware = mock.fn(() => true); // Allow message to continue
      const handler = mock.fn();
      
      router.registerHandler('test', handler);
      router.createMiddleware(middleware);
      
      const mockMessage = { type: 'test', requestId: 'req123', data: {} };
      
      await router.dispatchMessage('client1', mockMessage, mockAicliService, mockConnectionManager);
      
      assert.strictEqual(middleware.mock.calls.length, 1);
      assert.strictEqual(handler.mock.calls.length, 1);
    });

    it('should block message when middleware returns false', async () => {
      const middleware = mock.fn(() => false); // Block message
      const handler = mock.fn();
      
      router.registerHandler('test', handler);
      router.createMiddleware(middleware);
      
      const mockMessage = { type: 'test', requestId: 'req123', data: {} };
      
      await router.dispatchMessage('client1', mockMessage, mockAicliService, mockConnectionManager);
      
      assert.strictEqual(middleware.mock.calls.length, 1);
      assert.strictEqual(handler.mock.calls.length, 0); // Handler should not be called
    });

    it('should continue processing if middleware throws error', async () => {
      const middleware = mock.fn(() => {
        throw new Error('Middleware error');
      });
      const handler = mock.fn();
      
      router.registerHandler('test', handler);
      router.createMiddleware(middleware);
      
      const mockMessage = { type: 'test', requestId: 'req123', data: {} };
      
      await router.dispatchMessage('client1', mockMessage, mockAicliService, mockConnectionManager);
      
      assert.strictEqual(middleware.mock.calls.length, 1);
      assert.strictEqual(handler.mock.calls.length, 1); // Handler should still be called
    });
  });

  describe('message queueing', () => {
    it('should enable message queueing', () => {
      router.enableMessageQueueing({ batchSize: 5, flushInterval: 50 });
      
      const stats = router.getStats();
      assert.strictEqual(stats.queueEnabled, true);
      assert.strictEqual(stats.queueSize, 0);
    });

    it('should queue messages instead of processing immediately', async () => {
      router.enableMessageQueueing({ batchSize: 2 });
      
      const handler = mock.fn();
      router.registerHandler('test', handler);
      
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => ({
        type: 'test',
        requestId: 'req1'
      }));
      mockWebSocketUtilities.validateMessage.mock.mockImplementation(() => ({ valid: true }));
      
      // Queue a message
      await router.routeMessage('client1', Buffer.from('{}'), mockAicliService, mockConnectionManager);
      
      // Should be queued, not processed yet
      const stats = router.getStats();
      assert.strictEqual(stats.queueSize, 1);
    });

    it('should flush queue when batch size reached', async () => {
      router.enableMessageQueueing({ batchSize: 2 });
      
      // Mock the flush method to track calls
      const originalFlush = router.flushMessageQueue.bind(router);
      router.flushMessageQueue = mock.fn(originalFlush);
      
      // Add messages to reach batch size
      await router.routeMessage('client1', Buffer.from('{}'), mockAicliService, mockConnectionManager);
      await router.routeMessage('client2', Buffer.from('{}'), mockAicliService, mockConnectionManager);
      
      // Should trigger flush
      assert.strictEqual(router.flushMessageQueue.mock.calls.length, 1);
    });

    it('should disable message queueing', async () => {
      router.enableMessageQueueing({ batchSize: 5 });
      
      // Add a message to queue
      await router.routeMessage('client1', Buffer.from('{}'), mockAicliService, mockConnectionManager);
      
      router.disableMessageQueueing();
      
      const stats = router.getStats();
      assert.strictEqual(stats.queueEnabled, false);
      assert.strictEqual(stats.queueSize, 0); // Should be flushed
    });
  });

  describe('statistics', () => {
    it('should return correct stats', () => {
      router.registerHandler('ping', mock.fn());
      router.registerHandler('message', mock.fn());
      
      const stats = router.getStats();
      
      assert.strictEqual(stats.registeredHandlers, 2);
      assert.strictEqual(stats.handlerTypes.length, 2);
      assert.ok(stats.handlerTypes.includes('ping'));
      assert.ok(stats.handlerTypes.includes('message'));
      assert.strictEqual(stats.queueEnabled, false);
      assert.strictEqual(stats.queueSize, 0);
    });

    it('should show queue stats when enabled', () => {
      router.enableMessageQueueing();
      
      const stats = router.getStats();
      assert.strictEqual(stats.queueEnabled, true);
    });
  });

  describe('shutdown', () => {
    it('should shutdown cleanly', () => {
      router.registerHandler('test', mock.fn());
      router.enableMessageQueueing();
      
      router.shutdown();
      
      assert.strictEqual(router.handlers.size, 0);
      assert.strictEqual(router.listenerCount('messageReceived'), 0);
      
      const stats = router.getStats();
      assert.strictEqual(stats.queueEnabled, false);
    });

    it('should flush remaining messages on shutdown', async () => {
      router.enableMessageQueueing({ batchSize: 10 });
      
      // Add message to queue
      await router.routeMessage('client1', Buffer.from('{}'), mockAicliService, mockConnectionManager);
      
      const originalFlush = router.flushMessageQueue.bind(router);
      router.flushMessageQueue = mock.fn(originalFlush);
      
      router.shutdown();
      
      // Should call flush for remaining messages
      assert.strictEqual(router.flushMessageQueue.mock.calls.length, 1);
    });
  });

  describe('event emission', () => {
    it('should emit routing events', async () => {
      const handler = mock.fn();
      router.registerHandler('test', handler);
      
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => ({
        type: 'test',
        requestId: 'req123'
      }));
      mockWebSocketUtilities.validateMessage.mock.mockImplementation(() => ({ valid: true }));
      
      let receivedEvent = null;
      let dispatchedEvent = null;
      
      router.once('messageReceived', (event) => {
        receivedEvent = event;
      });
      
      router.once('messageDispatched', (event) => {
        dispatchedEvent = event;
      });
      
      await router.routeMessage('client1', Buffer.from('{}'), mockAicliService, mockConnectionManager);
      
      assert.ok(receivedEvent);
      assert.strictEqual(receivedEvent.clientId, 'client1');
      assert.strictEqual(receivedEvent.messageType, 'test');
      
      assert.ok(dispatchedEvent);
      assert.strictEqual(dispatchedEvent.clientId, 'client1');
      assert.strictEqual(dispatchedEvent.messageType, 'test');
    });

    it('should emit error events', async () => {
      mockWebSocketUtilities.safeParse.mock.mockImplementation(() => null);
      
      let errorEvent = null;
      router.once('routingError', (event) => {
        errorEvent = event;
      });
      
      await router.routeMessage('client1', Buffer.from('invalid'), mockAicliService, mockConnectionManager);
      
      assert.ok(errorEvent);
      assert.strictEqual(errorEvent.clientId, 'client1');
      assert.ok(errorEvent.error);
    });
  });
});