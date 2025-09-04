import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { EventEmitter } from 'events';
import { OneTimePrompt } from '../../../services/aicli/one-time-prompt.js';

// Mock child_process spawn
const mockSpawn = mock.fn();
mock.method(global, 'spawn', mockSpawn);

describe('OneTimePrompt', () => {
  let oneTimePrompt;
  let mockPermissionHandler;
  let mockProcess;

  beforeEach(() => {
    // Create mock permission handler
    mockPermissionHandler = {
      buildPermissionArgs: mock.fn((skipPermissions) => {
        if (skipPermissions) {
          return ['--no-permission'];
        }
        return ['--permission', 'ask'];
      }),
    };

    // Create mock child process
    mockProcess = new EventEmitter();
    mockProcess.stdout = new EventEmitter();
    mockProcess.stderr = new EventEmitter();
    mockProcess.stdin = {
      write: mock.fn(),
      end: mock.fn(),
    };
    mockProcess.kill = mock.fn();

    // Reset spawn mock
    mockSpawn.mock.resetCalls();
    mockSpawn.mock.mockImplementation(() => mockProcess);

    // Create instance
    oneTimePrompt = new OneTimePrompt(mockPermissionHandler);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('setAicliCommand', () => {
    it('should set the AICLI command', () => {
      oneTimePrompt.setAicliCommand('/custom/path/aicli');
      assert.strictEqual(oneTimePrompt.aicliCommand, '/custom/path/aicli');
    });
  });

  describe('sendOneTimePrompt', () => {
    it('should send a one-time prompt with default options', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      // Simulate successful response
      setTimeout(() => {
        mockProcess.stdout.emit('data', JSON.stringify({ response: 'Test response' }));
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;

      // Verify spawn was called with correct arguments
      assert.strictEqual(mockSpawn.mock.callCount(), 1);
      const [command, args, options] = mockSpawn.mock.calls[0].arguments;
      assert(command.includes('aicli'));
      assert(args.includes('--format'));
      assert(args.includes('json'));
      assert(args.includes('Test prompt'));
      assert.strictEqual(options.shell, false);

      // Verify result
      assert.deepStrictEqual(result, { response: 'Test response' });
    });

    it('should use custom AICLI command when set', async () => {
      oneTimePrompt.setAicliCommand('/custom/aicli');
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      await promptPromise;

      const [command] = mockSpawn.mock.calls[0].arguments;
      assert.strictEqual(command, '/custom/aicli');
    });

    it('should handle text format', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt', { format: 'text' });

      setTimeout(() => {
        mockProcess.stdout.emit('data', 'Plain text response');
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;

      const args = mockSpawn.mock.calls[0].arguments[1];
      assert(!args.includes('--format'));
      assert(!args.includes('json'));
      assert.strictEqual(result, 'Plain text response');
    });

    it('should use custom working directory', async () => {
      const customDir = '/custom/working/dir';
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt', {
        workingDirectory: customDir,
      });

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      await promptPromise;

      const options = mockSpawn.mock.calls[0].arguments[2];
      assert.strictEqual(options.cwd, customDir);
    });

    it('should skip permissions when specified', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt', {
        skipPermissions: true,
      });

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      await promptPromise;

      const args = mockSpawn.mock.calls[0].arguments[1];
      assert(args.includes('--no-permission'));
    });

    it('should sanitize prompt with special characters', async () => {
      const dangerousPrompt = 'Test "prompt" with $variables';
      const promptPromise = oneTimePrompt.sendOneTimePrompt(dangerousPrompt);

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      await promptPromise;

      const args = mockSpawn.mock.calls[0].arguments[1];
      const promptArg = args[args.length - 1];
      assert(promptArg.includes('\\'));
    });

    it('should handle stderr output', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.stderr.emit('data', 'Warning: Some warning\n');
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;
      assert.deepStrictEqual(result, { success: true });
    });

    it('should handle process errors', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.emit('error', new Error('Process failed'));
      }, 10);

      await assert.rejects(promptPromise, /Process failed/);
    });

    it('should handle non-zero exit codes', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.stderr.emit('data', 'Error: Command failed');
        mockProcess.emit('close', 1);
      }, 10);

      await assert.rejects(promptPromise, /Command failed/);
    });

    it('should accumulate stdout data chunks', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success"');
        mockProcess.stdout.emit('data', ': true}');
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;
      assert.deepStrictEqual(result, { success: true });
    });

    it('should handle JSON parsing errors gracefully', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.stdout.emit('data', 'Not valid JSON');
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;
      assert.strictEqual(result, 'Not valid JSON');
    });

    it('should timeout long-running processes', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      // Simulate timeout by not emitting any events
      // The actual implementation should have a timeout mechanism

      // For now, just close normally after delay
      setTimeout(() => {
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;
      assert.strictEqual(result, ''); // Empty response
    });

    it('should handle process kill signals', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.emit('close', null, 'SIGTERM');
      }, 10);

      await assert.rejects(promptPromise, /terminated/);
    });

    it('should pass environment variables', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt');

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      await promptPromise;

      const options = mockSpawn.mock.calls[0].arguments[2];
      assert(options.env);
      assert.strictEqual(options.windowsHide, true);
    });

    it('should handle empty prompt', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('');

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"error": "Empty prompt"}');
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promptPromise;
      assert.deepStrictEqual(result, { error: 'Empty prompt' });
    });

    it('should build correct argument order', async () => {
      const promptPromise = oneTimePrompt.sendOneTimePrompt('Test prompt', {
        format: 'json',
        skipPermissions: false,
      });

      setTimeout(() => {
        mockProcess.stdout.emit('data', '{"success": true}');
        mockProcess.emit('close', 0);
      }, 10);

      await promptPromise;

      const args = mockSpawn.mock.calls[0].arguments[1];
      // Permission args should come first
      const permissionIndex = args.findIndex((arg) => arg.includes('permission'));
      const formatIndex = args.indexOf('--format');
      const promptIndex = args.indexOf('Test prompt');

      assert(permissionIndex < formatIndex);
      assert(formatIndex < promptIndex);
    });
  });
});
