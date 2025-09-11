/**
 * Unit tests for chat-message-handler.js
 */

import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { createChatMessageHandler } from '../../handlers/chat-message-handler.js';

describe('ChatMessageHandler', () => {
  let mockAicliService;
  let mockPushNotificationService;
  let mockWebSocketService;
  let handler;

  beforeEach(() => {
    // Create mock services
    mockAicliService = {
      sendPrompt: mock.fn(async () => ({
        success: true,
        result: 'Test response from Claude',
        claudeSessionId: 'test-session-123',
      })),
      sessionManager: {
        getSession: mock.fn(() => ({
          isProcessing: false,
          processingStartTime: null,
        })),
      },
      on: mock.fn(),
      removeListener: mock.fn(),
    };

    mockPushNotificationService = {
      sendMessageNotification: mock.fn(async () => ({ success: true })),
      sendProgressNotification: mock.fn(async () => ({ success: true })),
      sendErrorNotification: mock.fn(async () => ({ success: true })),
    };

    mockWebSocketService = {
      sendError: mock.fn(),
      broadcastToSession: mock.fn(),
    };

    // Create handler with mocked services
    handler = createChatMessageHandler({
      aicliService: mockAicliService,
      pushNotificationService: mockPushNotificationService,
      webSocketService: mockWebSocketService,
    });
  });

  afterEach(() => {
    mock.reset();
  });

  it('should process a queued message successfully', async () => {
    const queuedMessage = {
      id: 'msg-1',
      priority: 1,
      message: {
        projectPath: '/test/project',
        deviceToken: 'test-device-token',
        attachments: [],
        autoResponse: false,
        requestId: 'req-123',
        sessionId: 'session-456',
        validatedMessage: 'Hello Claude',
        mode: 'normal',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify AICLI service was called
    assert.strictEqual(mockAicliService.sendPrompt.mock.calls.length, 1);
    assert.strictEqual(mockAicliService.sendPrompt.mock.calls[0].arguments[0], 'Hello Claude');

    // Verify push notification was sent
    assert.strictEqual(mockPushNotificationService.sendMessageNotification.mock.calls.length, 1);

    // Verify callback was called with success
    assert.strictEqual(callback.mock.calls.length, 1);
    assert.strictEqual(callback.mock.calls[0].arguments[0], null); // No error
    assert.deepStrictEqual(callback.mock.calls[0].arguments[1], {
      success: true,
      sessionId: 'test-session-123',
    });
  });

  it('should handle errors and send error notification', async () => {
    // Mock error response
    mockAicliService.sendPrompt = mock.fn(async () => {
      throw new Error('Claude API error');
    });

    const queuedMessage = {
      id: 'msg-2',
      priority: 1,
      message: {
        projectPath: '/test/project',
        deviceToken: 'test-device-token',
        requestId: 'req-456',
        validatedMessage: 'Hello Claude',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify error notification was sent
    assert.strictEqual(mockPushNotificationService.sendErrorNotification.mock.calls.length, 1);

    // Verify WebSocket error was sent (but no sessionId so it shouldn't be called)
    assert.strictEqual(mockWebSocketService.sendError.mock.calls.length, 0);

    // Verify callback was called with error
    assert.strictEqual(callback.mock.calls.length, 1);
    assert(callback.mock.calls[0].arguments[0] instanceof Error);
  });

  it('should send WebSocket error when sessionId is present', async () => {
    // Mock error response
    mockAicliService.sendPrompt = mock.fn(async () => {
      throw new Error('Claude API error');
    });

    const queuedMessage = {
      id: 'msg-error',
      priority: 1,
      message: {
        projectPath: '/test/project',
        deviceToken: 'test-device-token',
        requestId: 'req-error',
        sessionId: 'session-123',
        validatedMessage: 'Hello Claude',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify error notification was sent
    assert.strictEqual(mockPushNotificationService.sendErrorNotification.mock.calls.length, 1);

    // Verify WebSocket error was sent with sessionId
    assert.strictEqual(mockWebSocketService.sendError.mock.calls.length, 1);
    assert.strictEqual(mockWebSocketService.sendError.mock.calls[0].arguments[0], 'session-123');
    assert.strictEqual(mockWebSocketService.sendError.mock.calls[0].arguments[1], 'req-error');
    assert.strictEqual(
      mockWebSocketService.sendError.mock.calls[0].arguments[2],
      'Failed to process message'
    );
    assert.strictEqual(
      mockWebSocketService.sendError.mock.calls[0].arguments[3],
      'PROCESSING_ERROR'
    );

    // Verify callback was called with error
    assert.strictEqual(callback.mock.calls.length, 1);
    assert(callback.mock.calls[0].arguments[0] instanceof Error);
  });

  it('should handle SIGTERM as successful completion with continuation message', async () => {
    // Mock SIGTERM success response with isSigterm flag
    mockAicliService.sendPrompt = mock.fn(async () => ({
      success: true,
      result: '', // Empty result since we'll use continuation message
      claudeSessionId: 'test-session-123',
      isSigterm: true,
      sigtermReason: 'after 110 tools',
    }));

    const queuedMessage = {
      id: 'msg-sigterm',
      priority: 1,
      message: {
        projectPath: '/test/project',
        deviceToken: 'test-device-token',
        requestId: 'req-sigterm',
        sessionId: 'session-sigterm',
        validatedMessage: 'Hello Claude',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify regular message notification was sent with continuation message
    assert.strictEqual(mockPushNotificationService.sendMessageNotification.mock.calls.length, 1);
    const notificationCall = mockPushNotificationService.sendMessageNotification.mock.calls[0];
    assert.strictEqual(
      notificationCall.arguments[1].message,
      "I've completed many tasks and need to pause here. Send another message to continue where I left off."
    );
    assert.strictEqual(mockPushNotificationService.sendErrorNotification.mock.calls.length, 0);

    // Verify callback was called with success
    assert.strictEqual(callback.mock.calls.length, 1);
    assert.strictEqual(callback.mock.calls[0].arguments[0], null); // No error
    assert.deepStrictEqual(callback.mock.calls[0].arguments[1], {
      success: true,
      sessionId: 'test-session-123',
    });
  });

  it('should handle SIGTERM with accumulated streaming content', async () => {
    // Mock SIGTERM success response with accumulated content (but we'll replace it)
    mockAicliService.sendPrompt = mock.fn(async () => ({
      success: true,
      result:
        'I found several issues in your code:\n1. Missing error handling\n2. Undefined variables',
      claudeSessionId: 'test-session-123',
      isSigterm: true,
      sigtermReason: 'after 110 tools',
    }));

    const queuedMessage = {
      id: 'msg-sigterm-content',
      priority: 1,
      message: {
        projectPath: '/test/project',
        deviceToken: 'test-device-token',
        requestId: 'req-sigterm-content',
        sessionId: 'session-sigterm',
        validatedMessage: 'Analyze my code',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify regular message notification was sent with continuation message (not accumulated content)
    assert.strictEqual(mockPushNotificationService.sendMessageNotification.mock.calls.length, 1);
    const notificationCall = mockPushNotificationService.sendMessageNotification.mock.calls[0];
    assert.strictEqual(
      notificationCall.arguments[1].message,
      "I've completed many tasks and need to pause here. Send another message to continue where I left off."
    );
    assert.strictEqual(mockPushNotificationService.sendErrorNotification.mock.calls.length, 0);

    // Verify callback was called with success
    assert.strictEqual(callback.mock.calls.length, 1);
    assert.strictEqual(callback.mock.calls[0].arguments[0], null); // No error
    assert.deepStrictEqual(callback.mock.calls[0].arguments[1], {
      success: true,
      sessionId: 'test-session-123',
    });
  });

  it('should handle workspace mode messages', async () => {
    const queuedMessage = {
      id: 'msg-3',
      priority: 1,
      message: {
        projectPath: '__workspace__',
        deviceToken: 'test-device-token',
        requestId: 'req-789',
        validatedMessage: 'List all projects',
        mode: 'normal',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify streaming was enabled for workspace
    const sendPromptCall = mockAicliService.sendPrompt.mock.calls[0];
    assert.strictEqual(sendPromptCall.arguments[1].streaming, true);
    assert.strictEqual(sendPromptCall.arguments[1].workingDirectory, '__workspace__');
  });

  it('should attach and remove stream listeners', async () => {
    const queuedMessage = {
      id: 'msg-4',
      priority: 1,
      message: {
        projectPath: '/test/project',
        deviceToken: 'test-device-token',
        requestId: 'req-111',
        validatedMessage: 'Stream test',
      },
    };

    const callback = mock.fn();
    await handler(queuedMessage, callback);

    // Verify listener was attached and removed
    assert.strictEqual(mockAicliService.on.mock.calls.length, 1);
    assert.strictEqual(mockAicliService.on.mock.calls[0].arguments[0], 'streamChunk');
    assert.strictEqual(mockAicliService.removeListener.mock.calls.length, 1);
    assert.strictEqual(mockAicliService.removeListener.mock.calls[0].arguments[0], 'streamChunk');
  });
});
