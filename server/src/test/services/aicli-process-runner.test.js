import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';

// Mock child_process
const mockSpawn = mock.fn();
const mockChildProcess = mock.module('child_process', {
  spawn: mockSpawn
});

// Mock process monitor
const mockProcessMonitor = mock.module('../../utils/process-monitor.js', {
  processMonitor: {
    monitorProcess: mock.fn()
  }
});

// Mock utilities
const mockInputValidator = {
  validateAICLIArgs: mock.fn(),
  sanitizeSessionId: mock.fn((id) => id),
  sanitizePrompt: mock.fn((prompt) => prompt),
  validateWorkingDirectory: mock.fn()
};

const mockMessageProcessor = {
  parseStreamJsonOutput: mock.fn()
};

const mockAICLIConfig = {
  findAICLICommand: mock.fn(() => 'claude'),
  calculateTimeoutForCommand: mock.fn(() => 30000)
};

const mockAICLIUtils = mock.module('../../services/aicli-utils.js', {
  InputValidator: mockInputValidator,
  MessageProcessor: mockMessageProcessor,
  AICLIConfig: mockAICLIConfig
});

// Mock other dependencies
const mockMessageHandler = mock.module('../../services/aicli-message-handler.js', {
  AICLIMessageHandler: class MockMessageHandler {}
});

const mockStreamParser = mock.module('../../services/stream-parser.js', {
  ClaudeStreamParser: class MockStreamParser {
    parseData() { return []; }
  }
});

