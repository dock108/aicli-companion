import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { AICLILongRunningTaskManager } from '../../services/aicli-long-running-task-manager.js';

// Mock dependencies
const mockAICLIConfig = {
  calculateTimeoutForCommand: mock.fn()
};

const mockPushNotificationService = {
  sendClaudeResponseNotification: mock.fn()
};

const mockAICLIUtils = mock.module('../../services/aicli-utils.js', {
  AICLIConfig: mockAICLIConfig
});

const mockPushNotification = mock.module('../../services/push-notification.js', {
  pushNotificationService: mockPushNotificationService
});

describe('AICLILongRunningTaskManager', () => {
  let taskManager;
  let originalWebSocketClients;

  beforeEach(() => {
    taskManager = new AICLILongRunningTaskManager();
    
    // Reset mocks
    mockAICLIConfig.calculateTimeoutForCommand.mock.resetCalls();
    mockPushNotificationService.sendClaudeResponseNotification.mock.resetCalls();

    // Mock global webSocketClients
    originalWebSocketClients = global.webSocketClients;
    global.webSocketClients = new Map();
  });

  afterEach(() => {
    // Clean up any pending timeouts or intervals
    if (taskManager) {
      taskManager.removeAllListeners();
    }
    
    // Restore global
    global.webSocketClients = originalWebSocketClients;
  });

  describe('constructor', () => {
    it('should initialize as EventEmitter', () => {
      assert.ok(taskManager instanceof EventEmitter);
    });
  });

  describe('handlePotentialLongRunningTask', () => {
    it('should handle short-running task normally', async () => {
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 30000); // 30 seconds
      
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
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000); // 6.67 minutes
      
      const mockExecuteFunction = mock.fn(() => Promise.resolve({ type: 'result', result: 'long result' }));
      
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
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 600000); // 10 minutes
      
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
    it('should send periodic status updates', (done) => {
      const mockExecuteFunction = mock.fn(() => new Promise(() => {})); // Never resolves
      
      let statusUpdateCount = 0;
      taskManager.on('assistantMessage', (message) => {
        if (message.data.content[0].text.includes('Still working')) {
          statusUpdateCount++;
          if (statusUpdateCount === 1) {
            // Verify first status update
            assert.strictEqual(message.sessionId, 'test-session');
            assert.strictEqual(message.isComplete, false);
            assert.ok(message.data.content[0].text.includes('Still working'));
            done();
          }
        }
      });
      
      // Start the long-running process
      taskManager.runLongRunningProcess('test-session', 'Long prompt', mockExecuteFunction, 600000);
    });

    it('should handle successful completion', (done) => {
      const mockExecuteFunction = mock.fn(() => Promise.resolve({
        type: 'result',
        result: 'Task completed successfully'
      }));
      
      let completionMessage = null;
      taskManager.on('assistantMessage', (message) => {
        if (message.isComplete) {
          completionMessage = message;
        }
      });
      
      // Start the process
      taskManager.runLongRunningProcess('test-session', 'Test prompt', mockExecuteFunction, 400000);
      
      // Wait for completion
      setTimeout(() => {
        assert.ok(completionMessage);
        assert.strictEqual(completionMessage.sessionId, 'test-session');
        assert.strictEqual(completionMessage.isComplete, true);
        assert.strictEqual(completionMessage.data.content[0].text, 'Task completed successfully');
        
        // Should call push notification
        assert.strictEqual(mockPushNotificationService.sendClaudeResponseNotification.mock.calls.length, 1);
        done();
      }, 50);
    });

    it('should handle execution error', (done) => {
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
      taskManager.runLongRunningProcess('test-session', 'Failing prompt', mockExecuteFunction, 400000);
      
      // Wait for error handling
      setTimeout(() => {
        assert.ok(errorMessage);
        assert.strictEqual(errorMessage.sessionId, 'test-session');
        assert.strictEqual(errorMessage.isComplete, true);
        assert.ok(errorMessage.data.content[0].text.includes('Complex Request Failed'));
        assert.ok(errorMessage.data.content[0].text.includes('Task failed'));
        
        assert.ok(streamError);
        assert.strictEqual(streamError.sessionId, 'test-session');
        assert.strictEqual(streamError.error, 'Task failed');
        
        // Should call push notification for error
        assert.strictEqual(mockPushNotificationService.sendClaudeResponseNotification.mock.calls.length, 1);
        done();
      }, 50);
    });
  });

  describe('sendLongRunningCompletionNotification', () => {
    beforeEach(() => {
      // Set up mock webSocket clients
      global.webSocketClients.set('client1', {
        sessionIds: new Set(['test-session']),
        deviceToken: 'token1'
      });
      
      global.webSocketClients.set('client2', {
        sessionIds: new Set(['test-session', 'other-session']),
        deviceToken: 'token2'
      });
      
      global.webSocketClients.set('client3', {
        sessionIds: new Set(['other-session']),
        deviceToken: 'token3'
      });
      
      global.webSocketClients.set('client4', {
        sessionIds: new Set(['test-session'])
        // No device token
      });
    });

    it('should send notifications to clients with matching session and device token', () => {
      taskManager.sendLongRunningCompletionNotification('test-session', 'Test prompt', false);
      
      // Should send to client1 and client2 (both have test-session and device tokens)
      assert.strictEqual(mockPushNotificationService.sendClaudeResponseNotification.mock.calls.length, 2);
      
      const calls = mockPushNotificationService.sendClaudeResponseNotification.mock.calls;
      const clientIds = calls.map(call => call.arguments[0]);
      assert.ok(clientIds.includes('client1'));
      assert.ok(clientIds.includes('client2'));
      assert.ok(!clientIds.includes('client3')); // Wrong session
      assert.ok(!clientIds.includes('client4')); // No device token
    });

    it('should send success notification with correct data', () => {
      taskManager.sendLongRunningCompletionNotification('test-session', 'Test prompt for completion', false);
      
      const call = mockPushNotificationService.sendClaudeResponseNotification.mock.calls[0];
      const [clientId, notificationData] = call.arguments;
      
      assert.strictEqual(notificationData.sessionId, 'test-session');
      assert.strictEqual(notificationData.projectName, 'test');
      assert.ok(notificationData.message.includes('Task completed'));
      assert.ok(notificationData.message.includes('Test prompt for completion'));
      assert.strictEqual(notificationData.isLongRunningCompletion, true);
    });

    it('should send error notification with correct data', () => {
      taskManager.sendLongRunningCompletionNotification(
        'test-session', 
        'Failing prompt', 
        true, 
        'Something went wrong'
      );
      
      const call = mockPushNotificationService.sendClaudeResponseNotification.mock.calls[0];
      const [clientId, notificationData] = call.arguments;
      
      assert.ok(notificationData.message.includes('Task failed'));
      assert.ok(notificationData.message.includes('Failing prompt'));
      assert.ok(notificationData.message.includes('Something went wrong'));
    });

    it('should extract project name from session ID', () => {
      taskManager.sendLongRunningCompletionNotification('my_project_uuid123', 'Test prompt', false);
      
      const call = mockPushNotificationService.sendClaudeResponseNotification.mock.calls[0];
      const [clientId, notificationData] = call.arguments;
      
      assert.strictEqual(notificationData.projectName, 'my_project');
    });

    it('should handle complex project names', () => {
      taskManager.sendLongRunningCompletionNotification('multi_word_project_name_uuid456', 'Test', false);
      
      const call = mockPushNotificationService.sendClaudeResponseNotification.mock.calls[0];
      const [clientId, notificationData] = call.arguments;
      
      assert.strictEqual(notificationData.projectName, 'multi_word_project_name');
    });

    it('should handle no webSocket clients gracefully', () => {
      global.webSocketClients = null;
      
      assert.doesNotThrow(() => {
        taskManager.sendLongRunningCompletionNotification('test-session', 'Test prompt', false);
      });
      
      assert.strictEqual(mockPushNotificationService.sendClaudeResponseNotification.mock.calls.length, 0);
    });
  });

  describe('utility methods', () => {
    describe('isLongRunningCommand', () => {
      it('should return true for long commands', () => {
        mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000);
        
        const result = taskManager.isLongRunningCommand('Complex prompt');
        assert.strictEqual(result, true);
        assert.strictEqual(mockAICLIConfig.calculateTimeoutForCommand.mock.calls.length, 1);
      });

      it('should return false for short commands', () => {
        mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 30000);
        
        const result = taskManager.isLongRunningCommand('Simple prompt');
        assert.strictEqual(result, false);
      });
    });

    describe('getEstimatedCompletionTime', () => {
      it('should return time in minutes', () => {
        mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 600000); // 10 minutes
        
        const result = taskManager.getEstimatedCompletionTime('Test prompt');
        assert.strictEqual(result, 10);
      });

      it('should round to nearest minute', () => {
        mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 330000); // 5.5 minutes
        
        const result = taskManager.getEstimatedCompletionTime('Test prompt');
        assert.strictEqual(result, 6); // Rounded up
      });

      it('should handle partial minutes', () => {
        mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 90000); // 1.5 minutes
        
        const result = taskManager.getEstimatedCompletionTime('Test prompt');
        assert.strictEqual(result, 2); // Rounded up
      });
    });
  });

  describe('event handling', () => {
    it('should emit assistantMessage events', (done) => {
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000);
      
      const mockExecuteFunction = mock.fn(() => Promise.resolve({ result: 'test' }));
      
      let eventCount = 0;
      taskManager.on('assistantMessage', (message) => {
        eventCount++;
        assert.ok(message.sessionId);
        assert.ok(message.data);
        
        if (eventCount === 1) {
          // First event should be the initial status
          assert.strictEqual(message.isComplete, false);
          done();
        }
      });
      
      taskManager.handlePotentialLongRunningTask('test-session', 'Long prompt', mockExecuteFunction);
    });

    it('should emit streamError events on failure', (done) => {
      const mockExecuteFunction = mock.fn(() => Promise.reject(new Error('Test error')));
      
      taskManager.on('streamError', (error) => {
        assert.strictEqual(error.sessionId, 'test-session');
        assert.strictEqual(error.error, 'Test error');
        done();
      });
      
      taskManager.runLongRunningProcess('test-session', 'Test prompt', mockExecuteFunction, 400000);
    });
  });
});