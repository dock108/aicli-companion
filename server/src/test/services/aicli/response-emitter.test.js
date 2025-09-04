import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { ResponseEmitter } from '../../../services/aicli/response-emitter.js';

// Mock AICLIMessageHandler
const mockAICLIMessageHandler = {
  createSessionBuffer: mock.fn(() => ({
    assistantMessages: [],
    userMessages: [],
    systemMessages: [],
    messages: [],
    toolUseInProgress: false,
    permissionRequests: [],
    deliverables: [],
    permissionRequestSent: false,
    systemInit: null,
    pendingFinalResponse: null,
    claudeSessionId: null,
    chunks: new Map(),
    lastActivity: Date.now(),
    isActive: true,
    thinkingMetadata: {},
    pendingPermission: false,
    finalResponseData: null,
    deferredFinalResult: null,
  })),

  processResponse: mock.fn((response, _buffer, _options) => {
    // Return different results based on response type
    if (response.type === 'permission_request') {
      return {
        action: 'permission_request',
        data: {
          prompt: response.prompt,
          options: response.options,
          default: response.default,
          messageId: 'msg123',
          content: 'Permission required',
          model: 'claude-3',
          usage: { tokens: 100 },
        },
      };
    }
    if (response.type === 'tool_use') {
      return {
        action: 'tool_use',
        data: {
          messageId: 'msg456',
          content: 'Using tool',
          model: 'claude-3',
          usage: { tokens: 150 },
        },
      };
    }
    if (response.type === 'final') {
      return {
        action: 'final_result',
        data: {
          content: 'Final response',
          model: 'claude-3',
          usage: { tokens: 200 },
        },
      };
    }
    if (response.type === 'buffer') {
      return {
        action: 'buffer',
        reason: 'Buffering message',
      };
    }
    if (response.type === 'skip') {
      return {
        action: 'skip',
        reason: 'Skipping message',
      };
    }
    return { action: 'unknown' };
  }),
};

