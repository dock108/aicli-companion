import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { WebSocketEventBroadcaster } from '../../services/websocket-event-broadcaster.js';

describe('WebSocketEventBroadcaster', () => {
  let broadcaster;
  let mockConnectionManager;
  let mockAicliService;
  let mockClients;

  beforeEach(() => {
    // Mock clients
    mockClients = new Map();
    mockClients.set('client1', {
      ws: { readyState: 1 },
      sessionIds: new Set(['session1']),
      subscribedEvents: new Set(['event1', 'event2']),
    });
    mockClients.set('client2', {
      ws: { readyState: 1 },
      sessionIds: new Set(['session1', 'session2']),
      subscribedEvents: new Set(['event1']),
    });

    // Mock connection manager
    mockConnectionManager = {
      getAllClients: mock.fn(() => mockClients),
      getClientsBySession: mock.fn(() => [
        { clientId: 'client1', client: mockClients.get('client1') },
        { clientId: 'client2', client: mockClients.get('client2') },
      ]),
    };

    // Mock AICLI service
    mockAicliService = new EventEmitter();

    // Create broadcaster
    broadcaster = new WebSocketEventBroadcaster(mockConnectionManager);

    // Reset mocks
    mockConnectionManager.getAllClients.mock.resetCalls();
    mockConnectionManager.getClientsBySession.mock.resetCalls();
  });

  afterEach(() => {
    if (broadcaster) {
      broadcaster.shutdown();
    }
  });

  describe('constructor', () => {
    it('should initialize with connection manager', () => {
      assert.ok(broadcaster instanceof EventEmitter);
      assert.strictEqual(broadcaster.connectionManager, mockConnectionManager);
      assert.ok(broadcaster.eventListeners instanceof Map);
    });
  });

  describe('setupEventListeners', () => {
    it('should set up all event listeners', () => {
      broadcaster.setupEventListeners(mockAicliService);

      // Verify event listeners were added
      assert.strictEqual(broadcaster.eventListeners.size, 1);
      assert.ok(broadcaster.eventListeners.has(mockAicliService));

      const serviceListeners = broadcaster.eventListeners.get(mockAicliService);
      assert.ok(serviceListeners.has('streamData'));
      assert.ok(serviceListeners.has('systemInit'));
      assert.ok(serviceListeners.has('assistantMessage'));
      assert.ok(serviceListeners.has('toolUse'));
      assert.ok(serviceListeners.has('toolResult'));
      assert.ok(serviceListeners.has('conversationResult'));
      assert.ok(serviceListeners.has('permissionRequired'));
      assert.ok(serviceListeners.has('processStart'));
      assert.ok(serviceListeners.has('processExit'));
      assert.ok(serviceListeners.has('processStderr'));
      assert.ok(serviceListeners.has('streamChunk'));
      assert.ok(serviceListeners.has('commandProgress'));
      assert.ok(serviceListeners.has('streamError'));
    });
  });

  describe('validateEventData', () => {
    it('should validate data with sessionId', () => {
      const valid = broadcaster.validateEventData({ sessionId: 'session1', data: 'test' }, 'test');
      assert.strictEqual(valid, true);
    });

    it('should reject data without sessionId', () => {
      const valid = broadcaster.validateEventData({ data: 'test' }, 'test');
      assert.strictEqual(valid, false);
    });

    it('should reject null/undefined data', () => {
      assert.strictEqual(broadcaster.validateEventData(null, 'test'), false);
      assert.strictEqual(broadcaster.validateEventData(undefined, 'test'), false);
    });
  });

  describe('event handlers', () => {
    beforeEach(() => {
      broadcaster.setupEventListeners(mockAicliService);
    });

    it('should handle valid stream data event', () => {
      // Mock broadcastToSession to verify it's called
      broadcaster.broadcastToSession = mock.fn();

      const eventData = {
        sessionId: 'session1',
        data: 'test content',
        isComplete: true,
        originalMessage: 'original',
      };

      broadcaster.handleStreamDataEvent(eventData);

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 1);
      const [sessionId, message] = broadcaster.broadcastToSession.mock.calls[0].arguments;

      assert.strictEqual(sessionId, 'session1');
      assert.strictEqual(message.type, 'streamData');
      assert.strictEqual(message.data.sessionId, 'session1');
      assert.strictEqual(message.data.isComplete, true);
      assert.ok(message.timestamp);
    });

    it('should handle system init event', () => {
      broadcaster.broadcastToSession = mock.fn();

      const eventData = {
        sessionId: 'session1',
        data: { status: 'initialized' },
      };

      broadcaster.handleSystemInitEvent(eventData);

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 1);
      const [_sessionId, message] = broadcaster.broadcastToSession.mock.calls[0].arguments;

      assert.strictEqual(message.type, 'systemInit');
      assert.deepStrictEqual(message.data, { status: 'initialized' });
    });

    it('should handle assistant message event', () => {
      broadcaster.broadcastToSession = mock.fn();

      const eventData = {
        sessionId: 'session1',
        data: { content: 'Hello from assistant' },
      };

      broadcaster.handleAssistantMessageEvent(eventData);

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 1);
      const [_sessionId2, message] = broadcaster.broadcastToSession.mock.calls[0].arguments;

      assert.strictEqual(message.type, 'assistantMessage');
      assert.deepStrictEqual(message.data, { content: 'Hello from assistant' });
    });

    it('should handle permission required event', () => {
      broadcaster.broadcastToSession = mock.fn();

      const eventData = {
        sessionId: 'session1',
        prompt: 'Allow file write?',
        options: ['allow', 'deny'],
        default: 'deny',
      };

      broadcaster.handlePermissionRequiredEvent(eventData);

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 1);
      const [_sessionId3, message] = broadcaster.broadcastToSession.mock.calls[0].arguments;

      assert.strictEqual(message.type, 'permissionRequired');
      assert.strictEqual(message.data.sessionId, 'session1');
      assert.strictEqual(message.data.prompt, 'Allow file write?');
      assert.deepStrictEqual(message.data.options, ['allow', 'deny']);
      assert.strictEqual(message.data.default, 'deny');
    });

    it('should handle process start event', () => {
      broadcaster.broadcastToSession = mock.fn();

      const eventData = {
        sessionId: 'session1',
        pid: 12345,
        command: 'claude',
        workingDirectory: '/test',
        type: 'command',
      };

      broadcaster.handleProcessStartEvent(eventData);

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 1);
      const [_sessionId4, message] = broadcaster.broadcastToSession.mock.calls[0].arguments;

      assert.strictEqual(message.type, 'processStart');
      assert.strictEqual(message.data.sessionId, 'session1');
      assert.strictEqual(message.data.pid, 12345);
      assert.strictEqual(message.data.command, 'claude');
      assert.strictEqual(message.data.processType, 'command');
    });

    it('should handle stream error event', () => {
      broadcaster.broadcastToSession = mock.fn();

      const eventData = {
        sessionId: 'session1',
        error: 'Stream failed',
        details: { code: 'STREAM_ERROR' },
      };

      broadcaster.handleStreamErrorEvent(eventData);

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 1);
      const [_sessionId5, message] = broadcaster.broadcastToSession.mock.calls[0].arguments;

      assert.strictEqual(message.type, 'streamError');
      assert.strictEqual(message.data.sessionId, 'session1');
      assert.strictEqual(message.data.error, 'Stream failed');
      assert.deepStrictEqual(message.data.details, { code: 'STREAM_ERROR' });
    });

    it('should reject invalid events', () => {
      broadcaster.broadcastToSession = mock.fn();

      // Event without sessionId
      broadcaster.handleStreamDataEvent({ data: 'test' });

      assert.strictEqual(broadcaster.broadcastToSession.mock.calls.length, 0);
    });
  });

  describe('broadcasting methods', () => {
    it('should emit messageBroadcast event', () => {
      let broadcastEvent = null;
      broadcaster.once('messageBroadcast', (event) => {
        broadcastEvent = event;
      });

      const message = { type: 'test', data: 'test message', timestamp: new Date().toISOString() };
      broadcaster.broadcastToSession('session1', message);

      assert.ok(broadcastEvent);
      assert.strictEqual(broadcastEvent.sessionId, 'session1');
      assert.strictEqual(broadcastEvent.messageType, 'test');
      assert.strictEqual(broadcastEvent.clientCount, 2);
    });

    it('should emit systemBroadcast event', () => {
      let systemBroadcastEvent = null;
      broadcaster.once('systemBroadcast', (event) => {
        systemBroadcastEvent = event;
      });

      const message = {
        type: 'system',
        data: 'system message',
        timestamp: new Date().toISOString(),
      };
      broadcaster.broadcastToAll(message);

      assert.ok(systemBroadcastEvent);
      assert.strictEqual(systemBroadcastEvent.messageType, 'system');
      assert.strictEqual(systemBroadcastEvent.totalClients, 2);
    });

    it('should emit eventBroadcast for subscribed clients', () => {
      let eventBroadcastEvent = null;
      broadcaster.once('eventBroadcast', (event) => {
        eventBroadcastEvent = event;
      });

      const message = {
        type: 'notification',
        data: 'event message',
        timestamp: new Date().toISOString(),
      };
      broadcaster.broadcastToSubscribed('event1', message);

      assert.ok(eventBroadcastEvent);
      assert.strictEqual(eventBroadcastEvent.eventType, 'event1');
      assert.strictEqual(eventBroadcastEvent.messageType, 'notification');
    });
  });

  describe('removeEventListeners', () => {
    it('should remove all listeners for a service', () => {
      broadcaster.setupEventListeners(mockAicliService);

      assert.strictEqual(broadcaster.eventListeners.size, 1);

      broadcaster.removeEventListeners(mockAicliService);

      assert.strictEqual(broadcaster.eventListeners.size, 0);
    });

    it('should handle removing listeners for non-existent service', () => {
      const otherService = new EventEmitter();

      assert.doesNotThrow(() => {
        broadcaster.removeEventListeners(otherService);
      });
    });
  });

  describe('getStats', () => {
    it('should return correct statistics', () => {
      broadcaster.setupEventListeners(mockAicliService);

      const stats = broadcaster.getStats();

      assert.strictEqual(stats.connectedClients, 2);
      assert.strictEqual(stats.totalSubscriptions, 3); // client1: 2, client2: 1
      assert.deepStrictEqual(stats.eventSubscriptions, {
        event1: 2, // Both clients
        event2: 1, // Only client1
      });
      assert.strictEqual(stats.activeListeners, 1);
    });

    it('should handle clients without subscriptions', () => {
      mockClients.set('client3', {
        ws: { readyState: 1 },
        sessionIds: new Set(['session3']),
        // No subscribedEvents
      });

      const stats = broadcaster.getStats();

      assert.strictEqual(stats.connectedClients, 3);
      assert.strictEqual(stats.totalSubscriptions, 3); // Only from client1 and client2
    });
  });

  describe('shutdown', () => {
    it('should clean up all resources', () => {
      broadcaster.setupEventListeners(mockAicliService);

      assert.strictEqual(broadcaster.eventListeners.size, 1);

      broadcaster.shutdown();

      assert.strictEqual(broadcaster.eventListeners.size, 0);
    });
  });

  describe('event integration', () => {
    it('should handle multiple event types in sequence', () => {
      broadcaster.setupEventListeners(mockAicliService);

      let broadcastCount = 0;
      broadcaster.on('messageBroadcast', () => {
        broadcastCount++;
      });

      // Emit various events
      mockAicliService.emit('streamData', { sessionId: 'session1', data: 'test1' });
      mockAicliService.emit('assistantMessage', {
        sessionId: 'session1',
        data: { content: 'hello' },
      });
      mockAicliService.emit('toolUse', { sessionId: 'session1', data: { tool: 'Read' } });
      mockAicliService.emit('streamError', { sessionId: 'session1', error: 'failed' });

      assert.strictEqual(broadcastCount, 4);
    });

    it('should filter out invalid events', () => {
      broadcaster.setupEventListeners(mockAicliService);

      let broadcastCount = 0;
      broadcaster.on('messageBroadcast', () => {
        broadcastCount++;
      });

      // Emit valid and invalid events
      mockAicliService.emit('streamData', { sessionId: 'session1', data: 'valid' });
      mockAicliService.emit('streamData', { data: 'invalid - no sessionId' });
      mockAicliService.emit('assistantMessage', {
        sessionId: 'session1',
        data: { content: 'valid' },
      });

      assert.strictEqual(broadcastCount, 2); // Only valid events
    });
  });
});
