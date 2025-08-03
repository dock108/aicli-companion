import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'events';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';

// Mock child process
class MockChildProcess extends EventEmitter {
  constructor() {
    super();
    this.pid = 12345;
    this.stdin = {
      write: () => {},
      end: () => {},
    };
    this.stdout = new EventEmitter();
    this.stderr = new EventEmitter();
  }
}

describe('AICLIProcessRunner - Additional Coverage', () => {
  let runner;
  let mockSpawn;
  let spawnedProcess;

  beforeEach(() => {
    spawnedProcess = null;
    mockSpawn = (_command, _args, _options) => {
      spawnedProcess = new MockChildProcess();
      return spawnedProcess;
    };

    runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });
  });

  afterEach(() => {
    if (spawnedProcess) {
      spawnedProcess.removeAllListeners();
    }
  });

  describe('Permission Configuration', () => {
    it('should set permission mode', () => {
      runner.setPermissionMode('acceptEdits');
      assert.strictEqual(runner.permissionMode, 'acceptEdits');
    });

    it('should ignore invalid permission modes', () => {
      runner.setPermissionMode('invalid');
      assert.strictEqual(runner.permissionMode, 'default');
    });

    it('should set allowed tools', () => {
      runner.setAllowedTools(['Read', 'Write']);
      assert.deepStrictEqual(runner.allowedTools, ['Read', 'Write']);
    });

    it('should set disallowed tools', () => {
      runner.setDisallowedTools(['Bash', 'Edit']);
      assert.deepStrictEqual(runner.disallowedTools, ['Bash', 'Edit']);
    });

    it('should set skip permissions', () => {
      runner.setSkipPermissions(true);
      assert.strictEqual(runner.skipPermissions, true);
    });
  });

  describe('addPermissionArgs', () => {
    it('should add permission args when not skipping', () => {
      runner.setPermissionMode('plan');
      runner.setAllowedTools(['Read', 'Write']);
      runner.setDisallowedTools(['Bash']);

      const args = [];
      runner.addPermissionArgs(args);

      assert.ok(args.includes('--permission-mode'));
      assert.ok(args.includes('plan'));
      assert.ok(args.includes('--allowedTools'));
      assert.ok(args.includes('Read,Write'));
      assert.ok(args.includes('--disallowedTools'));
      assert.ok(args.includes('Bash'));
    });

    it('should skip permission args when skipPermissions is true', () => {
      runner.setSkipPermissions(true);
      runner.setPermissionMode('plan');

      const args = [];
      runner.addPermissionArgs(args);

      assert.ok(args.includes('--dangerously-skip-permissions'));
      assert.ok(!args.includes('--permission-mode'));
    });
  });

  describe('testAICLICommand', () => {
    it('should test version command', async () => {
      const versionPromise = runner.testAICLICommand('version');

      // Simulate successful version output
      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result","version":"1.0.0"}\n'));
        spawnedProcess.emit('close', 0);
      });

      const result = await versionPromise;
      assert.ok(result);
    });

    it('should test help command', async () => {
      const helpPromise = runner.testAICLICommand('help');

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result","help":"..."}\n'));
        spawnedProcess.emit('close', 0);
      });

      const result = await helpPromise;
      assert.ok(result);
    });

    it('should test simple command', async () => {
      const simplePromise = runner.testAICLICommand('simple');

      process.nextTick(() => {
        spawnedProcess.stdout.emit(
          'data',
          Buffer.from('{"type":"result","response":"Hello world"}\n')
        );
        spawnedProcess.emit('close', 0);
      });

      const result = await simplePromise;
      assert.ok(result);
    });

    it('should test json command', async () => {
      const jsonPromise = runner.testAICLICommand('json');

      process.nextTick(() => {
        spawnedProcess.stdout.emit(
          'data',
          Buffer.from('{"type":"result","response":"Hello world"}\n')
        );
        spawnedProcess.emit('close', 0);
      });

      const result = await jsonPromise;
      assert.ok(result);
    });

    it('should throw on unknown test type', async () => {
      await assert.rejects(runner.testAICLICommand('unknown'), /Unknown test type/);
    });
  });

  describe('Stream parsing and event emission', () => {
    it('should emit streamChunk events for parsed chunks', async () => {
      const chunks = [];
      runner.on('streamChunk', (data) => chunks.push(data));

      const promise = runner.runAICLIProcess(
        ['--test'],
        'test prompt',
        '/test/dir',
        'test-session'
      );

      process.nextTick(() => {
        // Send valid JSON output with stream content
        spawnedProcess.stdout.emit(
          'data',
          Buffer.from('{"type":"content","content":"Regular text output"}\n')
        );
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"content","content":"## Code"}\n'));
        spawnedProcess.stdout.emit(
          'data',
          Buffer.from('{"type":"content","content":"```javascript\\nconst x = 1;\\n```"}\n')
        );
        spawnedProcess.emit('close', 0);
      });

      await promise;
      assert.ok(chunks.length > 0);
    });

    it('should emit processStderr events', async () => {
      const stderrEvents = [];
      runner.on('processStderr', (data) => stderrEvents.push(data));

      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.stderr.emit('data', Buffer.from('Warning: test warning\n'));
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result"}\n'));
        spawnedProcess.emit('close', 0);
      });

      await promise;
      assert.strictEqual(stderrEvents.length, 1);
      assert.ok(stderrEvents[0].data.includes('Warning'));
    });
  });

  describe('Error handling', () => {
    it('should handle spawn errors', async () => {
      const errorSpawn = () => {
        const error = new Error('spawn failed');
        error.code = 'ENOENT';
        throw error;
      };

      const errorRunner = new AICLIProcessRunner({ spawnFunction: errorSpawn });

      await assert.rejects(
        errorRunner.runAICLIProcess(['--test'], null, '/test', 'session'),
        /AICLI CLI not found/
      );
    });

    it('should handle process errors', async () => {
      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.emit('error', new Error('Process failed'));
      });

      await assert.rejects(promise, /Process failed/);
    });

    it('should handle non-zero exit codes', async () => {
      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.stderr.emit('data', Buffer.from('Error occurred\n'));
        spawnedProcess.emit('close', 1);
      });

      await assert.rejects(promise, /exited with code 1/);
    });

    it('should handle empty output', async () => {
      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.emit('close', 0);
      });

      await assert.rejects(promise, /empty output/);
    });

    it('should handle invalid JSON output', async () => {
      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('not valid json\n'));
        spawnedProcess.emit('close', 0);
      });

      await assert.rejects(promise, /No valid JSON objects found/);
    });
  });

  describe('executeAICLICommand', () => {
    it('should handle session with initial prompt', async () => {
      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test',
        conversationStarted: false,
        initialPrompt: 'Initial context',
      };

      const promise = runner.executeAICLICommand(session, 'User command');

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result","response":"ok"}\n'));
        spawnedProcess.emit('close', 0);
      });

      const result = await promise;
      assert.ok(result);
    });

    it('should handle restored session', async () => {
      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test',
        conversationStarted: false,
        isRestoredSession: true,
      };

      const promise = runner.executeAICLICommand(session, 'Command');

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result"}\n'));
        spawnedProcess.emit('close', 0);
      });

      const result = await promise;
      assert.ok(result);
    });
  });

  describe('Health monitoring', () => {
    it('should create and cleanup health monitor', async () => {
      let monitorCleaned = false;

      // Override createHealthMonitor to track cleanup
      runner.createHealthMonitor = (_proc, _sessionId) => {
        return {
          recordActivity: () => {},
          cleanup: () => {
            monitorCleaned = true;
          },
        };
      };

      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result"}\n'));
        spawnedProcess.emit('close', 0);
      });

      await promise;
      assert.ok(monitorCleaned);
    });
  });

  describe('Process output handling', () => {
    it('should handle truncation error messages', async () => {
      const promise = runner.runAICLIProcess(['--test'], null, '/test/dir', 'test-session');

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"unterminated": "string...'));
        spawnedProcess.emit('close', 0);
      });

      await assert.rejects(promise, /No valid JSON objects found/);
    });

    it('should write prompt to stdin when using --print', async () => {
      let stdinWritten = false;
      let stdinEnded = false;

      spawnedProcess = null;
      mockSpawn = (_command, _args, _options) => {
        const proc = new MockChildProcess();
        proc.stdin = {
          write: (_data) => {
            stdinWritten = true;
          },
          end: () => {
            stdinEnded = true;
          },
        };
        spawnedProcess = proc;
        return proc;
      };

      runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });

      const promise = runner.runAICLIProcess(
        ['--print', '--test'],
        'test prompt',
        '/test/dir',
        'test-session'
      );

      process.nextTick(() => {
        spawnedProcess.stdout.emit('data', Buffer.from('{"type":"result"}\n'));
        spawnedProcess.emit('close', 0);
      });

      await promise;
      assert.ok(stdinWritten);
      assert.ok(stdinEnded);
    });
  });
});
