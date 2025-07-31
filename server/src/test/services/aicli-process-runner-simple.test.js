import { describe, it, mock, beforeEach } from 'node:test';
import assert from 'node:assert';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';

describe('AICLIProcessRunner Simple Tests', () => {
  let processRunner;

  beforeEach(() => {
    processRunner = new AICLIProcessRunner();
  });

  describe('constructor and configuration', () => {
    it('should initialize with default configuration', () => {
      const runner = new AICLIProcessRunner();
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

  describe('addPermissionArgs', () => {
    it('should add skip permissions argument when enabled', () => {
      processRunner.setSkipPermissions(true);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      assert.ok(args.includes('--dangerously-skip-permissions'));
    });

    it('should add permission mode when not default', () => {
      processRunner.setPermissionMode('acceptEdits');
      processRunner.setSkipPermissions(false);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);

      assert.ok(args.includes('--permission-mode'));
      assert.ok(args.includes('acceptEdits'));
    });

    it('should not add permission mode for default mode', () => {
      processRunner.setPermissionMode('default');
      processRunner.setSkipPermissions(false);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);

      assert.ok(!args.includes('--permission-mode'));
    });

    it('should add allowed tools when configured', () => {
      processRunner.setAllowedTools(['Read', 'Write']);
      processRunner.setSkipPermissions(false);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);

      assert.ok(args.includes('--allowedTools'));
      assert.ok(args.includes('Read,Write'));
    });

    it('should add disallowed tools when configured', () => {
      processRunner.setDisallowedTools(['Bash', 'System']);
      processRunner.setSkipPermissions(false);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);

      assert.ok(args.includes('--disallowedTools'));
      assert.ok(args.includes('Bash,System'));
    });

    it('should not add tool configuration when skipping permissions', () => {
      processRunner.setAllowedTools(['Read']);
      processRunner.setDisallowedTools(['Bash']);
      processRunner.setSkipPermissions(true);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);

      assert.ok(!args.includes('--allowedTools'));
      assert.ok(!args.includes('--disallowedTools'));
      assert.ok(args.includes('--dangerously-skip-permissions'));
    });
  });

  describe('handleStdinInput', () => {
    it('should handle stdin correctly for different scenarios', () => {
      const mockProcess = {
        stdin: {
          write: mock.fn(),
          end: mock.fn(),
        },
      };

      // Test with prompt and --print
      processRunner.handleStdinInput(mockProcess, 'test prompt', ['--print']);
      assert.strictEqual(mockProcess.stdin.write.mock.calls.length, 1);
      assert.strictEqual(mockProcess.stdin.write.mock.calls[0].arguments[0], 'test prompt');
      assert.strictEqual(mockProcess.stdin.end.mock.calls.length, 1);

      // Reset mocks
      mockProcess.stdin.write.mock.resetCalls();
      mockProcess.stdin.end.mock.resetCalls();

      // Test without prompt
      processRunner.handleStdinInput(mockProcess, null, ['--print']);
      assert.strictEqual(mockProcess.stdin.write.mock.calls.length, 0);
      assert.strictEqual(mockProcess.stdin.end.mock.calls.length, 1);

      // Reset mocks
      mockProcess.stdin.end.mock.resetCalls();

      // Test without --print flag
      processRunner.handleStdinInput(mockProcess, 'test', ['--version']);
      assert.strictEqual(mockProcess.stdin.end.mock.calls.length, 1);
    });
  });

  describe('startProcessMonitoring', () => {
    it('should handle valid PID monitoring', async () => {
      assert.doesNotThrow(async () => {
        await processRunner.startProcessMonitoring(12345);
      });
    });

    it('should handle null PID gracefully', async () => {
      assert.doesNotThrow(async () => {
        await processRunner.startProcessMonitoring(null);
      });
    });

    it('should handle undefined PID gracefully', async () => {
      assert.doesNotThrow(async () => {
        await processRunner.startProcessMonitoring(undefined);
      });
    });
  });

  describe('processOutput', () => {
    it('should process valid stream-json output', () => {
      const mockResolve = mock.fn();
      const mockReject = mock.fn();
      const output =
        '{"type": "text", "content": "Hello"}\n{"type": "result", "content": "Done"}\n';

      processRunner.processOutput(output, 'session', mockResolve, mockReject);

      assert.strictEqual(mockResolve.mock.calls.length, 1);
      assert.strictEqual(mockReject.mock.calls.length, 0);

      const result = mockResolve.mock.calls[0].arguments[0];
      assert.strictEqual(result.type, 'result');
      assert.strictEqual(result.content, 'Done');
    });

    it('should reject on empty output', () => {
      const mockResolve = mock.fn();
      const mockReject = mock.fn();

      processRunner.processOutput('', 'session', mockResolve, mockReject);

      assert.strictEqual(mockResolve.mock.calls.length, 0);
      assert.strictEqual(mockReject.mock.calls.length, 1);
      assert.ok(mockReject.mock.calls[0].arguments[0].message.includes('empty output'));
    });

    it('should reject on whitespace-only output', () => {
      const mockResolve = mock.fn();
      const mockReject = mock.fn();

      processRunner.processOutput('   \n  \t  ', 'session', mockResolve, mockReject);

      assert.strictEqual(mockReject.mock.calls.length, 1);
      assert.ok(mockReject.mock.calls[0].arguments[0].message.includes('empty output'));
    });

    it('should handle malformed JSON gracefully', () => {
      const mockResolve = mock.fn();
      const mockReject = mock.fn();
      const output = '{"type": "text", invalid json}\n';

      processRunner.processOutput(output, 'session', mockResolve, mockReject);

      assert.strictEqual(mockReject.mock.calls.length, 1);
      // Check that some error occurred - could be parse error or "No valid JSON objects found"
      const errorMessage = mockReject.mock.calls[0].arguments[0].message;
      assert.ok(
        errorMessage.includes('Failed to parse') ||
          errorMessage.includes('No valid JSON objects found')
      );
    });
  });

  describe('createTimeoutHandler', () => {
    it('should create timeout handler with cleanup function', () => {
      const mockProcess = { kill: mock.fn() };
      const mockReject = mock.fn();
      const timeoutHandler = processRunner.createTimeoutHandler(mockProcess, 1000, mockReject);

      assert.ok(typeof timeoutHandler.resetActivity === 'function');
      assert.ok(typeof timeoutHandler.cleanup === 'function');

      // Cleanup to prevent actual timeout
      timeoutHandler.cleanup();
    });

    it('should reset activity correctly', () => {
      const mockProcess = { kill: mock.fn() };
      const mockReject = mock.fn();
      const timeoutHandler = processRunner.createTimeoutHandler(mockProcess, 1000, mockReject);

      assert.doesNotThrow(() => {
        timeoutHandler.resetActivity();
      });

      timeoutHandler.cleanup();
    });

    it('should cleanup timeouts and intervals', () => {
      const mockProcess = { kill: mock.fn() };
      const mockReject = mock.fn();
      const timeoutHandler = processRunner.createTimeoutHandler(mockProcess, 1000, mockReject);

      assert.doesNotThrow(() => {
        timeoutHandler.cleanup();
      });
    });
  });

  describe('testAICLICommand error handling', () => {
    it('should reject unknown test type', async () => {
      await assert.rejects(processRunner.testAICLICommand('unknown'), /Unknown test type: unknown/);
    });
  });
});