// Skip these tests due to ES module mocking limitations with Node.js test runner
describe.skip('ResponseEmitter', () => {
  let responseEmitter;
  let mockSessionManager;
  let mockEventEmitter;
  let emittedEvents;

  beforeEach(() => {
    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});

    // Track emitted events
    emittedEvents = [];

    // Mock event emitter
    mockEventEmitter = {
      emit: mock.fn((event, data) => {
        emittedEvents.push({ event, data });
      }),
    };

    // Mock session manager
    mockSessionManager = {
      sessionMessageBuffers: new Map(),

      getSessionBuffer: mock.fn((sessionId) => {
        return mockSessionManager.sessionMessageBuffers.get(sessionId);
      }),

      setSessionBuffer: mock.fn((sessionId, buffer) => {
        mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);
      }),

      clearSessionBuffer: mock.fn((sessionId) => {
        mockSessionManager.sessionMessageBuffers.delete(sessionId);
      }),

      getSession: mock.fn(async (sessionId) => {
        return { sessionId, workingDirectory: '/test/dir' };
      }),

      trackSessionForRouting: mock.fn(async (_sessionId, _workingDirectory) => {
        // Mock implementation
      }),
    };

    responseEmitter = new ResponseEmitter(mockSessionManager, mockEventEmitter);

    // Override the AICLIMessageHandler import
    global.AICLIMessageHandler = mockAICLIMessageHandler;
  });

  afterEach(() => {
    mock.restoreAll();
    delete global.AICLIMessageHandler;
  });

  describe('emitAICLIResponse', () => {
    it('should skip processing for null sessionId', async () => {
      await responseEmitter.emitAICLIResponse(null, { type: 'test' }, false);

      assert.strictEqual(mockSessionManager.getSessionBuffer.mock.callCount(), 0);
      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should create buffer on-demand if not exists', async () => {
      const sessionId = 'session123';
      const response = { type: 'final' };

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(mockSessionManager.getSessionBuffer.mock.callCount(), 1);
      assert.strictEqual(mockSessionManager.setSessionBuffer.mock.callCount(), 1);
      assert.strictEqual(mockAICLIMessageHandler.createSessionBuffer.mock.callCount(), 1);
    });

    it('should track session for routing if not exists', async () => {
      const sessionId = 'session123';
      const response = { type: 'final' };

      mockSessionManager.getSession.mock.mockImplementation(() => null);

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(mockSessionManager.trackSessionForRouting.mock.callCount(), 1);
    });

    it('should handle permission request', async () => {
      const sessionId = 'session123';
      const response = { type: 'permission_request', prompt: 'Allow?', options: ['yes', 'no'] };

      // Set up existing buffer
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 2);
      assert.strictEqual(emittedEvents[0].event, 'permissionRequired');
      assert.strictEqual(emittedEvents[1].event, 'assistantMessage');
      assert.strictEqual(emittedEvents[1].data.data.type, 'permission_request');
    });

    it('should handle tool use', async () => {
      const sessionId = 'session123';
      const response = { type: 'tool_use' };

      // Set up existing buffer
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'assistantMessage');
      assert.strictEqual(emittedEvents[0].data.data.type, 'tool_use');
    });

    it('should handle final result', async () => {
      const sessionId = 'session123';
      const response = { type: 'final' };

      // Set up existing buffer
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Override the AICLIMessageHandler import
      global.AICLIMessageHandler = mockAICLIMessageHandler;

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.strictEqual(mockSessionManager.clearSessionBuffer.mock.callCount(), 1);
    });

    it('should handle buffer action', async () => {
      const sessionId = 'session123';
      const response = { type: 'buffer' };

      // Set up existing buffer
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should handle skip action', async () => {
      const sessionId = 'session123';
      const response = { type: 'skip' };

      // Set up existing buffer
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should pass options to processResponse', async () => {
      const sessionId = 'session123';
      const response = { type: 'final' };
      const options = { custom: 'option' };

      // Set up existing buffer
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitAICLIResponse(sessionId, response, false, options);

      const processCall = mockAICLIMessageHandler.processResponse.mock.calls[0];
      assert.deepStrictEqual(processCall.arguments[2], options);
    });
  });

  describe('handleFinalResultEmission', () => {
    it('should buffer final response when permission pending', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };

      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      buffer.pendingPermission = true;
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.handleFinalResultEmission(sessionId, data);

      assert.strictEqual(buffer.pendingFinalResponse, true);
      assert.deepStrictEqual(buffer.finalResponseData, data);
      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should defer emission when requested', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };
      const options = { deferEmission: true };

      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.handleFinalResultEmission(sessionId, data, options);

      assert.deepStrictEqual(buffer.deferredFinalResult, data);
      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should emit final result immediately', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };

      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.handleFinalResultEmission(sessionId, data);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.deepStrictEqual(emittedEvents[0].data.data, data);
      assert.strictEqual(mockSessionManager.clearSessionBuffer.mock.callCount(), 1);
    });

    it('should handle missing buffer', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };

      await responseEmitter.handleFinalResultEmission(sessionId, data);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
    });
  });

  describe('emitDeferredResult', () => {
    it('should emit deferred result', async () => {
      const sessionId = 'session123';
      const deferredData = { content: 'Deferred result' };

      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      buffer.deferredFinalResult = deferredData;
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitDeferredResult(sessionId);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.deepStrictEqual(emittedEvents[0].data.data, deferredData);
      assert.strictEqual(buffer.deferredFinalResult, null);
    });

    it('should handle missing buffer', async () => {
      const sessionId = 'session123';

      await responseEmitter.emitDeferredResult(sessionId);

      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should handle buffer without deferred result', async () => {
      const sessionId = 'session123';

      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitDeferredResult(sessionId);

      assert.strictEqual(emittedEvents.length, 0);
    });
  });

  describe('getSessionBuffer', () => {
    it('should return buffer data', () => {
      const sessionId = 'session123';
      const buffer = mockAICLIMessageHandler.createSessionBuffer();
      buffer.messages = ['msg1', 'msg2'];
      buffer.pendingPermission = true;
      buffer.pendingFinalResponse = true;
      buffer.finalResponseData = { data: 'final' };

      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      const result = responseEmitter.getSessionBuffer(sessionId);

      assert.deepStrictEqual(result.messages, ['msg1', 'msg2']);
      assert.strictEqual(result.pendingPermission, true);
      assert.strictEqual(result.pendingFinalResponse, true);
      assert.deepStrictEqual(result.finalResponseData, { data: 'final' });
    });

    it('should return null for missing buffer', () => {
      const result = responseEmitter.getSessionBuffer('nonexistent');

      assert.strictEqual(result, null);
    });

    it('should handle invalid buffer', () => {
      const sessionId = 'session123';
      mockSessionManager.sessionMessageBuffers.set(sessionId, 'invalid');

      const result = responseEmitter.getSessionBuffer(sessionId);

      assert.strictEqual(result, null);
    });
  });

  describe('clearSessionBuffer', () => {
    it('should clear session buffer', () => {
      const sessionId = 'session123';

      responseEmitter.clearSessionBuffer(sessionId);

      assert.strictEqual(mockSessionManager.clearSessionBuffer.mock.callCount(), 1);
      assert.strictEqual(
        mockSessionManager.clearSessionBuffer.mock.calls[0].arguments[0],
        sessionId
      );
    });

    it('should handle missing clearSessionBuffer method', () => {
      delete mockSessionManager.clearSessionBuffer;

      assert.doesNotThrow(() => {
        responseEmitter.clearSessionBuffer('session123');
      });
    });
  });
});
