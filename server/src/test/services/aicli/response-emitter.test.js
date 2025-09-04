import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { ResponseEmitter } from '../../../services/aicli/response-emitter.js';

describe('ResponseEmitter', () => {
  let responseEmitter;
  let mockSessionManager;
  let mockEventEmitter;
  let mockBuffer;

  beforeEach(() => {
    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});

    // Create mock buffer
    mockBuffer = {
      messages: [],
      userMessages: [],
      assistantMessages: [],
      isActive: true,
      lastActivity: Date.now(),
    };

    // Create mock session manager
    mockSessionManager = {
      getSessionBuffer: mock.fn((sessionId) => {
        if (sessionId === 'existing-session') {
          return mockBuffer;
        }
        return null;
      }),
      setSessionBuffer: mock.fn(),
      getSession: mock.fn(async (sessionId) => {
        if (sessionId === 'tracked-session') {
          return { sessionId: 'tracked-session', workingDirectory: '/test' };
        }
        return null;
      }),
      trackSessionForRouting: mock.fn(),
    };

    // Create mock event emitter
    mockEventEmitter = {
      emit: mock.fn(),
    };

    // Create response emitter instance
    responseEmitter = new ResponseEmitter(mockSessionManager, mockEventEmitter);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('emitAICLIResponse', () => {
    it('should skip processing for null sessionId', async () => {
      await responseEmitter.emitAICLIResponse(null, 'test response');

      // Should skip processing for null sessionId
      assert.strictEqual(mockSessionManager.getSessionBuffer.mock.callCount(), 0);
    });

    it('should use existing buffer for known session', async () => {
      const response = { type: 'text', content: 'Test message' };

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockSessionManager.getSessionBuffer.mock.callCount(), 1);
      assert.strictEqual(mockSessionManager.setSessionBuffer.mock.callCount(), 0);
    });

    it('should create buffer on-demand for unknown session without tracked session', async () => {
      const response = { type: 'text', content: 'Test message' };

      await responseEmitter.emitAICLIResponse('new-session', response);

      // Should get session buffer (returns null)
      assert.strictEqual(mockSessionManager.getSessionBuffer.mock.callCount(), 1);

      // Should check for active session
      assert.strictEqual(mockSessionManager.getSession.mock.callCount(), 1);

      // Should track session for routing since no active session exists
      assert.strictEqual(mockSessionManager.trackSessionForRouting.mock.callCount(), 1);
      assert.deepStrictEqual(mockSessionManager.trackSessionForRouting.mock.calls[0].arguments, [
        'new-session',
        process.cwd(),
      ]);

      // Should create and set new buffer
      assert.strictEqual(mockSessionManager.setSessionBuffer.mock.callCount(), 1);

      // Should create and set new buffer
      assert.strictEqual(mockSessionManager.setSessionBuffer.mock.callCount(), 1);
    });

    it('should create buffer for tracked session', async () => {
      const response = { type: 'text', content: 'Test message' };

      await responseEmitter.emitAICLIResponse('tracked-session', response);

      // Should not track session since it already exists
      assert.strictEqual(mockSessionManager.trackSessionForRouting.mock.callCount(), 0);

      // Should create and set new buffer
      assert.strictEqual(mockSessionManager.setSessionBuffer.mock.callCount(), 1);
    });

    it('should emit permission request event', async () => {
      const response = {
        type: 'permission_request',
        content: {
          prompt: 'Allow file access?',
          options: ['yes', 'no'],
          default: 'no',
        },
      };

      // Mock the message handler to return permission request action
      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'permission_request',
        data: {
          prompt: response.content.prompt,
          options: response.content.options,
          default: response.content.default,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'permissionRequired');
      assert.deepStrictEqual(mockEventEmitter.emit.mock.calls[0].arguments[1], {
        sessionId: 'existing-session',
        prompt: 'Allow file access?',
        options: ['yes', 'no'],
        default: 'no',
      });

      // Permission request should be sent immediately
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'permissionRequired');
    });

    it('should emit text message event', async () => {
      const response = { type: 'text', content: 'Hello from AICLI' };

      // Mock message handler
      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_message',
        data: {
          message: response.content,
          isComplete: false,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'aicliResponse');
      assert.deepStrictEqual(mockEventEmitter.emit.mock.calls[0].arguments[1], {
        sessionId: 'existing-session',
        message: 'Hello from AICLI',
        isComplete: false,
        isStreaming: false,
        totalChunks: 1,
      });
    });

    it('should emit complete message event', async () => {
      const response = { type: 'complete', content: 'Done' };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_message',
        data: {
          message: 'Done',
          isComplete: true,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response, true);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      const emittedData = mockEventEmitter.emit.mock.calls[0].arguments[1];
      assert.strictEqual(emittedData.isComplete, true);
    });

    it('should emit error event', async () => {
      const response = { type: 'error', error: 'Command failed' };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_error',
        data: {
          error: 'Command failed',
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'aicliError');
      assert.deepStrictEqual(mockEventEmitter.emit.mock.calls[0].arguments[1], {
        sessionId: 'existing-session',
        error: 'Command failed',
      });
    });

    it('should emit stall detected event', async () => {
      const response = { type: 'stall', message: 'Process appears to be stalled' };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_stall',
        data: {
          message: 'Process appears to be stalled',
          duration: 30000,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'stallDetected');
      assert.deepStrictEqual(mockEventEmitter.emit.mock.calls[0].arguments[1], {
        sessionId: 'existing-session',
        message: 'Process appears to be stalled',
        duration: 30000,
      });
    });

    it('should handle thinking mode', async () => {
      const response = { type: 'thinking', content: 'Processing...' };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_thinking',
        data: {
          message: 'Processing...',
          isThinking: true,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'thinkingUpdate');
      assert(mockEventEmitter.emit.mock.calls[0].arguments[1].isThinking);
    });

    it('should handle tool use events', async () => {
      const response = {
        type: 'tool_use',
        tool: 'file_editor',
        parameters: { file: 'test.js', action: 'edit' },
      };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_tool_use',
        data: {
          tool: response.tool,
          parameters: response.parameters,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      assert.strictEqual(mockEventEmitter.emit.mock.calls[0].arguments[0], 'toolUse');
      assert.deepStrictEqual(mockEventEmitter.emit.mock.calls[0].arguments[1], {
        sessionId: 'existing-session',
        tool: 'file_editor',
        parameters: { file: 'test.js', action: 'edit' },
      });
    });

    it('should handle chunk aggregation', async () => {
      const response = {
        type: 'chunk',
        content: 'Part 1',
        chunkIndex: 0,
        totalChunks: 3,
      };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'aggregate_chunk',
        data: {
          message: 'Part 1',
          chunkIndex: 0,
          totalChunks: 3,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      // Should not emit for intermediate chunks
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 0);
    });

    it('should emit when all chunks received', async () => {
      const response = {
        type: 'chunk',
        content: 'Part 3',
        chunkIndex: 2,
        totalChunks: 3,
      };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_message',
        data: {
          message: 'Part 1 Part 2 Part 3',
          isComplete: false,
          totalChunks: 3,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 1);
      const emittedData = mockEventEmitter.emit.mock.calls[0].arguments[1];
      assert.strictEqual(emittedData.totalChunks, 3);
    });

    it('should handle buffer state', async () => {
      const response = { type: 'buffer_state', state: 'active' };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'update_buffer_state',
        data: {
          state: 'active',
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      // Buffer state updates should not emit events
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 0);
    });

    it('should pass options to message handler', async () => {
      const response = { type: 'text', content: 'Test' };
      const options = { isStreaming: true, metadata: { key: 'value' } };

      let capturedOptions;
      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', (resp, buf, opts) => {
        capturedOptions = opts;
        return {
          action: 'emit_message',
          data: { message: 'Test' },
        };
      });

      await responseEmitter.emitAICLIResponse('existing-session', response, false, options);

      assert.deepStrictEqual(capturedOptions, options);
    });

    it('should handle no action from message handler', async () => {
      const response = { type: 'unknown', content: 'Unknown type' };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: null,
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      // Should not emit any events
      assert.strictEqual(mockEventEmitter.emit.mock.callCount(), 0);
    });

    it('should handle metadata in responses', async () => {
      const response = {
        type: 'text',
        content: 'Test',
        metadata: {
          timestamp: Date.now(),
          requestId: 'req-123',
        },
      };

      mock.method(ResponseEmitter.prototype.constructor, 'processResponse', () => ({
        action: 'emit_message',
        data: {
          message: response.content,
          metadata: response.metadata,
        },
      }));

      await responseEmitter.emitAICLIResponse('existing-session', response);

      const emittedData = mockEventEmitter.emit.mock.calls[0].arguments[1];
      assert.deepStrictEqual(emittedData.metadata, response.metadata);
    });
  });
});
