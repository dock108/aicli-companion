import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { WebSocketMessageHandlers } from '../../services/websocket-message-handlers.js';
import { WebSocketUtilities } from '../../services/websocket-utilities.js';
import { pushNotificationService } from '../../services/push-notification.js';
import { messageQueueService } from '../../services/message-queue.js';
import fs from 'fs';
import path from 'path';

// Store original methods for restoration
const originalSendMessage = WebSocketUtilities.sendMessage;
const originalSendErrorMessage = WebSocketUtilities.sendErrorMessage;
const originalCreateResponse = WebSocketUtilities.createResponse;
const originalRegisterDevice = pushNotificationService.registerDevice;
const originalGetQueuedMessages = messageQueueService.getQueuedMessages;
const originalMarkMessagesDelivered = messageQueueService.markMessagesDelivered;
const originalExistsSync = fs.existsSync;
const originalStatSync = fs.statSync;
const originalResolve = path.resolve;

describe('WebSocketMessageHandlers', () => {
  let mockAicliService;
  let mockClients;
  let mockConnectionManager;

  beforeEach(() => {
    // Mock WebSocketUtilities methods
    WebSocketUtilities.sendMessage = mock.fn((clientId, message, clients) => {
      const client = clients.get(clientId);
      return client && client.ws.readyState === 1;
    });
    WebSocketUtilities.sendErrorMessage = mock.fn();
    WebSocketUtilities.createResponse = mock.fn((type, requestId, data) => ({
      type,
      requestId,
      data,
    }));

    // Mock push notification service
    pushNotificationService.registerDevice = mock.fn();

    // Mock message queue service
    messageQueueService.getQueuedMessages = mock.fn(() => []);
    messageQueueService.markMessagesDelivered = mock.fn();

    // Mock fs and path modules
    fs.existsSync = mock.fn(() => true);
    fs.statSync = mock.fn(() => ({ isDirectory: () => true }));
    path.resolve = mock.fn((p) => `/resolved${p}`);

    // Mock AICLI service
    mockAicliService = {
      sendPrompt: mock.fn(() => Promise.resolve({ result: 'test response' })),
      createInteractiveSession: mock.fn(() =>
        Promise.resolve({
          success: true,
          sessionId: 'session123',
          message: 'Session created',
        })
      ),
      sendToExistingSession: mock.fn(() =>
        Promise.resolve({
          success: true,
          message: 'Message sent',
        })
      ),
      closeSession: mock.fn(() =>
        Promise.resolve({
          success: true,
          message: 'Session closed',
        })
      ),
      handlePermissionPrompt: mock.fn(() =>
        Promise.resolve({
          accepted: true,
          message: 'Permission granted',
        })
      ),
      healthCheck: mock.fn(() => Promise.resolve({ status: 'healthy' })),
      getActiveSessions: mock.fn(() => ['session1', 'session2']),
      testAICLICommand: mock.fn(() => Promise.resolve({ version: '1.0.0' })),
    };

    // Mock clients
    mockClients = new Map();
    mockClients.set('client1', {
      ws: { readyState: 1 },
      lastActivity: new Date(),
    });

    // Mock connection manager
    mockConnectionManager = {
      addSessionToClient: mock.fn(),
      removeSessionFromClient: mock.fn(),
      subscribeClient: mock.fn(),
    };
  });

  afterEach(() => {
    // Restore original methods
    WebSocketUtilities.sendMessage = originalSendMessage;
    WebSocketUtilities.sendErrorMessage = originalSendErrorMessage;
    WebSocketUtilities.createResponse = originalCreateResponse;
    pushNotificationService.registerDevice = originalRegisterDevice;
    messageQueueService.getQueuedMessages = originalGetQueuedMessages;
    messageQueueService.markMessagesDelivered = originalMarkMessagesDelivered;
    fs.existsSync = originalExistsSync;
    fs.statSync = originalStatSync;
    path.resolve = originalResolve;
  });

  describe('handleAskMessage', () => {
    it('should handle successful ask request', async () => {
      const data = {
        prompt: 'Test prompt',
        workingDirectory: '/test/dir',
        options: { format: 'json' },
      };

      await WebSocketMessageHandlers.handleAskMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(mockAicliService.sendPrompt.mock.calls.length, 1);
      assert.strictEqual(mockAicliService.sendPrompt.mock.calls[0].arguments[0], 'Test prompt');

      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
    });

    it('should handle ask request failure', async () => {
      mockAicliService.sendPrompt.mock.mockImplementation(() => {
        throw new Error('Ask failed');
      });

      const data = { prompt: 'Test prompt' };

      await WebSocketMessageHandlers.handleAskMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'ASK_FAILED');
      assert.strictEqual(errorCall.arguments[3], 'Ask failed');
    });
  });

  describe('handleStreamStartMessage', () => {
    it('should handle successful stream start', async () => {
      const data = {
        sessionId: 'session123',
        initialPrompt: 'Initial prompt',
        workingDirectory: '/test/dir',
      };

      await WebSocketMessageHandlers.handleStreamStartMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(mockAicliService.createInteractiveSession.mock.calls.length, 1);
      assert.strictEqual(mockConnectionManager.addSessionToClient.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
      assert.strictEqual(response.data.sessionId, 'session123');
    });

    it('should deliver queued messages on stream start', async () => {
      const queuedMessages = [
        { type: 'test', data: 'message1' },
        { type: 'test', data: 'message2' },
      ];

      messageQueueService.getQueuedMessages.mock.mockImplementation(() => queuedMessages);

      const data = { sessionId: 'session123', initialPrompt: 'test' };

      await WebSocketMessageHandlers.handleStreamStartMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      // Should send initial response + queued messages
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 3);
      assert.strictEqual(messageQueueService.markMessagesDelivered.mock.calls.length, 1);
    });

    it('should handle stream start failure', async () => {
      mockAicliService.createInteractiveSession.mock.mockImplementation(() =>
        Promise.resolve({ success: false, message: 'Session creation failed' })
      );

      const data = { sessionId: 'session123', initialPrompt: 'test' };

      await WebSocketMessageHandlers.handleStreamStartMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      assert.strictEqual(mockConnectionManager.addSessionToClient.mock.calls.length, 0);
    });
  });

  describe('handleStreamSendMessage', () => {
    it('should handle successful stream send', async () => {
      const data = {
        sessionId: 'session123',
        prompt: 'Test message',
      };

      await WebSocketMessageHandlers.handleStreamSendMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(mockAicliService.sendToExistingSession.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
      assert.strictEqual(response.data.sessionId, 'session123');
    });

    it('should handle stream send failure', async () => {
      mockAicliService.sendToExistingSession.mock.mockImplementation(() => {
        throw new Error('Send failed');
      });

      const data = { sessionId: 'session123', prompt: 'test' };

      await WebSocketMessageHandlers.handleStreamSendMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'STREAM_SEND_FAILED');
    });
  });

  describe('handleStreamCloseMessage', () => {
    it('should handle successful stream close', async () => {
      const data = { sessionId: 'session123' };

      await WebSocketMessageHandlers.handleStreamCloseMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(mockAicliService.closeSession.mock.calls.length, 1);
      assert.strictEqual(mockConnectionManager.removeSessionFromClient.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
    });

    it('should handle stream close failure', async () => {
      mockAicliService.closeSession.mock.mockImplementation(() => {
        throw new Error('Close failed');
      });

      const data = { sessionId: 'session123' };

      await WebSocketMessageHandlers.handleStreamCloseMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
    });
  });

  describe('handlePermissionMessage', () => {
    it('should handle permission response', async () => {
      const data = {
        sessionId: 'session123',
        response: 'accept',
      };

      await WebSocketMessageHandlers.handlePermissionMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(mockAicliService.handlePermissionPrompt.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
      assert.strictEqual(response.data.accepted, true);
    });

    it('should handle permission failure', async () => {
      mockAicliService.handlePermissionPrompt.mock.mockImplementation(() => {
        throw new Error('Permission failed');
      });

      const data = { sessionId: 'session123', response: 'accept' };

      await WebSocketMessageHandlers.handlePermissionMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
    });
  });

  describe('handlePingMessage', () => {
    it('should respond to ping with pong', () => {
      const data = { timestamp: '2023-01-01T00:00:00Z' };

      WebSocketMessageHandlers.handlePingMessage('client1', 'req123', data, mockClients);

      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.clientTimestamp, '2023-01-01T00:00:00Z');
      assert.ok(response.data.serverTimestamp);
    });

    it('should handle ping without timestamp', () => {
      WebSocketMessageHandlers.handlePingMessage('client1', 'req123', null, mockClients);

      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
    });
  });

  describe('handleSubscribeMessage', () => {
    it('should handle event subscription', () => {
      const data = { events: ['event1', 'event2'] };

      WebSocketMessageHandlers.handleSubscribeMessage(
        'client1',
        'req123',
        data,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(mockConnectionManager.subscribeClient.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
      assert.deepStrictEqual(response.data.subscribedEvents, ['event1', 'event2']);
    });

    it('should handle invalid events array', () => {
      const data = { events: 'not-an-array' };

      WebSocketMessageHandlers.handleSubscribeMessage(
        'client1',
        'req123',
        data,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'SUBSCRIPTION_FAILED');
      assert.ok(errorCall.arguments[3].includes('must be an array'));
    });
  });

  describe('handleSetWorkingDirectoryMessage', () => {
    it('should set valid working directory', async () => {
      const data = { workingDirectory: '/test/dir' };

      await WebSocketMessageHandlers.handleSetWorkingDirectoryMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(fs.existsSync.mock.calls.length, 1);
      assert.strictEqual(fs.statSync.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
      assert.strictEqual(response.data.workingDirectory, '/resolved/test/dir');
    });

    it('should handle non-existent directory', async () => {
      fs.existsSync.mock.mockImplementation(() => false);

      const data = { workingDirectory: '/nonexistent' };

      await WebSocketMessageHandlers.handleSetWorkingDirectoryMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.strictEqual(errorCall.arguments[2], 'SET_DIRECTORY_FAILED');
      assert.ok(errorCall.arguments[3].includes('does not exist'));
    });

    it('should handle non-directory path', async () => {
      fs.statSync.mock.mockImplementation(() => ({ isDirectory: () => false }));

      const data = { workingDirectory: '/test/file.txt' };

      await WebSocketMessageHandlers.handleSetWorkingDirectoryMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.ok(errorCall.arguments[3].includes('not a directory'));
    });
  });

  describe('handleAICLICommandMessage', () => {
    it('should handle status command', async () => {
      const data = {
        sessionId: 'session123',
        command: 'status',
        args: [],
      };

      await WebSocketMessageHandlers.handleAICLICommandMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(mockAicliService.healthCheck.mock.calls.length, 1);
      assert.strictEqual(mockConnectionManager.addSessionToClient.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
    });

    it('should handle sessions command', async () => {
      const data = { command: 'sessions' };

      await WebSocketMessageHandlers.handleAICLICommandMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(mockAicliService.getActiveSessions.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
    });

    it('should handle test command', async () => {
      const data = { command: 'test', args: ['version'] };

      await WebSocketMessageHandlers.handleAICLICommandMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(mockAicliService.testAICLICommand.mock.calls.length, 1);
      assert.strictEqual(mockAicliService.testAICLICommand.mock.calls[0].arguments[0], 'version');
    });

    it('should handle unknown command', async () => {
      const data = { command: 'unknown' };

      await WebSocketMessageHandlers.handleAICLICommandMessage(
        'client1',
        'req123',
        data,
        mockAicliService,
        mockClients,
        mockConnectionManager
      );

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
      const errorCall = WebSocketUtilities.sendErrorMessage.mock.calls[0];
      assert.ok(errorCall.arguments[3].includes('Unknown command'));
    });
  });

  describe('handleClientBackgroundingMessage', () => {
    it('should handle client backgrounding', () => {
      const data = { isBackgrounding: true };

      WebSocketMessageHandlers.handleClientBackgroundingMessage(
        'client1',
        'req123',
        data,
        mockClients
      );

      const client = mockClients.get('client1');
      assert.strictEqual(client.isBackgrounded, true);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
      assert.strictEqual(response.data.isBackgrounding, true);
    });

    it('should handle client foregrounding', () => {
      const data = { isBackgrounding: false };

      WebSocketMessageHandlers.handleClientBackgroundingMessage(
        'client1',
        'req123',
        data,
        mockClients
      );

      const client = mockClients.get('client1');
      assert.strictEqual(client.isBackgrounded, false);
    });

    it('should handle non-existent client gracefully', () => {
      const data = { isBackgrounding: true };

      WebSocketMessageHandlers.handleClientBackgroundingMessage(
        'nonexistent',
        'req123',
        data,
        mockClients
      );

      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
    });
  });

  describe('handleRegisterDeviceMessage', () => {
    it('should register device successfully', () => {
      const data = {
        deviceToken: 'device-token-12345',
        deviceInfo: { platform: 'iOS', version: '15.0' },
      };

      WebSocketMessageHandlers.handleRegisterDeviceMessage('client1', 'req123', data, mockClients);

      const client = mockClients.get('client1');
      assert.strictEqual(client.deviceToken, 'device-token-12345');
      assert.deepStrictEqual(client.deviceInfo, { platform: 'iOS', version: '15.0' });

      assert.strictEqual(pushNotificationService.registerDevice.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);

      const response = WebSocketUtilities.sendMessage.mock.calls[0].arguments[1];
      assert.strictEqual(response.data.success, true);
    });

    it('should handle registration failure', () => {
      pushNotificationService.registerDevice.mock.mockImplementation(() => {
        throw new Error('Registration failed');
      });

      const data = { deviceToken: 'token', deviceInfo: {} };

      WebSocketMessageHandlers.handleRegisterDeviceMessage('client1', 'req123', data, mockClients);

      assert.strictEqual(WebSocketUtilities.sendErrorMessage.mock.calls.length, 1);
    });

    it('should handle non-existent client', () => {
      const data = { deviceToken: 'token', deviceInfo: {} };

      WebSocketMessageHandlers.handleRegisterDeviceMessage(
        'nonexistent',
        'req123',
        data,
        mockClients
      );

      // Should still try to register with push service
      assert.strictEqual(pushNotificationService.registerDevice.mock.calls.length, 1);
      assert.strictEqual(WebSocketUtilities.sendMessage.mock.calls.length, 1);
    });
  });

  describe('utility methods', () => {
    describe('getAllHandlers', () => {
      it('should return all handlers', () => {
        const handlers = WebSocketMessageHandlers.getAllHandlers();

        assert.ok(typeof handlers.ask === 'function');
        assert.ok(typeof handlers.streamStart === 'function');
        assert.ok(typeof handlers.streamSend === 'function');
        assert.ok(typeof handlers.streamClose === 'function');
        assert.ok(typeof handlers.permission === 'function');
        assert.ok(typeof handlers.ping === 'function');
        assert.ok(typeof handlers.subscribe === 'function');
        assert.ok(typeof handlers.setWorkingDirectory === 'function');
        assert.ok(typeof handlers.aicliCommand === 'function');
        assert.ok(typeof handlers.client_backgrounding === 'function');
        assert.ok(typeof handlers.registerDevice === 'function');
      });
    });

    describe('getHandler', () => {
      it('should return specific handler', () => {
        const handler = WebSocketMessageHandlers.getHandler('ping');
        assert.strictEqual(handler, WebSocketMessageHandlers.handlePingMessage);
      });

      it('should return null for unknown handler', () => {
        const handler = WebSocketMessageHandlers.getHandler('unknown');
        assert.strictEqual(handler, null);
      });
    });

    describe('getSupportedTypes', () => {
      it('should return list of supported message types', () => {
        const types = WebSocketMessageHandlers.getSupportedTypes();

        assert.ok(Array.isArray(types));
        assert.ok(types.includes('ask'));
        assert.ok(types.includes('streamStart'));
        assert.ok(types.includes('ping'));
        assert.ok(types.includes('subscribe'));
        assert.strictEqual(types.length, 11);
      });
    });
  });
});
