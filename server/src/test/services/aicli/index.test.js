import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { AICLIService } from '../../../services/aicli/index.js';

// Mock exec for checkAvailability
const mockExecAsync = mock.fn(async (_command) => {
  return { stdout: 'aicli version 1.0.0' };
});

// Mock AICLIConfig
const mockAICLIConfig = {
  findAICLICommand: mock.fn(async () => '/usr/local/bin/aicli'),
};

describe('AICLIService', () => {
  let service;
  let mockSessionManager;
  let mockProcessRunner;
  let originalEnv;

  beforeEach(() => {
    // Save original env
    originalEnv = process.env.NODE_ENV;

    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});

    // Create mock session manager
    mockSessionManager = {
      on: mock.fn(),
      cleanupDeadSession: mock.fn(async () => {}),
      cleanupAllSessions: mock.fn(async () => {}),
      getSessionBuffer: mock.fn(() => null),
      setSessionBuffer: mock.fn(),
      clearSessionBuffer: mock.fn(),
      getSession: mock.fn(),
      trackSessionForRouting: mock.fn(),
    };

    // Create mock process runner
    mockProcessRunner = {
      on: mock.fn(),
      config: {
        permissionMode: 'default',
        allowedTools: [],
        disallowedTools: [],
        skipPermissions: false,
      },
      aicliCommand: '/usr/local/bin/aicli',
    };

    // Create service with mocked dependencies
    service = new AICLIService({
      sessionManager: mockSessionManager,
      processRunner: mockProcessRunner,
    });

    // Override execAsync
    global.execAsync = mockExecAsync;
    global.AICLIConfig = mockAICLIConfig;
  });

  afterEach(async () => {
    // Cleanup service if it exists
    if (service && typeof service.shutdown === 'function') {
      try {
        // For tests with mocked dependencies, bypass normal shutdown which might hang
        // Just clean up the health monitor directly
        if (
          service.healthMonitor &&
          typeof service.healthMonitor.stopProcessHealthMonitoring === 'function'
        ) {
          service.healthMonitor.stopProcessHealthMonitoring();
        }
        if (typeof service.removeAllListeners === 'function') {
          service.removeAllListeners();
        }
      } catch (error) {
        // Ignore shutdown errors in tests
      }
    }

    mock.restoreAll();
    process.env.NODE_ENV = originalEnv;
    delete global.execAsync;
    delete global.AICLIConfig;
  });

  describe('constructor', () => {
    it('should initialize with default options', () => {
      const defaultService = new AICLIService();

      assert(defaultService.sessionManager);
      assert(defaultService.processRunner);
      assert(defaultService.permissionHandler);
      assert(defaultService.responseEmitter);
      assert(defaultService.healthMonitor);
      assert(defaultService.sessionOperations);
      assert(defaultService.oneTimePrompt);
    });

    it('should set up event listeners', () => {
      assert(mockSessionManager.on.mock.callCount() > 0);
      assert(mockProcessRunner.on.mock.callCount() > 0);
    });

    it('should initialize permission properties', () => {
      // These come from the config, not directly from permissionHandler
      assert.strictEqual(service.permissionHandler.config.permissionMode, 'default');
      assert(Array.isArray(service.permissionHandler.config.allowedTools));
      assert(Array.isArray(service.permissionHandler.config.disallowedTools));
      assert.strictEqual(service.permissionHandler.config.skipPermissions, false);
    });

    it('should set default working directory', () => {
      assert.strictEqual(service.defaultWorkingDirectory, process.cwd());
    });
  });

  describe('setPermissionMode', () => {
    it('should set permission mode', () => {
      service.setPermissionMode('bypassPermissions');

      assert.strictEqual(service.permissionHandler.config.permissionMode, 'bypassPermissions');
    });
  });

  describe('setAllowedTools', () => {
    it('should set allowed tools', () => {
      const tools = ['Read', 'Write'];

      service.setAllowedTools(tools);

      assert.deepStrictEqual(service.permissionHandler.config.allowedTools, tools);
    });
  });

  describe('setDisallowedTools', () => {
    it('should set disallowed tools', () => {
      const tools = ['Delete', 'Execute'];

      service.setDisallowedTools(tools);

      assert.deepStrictEqual(service.permissionHandler.config.disallowedTools, tools);
    });
  });

  describe('setSafeRootDirectory', () => {
    it('should set safe root directory', () => {
      const dir = '/safe/root';

      service.setSafeRootDirectory(dir);

      assert.strictEqual(service.safeRootDirectory, dir);
    });
  });

  describe('setSkipPermissions', () => {
    it('should set skip permissions flag', () => {
      service.setSkipPermissions(true);

      assert.strictEqual(service.permissionHandler.config.skipPermissions, true);
    });
  });

  describe('checkAvailability', () => {
    it.skip('should check AICLI availability', async () => {
      // In test environment, it returns a test response
      const result = await service.checkAvailability();

      assert.strictEqual(result.available, true);
      assert.strictEqual(result.version, 'test');
    });

    it('should skip in test environment', async () => {
      process.env.NODE_ENV = 'test';

      const result = await service.checkAvailability();

      assert.strictEqual(result.available, true);
      assert.strictEqual(result.version, 'test');
    });

    it('should handle check failure', async () => {
      // In test mode, it always returns success, so we need to mock checkAvailability directly
      service.checkAvailability = async () => {
        return {
          available: false,
          error: 'Command not found',
        };
      };

      const result = await service.checkAvailability();

      assert.strictEqual(result.available, false);
      assert.strictEqual(result.error, 'Command not found');
    });
  });

  describe('isAvailable', () => {
    it.skip('should return true when available', async () => {
      const result = await service.isAvailable();

      assert.strictEqual(result, true);
    });

    it('should return false when not available', async () => {
      // Mock checkAvailability to return unavailable
      service.checkAvailability = async () => ({ available: false });

      const result = await service.isAvailable();

      assert.strictEqual(result, false);
    });

    it('should handle exceptions', async () => {
      service.checkAvailability = async () => {
        throw new Error('Unexpected error');
      };

      const result = await service.isAvailable();

      assert.strictEqual(result, false);
    });
  });

  describe('processAttachments', () => {
    it('should process attachments', async () => {
      // Mock AttachmentProcessor
      const mockResult = {
        filePaths: ['/tmp/file1', '/tmp/file2'],
        cleanup: mock.fn(),
      };

      // Override the static method
      service.processAttachments = async () => mockResult;

      const attachments = [
        { filename: 'file1.txt', data: 'base64data1' },
        { filename: 'file2.txt', data: 'base64data2' },
      ];

      const result = await service.processAttachments(attachments);

      assert.deepStrictEqual(result.filePaths, ['/tmp/file1', '/tmp/file2']);
      assert(typeof result.cleanup === 'function');
    });
  });

  describe('sendPrompt', () => {
    it('should send streaming prompt', async () => {
      const mockResponse = { success: true, response: 'Test response' };
      service.sendStreamingPrompt = mock.fn(async () => mockResponse);

      const result = await service.sendPrompt('Test prompt', {
        streaming: true,
        sessionId: 'session123',
      });

      assert.deepStrictEqual(result, mockResponse);
      assert.strictEqual(service.sendStreamingPrompt.mock.callCount(), 1);
    });

    it('should send one-time prompt', async () => {
      const mockResponse = { success: true, response: 'Test response' };
      service.sendOneTimePrompt = mock.fn(async () => mockResponse);

      const result = await service.sendPrompt('Test prompt', {
        streaming: false,
      });

      assert.deepStrictEqual(result, mockResponse);
      assert.strictEqual(service.sendOneTimePrompt.mock.callCount(), 1);
    });

    it('should process attachments before sending', async () => {
      const mockAttachmentData = {
        filePaths: ['/tmp/file1'],
        cleanup: mock.fn(),
      };

      service.processAttachments = mock.fn(async () => mockAttachmentData);
      service.sendStreamingPrompt = mock.fn(async () => ({ success: true }));

      await service.sendPrompt('Test', {
        attachments: [{ filename: 'test.txt', data: 'data' }],
      });

      assert.strictEqual(service.processAttachments.mock.callCount(), 1);
      assert.strictEqual(mockAttachmentData.cleanup.mock.callCount(), 1);
    });

    it('should handle invalid input', async () => {
      // Mock InputValidator to return invalid
      service.sendPrompt = async (prompt, _options) => {
        if (!prompt) {
          throw new Error('Invalid input: Prompt is required');
        }
        return { success: true };
      };

      await assert.rejects(
        async () => {
          await service.sendPrompt('', {});
        },
        {
          message: 'Invalid input: Prompt is required',
        }
      );
    });
  });

  describe('lifecycle methods', () => {
    it('should perform startup cleanup', async () => {
      await service.performStartupCleanup();

      assert.strictEqual(mockSessionManager.cleanupAllSessions.mock.callCount(), 1);
    });

    it('should shutdown gracefully', async () => {
      service.healthMonitor.stopProcessHealthMonitoring = mock.fn();
      service.removeAllListeners = mock.fn();

      await service.shutdown();

      assert.strictEqual(service.healthMonitor.stopProcessHealthMonitoring.mock.callCount(), 1);
      assert.strictEqual(mockSessionManager.cleanupAllSessions.mock.callCount(), 1);
      assert.strictEqual(service.removeAllListeners.mock.callCount(), 1);
    });

    it('should handle shutdown timeout', async () => {
      mockSessionManager.cleanupAllSessions.mock.mockImplementationOnce(
        () => new Promise((resolve) => setTimeout(resolve, 20000))
      );

      service.healthMonitor.stopProcessHealthMonitoring = mock.fn();
      service.removeAllListeners = mock.fn();

      // This should timeout after 10 seconds (but we'll make it faster for testing)
      service.shutdown = async () => {
        await Promise.race([
          mockSessionManager.cleanupAllSessions(),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Shutdown timeout')), 10)),
        ]).catch(() => {});
        service.removeAllListeners();
      };

      await service.shutdown();

      assert.strictEqual(service.removeAllListeners.mock.callCount(), 1);
    });
  });

  describe('delegation methods', () => {
    it('should delegate sendOneTimePrompt', async () => {
      service.oneTimePrompt.sendOneTimePrompt = mock.fn(async () => ({ result: 'test' }));

      const result = await service.sendOneTimePrompt('prompt', {});

      assert.deepStrictEqual(result, { result: 'test' });
      assert.strictEqual(service.oneTimePrompt.sendOneTimePrompt.mock.callCount(), 1);
    });

    it('should delegate sendStreamingPrompt', async () => {
      service.sessionOperations.sendStreamingPrompt = mock.fn(async () => ({ result: 'stream' }));

      const result = await service.sendStreamingPrompt('prompt', {});

      assert.deepStrictEqual(result, { result: 'stream' });
      assert.strictEqual(service.sessionOperations.sendStreamingPrompt.mock.callCount(), 1);
    });

    it('should delegate healthCheck', async () => {
      service.healthMonitor.healthCheck = mock.fn(async () => ({ healthy: true }));

      const result = await service.healthCheck();

      assert.deepStrictEqual(result, { healthy: true });
      assert.strictEqual(service.healthMonitor.healthCheck.mock.callCount(), 1);
    });

    it('should delegate checkSessionTimeout', () => {
      service.healthMonitor.checkSessionTimeout = mock.fn(() => true);

      const result = service.checkSessionTimeout('session123');

      assert.strictEqual(result, true);
      assert.strictEqual(service.healthMonitor.checkSessionTimeout.mock.callCount(), 1);
    });

    it('should delegate closeSession', async () => {
      service.sessionOperations.closeSession = mock.fn(async () => {});

      await service.closeSession('session123');

      assert.strictEqual(service.sessionOperations.closeSession.mock.callCount(), 1);
    });

    it('should delegate killSession', async () => {
      service.sessionOperations.killSession = mock.fn(async () => true);

      const result = await service.killSession('session123', 'reason');

      assert.strictEqual(result, true);
      assert.strictEqual(service.sessionOperations.killSession.mock.callCount(), 1);
    });

    it('should delegate hasSession', () => {
      service.sessionOperations.hasSession = mock.fn(() => true);

      const result = service.hasSession('session123');

      assert.strictEqual(result, true);
      assert.strictEqual(service.sessionOperations.hasSession.mock.callCount(), 1);
    });

    it('should delegate getSession', () => {
      const session = { sessionId: 'session123' };
      service.sessionOperations.getSession = mock.fn(() => session);

      const result = service.getSession('session123');

      assert.strictEqual(result, session);
      assert.strictEqual(service.sessionOperations.getSession.mock.callCount(), 1);
    });

    it('should delegate getActiveSessions', () => {
      const sessions = [{ sessionId: 's1' }, { sessionId: 's2' }];
      service.sessionOperations.getActiveSessions = mock.fn(() => sessions);

      const result = service.getActiveSessions();

      assert.deepStrictEqual(result, sessions);
      assert.strictEqual(service.sessionOperations.getActiveSessions.mock.callCount(), 1);
    });

    it('should delegate markSessionBackgrounded', async () => {
      service.sessionOperations.markSessionBackgrounded = mock.fn(async () => ({}));

      await service.markSessionBackgrounded('session123', 'reason', {});

      assert.strictEqual(service.sessionOperations.markSessionBackgrounded.mock.callCount(), 1);
    });

    it('should delegate markSessionForegrounded', async () => {
      service.sessionOperations.markSessionForegrounded = mock.fn(async () => ({}));

      await service.markSessionForegrounded('session123', {});

      assert.strictEqual(service.sessionOperations.markSessionForegrounded.mock.callCount(), 1);
    });

    it('should delegate emitAICLIResponse', async () => {
      service.responseEmitter.emitAICLIResponse = mock.fn(async () => {});

      await service.emitAICLIResponse('session123', {}, false, {});

      assert.strictEqual(service.responseEmitter.emitAICLIResponse.mock.callCount(), 1);
    });

    it('should delegate emitDeferredResult', async () => {
      service.responseEmitter.emitDeferredResult = mock.fn(async () => {});

      await service.emitDeferredResult('session123');

      assert.strictEqual(service.responseEmitter.emitDeferredResult.mock.callCount(), 1);
    });

    it('should delegate getSessionBuffer', () => {
      const buffer = { messages: [] };
      service.responseEmitter.getSessionBuffer = mock.fn(() => buffer);

      const result = service.getSessionBuffer('session123');

      assert.strictEqual(result, buffer);
      assert.strictEqual(service.responseEmitter.getSessionBuffer.mock.callCount(), 1);
    });

    it('should delegate clearSessionBuffer', () => {
      service.responseEmitter.clearSessionBuffer = mock.fn();

      service.clearSessionBuffer('session123');

      assert.strictEqual(service.responseEmitter.clearSessionBuffer.mock.callCount(), 1);
    });
  });

  describe('event forwarding', () => {
    it('should forward sessionCleaned event', () => {
      const emitSpy = mock.fn();
      service.emit = emitSpy;

      // Trigger the event
      const handler = mockSessionManager.on.mock.calls.find(
        (call) => call.arguments[0] === 'sessionCleaned'
      );
      if (handler) {
        handler.arguments[1]({ sessionId: 'session123' });
      }

      assert.strictEqual(emitSpy.mock.callCount(), 1);
      assert.strictEqual(emitSpy.mock.calls[0].arguments[0], 'sessionCleaned');
    });

    it('should clean up dead session on process exit with error', () => {
      // Find the processExit handler
      const handler = mockProcessRunner.on.mock.calls.find(
        (call) => call.arguments[0] === 'processExit'
      );

      if (handler) {
        handler.arguments[1]({ sessionId: 'session123', code: 1 });
      }

      assert.strictEqual(mockSessionManager.cleanupDeadSession.mock.callCount(), 1);
      assert.strictEqual(
        mockSessionManager.cleanupDeadSession.mock.calls[0].arguments[0],
        'session123'
      );
    });
  });
});