describe('AICLIProcessRunner', () => {
  let processRunner;
  let mockProcess;

  beforeEach(() => {
    processRunner = new AICLIProcessRunner();
    
    // Create mock process
    mockProcess = new EventEmitter();
    mockProcess.pid = 12345;
    mockProcess.stdin = new EventEmitter();
    mockProcess.stdin.write = mock.fn();
    mockProcess.stdin.end = mock.fn();
    mockProcess.stdout = new EventEmitter();
    mockProcess.stderr = new EventEmitter();
    mockProcess.kill = mock.fn();

    // Reset mocks
    mockSpawn.mock.resetCalls();
    mockSpawn.mock.mockImplementation(() => mockProcess);
    
    mockProcessMonitor.processMonitor.monitorProcess.mock.resetCalls();
    mockInputValidator.validateAICLIArgs.mock.resetCalls();
    mockMessageProcessor.parseStreamJsonOutput.mock.resetCalls();
    mockAICLIConfig.findAICLICommand.mock.resetCalls();
    mockAICLIConfig.calculateTimeoutForCommand.mock.resetCalls();
  });

  afterEach(() => {
    // Clean up any pending timeouts or intervals
    if (processRunner) {
      processRunner.removeAllListeners();
    }
  });

  describe('constructor', () => {
    it('should initialize with default configuration', () => {
      assert.ok(processRunner instanceof EventEmitter);
      assert.strictEqual(processRunner.permissionMode, 'default');
      assert.deepStrictEqual(processRunner.allowedTools, ['Read', 'Write', 'Edit']);
      assert.deepStrictEqual(processRunner.disallowedTools, []);
      assert.strictEqual(processRunner.skipPermissions, false);
    });

    it('should find AICLI command on initialization', () => {
      assert.strictEqual(mockAICLIConfig.findAICLICommand.mock.calls.length, 1);
    });
  });

  describe('permission configuration', () => {
    it('should set valid permission mode', () => {
      processRunner.setPermissionMode('acceptEdits');
      assert.strictEqual(processRunner.permissionMode, 'acceptEdits');

      processRunner.setPermissionMode('bypassPermissions');
      assert.strictEqual(processRunner.permissionMode, 'bypassPermissions');

      processRunner.setPermissionMode('plan');
      assert.strictEqual(processRunner.permissionMode, 'plan');
    });

    it('should reject invalid permission mode', () => {
      const originalMode = processRunner.permissionMode;
      processRunner.setPermissionMode('invalid');
      assert.strictEqual(processRunner.permissionMode, originalMode);
    });

    it('should set allowed tools', () => {
      const tools = ['Read', 'Write'];
      processRunner.setAllowedTools(tools);
      assert.deepStrictEqual(processRunner.allowedTools, tools);
    });

    it('should set disallowed tools', () => {
      const tools = ['Edit', 'Bash'];
      processRunner.setDisallowedTools(tools);
      assert.deepStrictEqual(processRunner.disallowedTools, tools);
    });

    it('should set skip permissions flag', () => {
      processRunner.setSkipPermissions(true);
      assert.strictEqual(processRunner.skipPermissions, true);

      processRunner.setSkipPermissions(false);
      assert.strictEqual(processRunner.skipPermissions, false);
    });
  });

  describe('addPermissionArgs', () => {
    it('should add skip-permissions flag when enabled', () => {
      processRunner.setSkipPermissions(true);
      const args = [];
      processRunner.addPermissionArgs(args);
      
      assert.ok(args.includes('--dangerously-skip-permissions'));
    });

    it('should add permission mode when not default', () => {
      processRunner.setPermissionMode('acceptEdits');
      const args = [];
      processRunner.addPermissionArgs(args);
      
      assert.ok(args.includes('--permission-mode'));
      assert.ok(args.includes('acceptEdits'));
    });

    it('should add allowed tools', () => {
      processRunner.setAllowedTools(['Read', 'Write']);
      const args = [];
      processRunner.addPermissionArgs(args);
      
      assert.ok(args.includes('--allowedTools'));
      assert.ok(args.includes('Read,Write'));
    });

    it('should add disallowed tools', () => {
      processRunner.setDisallowedTools(['Bash', 'Edit']);
      const args = [];
      processRunner.addPermissionArgs(args);
      
      assert.ok(args.includes('--disallowedTools'));
      assert.ok(args.includes('Bash,Edit'));
    });

    it('should not add permission args when skipping permissions', () => {
      processRunner.setSkipPermissions(true);
      processRunner.setPermissionMode('acceptEdits');
      processRunner.setAllowedTools(['Read']);
      
      const args = [];
      processRunner.addPermissionArgs(args);
      
      assert.strictEqual(args.length, 1); // Only skip-permissions flag
      assert.ok(args.includes('--dangerously-skip-permissions'));
      assert.ok(!args.includes('--permission-mode'));
      assert.ok(!args.includes('--allowedTools'));
    });
  });

  describe('executeAICLICommand', () => {
    const mockSession = {
      sessionId: 'test-session',
      workingDirectory: '/tmp',
      conversationStarted: false,
      initialPrompt: 'Initial prompt'
    };

    beforeEach(() => {
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 30000);
    });

    it('should build correct args for new session', async () => {
      const prompt = 'Test prompt';
      
      // Mock successful execution
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      const executePromise = processRunner.executeAICLICommand(mockSession, prompt);
      
      // Verify spawn was called with correct args
      assert.strictEqual(mockSpawn.mock.calls.length, 1);
      const [command, args, options] = mockSpawn.mock.calls[0].arguments;
      
      assert.strictEqual(command, 'claude');
      assert.ok(args.includes('--print'));
      assert.ok(args.includes('--output-format'));
      assert.ok(args.includes('stream-json'));
      assert.ok(args.includes('--verbose'));
      assert.ok(!args.includes('--continue')); // New session
      assert.strictEqual(options.cwd, '/tmp');

      await executePromise;
    });

    it('should add continue flag for existing session', async () => {
      const sessionWithHistory = {
        ...mockSession,
        conversationStarted: true
      };
      
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      const executePromise = processRunner.executeAICLICommand(sessionWithHistory, 'Test');
      
      const [command, args] = mockSpawn.mock.calls[0].arguments;
      assert.ok(args.includes('--continue'));

      await executePromise;
    });

    it('should combine initial prompt with command prompt for new session', async () => {
      setTimeout(() => {
        mockProcess.stdin.write = mock.fn();
        mockProcess.stdin.end = mock.fn();
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      await processRunner.executeAICLICommand(mockSession, 'Test prompt');
      
      // Should write combined prompt to stdin
      assert.strictEqual(mockProcess.stdin.write.mock.calls.length, 1);
      const writtenPrompt = mockProcess.stdin.write.mock.calls[0].arguments[0];
      assert.ok(writtenPrompt.includes('Initial prompt'));
      assert.ok(writtenPrompt.includes('Test prompt'));
    });

    it('should delegate to long-running task manager for long commands', async () => {
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 400000); // > 300000
      
      const mockLongRunningTaskManager = {
        handlePotentialLongRunningTask: mock.fn(() => Promise.resolve({ result: 'long-task' }))
      };

      const result = await processRunner.executeAICLICommand(
        mockSession, 
        'Long prompt', 
        mockLongRunningTaskManager
      );
      
      assert.strictEqual(mockLongRunningTaskManager.handlePotentialLongRunningTask.mock.calls.length, 1);
      assert.deepStrictEqual(result, { result: 'long-task' });
    });

    it('should handle process spawn error', async () => {
      mockSpawn.mock.mockImplementation(() => {
        throw new Error('ENOENT');
      });

      await assert.rejects(
        processRunner.executeAICLICommand(mockSession, 'Test'),
        /AICLI CLI not found/
      );
    });
  });

  describe('process events', () => {
    const mockSession = {
      sessionId: 'test-session',
      workingDirectory: '/tmp',
      conversationStarted: false
    };

    it('should emit processStart event', async () => {
      let processStartEvent = null;
      processRunner.once('processStart', (event) => {
        processStartEvent = event;
      });

      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      await processRunner.executeAICLICommand(mockSession, 'Test');
      
      assert.ok(processStartEvent);
      assert.strictEqual(processStartEvent.sessionId, 'test-session');
      assert.strictEqual(processStartEvent.pid, 12345);
      assert.strictEqual(processStartEvent.type, 'command');
    });

    it('should emit streamChunk events for stdout', (done) => {
      const chunks = [];
      processRunner.on('streamChunk', (event) => {
        chunks.push(event);
      });

      // Start execution
      const executePromise = processRunner.executeAICLICommand(mockSession, 'Test');
      
      setTimeout(() => {
        // Simulate stdout data
        mockProcess.stdout.emit('data', Buffer.from('{"type": "status", "message": "Processing"}\n'));
        
        setTimeout(() => {
          mockProcess.emit('close', 0);
          
          // Verify events were emitted
          assert.ok(chunks.length > 0);
          done();
        }, 20);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);
    });

    it('should emit processStderr events for stderr', (done) => {
      let stderrEvent = null;
      processRunner.once('processStderr', (event) => {
        stderrEvent = event;
      });

      // Start execution
      processRunner.executeAICLICommand(mockSession, 'Test');
      
      setTimeout(() => {
        // Simulate stderr data
        mockProcess.stderr.emit('data', Buffer.from('Warning: something happened'));
        
        setTimeout(() => {
          assert.ok(stderrEvent);
          assert.strictEqual(stderrEvent.sessionId, 'test-session');
          assert.ok(stderrEvent.data.includes('Warning'));
          done();
        }, 20);
      }, 10);
    });

    it('should emit processExit event on close', async () => {
      let exitEvent = null;
      processRunner.once('processExit', (event) => {
        exitEvent = event;
      });

      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      await processRunner.executeAICLICommand(mockSession, 'Test');
      
      assert.ok(exitEvent);
      assert.strictEqual(exitEvent.sessionId, 'test-session');
      assert.strictEqual(exitEvent.code, 0);
      assert.strictEqual(exitEvent.pid, 12345);
    });
  });

  describe('output processing', () => {
    const mockSession = {
      sessionId: 'test-session',
      workingDirectory: '/tmp',
      conversationStarted: false
    };

    it('should parse successful response', async () => {
      const mockResponse = { type: 'result', message: 'Hello world' };
      
      setTimeout(() => {
        mockProcess.stdout.emit('data', Buffer.from(JSON.stringify(mockResponse) + '\n'));
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [mockResponse]);

      const result = await processRunner.executeAICLICommand(mockSession, 'Test');
      
      assert.deepStrictEqual(result, mockResponse);
      assert.strictEqual(mockMessageProcessor.parseStreamJsonOutput.mock.calls.length, 1);
    });

    it('should handle empty output', async () => {
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => []);

      await assert.rejects(
        processRunner.executeAICLICommand(mockSession, 'Test'),
        /No valid JSON objects found/
      );
    });

    it('should handle non-zero exit code', async () => {
      setTimeout(() => {
        mockProcess.stderr.emit('data', Buffer.from('Error: command failed'));
        mockProcess.emit('close', 1);
      }, 10);

      await assert.rejects(
        processRunner.executeAICLICommand(mockSession, 'Test'),
        /exited with code 1/
      );
    });

    it('should handle process error', async () => {
      setTimeout(() => {
        mockProcess.emit('error', new Error('Process crashed'));
      }, 10);

      await assert.rejects(
        processRunner.executeAICLICommand(mockSession, 'Test'),
        /Process crashed/
      );
    });
  });

  describe('timeout handling', () => {
    const mockSession = {
      sessionId: 'test-session',
      workingDirectory: '/tmp',
      conversationStarted: false
    };

    it('should timeout if process takes too long', async () => {
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 50); // 50ms timeout

      // Don't emit close event, let it timeout
      
      await assert.rejects(
        processRunner.executeAICLICommand(mockSession, 'Test'),
        /timed out/
      );
      
      // Verify process was killed
      assert.strictEqual(mockProcess.kill.mock.calls.length, 1);
      assert.strictEqual(mockProcess.kill.mock.calls[0].arguments[0], 'SIGTERM');
    });

    it('should use activity-based timeout after receiving output', async () => {
      mockAICLIConfig.calculateTimeoutForCommand.mock.mockImplementation(() => 1000); // 1s timeout
      
      setTimeout(() => {
        // Send some output to trigger activity-based timeout
        mockProcess.stdout.emit('data', Buffer.from('{"type": "status"}\n'));
        
        // Then don't send anything else - should timeout due to silence
      }, 10);

      await assert.rejects(
        processRunner.executeAICLICommand(mockSession, 'Test'),
        /timed out/
      );
    });
  });

  describe('testAICLICommand', () => {
    it('should test version command', async () => {
      setTimeout(() => {
        mockProcess.stdout.emit('data', Buffer.from('claude-cli 1.0.0\n'));
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', version: '1.0.0' }
      ]);

      const result = await processRunner.testAICLICommand('version');
      
      const [command, args] = mockSpawn.mock.calls[0].arguments;
      assert.ok(args.includes('--version'));
      assert.deepStrictEqual(result, { type: 'result', version: '1.0.0' });
    });

    it('should test help command', async () => {
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', help: 'Usage: claude [options]' }
      ]);

      const result = await processRunner.testAICLICommand('help');
      
      const [command, args] = mockSpawn.mock.calls[0].arguments;
      assert.ok(args.includes('--help'));
    });

    it('should reject unknown test type', async () => {
      await assert.rejects(
        processRunner.testAICLICommand('unknown'),
        /Unknown test type/
      );
    });
  });

  describe('stdin handling', () => {
    const mockSession = {
      sessionId: 'test-session',
      workingDirectory: '/tmp',
      conversationStarted: false
    };

    it('should write prompt to stdin when using --print', async () => {
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      await processRunner.executeAICLICommand(mockSession, 'Test prompt');
      
      // Should write to stdin
      assert.strictEqual(mockProcess.stdin.write.mock.calls.length, 1);
      assert.strictEqual(mockProcess.stdin.end.mock.calls.length, 1);
    });

    it('should close stdin when no prompt', async () => {
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);
      
      mockMessageProcessor.parseStreamJsonOutput.mock.mockImplementation(() => [
        { type: 'result', message: 'Success' }
      ]);

      await processRunner.executeAICLICommand(mockSession, null);
      
      // Should only close stdin, no write
      assert.strictEqual(mockProcess.stdin.write.mock.calls.length, 0);
      assert.strictEqual(mockProcess.stdin.end.mock.calls.length, 1);
    });
  });
});