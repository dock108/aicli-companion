import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'events';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';

describe('AICLI Process Runner - Basic Tests', () => {
  let processRunner;

  beforeEach(() => {
    // Always use test mode to avoid spawning real processes
    process.env.NODE_ENV = 'test';
    processRunner = new AICLIProcessRunner();
  });

  describe('Configuration', () => {
    it('should create instance with default options', () => {
      assert.ok(processRunner);
      // _aicliCommand is lazily initialized as null, use the getter instead
      assert.ok(processRunner.aicliCommand);
    });

    it('should set permission mode', () => {
      processRunner.setPermissionMode('strict');
      assert.ok(processRunner);
    });

    it('should set allowed tools', () => {
      processRunner.setAllowedTools(['Read', 'Write']);
      assert.ok(processRunner.allowedTools);
      assert.strictEqual(processRunner.allowedTools.length, 2);
    });

    it('should set disallowed tools', () => {
      processRunner.setDisallowedTools(['Bash']);
      assert.ok(processRunner.disallowedTools);
      assert.strictEqual(processRunner.disallowedTools.length, 1);
    });

    it('should set skip permissions', () => {
      processRunner.setSkipPermissions(true);
      assert.strictEqual(processRunner.skipPermissions, true);
    });
  });

  describe('Health Monitor', () => {
    it('should create health monitor', () => {
      const monitor = processRunner.createHealthMonitor({ pid: 12345 }, 'test-session');
      assert.ok(monitor);
      assert.ok(monitor.recordActivity);
      assert.ok(monitor.cleanup);

      // Cleanup to avoid interval leak
      monitor.cleanup();
    });

    it('should handle null process in health monitor', () => {
      const monitor = processRunner.createHealthMonitor(null, 'test-session');
      assert.ok(monitor);
      monitor.cleanup();
    });
  });

  describe('Command Finding', () => {
    it('should find AICLI command in test mode', () => {
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'claude');
    });
  });

  describe('Permission Arguments', () => {
    it('should add permission args when configured', () => {
      processRunner.setSkipPermissions(true);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      // The actual implementation uses --dangerously-skip-permissions
      assert.ok(args.includes('--dangerously-skip-permissions'));
    });

    it('should add allowed tools to args when skip permissions is disabled', () => {
      processRunner.setSkipPermissions(false); // Disable skip permissions first
      processRunner.setAllowedTools(['Read', 'Write']);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      // The actual implementation uses --allowedTools (camelCase)
      assert.ok(args.includes('--allowedTools'));
    });

    it('should add disallowed tools to args when skip permissions is disabled', () => {
      processRunner.setSkipPermissions(false); // Disable skip permissions first
      processRunner.setDisallowedTools(['Bash']);
      const args = ['--print'];
      processRunner.addPermissionArgs(args);
      // The actual implementation uses --disallowedTools (camelCase)
      assert.ok(args.includes('--disallowedTools'));
    });
  });

  describe('createInteractiveSession', () => {
    it('should reject when spawn fails', async () => {
      const mockSpawn = () => {
        throw new Error('Spawn failed');
      };

      const runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });

      await assert.rejects(
        () => runner.createInteractiveSession('/test/dir'),
        /Failed to start Claude CLI/
      );
    });

    it('should reject when process has no PID', async () => {
      const mockSpawn = () => ({
        pid: null,
        stdout: new EventEmitter(),
        stderr: new EventEmitter(),
        stdin: { write: () => {} },
        on: () => {},
      });

      const runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });

      await assert.rejects(() => runner.createInteractiveSession('/test/dir'), /no PID/);
    });

    it('should resolve with process and session info', async () => {
      const mockProcess = new EventEmitter();
      mockProcess.pid = 12345;
      mockProcess.stdout = new EventEmitter();
      mockProcess.stderr = new EventEmitter();
      mockProcess.stdin = { write: () => {} };

      const mockSpawn = () => mockProcess;

      const runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });

      const promise = runner.createInteractiveSession('/test/dir');

      // Simulate initial response
      setTimeout(() => {
        mockProcess.stdout.emit(
          'data',
          `${JSON.stringify({
            type: 'system',
            subtype: 'init',
            session_id: 'test-session-123',
          })}\n`
        );
      }, 10);

      const result = await promise;
      assert.ok(result);
      assert.ok(result.process);
      assert.strictEqual(result.process.pid, 12345);
      assert.strictEqual(result.sessionId, 'test-session-123');
    });
  });

  describe('sendToInteractiveSession', () => {
    it('should send message to process stdin', async () => {
      let writtenData = '';
      const mockProcess = {
        stdin: {
          write: (data, callback) => {
            writtenData = data;
            if (callback) callback();
          },
        },
        stdout: new EventEmitter(),
        stderr: new EventEmitter(),
      };

      const sessionInfo = {
        process: mockProcess,
        sessionId: 'test-session',
      };

      const runner = new AICLIProcessRunner();

      // Set up the promise to resolve
      const promise = runner.sendToInteractiveSession(sessionInfo, 'Hello Claude');

      // Simulate response
      setTimeout(() => {
        mockProcess.stdout.emit(
          'data',
          `${JSON.stringify({ type: 'result', result: 'Response', session_id: 'test-session' })}\n`
        );
      }, 10);

      const _result = await promise;
      assert.ok(writtenData.includes('Hello Claude'));
    });

    it('should handle process error on stdin write', async () => {
      const mockProcess = {
        stdin: {
          write: (data, callback) => {
            if (callback) callback(new Error('Write failed'));
          },
        },
        stdout: new EventEmitter(),
        stderr: new EventEmitter(),
      };

      const sessionInfo = {
        process: mockProcess,
        sessionId: 'test-session',
      };

      const runner = new AICLIProcessRunner();
      await assert.rejects(
        () => runner.sendToInteractiveSession(sessionInfo, 'Hello'),
        /Write failed/
      );
    });
  });

  describe('executeAICLICommand', () => {
    it('should execute AICLI command with session', async () => {
      const mockProcess = new EventEmitter();
      mockProcess.pid = 12345;
      mockProcess.stdout = new EventEmitter();
      mockProcess.stderr = new EventEmitter();
      mockProcess.stdin = {
        write: (data, encoding, callback) => {
          if (callback) callback();
        },
        end: () => {},
      };

      const mockSpawn = () => mockProcess;

      const runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });

      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test/dir',
        requestId: 'req-123',
      };

      const promise = runner.executeAICLICommand(session, 'Test message');

      // Simulate process output and exit
      setTimeout(() => {
        mockProcess.stdout.emit(
          'data',
          `${JSON.stringify({ type: 'result', result: 'Response' })}\n`
        );
        mockProcess.emit('close', 0);
      }, 10);

      const result = await promise;
      assert.ok(result);
      assert.strictEqual(result.type, 'result');
    });

    it('should handle command execution errors', async () => {
      const mockProcess = new EventEmitter();
      mockProcess.pid = 12345;
      mockProcess.stdout = new EventEmitter();
      mockProcess.stderr = new EventEmitter();
      mockProcess.stdin = {
        write: (data, encoding, callback) => {
          if (callback) callback();
        },
        end: () => {},
      };

      const mockSpawn = () => mockProcess;

      const runner = new AICLIProcessRunner({ spawnFunction: mockSpawn });

      const session = {
        sessionId: 'test-session',
        workingDirectory: '/test/dir',
        requestId: 'req-123',
      };

      const promise = runner.executeAICLICommand(session, 'Test message');

      // Simulate process error
      setTimeout(() => {
        mockProcess.stderr.emit('data', 'Error occurred');
        mockProcess.emit('close', 1);
      }, 10);

      await assert.rejects(promise, /exited with code 1/);
    });
  });

  describe('setAllowedTools and setDisallowedTools', () => {
    it('should set allowed tools array', () => {
      const tools = ['Read', 'Write', 'Edit'];
      processRunner.setAllowedTools(tools);
      assert.deepStrictEqual(processRunner.allowedTools, tools);
    });

    it('should handle empty allowed tools array', () => {
      processRunner.setAllowedTools([]);
      assert.deepStrictEqual(processRunner.allowedTools, []);
    });

    it('should set disallowed tools array', () => {
      const tools = ['Bash', 'WebSearch'];
      processRunner.setDisallowedTools(tools);
      assert.deepStrictEqual(processRunner.disallowedTools, tools);
    });

    it('should handle empty disallowed tools array', () => {
      processRunner.setDisallowedTools([]);
      assert.deepStrictEqual(processRunner.disallowedTools, []);
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
  });

  describe('EventEmitter functionality', () => {
    it('should inherit from EventEmitter', () => {
      assert.ok(processRunner instanceof EventEmitter);
    });

    it('should emit and handle events', () => {
      let received = null;
      processRunner.once('test-event', (data) => {
        received = data;
      });

      processRunner.emit('test-event', 'test-data');
      assert.strictEqual(received, 'test-data');
    });
  });
});
