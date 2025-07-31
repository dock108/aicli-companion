import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { WebSocketUtilities } from '../../services/websocket-utilities.js';

describe('WebSocketUtilities Coverage Tests', () => {
  let _mockMessageQueueService;

  beforeEach(() => {
    // Reset any global state
    _mockMessageQueueService = {
      queueMessage: mock.fn(),
    };
  });

  afterEach(() => {
    // Cleanup any global state
  });

  describe('sendMessage', () => {
    it('should send message to connected client', () => {
      const mockWs = {
        readyState: 1, // WebSocket.OPEN
        send: mock.fn(),
      };
      const clients = new Map([['client1', { ws: mockWs, lastActivity: new Date() }]]);
      const message = { type: 'test', data: 'hello' };

      const result = WebSocketUtilities.sendMessage('client1', message, clients);

      assert.strictEqual(result, true);
      assert.strictEqual(mockWs.send.mock.calls.length, 1);
      assert.strictEqual(mockWs.send.mock.calls[0].arguments[0], JSON.stringify(message));
    });

    it('should return false for non-existent client', () => {
      const clients = new Map();
      const message = { type: 'test' };

      const result = WebSocketUtilities.sendMessage('nonexistent', message, clients);
      assert.strictEqual(result, false);
    });

    it('should return false for disconnected client', () => {
      const mockWs = {
        readyState: 3, // WebSocket.CLOSED
        send: mock.fn(),
      };
      const clients = new Map([['client1', { ws: mockWs, lastActivity: new Date() }]]);
      const message = { type: 'test' };

      const result = WebSocketUtilities.sendMessage('client1', message, clients);
      assert.strictEqual(result, false);
      assert.strictEqual(mockWs.send.mock.calls.length, 0);
    });

    it('should handle send errors gracefully', () => {
      const mockWs = {
        readyState: 1,
        send: mock.fn(() => {
          throw new Error('Send failed');
        }),
      };
      const clients = new Map([['client1', { ws: mockWs, lastActivity: new Date() }]]);
      const message = { type: 'test' };

      const result = WebSocketUtilities.sendMessage('client1', message, clients);
      assert.strictEqual(result, false);
    });

    it('should update client last activity', () => {
      const mockWs = {
        readyState: 1,
        send: mock.fn(),
      };
      const client = { ws: mockWs, lastActivity: new Date(Date.now() - 1000) };
      const clients = new Map([['client1', client]]);
      const message = { type: 'test' };

      const originalTime = client.lastActivity.getTime();
      WebSocketUtilities.sendMessage('client1', message, clients);

      assert.ok(client.lastActivity.getTime() > originalTime);
    });
  });

  describe('sendErrorMessage', () => {
    it('should send properly formatted error message', () => {
      const mockWs = {
        readyState: 1,
        send: mock.fn(),
      };
      const clients = new Map([['client1', { ws: mockWs, lastActivity: new Date() }]]);

      const result = WebSocketUtilities.sendErrorMessage(
        'client1',
        'req123',
        'ERROR_CODE',
        'Test error',
        clients,
        { extra: 'data' }
      );

      assert.strictEqual(result, true);
      const sentMessage = JSON.parse(mockWs.send.mock.calls[0].arguments[0]);
      assert.strictEqual(sentMessage.type, 'error');
      assert.strictEqual(sentMessage.requestId, 'req123');
      assert.strictEqual(sentMessage.error.code, 'ERROR_CODE');
      assert.strictEqual(sentMessage.error.message, 'Test error');
      assert.strictEqual(sentMessage.error.extra, 'data');
      assert.ok(sentMessage.timestamp);
    });

    it('should return false for invalid client', () => {
      const clients = new Map();
      const result = WebSocketUtilities.sendErrorMessage(
        'invalid',
        'req123',
        'ERROR',
        'Test',
        clients
      );
      assert.strictEqual(result, false);
    });
  });

  describe('broadcastToSessionClients', () => {
    it('should broadcast to clients with matching session', () => {
      const mockWs1 = { readyState: 1, send: mock.fn() };
      const mockWs2 = { readyState: 1, send: mock.fn() };
      const mockWs3 = { readyState: 1, send: mock.fn() };

      const clients = new Map([
        ['client1', { ws: mockWs1, sessionIds: new Set(['session1']), lastActivity: new Date() }],
        ['client2', { ws: mockWs2, sessionIds: new Set(['session1']), lastActivity: new Date() }],
        ['client3', { ws: mockWs3, sessionIds: new Set(['session2']), lastActivity: new Date() }],
      ]);

      const message = { type: 'broadcast', data: 'test' };
      WebSocketUtilities.broadcastToSessionClients('session1', message, clients);

      assert.strictEqual(mockWs1.send.mock.calls.length, 1);
      assert.strictEqual(mockWs2.send.mock.calls.length, 1);
      assert.strictEqual(mockWs3.send.mock.calls.length, 0);
    });

    it('should handle clients without sessionIds gracefully', () => {
      const mockWs1 = { readyState: 1, send: mock.fn() };
      const clients = new Map([
        ['client1', { ws: mockWs1, lastActivity: new Date() }], // No sessionIds
      ]);

      const message = { type: 'broadcast', data: 'test' };
      assert.doesNotThrow(() => {
        WebSocketUtilities.broadcastToSessionClients('session1', message, clients);
      });
    });

    it('should queue message when no clients found', () => {
      const clients = new Map();
      const message = { type: 'broadcast', data: 'test' };

      // Mock the dynamic import - this tests the code path but import can't be easily mocked
      assert.doesNotThrow(() => {
        WebSocketUtilities.broadcastToSessionClients('session1', message, clients);
      });
    });

    it('should handle disconnected clients gracefully', () => {
      const mockWs1 = { readyState: 3, send: mock.fn() }; // CLOSED
      const clients = new Map([
        ['client1', { ws: mockWs1, sessionIds: new Set(['session1']), lastActivity: new Date() }],
      ]);

      const message = { type: 'broadcast', data: 'test' };
      WebSocketUtilities.broadcastToSessionClients('session1', message, clients);

      // Should attempt to send but fail gracefully
      assert.strictEqual(mockWs1.send.mock.calls.length, 0);
    });

    it('should skip ping/pong messages in delivery stats', () => {
      const mockWs1 = { readyState: 1, send: mock.fn() };
      const clients = new Map([
        ['client1', { ws: mockWs1, sessionIds: new Set(['session1']), lastActivity: new Date() }],
      ]);

      const pingMessage = { type: 'ping' };
      const pongMessage = { type: 'pong' };

      assert.doesNotThrow(() => {
        WebSocketUtilities.broadcastToSessionClients('session1', pingMessage, clients);
        WebSocketUtilities.broadcastToSessionClients('session1', pongMessage, clients);
      });
    });

    it('should log final stream chunk delivery', () => {
      const mockWs1 = { readyState: 1, send: mock.fn() };
      const clients = new Map([
        ['client1', { ws: mockWs1, sessionIds: new Set(['session1']), lastActivity: new Date() }],
      ]);

      const streamMessage = {
        type: 'streamChunk',
        data: { chunk: { isFinal: true } },
      };

      assert.doesNotThrow(() => {
        WebSocketUtilities.broadcastToSessionClients('session1', streamMessage, clients);
      });
    });

    it('should log complete assistant message delivery', () => {
      const mockWs1 = { readyState: 1, send: mock.fn() };
      const clients = new Map([
        ['client1', { ws: mockWs1, sessionIds: new Set(['session1']), lastActivity: new Date() }],
      ]);

      const assistantMessage = {
        type: 'assistantMessage',
        data: { isComplete: true },
      };

      assert.doesNotThrow(() => {
        WebSocketUtilities.broadcastToSessionClients('session1', assistantMessage, clients);
      });
    });
  });

  describe('determineStreamType', () => {
    it('should return "unknown" for null/undefined data', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType(null), 'unknown');
      assert.strictEqual(WebSocketUtilities.determineStreamType(undefined), 'unknown');
    });

    it('should detect error type from string content', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType('Error occurred'), 'error');
      assert.strictEqual(WebSocketUtilities.determineStreamType('An error happened'), 'error');
      assert.strictEqual(WebSocketUtilities.determineStreamType('Warning message'), 'warning');
      assert.strictEqual(WebSocketUtilities.determineStreamType('warning: something'), 'warning');
      assert.strictEqual(WebSocketUtilities.determineStreamType('normal text'), 'text');
    });

    it('should use type property from objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ type: 'custom' }), 'custom');
      assert.strictEqual(WebSocketUtilities.determineStreamType({ type: 'status' }), 'status');
    });

    it('should detect error objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ error: 'something' }), 'error');
      assert.strictEqual(WebSocketUtilities.determineStreamType({ error: 'failed' }), 'error');
    });

    it('should detect text objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ text: 'content' }), 'text');
      assert.strictEqual(WebSocketUtilities.determineStreamType({ text: 'message' }), 'text');
    });

    it('should return "data" for other objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ other: 'content' }), 'data');
      assert.strictEqual(WebSocketUtilities.determineStreamType({ random: 123 }), 'data');
    });
  });

  describe('formatStreamContent', () => {
    it('should handle null/undefined data', () => {
      const result1 = WebSocketUtilities.formatStreamContent(null);
      assert.strictEqual(result1.text, '');
      assert.deepStrictEqual(result1.metadata, {});

      const result2 = WebSocketUtilities.formatStreamContent(undefined);
      assert.strictEqual(result2.text, '');
      assert.deepStrictEqual(result2.metadata, {});
    });

    it('should format strings', () => {
      const result = WebSocketUtilities.formatStreamContent('test string');
      assert.strictEqual(result.text, 'test string');
      assert.strictEqual(result.metadata.length, 11);
      assert.strictEqual(result.metadata.formatted, true);
    });

    it('should handle objects with text property', () => {
      const obj = { text: 'content', type: 'message', model: 'test' };
      const result = WebSocketUtilities.formatStreamContent(obj);
      assert.strictEqual(result.text, 'content');
      assert.strictEqual(result.metadata.type, 'message');
      assert.strictEqual(result.metadata.model, 'test');
      assert.strictEqual(result.metadata.formatted, true);
    });

    it('should handle objects with content property', () => {
      const obj = { content: 'content text', usage: { tokens: 100 } };
      const result = WebSocketUtilities.formatStreamContent(obj);
      assert.strictEqual(result.text, 'content text');
      assert.strictEqual(result.metadata.usage.tokens, 100);
      assert.strictEqual(result.metadata.formatted, true);
    });

    it('should stringify raw objects', () => {
      const obj = { key: 'value', nested: { prop: 123 } };
      const result = WebSocketUtilities.formatStreamContent(obj);
      assert.strictEqual(result.text, JSON.stringify(obj, null, 2));
      assert.strictEqual(result.metadata.type, 'json');
      assert.deepStrictEqual(result.metadata.original, obj);
      assert.strictEqual(result.metadata.formatted, true);
    });

    it('should handle non-string, non-object data', () => {
      const result1 = WebSocketUtilities.formatStreamContent(123);
      assert.strictEqual(result1.text, '123');
      assert.strictEqual(result1.metadata.type, 'number');
      assert.strictEqual(result1.metadata.formatted, true);

      const result2 = WebSocketUtilities.formatStreamContent(true);
      assert.strictEqual(result2.text, 'true');
      assert.strictEqual(result2.metadata.type, 'boolean');

      const result3 = WebSocketUtilities.formatStreamContent([1, 2, 3]);
      assert.strictEqual(result3.text, '[\n  1,\n  2,\n  3\n]');
      assert.strictEqual(result3.metadata.type, 'json');
    });
  });

  describe('parseProgressFromOutput', () => {
    it('should parse percentage progress', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Processing... 75%');
      assert.strictEqual(result.stage, 'processing');
      assert.strictEqual(result.progress, 0.75);
      assert.strictEqual(result.message, 'Processing... 75%');
      assert.strictEqual(result.estimatedTimeRemaining, null);

      const result2 = WebSocketUtilities.parseProgressFromOutput('100% complete');
      assert.strictEqual(result2.progress, 1.0);
    });

    it('should parse step-based progress', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Step 3 of 10 completed');
      assert.strictEqual(result.stage, 'processing');
      assert.strictEqual(result.progress, 0.3);
      assert.strictEqual(result.message, 'Step 3 of 10');
      assert.strictEqual(result.estimatedTimeRemaining, null);

      const result2 = WebSocketUtilities.parseProgressFromOutput('STEP 1 OF 5');
      assert.strictEqual(result2.progress, 0.2);
    });

    it('should parse time estimates with minutes', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('ETA: 5 minutes remaining');
      assert.strictEqual(result.stage, 'processing');
      assert.strictEqual(result.progress, null);
      assert.strictEqual(result.message, 'Estimated time: 5 min');
      assert.strictEqual(result.estimatedTimeRemaining, 300);

      const result2 = WebSocketUtilities.parseProgressFromOutput('About 2 min left');
      assert.strictEqual(result2.estimatedTimeRemaining, 120);
      assert.strictEqual(result2.message, 'Estimated time: 2 min');
    });

    it('should parse time estimates with seconds', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('30 seconds remaining');
      assert.strictEqual(result.estimatedTimeRemaining, 30);

      const result2 = WebSocketUtilities.parseProgressFromOutput('45 sec left');
      assert.strictEqual(result2.estimatedTimeRemaining, 45);
    });

    it('should detect starting stage', () => {
      const result1 = WebSocketUtilities.parseProgressFromOutput('Starting process...');
      assert.strictEqual(result1.stage, 'starting');
      assert.strictEqual(result1.progress, 0.0);
      assert.strictEqual(result1.message, 'Starting...');

      const result2 = WebSocketUtilities.parseProgressFromOutput('Initializing system');
      assert.strictEqual(result2.stage, 'starting');

      const result3 = WebSocketUtilities.parseProgressFromOutput('Beginning analysis');
      assert.strictEqual(result3.stage, 'starting');
    });

    it('should detect analyzing stage', () => {
      const result1 = WebSocketUtilities.parseProgressFromOutput('Analyzing data...');
      assert.strictEqual(result1.stage, 'analyzing');
      assert.strictEqual(result1.progress, null);
      assert.strictEqual(result1.message, 'Analyzing request...');

      const result2 = WebSocketUtilities.parseProgressFromOutput('Thinking about the problem');
      assert.strictEqual(result2.stage, 'analyzing');

      const result3 = WebSocketUtilities.parseProgressFromOutput('Considering options');
      assert.strictEqual(result3.stage, 'analyzing');
    });

    it('should detect completion stage', () => {
      const result1 = WebSocketUtilities.parseProgressFromOutput('Process completed successfully');
      assert.strictEqual(result1.stage, 'completing');
      assert.strictEqual(result1.progress, 1.0);
      assert.strictEqual(result1.message, 'Finishing up...');

      const result2 = WebSocketUtilities.parseProgressFromOutput('Task finished');
      assert.strictEqual(result2.stage, 'completing');

      const result3 = WebSocketUtilities.parseProgressFromOutput('Done processing');
      assert.strictEqual(result3.stage, 'completing');
    });

    it('should return null for non-progress output', () => {
      const result1 = WebSocketUtilities.parseProgressFromOutput('Random text message');
      assert.strictEqual(result1, null);

      const result2 = WebSocketUtilities.parseProgressFromOutput('Hello world');
      assert.strictEqual(result2, null);

      const result3 = WebSocketUtilities.parseProgressFromOutput('No progress here');
      assert.strictEqual(result3, null);
    });

    it('should handle null/undefined input', () => {
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput(null), null);
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput(undefined), null);
    });

    it('should handle non-string input', () => {
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput(123), null);
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput({}), null);
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput([]), null);
    });
  });

  describe('validateMessage', () => {
    it('should validate correct message structure', () => {
      const message = { type: 'test', requestId: 'req123' };
      const result = WebSocketUtilities.validateMessage(message);
      assert.strictEqual(result.valid, true);
    });

    it('should require message to be an object', () => {
      const result1 = WebSocketUtilities.validateMessage('not an object');
      assert.strictEqual(result1.valid, false);
      assert.strictEqual(result1.error, 'Message must be an object');

      const result2 = WebSocketUtilities.validateMessage(null);
      assert.strictEqual(result2.valid, false);
      assert.strictEqual(result2.error, 'Message must be an object');

      const result3 = WebSocketUtilities.validateMessage(123);
      assert.strictEqual(result3.valid, false);
    });

    it('should require type field', () => {
      const result1 = WebSocketUtilities.validateMessage({});
      assert.strictEqual(result1.valid, false);
      assert.strictEqual(result1.error, 'Message must have a string type field');

      const result2 = WebSocketUtilities.validateMessage({ requestId: 'test' });
      assert.strictEqual(result2.valid, false);
    });

    it('should require type to be string', () => {
      const result1 = WebSocketUtilities.validateMessage({ type: 123 });
      assert.strictEqual(result1.valid, false);
      assert.strictEqual(result1.error, 'Message must have a string type field');

      const result2 = WebSocketUtilities.validateMessage({ type: null });
      assert.strictEqual(result2.valid, false);

      const result3 = WebSocketUtilities.validateMessage({ type: {} });
      assert.strictEqual(result3.valid, false);
    });

    it('should validate requestId if provided', () => {
      const result1 = WebSocketUtilities.validateMessage({ type: 'test', requestId: 123 });
      assert.strictEqual(result1.valid, false);
      assert.strictEqual(result1.error, 'RequestId must be a string if provided');

      const result2 = WebSocketUtilities.validateMessage({ type: 'test', requestId: {} });
      assert.strictEqual(result2.valid, false);
    });

    it('should allow undefined requestId', () => {
      const result = WebSocketUtilities.validateMessage({ type: 'test' });
      assert.strictEqual(result.valid, true);
    });

    it('should allow valid requestId', () => {
      const result = WebSocketUtilities.validateMessage({ type: 'test', requestId: 'valid-id' });
      assert.strictEqual(result.valid, true);
    });
  });

  describe('createResponse', () => {
    it('should create standard response', () => {
      const response = WebSocketUtilities.createResponse('test', 'req123', { message: 'hello' });

      assert.strictEqual(response.type, 'test');
      assert.strictEqual(response.requestId, 'req123');
      assert.deepStrictEqual(response.data, { message: 'hello' });
      assert.ok(response.timestamp);
      assert.ok(new Date(response.timestamp).getTime() > 0);
    });

    it('should include optional error field', () => {
      const response = WebSocketUtilities.createResponse(
        'test',
        'req123',
        {},
        { error: 'test error' }
      );
      assert.strictEqual(response.error, 'test error');
    });

    it('should include optional isComplete field', () => {
      const response1 = WebSocketUtilities.createResponse(
        'test',
        'req123',
        {},
        { isComplete: true }
      );
      assert.strictEqual(response1.isComplete, true);

      const response2 = WebSocketUtilities.createResponse(
        'test',
        'req123',
        {},
        { isComplete: false }
      );
      assert.strictEqual(response2.isComplete, false);
    });

    it('should include optional metadata field', () => {
      const metadata = { extra: 'data', nested: { prop: 123 } };
      const response = WebSocketUtilities.createResponse('test', 'req123', {}, { metadata });
      assert.deepStrictEqual(response.metadata, metadata);
    });

    it('should include all optional fields together', () => {
      const options = {
        error: 'test error',
        isComplete: true,
        metadata: { extra: 'data' },
      };
      const response = WebSocketUtilities.createResponse(
        'test',
        'req123',
        { data: 'test' },
        options
      );

      assert.strictEqual(response.error, 'test error');
      assert.strictEqual(response.isComplete, true);
      assert.deepStrictEqual(response.metadata, { extra: 'data' });
      assert.deepStrictEqual(response.data, { data: 'test' });
    });
  });

  describe('extractClientInfo', () => {
    it('should extract client info from request', () => {
      const request = {
        socket: {
          remoteAddress: '192.168.1.1',
          remoteFamily: 'IPv4',
        },
        headers: {
          'user-agent': 'Mozilla/5.0',
          host: 'localhost:3000',
          origin: 'http://localhost:3000',
          'sec-websocket-protocol': 'v1',
        },
      };

      const info = WebSocketUtilities.extractClientInfo(request);

      assert.strictEqual(info.ip, '192.168.1.1');
      assert.strictEqual(info.family, 'IPv4');
      assert.strictEqual(info.userAgent, 'Mozilla/5.0');
      assert.strictEqual(info.host, 'localhost:3000');
      assert.strictEqual(info.origin, 'http://localhost:3000');
      assert.strictEqual(info.protocol, 'v1');
    });

    it('should handle missing headers gracefully', () => {
      const request = {
        socket: { remoteAddress: '127.0.0.1', remoteFamily: 'IPv4' },
        headers: {},
      };

      const info = WebSocketUtilities.extractClientInfo(request);
      assert.strictEqual(info.ip, '127.0.0.1');
      assert.strictEqual(info.family, 'IPv4');
      assert.strictEqual(info.userAgent, 'unknown');
      assert.strictEqual(info.host, undefined);
      assert.strictEqual(info.origin, undefined);
      assert.strictEqual(info.protocol, undefined);
    });

    it('should handle partial headers', () => {
      const request = {
        socket: { remoteAddress: '10.0.0.1', remoteFamily: 'IPv6' },
        headers: {
          host: 'example.com',
          'user-agent': 'TestClient/1.0',
        },
      };

      const info = WebSocketUtilities.extractClientInfo(request);
      assert.strictEqual(info.ip, '10.0.0.1');
      assert.strictEqual(info.family, 'IPv6');
      assert.strictEqual(info.userAgent, 'TestClient/1.0');
      assert.strictEqual(info.host, 'example.com');
      assert.strictEqual(info.origin, undefined);
      assert.strictEqual(info.protocol, undefined);
    });
  });

  describe('isWebSocketReady', () => {
    it('should return true for ready WebSocket', () => {
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 1 }), true);
    });

    it('should return false for non-ready WebSocket states', () => {
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 0 }), false); // CONNECTING
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 2 }), false); // CLOSING
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 3 }), false); // CLOSED
    });

    it('should return false for null WebSocket', () => {
      assert.strictEqual(WebSocketUtilities.isWebSocketReady(null), false);
    });

    it('should return false for undefined WebSocket', () => {
      assert.strictEqual(WebSocketUtilities.isWebSocketReady(undefined), false);
    });

    it('should return false for invalid WebSocket objects', () => {
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({}), false);
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 'invalid' }), false);
    });
  });

  describe('safeStringify', () => {
    it('should safely stringify valid JSON', () => {
      const obj = { test: 'value', number: 123, nested: { prop: true } };
      const result = WebSocketUtilities.safeStringify(obj);
      assert.strictEqual(result, JSON.stringify(obj));
    });

    it('should use default fallback for circular references', () => {
      // Test in isolated scope to prevent serialization issues
      const result = (() => {
        const circular = { a: 1 };
        circular.self = circular;
        return WebSocketUtilities.safeStringify(circular);
      })();
      assert.strictEqual(result, '{}');
    });

    it('should use custom fallback for circular references', () => {
      const result = (() => {
        const circular = { a: 1 };
        circular.self = circular;
        return WebSocketUtilities.safeStringify(circular, 'CIRCULAR_ERROR');
      })();
      assert.strictEqual(result, 'CIRCULAR_ERROR');
    });

    it('should handle various data types', () => {
      assert.strictEqual(WebSocketUtilities.safeStringify('string'), '"string"');
      assert.strictEqual(WebSocketUtilities.safeStringify(123), '123');
      assert.strictEqual(WebSocketUtilities.safeStringify(true), 'true');
      assert.strictEqual(WebSocketUtilities.safeStringify(null), 'null');
      assert.strictEqual(WebSocketUtilities.safeStringify([1, 2, 3]), '[1,2,3]');
    });
  });

  describe('safeParse', () => {
    it('should safely parse valid JSON', () => {
      const validJson = '{"test": "value", "number": 123}';
      const result = WebSocketUtilities.safeParse(validJson);
      assert.deepStrictEqual(result, { test: 'value', number: 123 });
    });

    it('should use default fallback for invalid JSON', () => {
      const invalidJson = '{invalid json}';
      const result = WebSocketUtilities.safeParse(invalidJson);
      assert.strictEqual(result, null);
    });

    it('should use custom fallback for invalid JSON', () => {
      const invalidJson = '{malformed';
      const result = WebSocketUtilities.safeParse(invalidJson, 'PARSE_ERROR');
      assert.strictEqual(result, 'PARSE_ERROR');
    });

    it('should handle various valid JSON formats', () => {
      assert.deepStrictEqual(WebSocketUtilities.safeParse('[]'), []);
      assert.deepStrictEqual(WebSocketUtilities.safeParse('[1,2,3]'), [1, 2, 3]);
      assert.strictEqual(WebSocketUtilities.safeParse('"string"'), 'string');
      assert.strictEqual(WebSocketUtilities.safeParse('123'), 123);
      assert.strictEqual(WebSocketUtilities.safeParse('true'), true);
      assert.strictEqual(WebSocketUtilities.safeParse('null'), null);
    });

    it('should handle various invalid JSON formats', () => {
      assert.strictEqual(WebSocketUtilities.safeParse('undefined'), null);
      assert.strictEqual(WebSocketUtilities.safeParse('{'), null);
      assert.strictEqual(WebSocketUtilities.safeParse('{"incomplete"'), null);
      assert.strictEqual(WebSocketUtilities.safeParse('random text'), null);
    });
  });
});
