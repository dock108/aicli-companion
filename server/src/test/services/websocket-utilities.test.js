import { describe, it, mock } from 'node:test';
import assert from 'node:assert';
import { WebSocketUtilities } from '../../services/websocket-utilities.js';

describe('WebSocketUtilities', () => {
  describe('sendMessage', () => {
    it('should send message to connected client', () => {
      const mockWs = {
        readyState: 1, // WebSocket.OPEN
        send: mock.fn(),
      };
      const clients = new Map([
        ['client1', { ws: mockWs, lastActivity: new Date() }]
      ]);
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
      const clients = new Map([
        ['client1', { ws: mockWs, lastActivity: new Date() }]
      ]);
      const message = { type: 'test' };

      const result = WebSocketUtilities.sendMessage('client1', message, clients);
      assert.strictEqual(result, false);
      assert.strictEqual(mockWs.send.mock.calls.length, 0);
    });

    it('should handle send errors gracefully', () => {
      const mockWs = {
        readyState: 1,
        send: mock.fn(() => { throw new Error('Send failed'); }),
      };
      const clients = new Map([
        ['client1', { ws: mockWs, lastActivity: new Date() }]
      ]);
      const message = { type: 'test' };

      const result = WebSocketUtilities.sendMessage('client1', message, clients);
      assert.strictEqual(result, false);
    });

    it('should update client last activity', () => {
      const mockWs = {
        readyState: 1,
        send: mock.fn(),
      };
      const client = { ws: mockWs, lastActivity: new Date(0) };
      const clients = new Map([['client1', client]]);
      const message = { type: 'test' };

      WebSocketUtilities.sendMessage('client1', message, clients);

      assert.ok(client.lastActivity > new Date(0));
    });
  });

  describe('sendErrorMessage', () => {
    it('should send properly formatted error message', () => {
      const mockWs = {
        readyState: 1,
        send: mock.fn(),
      };
      const clients = new Map([
        ['client1', { ws: mockWs, lastActivity: new Date() }]
      ]);

      const result = WebSocketUtilities.sendErrorMessage(
        'client1',
        'req123',
        'TEST_ERROR',
        'Something went wrong',
        clients,
        { extra: 'data' }
      );

      assert.strictEqual(result, true);
      assert.strictEqual(mockWs.send.mock.calls.length, 1);

      const sentMessage = JSON.parse(mockWs.send.mock.calls[0].arguments[0]);
      assert.strictEqual(sentMessage.type, 'error');
      assert.strictEqual(sentMessage.requestId, 'req123');
      assert.strictEqual(sentMessage.error.code, 'TEST_ERROR');
      assert.strictEqual(sentMessage.error.message, 'Something went wrong');
      assert.strictEqual(sentMessage.error.extra, 'data');
      assert.ok(sentMessage.timestamp);
    });
  });

  describe('broadcastToSessionClients', () => {
    it('should broadcast to all clients with the session', () => {
      const mockWs1 = { readyState: 1, send: mock.fn() };
      const mockWs2 = { readyState: 1, send: mock.fn() };
      const mockWs3 = { readyState: 1, send: mock.fn() };

      const clients = new Map([
        ['client1', { ws: mockWs1, sessionIds: new Set(['session1']), lastActivity: new Date() }],
        ['client2', { ws: mockWs2, sessionIds: new Set(['session1', 'session2']), lastActivity: new Date() }],
        ['client3', { ws: mockWs3, sessionIds: new Set(['session2']), lastActivity: new Date() }],
      ]);

      const message = { type: 'broadcast', data: 'hello' };

      WebSocketUtilities.broadcastToSessionClients('session1', message, clients);

      // Should send to client1 and client2 (both have session1)
      assert.strictEqual(mockWs1.send.mock.calls.length, 1);
      assert.strictEqual(mockWs2.send.mock.calls.length, 1);
      assert.strictEqual(mockWs3.send.mock.calls.length, 0);
    });

    it('should handle no connected clients for session', () => {
      const clients = new Map();
      const message = { type: 'broadcast', data: 'hello' };

      // Should not throw error
      assert.doesNotThrow(() => {
        WebSocketUtilities.broadcastToSessionClients('session1', message, clients);
      });
    });

    it('should skip clients without sessionIds', () => {
      const mockWs = { readyState: 1, send: mock.fn() };
      const clients = new Map([
        ['client1', { ws: mockWs, lastActivity: new Date() }] // No sessionIds
      ]);

      const message = { type: 'broadcast' };

      WebSocketUtilities.broadcastToSessionClients('session1', message, clients);
      assert.strictEqual(mockWs.send.mock.calls.length, 0);
    });
  });

  describe('determineStreamType', () => {
    it('should return "unknown" for null/undefined data', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType(null), 'unknown');
      assert.strictEqual(WebSocketUtilities.determineStreamType(undefined), 'unknown');
    });

    it('should detect error type from string content', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType('Error: something failed'), 'error');
      assert.strictEqual(WebSocketUtilities.determineStreamType('Warning: be careful'), 'warning');
      assert.strictEqual(WebSocketUtilities.determineStreamType('Regular text'), 'text');
    });

    it('should use type property from objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ type: 'result' }), 'result');
      assert.strictEqual(WebSocketUtilities.determineStreamType({ type: 'status' }), 'status');
    });

    it('should detect error objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ error: 'failed' }), 'error');
    });

    it('should detect text objects', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ text: 'hello' }), 'text');
    });

    it('should return "data" for other object types', () => {
      assert.strictEqual(WebSocketUtilities.determineStreamType({ something: 'else' }), 'data');
    });
  });

  describe('formatStreamContent', () => {
    it('should format string data', () => {
      const result = WebSocketUtilities.formatStreamContent('hello world');
      
      assert.strictEqual(result.text, 'hello world');
      assert.strictEqual(result.metadata.length, 11);
      assert.strictEqual(result.metadata.formatted, true);
    });

    it('should format object with text property', () => {
      const data = {
        text: 'hello',
        type: 'message',
        model: 'claude-3',
        usage: { tokens: 10 }
      };
      
      const result = WebSocketUtilities.formatStreamContent(data);
      
      assert.strictEqual(result.text, 'hello');
      assert.strictEqual(result.metadata.type, 'message');
      assert.strictEqual(result.metadata.model, 'claude-3');
      assert.deepStrictEqual(result.metadata.usage, { tokens: 10 });
      assert.strictEqual(result.metadata.formatted, true);
    });

    it('should format object with content property', () => {
      const data = { content: 'world', metadata: { extra: 'info' } };
      
      const result = WebSocketUtilities.formatStreamContent(data);
      
      assert.strictEqual(result.text, 'world');
      assert.strictEqual(result.metadata.extra, 'info');
    });

    it('should stringify raw objects', () => {
      const data = { complex: { nested: 'object' } };
      
      const result = WebSocketUtilities.formatStreamContent(data);
      
      assert.ok(result.text.includes('complex'));
      assert.ok(result.text.includes('nested'));
      assert.strictEqual(result.metadata.type, 'json');
      assert.deepStrictEqual(result.metadata.original, data);
    });

    it('should handle null/undefined data', () => {
      const result1 = WebSocketUtilities.formatStreamContent(null);
      const result2 = WebSocketUtilities.formatStreamContent(undefined);
      
      assert.strictEqual(result1.text, '');
      assert.strictEqual(result2.text, '');
      assert.deepStrictEqual(result1.metadata, {});
      assert.deepStrictEqual(result2.metadata, {});
    });

    it('should handle non-string, non-object data', () => {
      const result = WebSocketUtilities.formatStreamContent(42);
      
      assert.strictEqual(result.text, '42');
      assert.strictEqual(result.metadata.type, 'number');
      assert.strictEqual(result.metadata.formatted, true);
    });
  });

  describe('parseProgressFromOutput', () => {
    it('should parse percentage progress', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Processing... 75%');
      
      assert.strictEqual(result.stage, 'processing');
      assert.strictEqual(result.progress, 0.75);
      assert.ok(result.message.includes('75%'));
    });

    it('should parse step-based progress', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Step 3 of 10 completed');
      
      assert.strictEqual(result.stage, 'processing');
      assert.strictEqual(result.progress, 0.3);
      assert.strictEqual(result.message, 'Step 3 of 10');
    });

    it('should parse time estimates', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Estimated time: 5 minutes remaining');
      
      assert.strictEqual(result.stage, 'processing');
      assert.strictEqual(result.estimatedTimeRemaining, 300); // 5 minutes in seconds
      assert.ok(result.message.includes('5 minutes'));
    });

    it('should detect starting stage', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Starting initialization...');
      
      assert.strictEqual(result.stage, 'starting');
      assert.strictEqual(result.progress, 0.0);
      assert.strictEqual(result.message, 'Starting...');
    });

    it('should detect analyzing stage', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Analyzing your request...');
      
      assert.strictEqual(result.stage, 'analyzing');
      assert.strictEqual(result.progress, null);
      assert.strictEqual(result.message, 'Analyzing request...');
    });

    it('should detect completion stage', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Task completed successfully');
      
      assert.strictEqual(result.stage, 'completing');
      assert.strictEqual(result.progress, 1.0);
      assert.strictEqual(result.message, 'Finishing up...');
    });

    it('should return null for non-progress output', () => {
      const result = WebSocketUtilities.parseProgressFromOutput('Regular log message');
      assert.strictEqual(result, null);
    });

    it('should handle null/undefined input', () => {
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput(null), null);
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput(undefined), null);
    });

    it('should handle non-string input', () => {
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput(42), null);
      assert.strictEqual(WebSocketUtilities.parseProgressFromOutput({}), null);
    });
  });

  describe('validateMessage', () => {
    it('should validate correct message structure', () => {
      const message = { type: 'test', requestId: 'req123', data: {} };
      const result = WebSocketUtilities.validateMessage(message);
      
      assert.strictEqual(result.valid, true);
    });

    it('should require message to be an object', () => {
      const result = WebSocketUtilities.validateMessage('not an object');
      
      assert.strictEqual(result.valid, false);
      assert.ok(result.error.includes('object'));
    });

    it('should require type field', () => {
      const message = { requestId: 'req123', data: {} };
      const result = WebSocketUtilities.validateMessage(message);
      
      assert.strictEqual(result.valid, false);
      assert.ok(result.error.includes('type'));
    });

    it('should require type to be string', () => {
      const message = { type: 123, requestId: 'req123' };
      const result = WebSocketUtilities.validateMessage(message);
      
      assert.strictEqual(result.valid, false);
      assert.ok(result.error.includes('string type'));
    });

    it('should validate requestId if provided', () => {
      const message = { type: 'test', requestId: 123 };
      const result = WebSocketUtilities.validateMessage(message);
      
      assert.strictEqual(result.valid, false);
      assert.ok(result.error.includes('RequestId'));
    });

    it('should allow undefined requestId', () => {
      const message = { type: 'test' };
      const result = WebSocketUtilities.validateMessage(message);
      
      assert.strictEqual(result.valid, true);
    });
  });

  describe('createResponse', () => {
    it('should create standard response', () => {
      const response = WebSocketUtilities.createResponse('test', 'req123', { hello: 'world' });
      
      assert.strictEqual(response.type, 'test');
      assert.strictEqual(response.requestId, 'req123');
      assert.deepStrictEqual(response.data, { hello: 'world' });
      assert.ok(response.timestamp);
    });

    it('should include optional fields', () => {
      const response = WebSocketUtilities.createResponse('test', 'req123', {}, {
        error: 'Something failed',
        isComplete: true,
        metadata: { extra: 'info' }
      });
      
      assert.strictEqual(response.error, 'Something failed');
      assert.strictEqual(response.isComplete, true);
      assert.deepStrictEqual(response.metadata, { extra: 'info' });
    });
  });

  describe('utility functions', () => {
    it('should extract client info from request', () => {
      const request = {
        socket: {
          remoteAddress: '127.0.0.1',
          remoteFamily: 'IPv4'
        },
        headers: {
          'user-agent': 'test-client',
          'host': 'localhost:3000',
          'origin': 'http://localhost',
          'sec-websocket-protocol': 'v1'
        }
      };
      
      const info = WebSocketUtilities.extractClientInfo(request);
      
      assert.strictEqual(info.ip, '127.0.0.1');
      assert.strictEqual(info.family, 'IPv4');
      assert.strictEqual(info.userAgent, 'test-client');
      assert.strictEqual(info.host, 'localhost:3000');
      assert.strictEqual(info.origin, 'http://localhost');
      assert.strictEqual(info.protocol, 'v1');
    });

    it('should check WebSocket ready state', () => {
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 1 }), true);
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 0 }), false);
      assert.strictEqual(WebSocketUtilities.isWebSocketReady({ readyState: 3 }), false);
      assert.strictEqual(WebSocketUtilities.isWebSocketReady(null), false);
    });

    it('should safely stringify JSON', () => {
      const obj = { test: 'value' };
      assert.strictEqual(WebSocketUtilities.safeStringify(obj), JSON.stringify(obj));
      
      // Test circular reference
      const circular = { a: 1 };
      circular.self = circular;
      assert.strictEqual(WebSocketUtilities.safeStringify(circular), '{}');
      assert.strictEqual(WebSocketUtilities.safeStringify(circular, 'fallback'), 'fallback');
    });

    it('should safely parse JSON', () => {
      const validJson = '{"test": "value"}';
      const result = WebSocketUtilities.safeParse(validJson);
      assert.deepStrictEqual(result, { test: 'value' });
      
      const invalidJson = '{invalid json}';
      assert.strictEqual(WebSocketUtilities.safeParse(invalidJson), null);
      assert.strictEqual(WebSocketUtilities.safeParse(invalidJson, 'fallback'), 'fallback');
    });
  });
});