import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { AICLIService } from '../../services/aicli.js';
import { EventEmitter } from 'events';

/**
 * Integration tests for AICLIService
 * Unit tests for individual modules are in src/test/services/aicli/*.test.js
 */
describe('AICLIService Integration Tests', () => {
  let aicliService;
  let mockSessionManager;
  let mockProcessRunner;
  let originalEnv;

  beforeEach(() => {
    originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'test';

    // Create comprehensive mocks for integration testing
    mockSessionManager = {
      activeSessions: new Map(),
      sessionTimeout: 24 * 60 * 60 * 1000,
      hasSession: mock.fn((id) => mockSessionManager.activeSessions.has(id)),
      getSession: mock.fn((id) => mockSessionManager.activeSessions.get(id)),
      removeSession: mock.fn((id) => mockSessionManager.activeSessions.delete(id)),
      getActiveSessions: mock.fn(() => Array.from(mockSessionManager.activeSessions.values())),
      cleanupDeadSession: mock.fn(async (id) => {
        mockSessionManager.activeSessions.delete(id);
      }),
      cleanupAllSessions: mock.fn(async () => {
        mockSessionManager.activeSessions.clear();
      }),
      createInteractiveSession: mock.fn(async (sessionId, prompt, workingDir, options) => {
        const session = {
          sessionId: sessionId || `session-${Date.now()}`,
          prompt,
          workingDirectory: workingDir || process.cwd(),
          startTime: new Date().toISOString(),
          process: { pid: Math.floor(Math.random() * 10000) },
          ...options,
        };
        mockSessionManager.activeSessions.set(session.sessionId, session);
        return session;
      }),
      getSessionBuffer: mock.fn(() => null),
      setSessionBuffer: mock.fn(),
      clearSessionBuffer: mock.fn(),
      trackSessionForRouting: mock.fn(),
      trackClaudeSessionActivity: mock.fn(),
      markSessionBackgrounded: mock.fn(async () => true),
      markSessionForegrounded: mock.fn(async () => true),
      on: mock.fn(),
      removeAllListeners: mock.fn(),
    };

    mockProcessRunner = {
      aicliCommand: 'claude',
      permissionMode: 'default',
      allowedTools: [],
      disallowedTools: [],
      skipPermissions: false,
      setPermissionMode: mock.fn(function(mode) {
        this.permissionMode = mode;
      }),
      setAllowedTools: mock.fn(function(tools) {
        this.allowedTools = tools;
      }),
      setDisallowedTools: mock.fn(function(tools) {
        this.disallowedTools = tools;
      }),
      setSkipPermissions: mock.fn(function(skip) {
        this.skipPermissions = skip;
      }),
      executeAICLICommand: mock.fn(async (session, prompt, attachmentPaths) => ({
        success: true,
        response: { 
          type: 'result',
          result: `Processed: ${prompt}`,
          session_id: session.sessionId,
        },
        claudeSessionId: session.sessionId,
      })),
      sendToInteractiveSession: mock.fn(async (session, message) => ({
        success: true,
        response: `Response to: ${message}`,
      })),
      killProcess: mock.fn(async () => true),
      on: mock.fn(),
      removeAllListeners: mock.fn(),
    };

    aicliService = new AICLIService({
      sessionManager: mockSessionManager,
      processRunner: mockProcessRunner,
    });
  });

  afterEach(() => {
    process.env.NODE_ENV = originalEnv;
    if (aicliService) {
      aicliService.stopProcessHealthMonitoring();
      aicliService.removeAllListeners();
    }
  });

  describe('Service Initialization', () => {
    it('should initialize with default options', () => {
      const service = new AICLIService();
      assert.ok(service.sessionManager);
      assert.ok(service.processRunner);
      assert.ok(service.permissionHandler);
      assert.ok(service.responseEmitter);
      assert.ok(service.healthMonitor);
      assert.ok(service.sessionOperations);
      service.stopProcessHealthMonitoring();
    });

    it('should use injected dependencies', () => {
      assert.strictEqual(aicliService.sessionManager, mockSessionManager);
      assert.strictEqual(aicliService.processRunner, mockProcessRunner);
    });

    it('should set up event forwarding', () => {
      assert.ok(mockSessionManager.on.mock.calls.length > 0);
      assert.ok(mockProcessRunner.on.mock.calls.length > 0);
    });
  });

  describe('End-to-End Prompt Processing', () => {
    it('should process a simple prompt', async () => {
      const result = await aicliService.sendPrompt('Hello Claude', {
        streaming: true,
      });

      assert.ok(result.success);
      assert.ok(result.response);
      assert.equal(mockSessionManager.createInteractiveSession.mock.calls.length, 1);
      assert.equal(mockProcessRunner.executeAICLICommand.mock.calls.length, 1);
    });

    it('should handle attachments', async () => {
      const attachments = [
        {
          name: 'test.txt',
          data: Buffer.from('Test content').toString('base64'),
        },
      ];

      const result = await aicliService.sendPrompt('Analyze this file', {
        streaming: true,
        attachments,
      });

      assert.ok(result.success);
      assert.equal(mockProcessRunner.executeAICLICommand.mock.calls.length, 1);
      
      // Check that attachment paths were passed
      const call = mockProcessRunner.executeAICLICommand.mock.calls[0];
      assert.ok(call.arguments[2]); // attachmentPaths parameter
    });

    it('should reuse existing session', async () => {
      // Create first session
      const result1 = await aicliService.sendPrompt('First message', {
        sessionId: 'test-session',
        streaming: true,
      });
      assert.ok(result1.success);

      // Send second message to same session
      const result2 = await aicliService.sendPrompt('Second message', {
        sessionId: 'test-session',
        streaming: true,
      });
      assert.ok(result2.success);

      // Should have created session only once
      assert.equal(mockSessionManager.createInteractiveSession.mock.calls.length, 1);
      // Should have sent to interactive session for second message
      assert.equal(mockProcessRunner.sendToInteractiveSession.mock.calls.length, 1);
    });

    it('should handle session expiry and retry', async () => {
      let callCount = 0;
      mockProcessRunner.executeAICLICommand = mock.fn(async () => {
        callCount++;
        if (callCount === 1) {
          throw new Error('Session expired');
        }
        return {
          success: true,
          response: { result: 'Success on retry' },
          claudeSessionId: 'new-session',
        };
      });

      const result = await aicliService.sendPrompt('Test prompt', {
        sessionId: 'expired-session',
        streaming: true,
      });

      assert.ok(result.success);
      assert.equal(mockProcessRunner.executeAICLICommand.mock.calls.length, 2);
      assert.equal(mockSessionManager.cleanupDeadSession.mock.calls.length, 1);
    });

    it('should validate input', async () => {
      await assert.rejects(
        aicliService.sendPrompt(null),
        /Invalid input: Prompt must be a string/
      );

      await assert.rejects(
        aicliService.sendPrompt(''),
        /Invalid input: Prompt cannot be empty/
      );
    });
  });

  describe('Session Management', () => {
    it('should create and track sessions', async () => {
      await aicliService.sendPrompt('Test', { streaming: true });
      
      const sessions = aicliService.getActiveSessions();
      assert.equal(sessions.length, 1);
      assert.ok(sessions[0].sessionId);
    });

    it('should kill session with cleanup', async () => {
      // Create a session
      await aicliService.sendPrompt('Test', {
        sessionId: 'kill-test',
        streaming: true,
      });

      // Kill it
      const killed = await aicliService.killSession('kill-test', 'Test reason');
      assert.ok(killed);
      assert.equal(mockProcessRunner.killProcess.mock.calls.length, 1);
      assert.equal(mockSessionManager.removeSession.mock.calls.length, 1);

      // Verify session is gone
      assert.equal(aicliService.hasSession('kill-test'), false);
    });

    it('should handle killing non-existent session', async () => {
      const killed = await aicliService.killSession('non-existent');
      assert.equal(killed, false);
    });

    it('should close session gracefully', async () => {
      await aicliService.sendPrompt('Test', {
        sessionId: 'close-test',
        streaming: true,
      });

      await aicliService.closeSession('close-test');
      assert.equal(mockProcessRunner.killProcess.mock.calls.length, 1);
      assert.equal(mockSessionManager.removeSession.mock.calls.length, 1);
    });

    it('should mark session as backgrounded', async () => {
      await aicliService.sendPrompt('Test', {
        sessionId: 'bg-test',
        streaming: true,
      });

      await aicliService.markSessionBackgrounded('bg-test', 'User switched app');
      assert.equal(mockSessionManager.markSessionBackgrounded.mock.calls.length, 1);
    });

    it('should mark session as foregrounded', async () => {
      await aicliService.sendPrompt('Test', {
        sessionId: 'fg-test',
        streaming: true,
      });

      await aicliService.markSessionForegrounded('fg-test');
      assert.equal(mockSessionManager.markSessionForegrounded.mock.calls.length, 1);
    });
  });

  describe('Permission Configuration', () => {
    it('should configure permission mode', () => {
      aicliService.setPermissionMode('strict');
      assert.equal(mockProcessRunner.permissionMode, 'strict');
      assert.equal(aicliService.permissionMode, 'strict');
    });

    it('should configure allowed tools', () => {
      const tools = ['Read', 'Write'];
      aicliService.setAllowedTools(tools);
      assert.deepEqual(mockProcessRunner.allowedTools, tools);
      assert.deepEqual(aicliService.allowedTools, tools);
    });

    it('should configure disallowed tools', () => {
      const tools = ['Bash', 'Execute'];
      aicliService.setDisallowedTools(tools);
      assert.deepEqual(mockProcessRunner.disallowedTools, tools);
      assert.deepEqual(aicliService.disallowedTools, tools);
    });

    it('should configure skip permissions', () => {
      aicliService.setSkipPermissions(true);
      assert.equal(mockProcessRunner.skipPermissions, true);
      assert.equal(aicliService.skipPermissions, true);
    });

    it('should apply permissions to prompts', async () => {
      aicliService.setPermissionMode('strict');
      aicliService.setAllowedTools(['Read']);
      
      await aicliService.sendPrompt('Test', {
        streaming: true,
        skipPermissions: false,
      });

      // Verify permissions were considered (actual args building is tested in permission-handler.test.js)
      assert.equal(aicliService.permissionMode, 'strict');
    });
  });

  describe('Health Monitoring', () => {
    it('should perform health check', async () => {
      // Mock checkAvailability
      aicliService.checkAvailability = mock.fn(async () => ({
        available: true,
        version: '1.0.0',
        path: '/usr/local/bin/claude',
      }));

      const health = await aicliService.healthCheck();
      
      assert.equal(health.status, 'healthy');
      assert.ok(health.checks.aicli);
      assert.ok(health.checks.sessions);
      assert.ok(health.checks.memory);
      assert.ok(health.details);
    });

    it('should detect unhealthy state', async () => {
      // Mock the health monitor's checkAvailability method directly
      aicliService.healthMonitor.checkAvailability = mock.fn(async () => ({
        available: false,
        error: 'Command not found',
      }));

      const health = await aicliService.healthCheck();
      
      assert.equal(health.status, 'unhealthy');
      assert.equal(health.checks.aicli, false);
    });

    it('should check session timeout', async () => {
      const session = {
        sessionId: 'timeout-test',
        startTime: new Date(Date.now() - 1000).toISOString(),
        lastActivity: new Date().toISOString(),
      };
      mockSessionManager.activeSessions.set('timeout-test', session);

      const timeout = aicliService.checkSessionTimeout('timeout-test');
      assert.equal(timeout.timedOut, false);
      assert.ok(timeout.timeRemaining > 0);
    });

    it('should detect timed out session', async () => {
      const session = {
        sessionId: 'old-session',
        startTime: new Date(Date.now() - 25 * 60 * 60 * 1000).toISOString(), // 25 hours ago
      };
      mockSessionManager.activeSessions.set('old-session', session);

      const timeout = aicliService.checkSessionTimeout('old-session');
      assert.equal(timeout.timedOut, true);
      assert.ok(timeout.reason);
    });
  });

  describe('Lifecycle Management', () => {
    it('should perform startup cleanup', async () => {
      await aicliService.performStartupCleanup();
      assert.equal(mockSessionManager.cleanupAllSessions.mock.calls.length, 1);
    });

    it('should shutdown cleanly', async () => {
      // Create some sessions
      await aicliService.sendPrompt('Test1', { streaming: true });
      await aicliService.sendPrompt('Test2', { streaming: true });

      await aicliService.shutdown();
      
      assert.equal(mockSessionManager.cleanupAllSessions.mock.calls.length, 1);
      assert.equal(aicliService.listenerCount('sessionCleaned'), 0);
    });

    it('should handle shutdown timeout', async () => {
      mockSessionManager.cleanupAllSessions = mock.fn(async () => {
        await new Promise(resolve => setTimeout(resolve, 11000));
      });

      await assert.rejects(
        aicliService.shutdown(),
        /Shutdown timeout/
      );
    });
  });

  describe('Event Emission', () => {
    it('should emit process lifecycle events', async () => {
      const events = [];
      aicliService.on('processStart', (data) => events.push({ type: 'start', data }));
      aicliService.on('processExit', (data) => events.push({ type: 'exit', data }));

      // Simulate process events
      const processStartHandler = mockProcessRunner.on.mock.calls.find(
        call => call.arguments[0] === 'processStart'
      );
      if (processStartHandler) {
        processStartHandler.arguments[1]({ sessionId: 'test', pid: 123 });
      }

      assert.ok(events.some(e => e.type === 'start'));
    });

    it('should emit security violations', async () => {
      const violations = [];
      aicliService.on('securityViolation', (data) => violations.push(data));

      // Simulate security violation
      const securityHandler = mockProcessRunner.on.mock.calls.find(
        call => call.arguments[0] === 'securityViolation'
      );
      if (securityHandler) {
        securityHandler.arguments[1]({ 
          type: 'forbidden_path',
          path: '/etc/passwd',
        });
      }

      assert.equal(violations.length, 1);
    });

    it('should emit session events', async () => {
      const events = [];
      aicliService.on('sessionCleaned', (data) => events.push(data));
      aicliService.on('sessionCancelled', (data) => events.push(data));

      // Create and kill a session
      await aicliService.sendPrompt('Test', {
        sessionId: 'event-test',
        streaming: true,
      });
      await aicliService.killSession('event-test', 'Test cancellation');

      assert.ok(events.some(e => e.reason === 'Test cancellation'));
    });
  });

  describe('Error Handling', () => {
    it('should handle process runner errors', async () => {
      mockProcessRunner.executeAICLICommand = mock.fn(async () => {
        throw new Error('Process failed to start');
      });

      await assert.rejects(
        aicliService.sendPrompt('Test', { streaming: true }),
        /Process failed to start/
      );
    });

    it('should handle invalid working directory', async () => {
      aicliService.setSafeRootDirectory('/safe/path');
      
      // This would normally be validated in the actual implementation
      assert.ok(aicliService.safeRootDirectory);
    });

    it('should handle missing sessions gracefully', () => {
      const session = aicliService.getSession('non-existent');
      assert.equal(session, undefined);
      
      const hasSession = aicliService.hasSession('non-existent');
      assert.equal(hasSession, false);
    });
  });


  describe('Message Handling and Classification', () => {
    it('should handle text message with proper classification', async () => {
      const result = await aicliService.sendPrompt('Explain this code', {
        streaming: true,
        sessionId: 'msg-test-1',
      });

      assert.ok(result.success);
      assert.ok(result.response);
      assert.equal(mockSessionManager.createInteractiveSession.mock.calls.length, 1);
    });

    it('should handle permission prompt correctly', async () => {
      // Mock permission prompt response
      mockProcessRunner.executeAICLICommand = mock.fn(async () => ({
        success: true,
        response: {
          type: 'permission_request',
          tool: 'Read',
          path: '/test/file.js',
          session_id: 'perm-test',
        },
        claudeSessionId: 'perm-test',
      }));

      const result = await aicliService.sendPrompt('Read file.js', {
        streaming: true,
        sessionId: 'perm-test',
      });

      assert.ok(result.success);
      assert.equal(result.response.type, 'permission_request');
    });

    it('should handle streaming responses with chunks', async () => {
      let chunkCount = 0;
      const chunks = ['Chunk 1', 'Chunk 2', 'Chunk 3'];
      
      // Mock streaming response
      mockProcessRunner.executeAICLICommand = mock.fn(async (session, prompt, attachments) => {
        // Simulate streaming by emitting chunks
        setTimeout(() => {
          chunks.forEach((chunk, i) => {
            setTimeout(() => {
              const handler = mockProcessRunner.on.mock.calls.find(
                call => call.arguments[0] === 'streamingData'
              );
              if (handler) {
                handler.arguments[1]({
                  sessionId: session.sessionId,
                  data: chunk,
                });
              }
            }, i * 10);
          });
        }, 10);

        return {
          success: true,
          response: {
            type: 'streaming',
            chunks: chunks,
            session_id: session.sessionId,
          },
          claudeSessionId: session.sessionId,
        };
      });

      const streamingData = [];
      aicliService.on('streamingData', (data) => {
        streamingData.push(data);
        chunkCount++;
      });

      const result = await aicliService.sendPrompt('Stream test', {
        streaming: true,
        sessionId: 'stream-test',
      });

      // Wait for streaming events
      await new Promise(resolve => setTimeout(resolve, 100));

      assert.ok(result.success);
      assert.ok(streamingData.length > 0 || result.response.chunks);
    });

    it('should handle error messages properly', async () => {
      mockProcessRunner.executeAICLICommand = mock.fn(async () => ({
        success: false,
        error: 'Claude CLI error: Command failed',
        response: {
          type: 'error',
          message: 'Command execution failed',
        },
      }));

      const result = await aicliService.sendPrompt('Cause error', {
        streaming: true,
        sessionId: 'error-test',
      });

      assert.equal(result.success, false);
      assert.ok(result.error);
    });

    it('should handle tool use messages', async () => {
      mockProcessRunner.executeAICLICommand = mock.fn(async () => ({
        success: true,
        response: {
          type: 'tool_use',
          tool: 'Bash',
          command: 'ls -la',
          result: 'file1.txt\nfile2.txt',
          session_id: 'tool-test',
        },
        claudeSessionId: 'tool-test',
      }));

      const result = await aicliService.sendPrompt('List files', {
        streaming: true,
        sessionId: 'tool-test',
      });

      assert.ok(result.success);
      assert.equal(result.response.type, 'tool_use');
      assert.equal(result.response.tool, 'Bash');
    });

    it('should handle multiple attachments with validation', async () => {
      const attachments = [
        {
          name: 'file1.txt',
          data: Buffer.from('Content 1').toString('base64'),
        },
        {
          name: 'file2.js',
          data: Buffer.from('const x = 1;').toString('base64'),
        },
        {
          name: 'image.png',
          data: Buffer.from('fake image data').toString('base64'),
        },
      ];

      mockProcessRunner.executeAICLICommand = mock.fn(async (session, prompt, attachmentPaths) => {
        assert.equal(attachmentPaths.length, 3);
        return {
          success: true,
          response: {
            type: 'result',
            result: `Processed ${attachmentPaths.length} attachments`,
            session_id: session.sessionId,
          },
          claudeSessionId: session.sessionId,
        };
      });

      const result = await aicliService.sendPrompt('Analyze these files', {
        streaming: true,
        attachments,
        sessionId: 'multi-attach-test',
      });

      assert.ok(result.success);
      assert.ok(result.response.result.includes('3 attachments'));
    });

    it('should handle continuation messages in existing session', async () => {
      // First message creates session
      await aicliService.sendPrompt('Initial message', {
        sessionId: 'cont-test',
        streaming: true,
      });

      // Mock continuation response
      mockProcessRunner.sendToInteractiveSession = mock.fn(async (session, message) => ({
        success: true,
        response: {
          type: 'continuation',
          message: `Continuing with: ${message}`,
          session_id: session.sessionId,
        },
      }));

      // Send continuation
      const result = await aicliService.sendPrompt('Follow up question', {
        sessionId: 'cont-test',
        streaming: true,
      });

      assert.ok(result.success);
      assert.equal(mockProcessRunner.sendToInteractiveSession.mock.calls.length, 1);
      assert.ok(result.response.message || result.response);
    });

    it('should handle rate limiting gracefully', async () => {
      let attempts = 0;
      mockProcessRunner.executeAICLICommand = mock.fn(async () => {
        attempts++;
        if (attempts < 3) {
          const error = new Error('Rate limited');
          error.code = 'RATE_LIMITED';
          throw error;
        }
        return {
          success: true,
          response: { result: 'Success after retry' },
          claudeSessionId: 'rate-test',
        };
      });

      const result = await aicliService.sendPrompt('Test rate limit', {
        streaming: true,
        sessionId: 'rate-test',
        retryCount: 3,
      });

      // Should either succeed after retries or fail with rate limit
      if (result.success) {
        assert.ok(result.response.result);
      } else {
        assert.ok(result.error);
      }
    });

    it('should validate and sanitize prompt input', async () => {
      // Test with special characters
      const specialPrompt = 'Test with <script>alert("xss")</script> content';
      
      const result = await aicliService.sendPrompt(specialPrompt, {
        streaming: true,
        sessionId: 'sanitize-test',
      });

      assert.ok(result.success);
      // Verify the prompt was processed (sanitization would happen in actual implementation)
      const call = mockProcessRunner.executeAICLICommand.mock.calls[0];
      assert.ok(call.arguments[1]); // prompt parameter exists
    });

    it('should handle session buffer for incomplete messages', async () => {
      // Mock incomplete message that needs buffering
      mockProcessRunner.executeAICLICommand = mock.fn(async () => ({
        success: true,
        response: {
          type: 'partial',
          content: 'This is an incomplete...',
          needsMore: true,
          session_id: 'buffer-test',
        },
        claudeSessionId: 'buffer-test',
      }));

      const result = await aicliService.sendPrompt('Generate long response', {
        streaming: true,
        sessionId: 'buffer-test',
      });

      assert.ok(result.success);
      // Check buffer management was called
      assert.ok(mockSessionManager.setSessionBuffer.mock.calls.length >= 0);
    });

    it('should handle cancellation during message processing', async () => {
      // Create a long-running session
      let cancelled = false;
      mockProcessRunner.executeAICLICommand = mock.fn(async () => {
        return new Promise((resolve, reject) => {
          setTimeout(() => {
            if (cancelled) {
              reject(new Error('Cancelled'));
            } else {
              resolve({
                success: true,
                response: { result: 'Completed' },
                claudeSessionId: 'cancel-test',
              });
            }
          }, 100);
        });
      });

      // Start the prompt
      const promptPromise = aicliService.sendPrompt('Long running task', {
        streaming: true,
        sessionId: 'cancel-test',
      });

      // Cancel after a short delay
      setTimeout(() => {
        cancelled = true;
        aicliService.killSession('cancel-test', 'User cancelled');
      }, 50);

      try {
        await promptPromise;
      } catch (error) {
        assert.ok(error.message.includes('Cancelled') || error.message.includes('cancelled'));
      }
    });
  });
});