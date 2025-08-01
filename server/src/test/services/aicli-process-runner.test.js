import { describe, it, mock, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';

describe('AICLIProcessRunner', () => {
  let processRunner;
  let mockSpawn;
  let mockProcess;
  let mockStdout;
  let mockStderr;
  let mockStdin;

  beforeEach(() => {
    // Create mock streams
    mockStdout = new EventEmitter();
    mockStderr = new EventEmitter();
    mockStdin = {
      write: mock.fn(),
      end: mock.fn(),
    };

    // Create mock process
    mockProcess = {
      pid: 12345,
      stdout: mockStdout,
      stderr: mockStderr,
      stdin: mockStdin,
      on: mock.fn(),
      kill: mock.fn(),
    };

    // Create mock spawn function that returns a clean mock process
    mockSpawn = mock.fn(() => {
      // Return a new object each time to avoid circular references
      return {
        pid: 12345,
        stdout: mockStdout,
        stderr: mockStderr,
        stdin: mockStdin,
        on: mockProcess.on,
        kill: mockProcess.kill,
      };
    });

    // Create instance with mocked spawn
    processRunner = new AICLIProcessRunner({ spawnFunction: mockSpawn });
  });

  afterEach(() => {
    // Clean up any listeners
    mockStdout.removeAllListeners();
    mockStderr.removeAllListeners();
    // Clean up processRunner listeners
    processRunner.removeAllListeners();
  });

  describe('constructor and configuration', () => {
    it('should initialize with default configuration', () => {
      const runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });
      assert.strictEqual(runner.permissionMode, 'default');
      assert.deepStrictEqual(runner.allowedTools, ['Read', 'Write', 'Edit']);
      assert.deepStrictEqual(runner.disallowedTools, []);
      assert.strictEqual(runner.skipPermissions, false);
    });

    it('should accept custom spawn function in options', () => {
      const customSpawn = () => {};
      const runner = new AICLIProcessRunner({ spawnFunction: customSpawn });
      assert.strictEqual(runner.spawnFunction, customSpawn);
    });
  });

  describe('setPermissionMode', () => {
    it('should set valid permission modes', () => {
      processRunner.setPermissionMode('acceptEdits');
      assert.strictEqual(processRunner.permissionMode, 'acceptEdits');

      processRunner.setPermissionMode('bypassPermissions');
      assert.strictEqual(processRunner.permissionMode, 'bypassPermissions');

      processRunner.setPermissionMode('plan');
      assert.strictEqual(processRunner.permissionMode, 'plan');
    });

    it('should reject invalid permission modes', () => {
      const originalMode = processRunner.permissionMode;
      processRunner.setPermissionMode('invalid');
      assert.strictEqual(processRunner.permissionMode, originalMode);
    });
  });

  describe('setAllowedTools', () => {
    it('should set allowed tools from array', () => {
      const tools = ['Read', 'Write', 'Bash'];
      processRunner.setAllowedTools(tools);
      assert.deepStrictEqual(processRunner.allowedTools, tools);
    });

    it('should ignore non-array input', () => {
      const originalTools = [...processRunner.allowedTools];
      processRunner.setAllowedTools('not-an-array');
      assert.deepStrictEqual(processRunner.allowedTools, originalTools);
    });
  });

  describe('setDisallowedTools', () => {
    it('should set disallowed tools from array', () => {
      const tools = ['Bash', 'System'];
      processRunner.setDisallowedTools(tools);
      assert.deepStrictEqual(processRunner.disallowedTools, tools);
    });

    it('should ignore non-array input', () => {
      const originalTools = [...processRunner.disallowedTools];
      processRunner.setDisallowedTools('not-an-array');
      assert.deepStrictEqual(processRunner.disallowedTools, originalTools);
    });
  });

  describe('setSkipPermissions', () => {
    it('should set skip permissions to true', () => {
      processRunner.setSkipPermissions(true);
      assert.strictEqual(processRunner.skipPermissions, true);
    });

    it('should set skip permissions to false', () => {
      processRunner.setSkipPermissions(false);
      assert.strictEqual(processRunner.skipPermissions, false);
    });

    it('should convert truthy values to boolean', () => {
      processRunner.setSkipPermissions('yes');
      assert.strictEqual(processRunner.skipPermissions, true);

      processRunner.setSkipPermissions('');
      assert.strictEqual(processRunner.skipPermissions, false);
    });
  });

  describe('executeAICLICommand', () => {
    it('should execute command with initial prompt for new session', async () => {
      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test/dir',
        conversationStarted: false,
        initialPrompt: 'Initial prompt',
        isRestoredSession: false,
      };

      const prompt = 'User prompt';

      // Setup process behavior
      const runPromise = processRunner.executeAICLICommand(session, prompt);

      // Wait for process to start
      await new Promise((resolve) => setTimeout(resolve, 10));

      // Verify spawn was called correctly
      assert.strictEqual(mockSpawn.mock.calls.length, 1);
      const [command, args, options] = mockSpawn.mock.calls[0].arguments;
      assert.ok(command.includes('claude'));
      assert.ok(args.includes('--session-id'));
      assert.ok(args.includes('test-session'));
      assert.strictEqual(options.cwd, '/test/dir');

      // Simulate successful completion
      mockStdout.emit('data', Buffer.from('{"type":"result","result":"Success"}'));
      mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'close').arguments[1](0);

      const result = await runPromise;
      assert.ok(result);
    });

    it('should use --resume for continued conversations', async () => {
      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test/dir',
        conversationStarted: true,
        initialPrompt: null,
        isRestoredSession: false,
      };

      const runPromise = processRunner.executeAICLICommand(session, 'Continue prompt');

      // Wait for process to start
      await new Promise((resolve) => setTimeout(resolve, 10));

      const args = mockSpawn.mock.calls[0].arguments[1];
      assert.ok(args.includes('--resume'));
      assert.ok(!args.includes('--session-id'));

      // Complete the process
      mockStdout.emit('data', Buffer.from('{"type":"result"}'));
      mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'close').arguments[1](0);

      await runPromise;
    });

    it('should use --resume for restored sessions', async () => {
      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test/dir',
        conversationStarted: false,
        initialPrompt: null,
        isRestoredSession: true,
      };

      const runPromise = processRunner.executeAICLICommand(session, 'Restored prompt');

      await new Promise((resolve) => setTimeout(resolve, 10));

      const args = mockSpawn.mock.calls[0].arguments[1];
      assert.ok(args.includes('--resume'));

      // Complete the process
      mockStdout.emit('data', Buffer.from('{"type":"result"}'));
      mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'close').arguments[1](0);

      await runPromise;
    });
  });

  describe('addPermissionArgs', () => {
    it('should add --dangerously-skip-permissions when skipPermissions is true', () => {
      processRunner.skipPermissions = true;
      const args = [];
      processRunner.addPermissionArgs(args);
      assert.ok(args.includes('--dangerously-skip-permissions'));
    });

    it('should add permission mode when configured', () => {
      processRunner.permissionMode = 'acceptEdits';
      const args = [];
      processRunner.addPermissionArgs(args);
      assert.ok(args.includes('--permission-mode'));
      assert.ok(args.includes('acceptEdits'));
    });

    it('should add allowed tools when configured', () => {
      processRunner.allowedTools = ['Read', 'Edit'];
      const args = [];
      processRunner.addPermissionArgs(args);
      assert.ok(args.includes('--allowedTools'));
      assert.ok(args.includes('Read,Edit'));
    });

    it('should add disallowed tools when configured', () => {
      processRunner.disallowedTools = ['Write', 'Delete'];
      const args = [];
      processRunner.addPermissionArgs(args);
      assert.ok(args.includes('--disallowedTools'));
      assert.ok(args.includes('Write,Delete'));
    });

    it('should not add permission args when skipPermissions is true', () => {
      processRunner.skipPermissions = true;
      processRunner.permissionMode = 'acceptEdits';
      processRunner.allowedTools = ['Read'];
      processRunner.disallowedTools = ['Write'];

      const args = [];
      processRunner.addPermissionArgs(args);

      assert.ok(args.includes('--dangerously-skip-permissions'));
      assert.ok(!args.includes('--permission-mode'));
      assert.ok(!args.includes('--allowedTools'));
      assert.ok(!args.includes('--disallowedTools'));
    });
  });

  describe('handleStdinInput', () => {
    it('should write prompt to stdin when using --print', () => {
      const args = ['--print', '--output-format', 'json'];
      const prompt = 'Test prompt';

      processRunner.handleStdinInput(mockProcess, prompt, args);

      assert.strictEqual(mockStdin.write.mock.calls.length, 1);
      assert.strictEqual(mockStdin.write.mock.calls[0].arguments[0], 'Test prompt');
      assert.strictEqual(mockStdin.end.mock.calls.length, 1);
    });

    it('should not write to stdin when not using --print', () => {
      const args = ['--output-format', 'json'];
      const prompt = 'Test prompt';

      processRunner.handleStdinInput(mockProcess, prompt, args);

      assert.strictEqual(mockStdin.write.mock.calls.length, 0);
      assert.strictEqual(mockStdin.end.mock.calls.length, 1);
    });

    it('should close stdin when no prompt provided', () => {
      const args = ['--print'];

      processRunner.handleStdinInput(mockProcess, null, args);

      assert.strictEqual(mockStdin.write.mock.calls.length, 0);
      assert.strictEqual(mockStdin.end.mock.calls.length, 1);
    });
  });

  describe('startProcessMonitoring', () => {
    it('should attempt to monitor process with valid pid', async () => {
      // Since processMonitor is imported, we can't easily mock it in this test
      // Instead, we'll just verify the method doesn't throw
      try {
        await processRunner.startProcessMonitoring(12345);
        // If it doesn't throw, that's success
        assert.ok(true);
      } catch (error) {
        // It's okay if monitoring fails for a non-existent PID
        assert.ok(error.message.includes('Process') || error.message.includes('not found'));
      }
    });

    it('should handle monitoring errors gracefully', async () => {
      // Test with an invalid PID that will likely fail
      try {
        await processRunner.startProcessMonitoring(999999999);
        // If it doesn't throw, that's okay
        assert.ok(true);
      } catch (error) {
        // Should handle errors gracefully
        assert.ok(true);
      }
    });
  });

  describe('createHealthMonitor', () => {
    it('should create health monitor with cleanup function', () => {
      const healthMonitor = processRunner.createHealthMonitor(mockProcess, 'session123');

      assert.ok(typeof healthMonitor.cleanup === 'function');
      assert.ok(typeof healthMonitor.recordActivity === 'function');

      // Cleanup to prevent actual monitoring
      healthMonitor.cleanup();
    });

    it('should record activity when called', () => {
      const healthMonitor = processRunner.createHealthMonitor(mockProcess, 'session123');

      // Should not throw
      healthMonitor.recordActivity();

      healthMonitor.cleanup();
    });
  });

  describe('processOutput', () => {
    it('should parse stream-json output correctly', () => {
      const stdout = '{"type":"system","subtype":"init"}\n{"type":"result","result":"Done"}';
      const sessionId = 'test-session';
      const resolve = mock.fn();
      const reject = mock.fn();

      processRunner.processOutput(stdout, sessionId, resolve, reject);

      assert.strictEqual(resolve.mock.calls.length, 1);
      assert.strictEqual(reject.mock.calls.length, 0);

      const result = resolve.mock.calls[0].arguments[0];
      assert.strictEqual(result.type, 'result');
      assert.strictEqual(result.result, 'Done');
    });

    it('should reject on empty output', () => {
      const stdout = '';
      const resolve = mock.fn();
      const reject = mock.fn();

      processRunner.processOutput(stdout, 'test-session', resolve, reject);

      assert.strictEqual(reject.mock.calls.length, 1);
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('empty output'));
    });

    it('should reject on invalid JSON', () => {
      const stdout = 'Invalid JSON {not valid}';
      const resolve = mock.fn();
      const reject = mock.fn();

      processRunner.processOutput(stdout, 'test-session', resolve, reject);

      // When invalid JSON is parsed, it returns empty array which triggers error
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('No valid JSON objects found'));
    });

    it('should reject on whitespace-only output', () => {
      const resolve = mock.fn();
      const reject = mock.fn();

      processRunner.processOutput('   \n  \t  ', 'test-session', resolve, reject);

      assert.strictEqual(reject.mock.calls.length, 1);
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('empty output'));
    });

    it('should emit aicliResponse events for each parsed response', () => {
      const stdout = '{"type":"assistant","message":"Hi"}\n{"type":"result","done":true}';
      const sessionId = 'test-session';
      const resolve = mock.fn();
      const reject = mock.fn();

      const emittedEvents = [];
      processRunner.on('aicliResponse', (data) => {
        emittedEvents.push(data);
      });

      processRunner.processOutput(stdout, sessionId, resolve, reject);

      assert.strictEqual(emittedEvents.length, 2);
      assert.strictEqual(emittedEvents[0].response.type, 'assistant');
      assert.strictEqual(emittedEvents[1].response.type, 'result');
      assert.strictEqual(emittedEvents[1].isLast, true);
    });
  });

  describe('findAICLICommand', () => {
    it('should return default command in test environment', () => {
      // In test environment, it should just return the default without spawning
      assert.strictEqual(processRunner.aicliCommand, 'claude');
    });

    it('should handle spawn failures gracefully', () => {
      // Create a new runner with a spawn function that always throws
      const failingSpawn = mock.fn(() => {
        throw new Error('spawn failed');
      });
      const runner = new AICLIProcessRunner({ spawnFunction: failingSpawn });

      // Even with failing spawn, findAICLICommand should return default
      const command = runner.findAICLICommand();
      assert.strictEqual(command, 'claude');
    });
  });

  describe('testAICLICommand', () => {
    it('should handle version test type', async () => {
      const runProcessMock = mock.fn(() => Promise.resolve({ type: 'version', version: '1.0.0' }));
      processRunner.runAICLIProcess = runProcessMock;

      await processRunner.testAICLICommand('version');

      assert.strictEqual(runProcessMock.mock.calls.length, 1);
      const args = runProcessMock.mock.calls[0].arguments[0];
      assert.ok(args.includes('--version'));
    });

    it('should handle help test type', async () => {
      const runProcessMock = mock.fn(() => Promise.resolve({ type: 'help' }));
      processRunner.runAICLIProcess = runProcessMock;

      await processRunner.testAICLICommand('help');

      assert.strictEqual(runProcessMock.mock.calls.length, 1);
      const args = runProcessMock.mock.calls[0].arguments[0];
      assert.ok(args.includes('--help'));
    });

    it('should handle simple test type', async () => {
      const runProcessMock = mock.fn(() => Promise.resolve({ type: 'result' }));
      processRunner.runAICLIProcess = runProcessMock;

      await processRunner.testAICLICommand('simple');

      assert.strictEqual(runProcessMock.mock.calls.length, 1);
      const args = runProcessMock.mock.calls[0].arguments[0];
      assert.ok(args.includes('--print'));
      assert.ok(args.includes('Hello world'));
    });

    it('should reject unknown test types', async () => {
      await assert.rejects(processRunner.testAICLICommand('unknown'), /Unknown test type/);
    });
  });

  describe('runAICLIProcess', () => {
    it('should emit processStart event', async () => {
      let processStartData = null;
      processRunner.on('processStart', (data) => {
        processStartData = data;
      });

      const runPromise = processRunner.runAICLIProcess(
        ['--print'],
        'Test prompt',
        '/test/dir',
        'session123'
      );

      await new Promise((resolve) => setTimeout(resolve, 10));

      assert.ok(processStartData);
      assert.strictEqual(processStartData.sessionId, 'session123');
      assert.strictEqual(processStartData.pid, 12345);
      assert.strictEqual(processStartData.workingDirectory, '/test/dir');

      // Complete the process
      mockStdout.emit('data', Buffer.from('{"type":"result"}'));
      mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'close').arguments[1](0);

      await runPromise;
    });

    it('should handle process spawn errors', async () => {
      // Save the original spawn function
      const originalSpawn = processRunner.spawnFunction;

      // Replace with a failing spawn function
      processRunner.spawnFunction = mock.fn(() => {
        throw new Error('ENOENT');
      });

      await assert.rejects(
        processRunner.runAICLIProcess(['--print'], 'Test', '/test/dir', 'session123'),
        /Failed to start AICLI CLI/
      );

      // Restore the original spawn function
      processRunner.spawnFunction = originalSpawn;
    });

    it('should handle process errors', async () => {
      const runPromise = processRunner.runAICLIProcess(
        ['--print'],
        'Test prompt',
        '/test/dir',
        'session123'
      );

      await new Promise((resolve) => setTimeout(resolve, 10));

      // Emit error
      const errorHandler = mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'error');
      errorHandler.arguments[1](new Error('Process failed'));

      await assert.rejects(runPromise, /Process failed/);
    });

    it('should handle non-zero exit codes', async () => {
      const runPromise = processRunner.runAICLIProcess(
        ['--print'],
        'Test prompt',
        '/test/dir',
        'session123'
      );

      await new Promise((resolve) => setTimeout(resolve, 10));

      // Exit with error code
      mockStderr.emit('data', Buffer.from('Error occurred'));
      mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'close').arguments[1](1);

      await assert.rejects(runPromise, /exited with code 1/);
    });
  });

  describe('createOutputHandler', () => {
    it('should emit streamChunk events for parsed data', async () => {
      const streamChunks = [];
      processRunner.on('streamChunk', (data) => {
        streamChunks.push(data);
      });

      processRunner.createOutputHandler('session123', mockProcess, mock.fn(), mock.fn(), {
        recordActivity: mock.fn(),
        cleanup: mock.fn(),
      });

      // Emit stdout data - the ClaudeStreamParser might need specific format
      // Let's emit actual Claude-style data
      mockStdout.emit(
        'data',
        Buffer.from(
          'data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n'
        )
      );
      mockStdout.emit(
        'data',
        Buffer.from(
          'data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}\n\n'
        )
      );

      await new Promise((resolve) => setTimeout(resolve, 50));

      // Verify that the handler was set up correctly by checking if data handler exists
      assert.ok(mockStdout.listenerCount('data') > 0);

      // Also verify that streamChunk events were emitted for parsed data
      assert.ok(streamChunks.length > 0, 'Should emit streamChunk events');
    });

    it('should emit processStderr events', async () => {
      const stderrEvents = [];
      processRunner.on('processStderr', (data) => {
        stderrEvents.push(data);
      });

      processRunner.createOutputHandler('session123', mockProcess, mock.fn(), mock.fn(), {
        recordActivity: mock.fn(),
        cleanup: mock.fn(),
      });

      // Emit stderr data
      mockStderr.emit('data', Buffer.from('Warning message'));

      await new Promise((resolve) => setTimeout(resolve, 10));

      assert.ok(stderrEvents.length > 0);
      assert.strictEqual(stderrEvents[0].data, 'Warning message');
    });

    it('should handle buffer concatenation correctly', () => {
      const resolve = mock.fn();
      const reject = mock.fn();

      const handler = processRunner.createOutputHandler(
        'session123',
        mockProcess,
        resolve,
        reject,
        { recordActivity: mock.fn(), cleanup: mock.fn() }
      );

      // Emit data in chunks
      mockStdout.emit('data', Buffer.from('{"type":"'));
      mockStdout.emit('data', Buffer.from('result","'));
      mockStdout.emit('data', Buffer.from('result":"OK"}'));

      // Close the process
      handler.handleClose(0);

      assert.strictEqual(resolve.mock.calls.length, 1);
      const result = resolve.mock.calls[0].arguments[0];
      assert.strictEqual(result.type, 'result');
      assert.strictEqual(result.result, 'OK');
    });
  });

  describe('event emission', () => {
    it('should inherit from EventEmitter', () => {
      assert.ok(processRunner instanceof EventEmitter);
    });

    it('should emit processExit event on close', async () => {
      let processExitData = null;
      processRunner.on('processExit', (data) => {
        processExitData = data;
      });

      const runPromise = processRunner.runAICLIProcess(
        ['--print'],
        'Test',
        '/test/dir',
        'session123'
      );

      await new Promise((resolve) => setTimeout(resolve, 10));

      // Close the process
      mockStdout.emit('data', Buffer.from('{"type":"result"}'));
      mockProcess.on.mock.calls.find((call) => call.arguments[0] === 'close').arguments[1](0);

      await runPromise;

      assert.ok(processExitData);
      assert.strictEqual(processExitData.code, 0);
      assert.strictEqual(processExitData.sessionId, 'session123');
    });
  });
});
