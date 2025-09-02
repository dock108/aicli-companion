import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { AICLIService } from '../../../services/aicli/index.js';

describe('AICLIService Integration Tests', () => {
  let aicliService;
  let mockSessionManager;
  let mockProcessRunner;

  beforeEach(() => {
    // Create mock session manager
    mockSessionManager = {
      activeSessions: new Map(),
      sessionTimeout: 24 * 60 * 60 * 1000,
      hasSession: mock.fn((id) => mockSessionManager.activeSessions.has(id)),
      getSession: mock.fn((id) => mockSessionManager.activeSessions.get(id)),
      removeSession: mock.fn((id) => mockSessionManager.activeSessions.delete(id)),
      getActiveSessions: mock.fn(() => Array.from(mockSessionManager.activeSessions.values())),
      cleanupDeadSession: mock.fn(),
      cleanupAllSessions: mock.fn(),
      createInteractiveSession: mock.fn(async (sessionId, prompt, workingDir, options) => {
        const session = {
          sessionId: sessionId || 'test-session',
          prompt,
          workingDirectory: workingDir,
          startTime: new Date().toISOString(),
          process: { pid: 12345 },
          ...options,
        };
        mockSessionManager.activeSessions.set(session.sessionId, session);
        return session;
      }),
      getSessionBuffer: mock.fn(),
      setSessionBuffer: mock.fn(),
      clearSessionBuffer: mock.fn(),
      trackSessionForRouting: mock.fn(),
      trackClaudeSessionActivity: mock.fn(),
      markSessionBackgrounded: mock.fn(),
      markSessionForegrounded: mock.fn(),
      on: mock.fn(),
      removeAllListeners: mock.fn(),
    };

    // Create mock process runner
    mockProcessRunner = {
      aicliCommand: 'claude',
      permissionMode: 'default',
      allowedTools: [],
      disallowedTools: [],
      skipPermissions: false,
      setPermissionMode: mock.fn((mode) => {
        mockProcessRunner.permissionMode = mode;
      }),
      setAllowedTools: mock.fn((tools) => {
        mockProcessRunner.allowedTools = tools;
      }),
      setDisallowedTools: mock.fn((tools) => {
        mockProcessRunner.disallowedTools = tools;
      }),
      setSkipPermissions: mock.fn((skip) => {
        mockProcessRunner.skipPermissions = skip;
      }),
      executeAICLICommand: mock.fn(async (session, prompt) => ({
        success: true,
        response: { result: 'Test response' },
        claudeSessionId: session.sessionId,
      })),
      sendToInteractiveSession: mock.fn(async (session, prompt) => ({
        success: true,
        response: 'Interactive response',
      })),
      killProcess: mock.fn(),
      on: mock.fn(),
      removeAllListeners: mock.fn(),
    };

    // Create service with mocked dependencies
    aicliService = new AICLIService({
      sessionManager: mockSessionManager,
      processRunner: mockProcessRunner,
    });

    // Set NODE_ENV to test to avoid timers
    process.env.NODE_ENV = 'test';
  });

  afterEach(() => {
    if (aicliService) {
      aicliService.removeAllListeners();
    }
  });

  describe('Constructor and Initialization', () => {
    it('should initialize with provided dependencies', () => {
      assert.ok(aicliService.sessionManager);
      assert.ok(aicliService.processRunner);
      assert.ok(aicliService.permissionHandler);
      assert.ok(aicliService.responseEmitter);
      assert.ok(aicliService.healthMonitor);
      assert.ok(aicliService.sessionOperations);
      assert.ok(aicliService.oneTimePrompt);
    });

    it('should forward events from session manager', () => {
      const listener = mock.fn();
      aicliService.on('sessionCleaned', listener);
      
      // Simulate event from session manager
      const sessionManagerOn = mockSessionManager.on.mock.calls[0];
      if (sessionManagerOn && sessionManagerOn.arguments[0] === 'sessionCleaned') {
        sessionManagerOn.arguments[1]({ sessionId: 'test' });
      }
      
      assert.equal(listener.mock.calls.length, 1);
    });
  });

  describe('Permission Configuration', () => {
    it('should delegate permission mode setting', () => {
      aicliService.setPermissionMode('strict');
      assert.equal(mockProcessRunner.setPermissionMode.mock.calls.length, 1);
      assert.equal(aicliService.permissionMode, 'strict');
    });

    it('should delegate allowed tools setting', () => {
      const tools = ['tool1', 'tool2'];
      aicliService.setAllowedTools(tools);
      assert.equal(mockProcessRunner.setAllowedTools.mock.calls.length, 1);
      assert.deepEqual(aicliService.allowedTools, tools);
    });

    it('should delegate disallowed tools setting', () => {
      const tools = ['danger1'];
      aicliService.setDisallowedTools(tools);
      assert.equal(mockProcessRunner.setDisallowedTools.mock.calls.length, 1);
      assert.deepEqual(aicliService.disallowedTools, tools);
    });

    it('should delegate skip permissions setting', () => {
      aicliService.setSkipPermissions(true);
      assert.equal(mockProcessRunner.setSkipPermissions.mock.calls.length, 1);
      assert.equal(aicliService.skipPermissions, true);
    });
  });

  describe('Message Classification', () => {
    it('should classify system messages', () => {
      const message = { type: 'system', content: 'test' };
      const result = aicliService.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'streamData');
      assert.equal(result.data.type, 'system');
    });

    it('should classify assistant messages', () => {
      const message = {
        type: 'assistant',
        message: { content: [{ type: 'text', text: 'Hello' }] },
      };
      const result = aicliService.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'assistantMessage');
    });

    it('should classify tool messages', () => {
      const message = {
        type: 'tool_use',
        tool_name: 'calculator',
        tool_id: '123',
      };
      const result = aicliService.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'toolUse');
    });
  });

  describe('Prompt Sending', () => {
    it('should send streaming prompt to new session', async () => {
      const result = await aicliService.sendPrompt('Test prompt', {
        streaming: true,
      });
      
      assert.equal(mockSessionManager.createInteractiveSession.mock.calls.length, 1);
      assert.equal(mockProcessRunner.executeAICLICommand.mock.calls.length, 1);
      assert.equal(result.success, true);
    });

    it('should send prompt to existing session', async () => {
      // Create a session first
      const session = {
        sessionId: 'existing-session',
        process: { pid: 12345 },
      };
      mockSessionManager.activeSessions.set('existing-session', session);
      
      const result = await aicliService.sendPrompt('Test prompt', {
        sessionId: 'existing-session',
        streaming: true,
      });
      
      assert.equal(mockProcessRunner.sendToInteractiveSession.mock.calls.length, 1);
      assert.equal(result.success, true);
    });

    it('should handle attachments', async () => {
      const attachments = [
        {
          name: 'test.txt',
          data: Buffer.from('test').toString('base64'),
        },
      ];
      
      const result = await aicliService.sendPrompt('Test prompt', {
        streaming: true,
        attachments,
      });
      
      assert.equal(result.success, true);
    });

    it('should validate input', async () => {
      await assert.rejects(
        aicliService.sendPrompt(null, { streaming: true }),
        /Invalid input/
      );
    });
  });

  describe('Session Management', () => {
    it('should check if session exists', () => {
      mockSessionManager.activeSessions.set('test-session', { sessionId: 'test-session' });
      assert.equal(aicliService.hasSession('test-session'), true);
      assert.equal(aicliService.hasSession('non-existent'), false);
    });

    it('should get session', () => {
      const session = { sessionId: 'test-session' };
      mockSessionManager.activeSessions.set('test-session', session);
      assert.equal(aicliService.getSession('test-session'), session);
    });

    it('should get active sessions', () => {
      const session1 = { sessionId: 'session1' };
      const session2 = { sessionId: 'session2' };
      mockSessionManager.activeSessions.set('session1', session1);
      mockSessionManager.activeSessions.set('session2', session2);
      
      const sessions = aicliService.getActiveSessions();
      assert.equal(sessions.length, 2);
    });

    it('should kill session', async () => {
      const session = { sessionId: 'test-session', process: { pid: 12345 } };
      mockSessionManager.activeSessions.set('test-session', session);
      
      const result = await aicliService.killSession('test-session');
      assert.equal(result, true);
      assert.equal(mockProcessRunner.killProcess.mock.calls.length, 1);
      assert.equal(mockSessionManager.removeSession.mock.calls.length, 1);
    });

    it('should handle killing non-existent session', async () => {
      const result = await aicliService.killSession('non-existent');
      assert.equal(result, false);
    });

    it('should close session', async () => {
      const session = { sessionId: 'test-session', process: { pid: 12345 } };
      mockSessionManager.activeSessions.set('test-session', session);
      
      await aicliService.closeSession('test-session');
      assert.equal(mockProcessRunner.killProcess.mock.calls.length, 1);
      assert.equal(mockSessionManager.removeSession.mock.calls.length, 1);
    });
  });

  describe('Health Monitoring', () => {
    it('should start process health monitoring', () => {
      const originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'production';
      
      aicliService.startProcessHealthMonitoring();
      assert.ok(aicliService.healthMonitor.processHealthCheckInterval);
      
      aicliService.stopProcessHealthMonitoring();
      process.env.NODE_ENV = originalEnv;
    });

    it('should check session timeout', () => {
      const session = {
        sessionId: 'test-session',
        lastActivity: new Date().toISOString(),
      };
      mockSessionManager.activeSessions.set('test-session', session);
      
      const result = aicliService.checkSessionTimeout('test-session');
      assert.equal(result.timedOut, false);
    });
  });

  describe('Lifecycle Management', () => {
    it('should perform startup cleanup', async () => {
      await aicliService.performStartupCleanup();
      assert.equal(mockSessionManager.cleanupAllSessions.mock.calls.length, 1);
    });

    it('should shutdown cleanly', async () => {
      await aicliService.shutdown();
      assert.equal(mockSessionManager.cleanupAllSessions.mock.calls.length, 1);
    });
  });

  describe('Utility Methods', () => {
    it('should extract text from messages', () => {
      const text = aicliService.extractTextFromMessage('test message');
      assert.equal(text, 'test message');
    });

    it.skip('should detect permission prompts', () => {
      assert.equal(
        aicliService.isPermissionPrompt({ type: 'permission_request' }),
        true
      );
      assert.equal(
        aicliService.isPermissionPrompt({ type: 'other' }),
        false
      );
    });

    it('should extract code blocks', () => {
      const content = '```js\ncode\n```';
      const blocks = aicliService.extractCodeBlocks(content);
      assert.equal(blocks.length, 1);
    });

    it('should check approval responses', () => {
      assert.equal(aicliService.containsApprovalResponse('yes'), true);
      assert.equal(aicliService.containsApprovalResponse('no'), false);
    });
  });
});