import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { SessionOperations } from '../../../services/aicli/session-operations.js';

describe('SessionOperations', () => {
  let sessionOperations;
  let mockSessionManager;
  let mockProcessRunner;
  let mockEventEmitter;
  let emittedEvents;

  beforeEach(() => {
    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});

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
      sessions: new Map(),

      getSession: mock.fn((sessionId) => {
        return mockSessionManager.sessions.get(sessionId);
      }),

      hasSession: mock.fn((sessionId) => {
        return mockSessionManager.sessions.has(sessionId);
      }),

      removeSession: mock.fn((sessionId) => {
        mockSessionManager.sessions.delete(sessionId);
      }),

      getActiveSessions: mock.fn(() => {
        return Array.from(mockSessionManager.sessions.values());
      }),

      trackSessionForRouting: mock.fn(async (sessionId, workingDirectory) => {
        // Mock implementation
      }),

      trackClaudeSessionActivity: mock.fn((sessionId) => {
        // Mock implementation
      }),

      markSessionBackgrounded: mock.fn(async (sessionId, reason, metadata) => {
        const session = mockSessionManager.sessions.get(sessionId);
        if (session) {
          session.backgrounded = true;
          session.backgroundReason = reason;
        }
        return session;
      }),

      markSessionForegrounded: mock.fn(async (sessionId, metadata) => {
        const session = mockSessionManager.sessions.get(sessionId);
        if (session) {
          session.backgrounded = false;
          session.backgroundReason = null;
        }
        return session;
      }),
    };

    // Mock process runner
    mockProcessRunner = {
      executeAICLICommand: mock.fn(async (session, prompt, attachmentPaths) => {
        return {
          success: true,
          claudeSessionId: 'claude123',
          response: { result: 'Command executed' },
        };
      }),

      killProcess: mock.fn(async (sessionId, reason) => {
        // Mock implementation
      }),
    };

    sessionOperations = new SessionOperations(
      mockSessionManager,
      mockProcessRunner,
      mockEventEmitter
    );
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('sendStreamingPrompt', () => {
    it('should continue existing Claude conversation', async () => {
      const sessionId = 'claude123';
      const prompt = 'Continue conversation';
      const options = {
        sessionId,
        workingDirectory: '/test/dir',
      };

      const result = await sessionOperations.sendStreamingPrompt(prompt, options);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.claudeSessionId, 'claude123');
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 1);
      
      const call = mockProcessRunner.executeAICLICommand.mock.calls[0];
      assert.strictEqual(call.arguments[0].claudeSessionId, sessionId);
      assert.strictEqual(call.arguments[1], prompt);
    });

    it('should start new conversation when sessionId is new', async () => {
      const prompt = 'Start conversation';
      const options = {
        sessionId: 'new',
        workingDirectory: '/test/dir',
      };

      const result = await sessionOperations.sendStreamingPrompt(prompt, options);

      assert.strictEqual(result.success, true);
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 1);
    });

    it('should start new conversation when sessionId is null', async () => {
      const prompt = 'Start conversation';
      const options = {
        sessionId: null,
        workingDirectory: '/test/dir',
      };

      const result = await sessionOperations.sendStreamingPrompt(prompt, options);

      assert.strictEqual(result.success, true);
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 1);
    });

    it('should handle attachmentPaths', async () => {
      const prompt = 'Process files';
      const attachmentPaths = ['/path/to/file1', '/path/to/file2'];
      const options = {
        sessionId: 'claude123',
        attachmentPaths,
      };

      const result = await sessionOperations.sendStreamingPrompt(prompt, {
        ...options,
        attachmentPaths,
      });

      assert.strictEqual(result.success, true);
      const call = mockProcessRunner.executeAICLICommand.mock.calls[0];
      assert.deepStrictEqual(call.arguments[2], attachmentPaths);
    });
  });

  describe('sendPromptToClaude', () => {
    it('should send prompt with options', async () => {
      const prompt = 'Test prompt';
      const options = {
        skipPermissions: true,
        attachmentPaths: ['/file1'],
        workingDirectory: '/custom/dir',
        retryCount: 5,
      };

      const result = await sessionOperations.sendPromptToClaude(prompt, options);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.claudeSessionId, 'claude123');
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 1);
    });

    it('should use default working directory', async () => {
      const prompt = 'Test prompt';
      const options = {
        defaultWorkingDirectory: '/default/dir',
        workingDirectory: null, // Explicitly null to use default
      };

      await sessionOperations.sendPromptToClaude(prompt, options);

      const call = mockProcessRunner.executeAICLICommand.mock.calls[0];
      // When workingDirectory is null, it uses defaultWorkingDirectory or process.cwd()
      assert.strictEqual(call.arguments[0].workingDirectory, '/default/dir');
    });

    it('should retry on session expired error', async () => {
      const prompt = 'Test prompt';
      
      let callCount = 0;
      mockProcessRunner.executeAICLICommand = mock.fn(async () => {
        callCount++;
        if (callCount === 1) {
          // First call throws session expired error
          const error = new Error('Session expired');
          throw error;
        } else {
          // Second call succeeds
          return {
            success: true,
            claudeSessionId: 'new-claude456',
            response: { result: 'Success after retry' },
          };
        }
      });

      const result = await sessionOperations.sendPromptToClaude(prompt, {});

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.claudeSessionId, 'new-claude456');
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 2);
    });

    it('should retry on session not found error', async () => {
      const prompt = 'Test prompt';
      
      // First call throws session not found error
      mockProcessRunner.executeAICLICommand.mock.mockImplementationOnce(() => {
        const error = new Error('session not found');
        throw error;
      });

      // Second call succeeds
      mockProcessRunner.executeAICLICommand.mock.mockImplementationOnce(async () => ({
        success: true,
        claudeSessionId: 'new-claude789',
        response: { result: 'Success' },
      }));

      const result = await sessionOperations.sendPromptToClaude(prompt, {});

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.claudeSessionId, 'new-claude789');
    });

    it('should throw non-session errors', async () => {
      const prompt = 'Test prompt';
      
      mockProcessRunner.executeAICLICommand.mock.mockImplementationOnce(() => {
        throw new Error('Network error');
      });

      await assert.rejects(
        async () => {
          await sessionOperations.sendPromptToClaude(prompt, {});
        },
        {
          message: 'Network error'
        }
      );
    });
  });

  describe('executeAICLICommand', () => {
    it('should execute command successfully', async () => {
      const session = { sessionId: 'session123', workingDirectory: '/dir' };
      const prompt = 'Execute this';
      const attachmentPaths = ['/file1'];

      const result = await sessionOperations.executeAICLICommand(session, prompt, attachmentPaths);

      assert.strictEqual(result.success, true);
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 1);
    });

    it('should handle rate limiting with retry', async () => {
      const session = { sessionId: 'session123' };
      const prompt = 'Rate limited prompt';
      
      let callCount = 0;
      mockProcessRunner.executeAICLICommand = mock.fn(async () => {
        callCount++;
        if (callCount === 1) {
          // First call throws rate limit error
          const error = new Error('Rate limited');
          error.code = 'RATE_LIMITED';
          throw error;
        } else {
          // Second call succeeds
          return {
            success: true,
            response: { result: 'Success after retry' },
          };
        }
      });

      const result = await sessionOperations.executeAICLICommand(session, prompt, [], 2);

      assert.strictEqual(result.success, true);
      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), 2);
    });

    it('should handle init response in error', async () => {
      const session = { sessionId: 'session123', workingDirectory: '/dir' };
      const prompt = 'Init prompt';
      
      mockProcessRunner.executeAICLICommand.mock.mockImplementationOnce(() => {
        const error = new Error('Init error');
        error.response = {
          type: 'system',
          subtype: 'init',
          session_id: 'claude-init-123',
        };
        throw error;
      });

      const result = await sessionOperations.executeAICLICommand(session, prompt);

      assert.strictEqual(result.success, true);
      assert.strictEqual(result.claudeSessionId, 'claude-init-123');
      assert.strictEqual(mockSessionManager.trackSessionForRouting.mock.callCount(), 1);
      assert.strictEqual(mockSessionManager.trackClaudeSessionActivity.mock.callCount(), 1);
    });

    it('should throw after max retry attempts', async () => {
      const session = { sessionId: 'session123' };
      const prompt = 'Always fails';
      const maxAttempts = 2;
      
      mockProcessRunner.executeAICLICommand.mock.mockImplementation(() => {
        const error = new Error('Rate limited');
        error.code = 'RATE_LIMITED';
        throw error;
      });

      await assert.rejects(
        async () => {
          await sessionOperations.executeAICLICommand(session, prompt, [], maxAttempts);
        },
        {
          message: 'Rate limited',
          code: 'RATE_LIMITED'
        }
      );

      assert.strictEqual(mockProcessRunner.executeAICLICommand.mock.callCount(), maxAttempts);
    });

    it('should bubble up session expired errors', async () => {
      const session = { sessionId: 'session123' };
      const prompt = 'Expired session';
      
      mockProcessRunner.executeAICLICommand.mock.mockImplementationOnce(() => {
        throw new Error('Session expired');
      });

      await assert.rejects(
        async () => {
          await sessionOperations.executeAICLICommand(session, prompt);
        },
        {
          message: 'Session expired'
        }
      );
    });
  });

  describe('closeSession', () => {
    it('should close existing session', async () => {
      const sessionId = 'session123';
      const session = { sessionId };
      mockSessionManager.sessions.set(sessionId, session);

      await sessionOperations.closeSession(sessionId);

      assert.strictEqual(mockProcessRunner.killProcess.mock.callCount(), 1);
      assert.strictEqual(mockSessionManager.removeSession.mock.callCount(), 1);
    });

    it('should handle non-existent session', async () => {
      await sessionOperations.closeSession('nonexistent');

      assert.strictEqual(mockProcessRunner.killProcess.mock.callCount(), 0);
      assert.strictEqual(mockSessionManager.removeSession.mock.callCount(), 0);
    });
  });

  describe('killSession', () => {
    it('should kill session with process', async () => {
      const sessionId = 'session123';
      const session = { sessionId, process: {} };
      mockSessionManager.sessions.set(sessionId, session);

      const result = await sessionOperations.killSession(sessionId, 'Test reason');

      assert.strictEqual(result, true);
      assert.strictEqual(mockProcessRunner.killProcess.mock.callCount(), 1);
      assert.strictEqual(mockSessionManager.removeSession.mock.callCount(), 1);
      assert.strictEqual(emittedEvents.length, 1);
      assert.strictEqual(emittedEvents[0].event, 'sessionCancelled');
      assert.strictEqual(emittedEvents[0].data.reason, 'Test reason');
    });

    it('should handle session without process', async () => {
      const sessionId = 'session123';
      const session = { sessionId };
      mockSessionManager.sessions.set(sessionId, session);

      const result = await sessionOperations.killSession(sessionId);

      assert.strictEqual(result, true);
      assert.strictEqual(mockProcessRunner.killProcess.mock.callCount(), 0);
      assert.strictEqual(mockSessionManager.removeSession.mock.callCount(), 1);
    });

    it('should return false for non-existent session', async () => {
      const result = await sessionOperations.killSession('nonexistent');

      assert.strictEqual(result, false);
      assert.strictEqual(emittedEvents.length, 0);
    });

    it('should handle kill process errors', async () => {
      const sessionId = 'session123';
      const session = { sessionId, process: {} };
      mockSessionManager.sessions.set(sessionId, session);

      mockProcessRunner.killProcess.mock.mockImplementationOnce(() => {
        throw new Error('Kill failed');
      });

      await assert.rejects(
        async () => {
          await sessionOperations.killSession(sessionId);
        },
        {
          message: 'Kill failed'
        }
      );
    });
  });

  describe('hasSession', () => {
    it('should return true for existing session', () => {
      mockSessionManager.sessions.set('session123', {});

      const result = sessionOperations.hasSession('session123');

      assert.strictEqual(result, true);
    });

    it('should return false for non-existent session', () => {
      const result = sessionOperations.hasSession('nonexistent');

      assert.strictEqual(result, false);
    });
  });

  describe('getSession', () => {
    it('should return existing session', () => {
      const session = { sessionId: 'session123' };
      mockSessionManager.sessions.set('session123', session);

      const result = sessionOperations.getSession('session123');

      assert.strictEqual(result, session);
    });

    it('should return undefined for non-existent session', () => {
      const result = sessionOperations.getSession('nonexistent');

      assert.strictEqual(result, undefined);
    });
  });

  describe('getActiveSessions', () => {
    it('should return all active sessions', () => {
      const session1 = { sessionId: 'session1' };
      const session2 = { sessionId: 'session2' };
      mockSessionManager.sessions.set('session1', session1);
      mockSessionManager.sessions.set('session2', session2);

      const result = sessionOperations.getActiveSessions();

      assert.strictEqual(result.length, 2);
      assert(result.includes(session1));
      assert(result.includes(session2));
    });

    it('should return empty array when no sessions', () => {
      const result = sessionOperations.getActiveSessions();

      assert.strictEqual(result.length, 0);
    });
  });

  describe('markSessionBackgrounded', () => {
    it('should mark session as backgrounded', async () => {
      const sessionId = 'session123';
      const session = { sessionId };
      mockSessionManager.sessions.set(sessionId, session);

      const result = await sessionOperations.markSessionBackgrounded(sessionId, 'User action', { extra: 'data' });

      assert.strictEqual(result, session);
      assert.strictEqual(mockSessionManager.markSessionBackgrounded.mock.callCount(), 1);
    });
  });

  describe('markSessionForegrounded', () => {
    it('should mark session as foregrounded', async () => {
      const sessionId = 'session123';
      const session = { sessionId, backgrounded: true };
      mockSessionManager.sessions.set(sessionId, session);

      const result = await sessionOperations.markSessionForegrounded(sessionId, { extra: 'data' });

      assert.strictEqual(result, session);
      assert.strictEqual(mockSessionManager.markSessionForegrounded.mock.callCount(), 1);
    });
  });
});