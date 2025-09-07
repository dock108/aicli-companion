import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import { ResponseEmitter } from '../../../services/aicli/response-emitter.js';
import { AICLIMessageHandler } from '../../../services/aicli-message-handler.js';

describe('ResponseEmitter', () => {
  let responseEmitter;
  let mockSessionManager;
  let mockEventEmitter;
  let emittedEvents;
  let consoleLogSpy;
  let consoleDebugSpy;

  beforeEach(() => {
    // Mock console methods
    consoleLogSpy = mock.method(console, 'log', () => {});
    consoleDebugSpy = mock.method(console, 'debug', () => {});

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

      getSessionBuffer: mock.fn(function (sessionId) {
        return this.sessionMessageBuffers.get(sessionId);
      }),

      setSessionBuffer: mock.fn(function (sessionId, buffer) {
        this.sessionMessageBuffers.set(sessionId, buffer);
      }),

      clearSessionBuffer: mock.fn(function (sessionId) {
        this.sessionMessageBuffers.delete(sessionId);
      }),

      getSession: mock.fn(async (sessionId) => {
        if (sessionId === 'no-session') {
          return null;
        }
        return { sessionId, workingDirectory: '/test/dir' };
      }),

      trackSessionForRouting: mock.fn(async () => {
        // Mock implementation
      }),
    };

    responseEmitter = new ResponseEmitter(mockSessionManager, mockEventEmitter);
  });

  describe('constructor', () => {
    it('should initialize with sessionManager and eventEmitter', () => {
      assert(responseEmitter.sessionManager === mockSessionManager);
      assert(typeof responseEmitter.emit === 'function');
    });
  });

  describe('emitAICLIResponse', () => {
    it('should skip processing for null sessionId', async () => {
      await responseEmitter.emitAICLIResponse(null, { type: 'test' }, false);

      assert.strictEqual(mockSessionManager.getSessionBuffer.mock.callCount(), 0);
      assert.strictEqual(emittedEvents.length, 0);
      assert(
        consoleDebugSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Skipping message buffer processing for null sessionId')
        )
      );
    });

    it('should create buffer on-demand if not exists', async () => {
      const sessionId = 'session123';
      const response = { type: 'content', content: 'test' };

      // Mock AICLIMessageHandler.processResponse to return a final result
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'final_result',
        data: { content: 'Final response' },
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      // getSessionBuffer is called once in emitAICLIResponse and once in handleFinalResultEmission
      assert(mockSessionManager.getSessionBuffer.mock.callCount() >= 1);
      assert.strictEqual(mockSessionManager.setSessionBuffer.mock.callCount(), 1);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Creating message buffer on-demand')
        )
      );

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should track session for routing if session does not exist', async () => {
      const sessionId = 'no-session';
      const response = { type: 'content', content: 'test' };

      // Mock AICLIMessageHandler.processResponse
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'buffer',
        reason: 'Buffering',
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(mockSessionManager.trackSessionForRouting.mock.callCount(), 1);

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should handle permission request action', async () => {
      const sessionId = 'session123';
      const response = { type: 'permission' };

      // Set up existing buffer
      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Mock processResponse to return permission request
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'permission_request',
        data: {
          prompt: 'Allow operation?',
          options: ['yes', 'no'],
          default: 'yes',
          messageId: 'msg123',
          content: 'Permission required',
          model: 'claude-3',
          usage: { tokens: 100 },
        },
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 2);
      assert.strictEqual(emittedEvents[0].event, 'permissionRequired');
      assert.strictEqual(emittedEvents[0].data.sessionId, sessionId);
      assert.strictEqual(emittedEvents[0].data.prompt, 'Allow operation?');
      assert.strictEqual(emittedEvents[1].event, 'assistantMessage');
      assert.strictEqual(emittedEvents[1].data.data.type, 'permission_request');

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should handle tool use action', async () => {
      const sessionId = 'session123';
      const response = { type: 'tool' };

      // Set up existing buffer
      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Mock processResponse to return tool use
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'tool_use',
        data: {
          messageId: 'msg456',
          content: 'Using tool',
          model: 'claude-3',
          usage: { tokens: 150 },
        },
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'assistantMessage');
      assert.strictEqual(emittedEvents[0].data.data.type, 'tool_use');

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should handle final result action', async () => {
      const sessionId = 'session123';
      const response = { type: 'final' };

      // Set up existing buffer
      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Mock processResponse to return final result
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'final_result',
        data: {
          content: 'Final response',
          model: 'claude-3',
          usage: { tokens: 200 },
        },
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.strictEqual(mockSessionManager.clearSessionBuffer.mock.callCount(), 1);

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should handle buffer action', async () => {
      const sessionId = 'session123';
      const response = { type: 'buffer' };

      // Set up existing buffer
      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Mock processResponse to return buffer action
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'buffer',
        reason: 'Buffering message for later',
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 0);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Buffering message for later')
        )
      );

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should handle skip action', async () => {
      const sessionId = 'session123';
      const response = { type: 'skip' };

      // Set up existing buffer
      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Mock processResponse to return skip action
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      AICLIMessageHandler.processResponse = mock.fn(() => ({
        action: 'skip',
        reason: 'Message not relevant',
      }));

      await responseEmitter.emitAICLIResponse(sessionId, response, false);

      assert.strictEqual(emittedEvents.length, 0);
      assert(
        consoleLogSpy.mock.calls.some((call) => call.arguments[0].includes('Message not relevant'))
      );

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });

    it('should pass options to processResponse', async () => {
      const sessionId = 'session123';
      const response = { type: 'test' };
      const options = { custom: 'option', deferEmission: false };

      // Set up existing buffer
      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      // Mock processResponse
      const originalProcessResponse = AICLIMessageHandler.processResponse;
      const processResponseMock = mock.fn(() => ({
        action: 'skip',
        reason: 'test',
      }));
      AICLIMessageHandler.processResponse = processResponseMock;

      await responseEmitter.emitAICLIResponse(sessionId, response, false, options);

      assert.strictEqual(processResponseMock.mock.callCount(), 1);
      const call = processResponseMock.mock.calls[0];
      assert.deepStrictEqual(call.arguments[2], options);

      // Restore original
      AICLIMessageHandler.processResponse = originalProcessResponse;
    });
  });

  describe('handleFinalResultEmission', () => {
    it('should buffer final response when permission pending', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };

      const buffer = AICLIMessageHandler.createSessionBuffer();
      buffer.pendingPermission = true;
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.handleFinalResultEmission(sessionId, data);

      assert.strictEqual(buffer.pendingFinalResponse, true);
      assert.deepStrictEqual(buffer.finalResponseData, data);
      assert.strictEqual(emittedEvents.length, 0);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Buffering final response')
        )
      );
    });

    it('should defer emission when requested', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };
      const options = { deferEmission: true };

      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.handleFinalResultEmission(sessionId, data, options);

      assert.deepStrictEqual(buffer.deferredFinalResult, data);
      assert.strictEqual(emittedEvents.length, 0);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Deferring final result emission')
        )
      );
    });

    it('should emit final result immediately by default', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };

      const buffer = AICLIMessageHandler.createSessionBuffer();
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.handleFinalResultEmission(sessionId, data);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.deepStrictEqual(emittedEvents[0].data.data, data);
      assert.strictEqual(mockSessionManager.clearSessionBuffer.mock.callCount(), 1);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Sending final response')
        )
      );
    });

    it('should handle missing buffer gracefully', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };

      // Don't set up a buffer - it should still work
      await responseEmitter.handleFinalResultEmission(sessionId, data);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.deepStrictEqual(emittedEvents[0].data.data, data);
    });

    it('should handle deferEmission with no buffer', async () => {
      const sessionId = 'session123';
      const data = { content: 'Final result' };
      const options = { deferEmission: true };

      // Don't set up a buffer
      await responseEmitter.handleFinalResultEmission(sessionId, data, options);

      // Should still log but not crash
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Deferring final result emission')
        )
      );
      assert.strictEqual(emittedEvents.length, 0);
    });
  });

  describe('emitDeferredResult', () => {
    it('should emit deferred result when present', async () => {
      const sessionId = 'session123';
      const deferredData = { content: 'Deferred result' };

      const buffer = AICLIMessageHandler.createSessionBuffer();
      buffer.deferredFinalResult = deferredData;
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitDeferredResult(sessionId);

      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'conversationResult');
      assert.deepStrictEqual(emittedEvents[0].data.data, deferredData);
      assert.strictEqual(buffer.deferredFinalResult, null);
      assert(
        consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Emitting deferred final result')
        )
      );
    });

    it('should handle missing buffer gracefully', async () => {
      const sessionId = 'session123';

      await responseEmitter.emitDeferredResult(sessionId);

      assert.strictEqual(emittedEvents.length, 0);
      // Should not throw or log anything
    });

    it('should handle buffer without deferred result', async () => {
      const sessionId = 'session123';

      const buffer = AICLIMessageHandler.createSessionBuffer();
      // No deferredFinalResult set
      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      await responseEmitter.emitDeferredResult(sessionId);

      assert.strictEqual(emittedEvents.length, 0);
      // Should not log emission message
      assert(
        !consoleLogSpy.mock.calls.some((call) =>
          call.arguments[0].includes('Emitting deferred final result')
        )
      );
    });
  });

  describe('getSessionBuffer', () => {
    it('should return formatted buffer data when buffer exists', () => {
      const sessionId = 'session123';
      const buffer = AICLIMessageHandler.createSessionBuffer();
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

    it('should return null for non-existent session', () => {
      const result = responseEmitter.getSessionBuffer('nonexistent');
      assert.strictEqual(result, null);
    });

    it('should handle missing sessionMessageBuffers map', () => {
      const tempSessionManager = responseEmitter.sessionManager;
      responseEmitter.sessionManager = {};

      const result = responseEmitter.getSessionBuffer('session123');
      assert.strictEqual(result, null);

      responseEmitter.sessionManager = tempSessionManager;
    });

    it('should handle invalid buffer type', () => {
      const sessionId = 'session123';
      mockSessionManager.sessionMessageBuffers.set(sessionId, 'invalid-buffer');

      const result = responseEmitter.getSessionBuffer(sessionId);
      assert.strictEqual(result, null);
    });

    it('should handle buffer with missing properties', () => {
      const sessionId = 'session123';
      const buffer = {}; // Empty object, missing expected properties

      mockSessionManager.sessionMessageBuffers.set(sessionId, buffer);

      const result = responseEmitter.getSessionBuffer(sessionId);

      // Should provide defaults for missing properties
      assert.deepStrictEqual(result.messages, []);
      assert.strictEqual(result.pendingPermission, false);
      assert.strictEqual(result.pendingFinalResponse, false);
      assert.strictEqual(result.finalResponseData, null);
    });
  });

  describe('clearSessionBuffer', () => {
    it('should clear session buffer through session manager', () => {
      const sessionId = 'session123';

      responseEmitter.clearSessionBuffer(sessionId);

      assert.strictEqual(mockSessionManager.clearSessionBuffer.mock.callCount(), 1);
      const call = mockSessionManager.clearSessionBuffer.mock.calls[0];
      assert.strictEqual(call.arguments[0], sessionId);
    });

    it('should handle missing clearSessionBuffer method gracefully', () => {
      const sessionId = 'session123';
      const tempClearMethod = mockSessionManager.clearSessionBuffer;
      delete mockSessionManager.clearSessionBuffer;

      // Should not throw
      assert.doesNotThrow(() => {
        responseEmitter.clearSessionBuffer(sessionId);
      });

      mockSessionManager.clearSessionBuffer = tempClearMethod;
    });

    it('should handle null session manager gracefully', () => {
      const sessionId = 'session123';
      const tempSessionManager = responseEmitter.sessionManager;
      responseEmitter.sessionManager = null;

      // Should not throw
      assert.doesNotThrow(() => {
        responseEmitter.clearSessionBuffer(sessionId);
      });

      responseEmitter.sessionManager = tempSessionManager;
    });
  });
});
