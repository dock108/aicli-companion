import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { AICLILongRunningTaskManager } from '../../services/aicli-long-running-task-manager.js';
import { AICLIConfig } from '../../services/aicli-utils.js';
import { pushNotificationService } from '../../services/push-notification.js';

// Store original methods
const originalCalculateTimeout = AICLIConfig.calculateTimeoutForCommand;
const originalSendNotification = pushNotificationService.sendClaudeResponseNotification;
const originalSendToMultipleClients = pushNotificationService.sendToMultipleClients;

describe('AICLILongRunningTaskManager', () => {
  let taskManager;
  let originalWebSocketClients;

  beforeEach(() => {
    // Mock the methods
    AICLIConfig.calculateTimeoutForCommand = mock.fn();
    pushNotificationService.sendClaudeResponseNotification = mock.fn();
    pushNotificationService.sendToMultipleClients = mock.fn();

    taskManager = new AICLILongRunningTaskManager();

    // Mock global webSocketClients
    originalWebSocketClients = global.webSocketClients;
    global.webSocketClients = new Map();
  });

  afterEach(() => {
    // Clean up any pending timeouts or intervals
    if (taskManager) {
      taskManager.removeAllListeners();
    }

    // Restore original methods
    AICLIConfig.calculateTimeoutForCommand = originalCalculateTimeout;
    pushNotificationService.sendClaudeResponseNotification = originalSendNotification;
    pushNotificationService.sendToMultipleClients = originalSendToMultipleClients;

    // Restore global
    global.webSocketClients = originalWebSocketClients;

    // Force cleanup of any remaining timers (safety net)
    // This is a workaround for the test that creates intervals
    if (global._cleanupFunctions) {
      global._cleanupFunctions.forEach((fn) => fn());
      global._cleanupFunctions = [];
    }
  });

  describe('constructor', () => {
    it('should initialize as EventEmitter', () => {
      assert.ok(taskManager instanceof EventEmitter);
    });
  });

  describe('handlePotentialLongRunningTask', () => {
    it('should handle short-running task normally', async () => {
      AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 30000); // 30 seconds

      const mockExecuteFunction = mock.fn(() => Promise.resolve({ result: 'quick result' }));

      const result = await taskManager.handlePotentialLongRunningTask(
        'test-session',
        'Quick prompt',
        mockExecuteFunction
      );

      assert.strictEqual(mockExecuteFunction.mock.calls.length, 1);
      assert.deepStrictEqual(result, { result: 'quick result' });
    });

    it('should handle long-running task with immediate acknowledgment', async () => {
      AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000); // 6.67 minutes

      const mockExecuteFunction = mock.fn(() =>
        Promise.resolve({ type: 'result', result: 'long result' })
      );

      let assistantMessage = null;
      taskManager.once('assistantMessage', (message) => {
        assistantMessage = message;
      });

      const result = await taskManager.handlePotentialLongRunningTask(
        'test-session',
        'Complex long prompt',
        mockExecuteFunction
      );

      // Should return immediate acknowledgment
      assert.strictEqual(result.type, 'status');
      assert.strictEqual(result.subtype, 'long_running_started');
      assert.strictEqual(result.session_id, 'test-session');
      assert.strictEqual(result.status, 'processing');
      assert.ok(result.estimated_duration_ms > 300000);

      // Should emit initial assistant message
      assert.ok(assistantMessage);
      assert.strictEqual(assistantMessage.sessionId, 'test-session');
      assert.strictEqual(assistantMessage.isComplete, false);
      assert.ok(assistantMessage.data.content[0].text.includes('Processing Complex Request'));

      // mockExecuteFunction should be called asynchronously (not awaited)
      // We can't easily test the async execution without making this test async and waiting
    });

    it('should calculate correct estimated time', async () => {
      AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 600000); // 10 minutes

      const mockExecuteFunction = mock.fn(() => Promise.resolve({ result: 'result' }));

      const result = await taskManager.handlePotentialLongRunningTask(
        'test-session',
        'Long prompt',
        mockExecuteFunction
      );

      assert.strictEqual(result.estimated_duration_ms, 600000);
      // 10 minutes = 600000ms
    });
  });

  describe('runLongRunningProcess', () => {
    it('should send periodic status updates', async () => {
      // Mock timer functions for this test
      const originalSetInterval = global.setInterval;
      const originalClearInterval = global.clearInterval;
      let intervalId;
      let intervalCallback;

      // Capture the interval callback
      global.setInterval = mock.fn((callback, _delay) => {
        intervalCallback = callback;
        intervalId = Symbol('interval');
        return intervalId;
      });

      global.clearInterval = mock.fn((id) => {
        if (id === intervalId) {
          intervalCallback = null;
        }
      });

      const mockExecuteFunction = mock.fn(
        () =>
          new Promise((resolve) => {
            // Simulate status update after a short delay
            setTimeout(() => {
              if (intervalCallback) {
                intervalCallback(); // Trigger status update
              }
              // Then resolve
              setTimeout(() => resolve({ type: 'result', result: 'done' }), 10);
            }, 50);
          })
      );

      let statusUpdateReceived = false;
      taskManager.on('assistantMessage', (message) => {
        if (message.data.content[0].text.includes('Still working')) {
          // Verify status update
          assert.strictEqual(message.sessionId, 'test-session');
          assert.strictEqual(message.isComplete, false);
          assert.ok(message.data.content[0].text.includes('Still working'));
          statusUpdateReceived = true;
        }
      });

      // Start the long-running process
      await taskManager.runLongRunningProcess(
        'test-session',
        'Long prompt',
        mockExecuteFunction,
        600000
      );

      // Verify interval was created and cleared
      assert.strictEqual(global.setInterval.mock.calls.length, 1);
      assert.strictEqual(global.clearInterval.mock.calls.length, 1);
      assert.ok(statusUpdateReceived, 'Status update should have been received');

      // Restore timers
      global.setInterval = originalSetInterval;
      global.clearInterval = originalClearInterval;
    });

    it('should handle successful completion', async () => {
      // Add a mock client with device token
      global.webSocketClients.set('client1', {
        sessionIds: new Set(['test-session']),
        deviceToken: 'test-token',
      });

      const mockExecuteFunction = mock.fn(() =>
        Promise.resolve({
          type: 'result',
          result: 'Task completed successfully',
        })
      );

      let completionMessage = null;
      taskManager.on('assistantMessage', (message) => {
        if (message.isComplete) {
          completionMessage = message;
        }
      });

      // Start the process
      await taskManager.runLongRunningProcess(
        'test-session',
        'Test prompt',
        mockExecuteFunction,
        400000
      );

      assert.ok(completionMessage);
      assert.strictEqual(completionMessage.sessionId, 'test-session');
      assert.strictEqual(completionMessage.isComplete, true);
      assert.strictEqual(completionMessage.data.content[0].text, 'Task completed successfully');

      // Should call push notification
      assert.strictEqual(pushNotificationService.sendToMultipleClients.mock.calls.length, 1);
    });

    it('should handle execution error', async () => {
      // Add a mock client with device token
      global.webSocketClients.set('client1', {
        sessionIds: new Set(['test-session']),
        deviceToken: 'test-token',
      });

      const mockExecuteFunction = mock.fn(() => Promise.reject(new Error('Task failed')));

      let errorMessage = null;
      let streamError = null;

      taskManager.on('assistantMessage', (message) => {
        if (message.isComplete && message.data.content[0].text.includes('Complex Request Failed')) {
          errorMessage = message;
        }
      });

      taskManager.on('streamError', (error) => {
        streamError = error;
      });

      // Start the process
      await taskManager.runLongRunningProcess(
        'test-session',
        'Failing prompt',
        mockExecuteFunction,
        400000
      );

      assert.ok(errorMessage);
      assert.strictEqual(errorMessage.sessionId, 'test-session');
      assert.strictEqual(errorMessage.isComplete, true);
      assert.ok(errorMessage.data.content[0].text.includes('Complex Request Failed'));
      assert.ok(errorMessage.data.content[0].text.includes('Task failed'));

      assert.ok(streamError);
      assert.strictEqual(streamError.sessionId, 'test-session');
      assert.strictEqual(streamError.error, 'Task failed');

      // Should call push notification for error
      assert.strictEqual(pushNotificationService.sendToMultipleClients.mock.calls.length, 1);
    });
  });

  describe('sendLongRunningCompletionNotification', () => {
    beforeEach(() => {
      // Set up mock webSocket clients
      global.webSocketClients.set('client1', {
        sessionIds: new Set([
          'test-session',
          'test_session_uuid123',
          'my_project_uuid123',
          'multi_word_project_name_uuid456',
        ]),
        deviceToken: 'token1',
      });

      global.webSocketClients.set('client2', {
        sessionIds: new Set(['test-session', 'other-session']),
        deviceToken: 'token2',
      });

      global.webSocketClients.set('client3', {
        sessionIds: new Set(['other-session']),
        deviceToken: 'token3',
      });

      global.webSocketClients.set('client4', {
        sessionIds: new Set(['test-session']),
        // No device token
      });
    });

    it('should send notifications to clients with matching session and device token', async () => {
      await taskManager.sendLongRunningCompletionNotification('test-session', 'Test prompt', false);

      // Should call sendToMultipleClients with client1 and client2
      assert.strictEqual(pushNotificationService.sendToMultipleClients.mock.calls.length, 1);

      const call = pushNotificationService.sendToMultipleClients.mock.calls[0];
      const clientIds = call.arguments[0];
      assert.strictEqual(clientIds.length, 2);
      assert.ok(clientIds.includes('client1'));
      assert.ok(clientIds.includes('client2'));
      assert.ok(!clientIds.includes('client3')); // Wrong session
      assert.ok(!clientIds.includes('client4')); // No device token
    });

    it('should send success notification with correct data', async () => {
      await taskManager.sendLongRunningCompletionNotification(
        'test_session_uuid123',
        'Test prompt for completion',
        false
      );

      const call = pushNotificationService.sendToMultipleClients.mock.calls[0];
      const [clientIds, notificationData] = call.arguments;

      assert.strictEqual(clientIds.length, 1);
      assert.ok(clientIds.includes('client1'));
      assert.strictEqual(notificationData.sessionId, 'test_session_uuid123');
      assert.strictEqual(notificationData.projectName, 'test_session');
      assert.ok(notificationData.message.includes('Task completed'));
      assert.ok(notificationData.message.includes('Test prompt for completion'));
      assert.strictEqual(notificationData.isLongRunningCompletion, true);
    });

    it('should send error notification with correct data', async () => {
      await taskManager.sendLongRunningCompletionNotification(
        'test-session',
        'Failing prompt',
        true,
        'Something went wrong'
      );

      const call = pushNotificationService.sendToMultipleClients.mock.calls[0];
      const [clientIds, notificationData] = call.arguments;

      assert.strictEqual(clientIds.length, 2);
      assert.ok(notificationData.message.includes('Task failed'));
      assert.ok(notificationData.message.includes('Failing prompt'));
      assert.ok(notificationData.message.includes('Something went wrong'));
    });

    it('should extract project name from session ID', async () => {
      await taskManager.sendLongRunningCompletionNotification(
        'my_project_uuid123',
        'Test prompt',
        false
      );

      const call = pushNotificationService.sendToMultipleClients.mock.calls[0];
      const [_clientIds, notificationData] = call.arguments;

      assert.strictEqual(notificationData.projectName, 'my_project');
    });

    it('should handle complex project names', async () => {
      await taskManager.sendLongRunningCompletionNotification(
        'multi_word_project_name_uuid456',
        'Test',
        false
      );

      const call = pushNotificationService.sendToMultipleClients.mock.calls[0];
      const [_clientIds, notificationData] = call.arguments;

      assert.strictEqual(notificationData.projectName, 'multi_word_project_name');
    });

    it('should handle no webSocket clients gracefully', () => {
      global.webSocketClients = null;

      assert.doesNotThrow(() => {
        taskManager.sendLongRunningCompletionNotification('test-session', 'Test prompt', false);
      });

      // Should be called with empty client IDs array when no clients
      assert.strictEqual(pushNotificationService.sendToMultipleClients.mock.calls.length, 1);

      const call = pushNotificationService.sendToMultipleClients.mock.calls[0];
      const [clientIds] = call.arguments;
      assert.strictEqual(clientIds.length, 0);
    });
  });

  describe('utility methods', () => {
    describe('isLongRunningCommand', () => {
      it('should return true for long commands', () => {
        AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000);

        const result = taskManager.isLongRunningCommand('Complex prompt');
        assert.strictEqual(result, true);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand.mock.calls.length, 1);
      });

      it('should return false for short commands', () => {
        AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 30000);

        const result = taskManager.isLongRunningCommand('Simple prompt');
        assert.strictEqual(result, false);
      });
    });

    describe('getEstimatedCompletionTime', () => {
      it('should return time in minutes', () => {
        AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 600000); // 10 minutes

        const result = taskManager.getEstimatedCompletionTime('Test prompt');
        assert.strictEqual(result, 10);
      });

      it('should round to nearest minute', () => {
        AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 330000); // 5.5 minutes

        const result = taskManager.getEstimatedCompletionTime('Test prompt');
        assert.strictEqual(result, 6); // Rounded up
      });

      it('should handle partial minutes', () => {
        AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 90000); // 1.5 minutes

        const result = taskManager.getEstimatedCompletionTime('Test prompt');
        assert.strictEqual(result, 2); // Rounded up
      });
    });
  });

  describe('event handling', () => {
    it('should emit assistantMessage events', async () => {
      AICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000);

      const mockExecuteFunction = mock.fn(() => Promise.resolve({ result: 'test' }));

      const firstEventPromise = new Promise((resolve) => {
        let eventCount = 0;
        taskManager.on('assistantMessage', (message) => {
          eventCount++;
          assert.ok(message.sessionId);
          assert.ok(message.data);

          if (eventCount === 1) {
            // First event should be the initial status
            assert.strictEqual(message.isComplete, false);
            resolve();
          }
        });
      });

      taskManager.handlePotentialLongRunningTask(
        'test-session',
        'Long prompt',
        mockExecuteFunction
      );

      await firstEventPromise;
    });

    it('should emit streamError events on failure', async () => {
      const mockExecuteFunction = mock.fn(() => Promise.reject(new Error('Test error')));

      const errorPromise = new Promise((resolve) => {
        taskManager.on('streamError', (error) => {
          assert.strictEqual(error.sessionId, 'test-session');
          assert.strictEqual(error.error, 'Test error');
          resolve();
        });
      });

      const processPromise = taskManager.runLongRunningProcess(
        'test-session',
        'Test prompt',
        mockExecuteFunction,
        400000
      );

      await Promise.race([errorPromise, processPromise]);
    });
  });
});
