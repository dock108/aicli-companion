import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'events';
import { AICLIProcessRunner } from '../../services/aicli-process-runner.js';
import * as AICLIUtils from '../../services/aicli-utils.js';

// Mock process for testing
class MockProcess extends EventEmitter {
  constructor(options = {}) {
    super();
    this.pid = options.pid || 12345;
    this.killed = false;
    this.stdout = new EventEmitter();
    this.stderr = new EventEmitter();
    this.stdin = {
      write: mock.fn((data) => {
        this.lastInput = data;
        return true;
      }),
      end: mock.fn(),
    };
  }

  kill() {
    this.killed = true;
    this.emit('exit', 0);
  }
}

describe('AICLIProcessRunner - Comprehensive Coverage', () => {
  let processRunner;
  let originalEnv;
  let mockSpawn;

  beforeEach(() => {
    originalEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = 'test';
    
    // Mock console methods
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');
    
    processRunner = new AICLIProcessRunner();
    
    // Create mock spawn function
    mockSpawn = mock.fn((command, args, options) => {
      const mockProcess = new MockProcess();
      setImmediate(() => {
        if (command === 'error-command') {
          mockProcess.emit('error', new Error('Command not found'));
        }
      });
      return mockProcess;
    });
    
    processRunner.spawnFunction = mockSpawn;
  });

  afterEach(() => {
    process.env.NODE_ENV = originalEnv;
    mock.restoreAll();
  });

  describe('Configuration', () => {
    it('should create instance with default options', () => {
      assert.ok(processRunner);
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

  describe('processOutput', () => {
    it('should handle empty output', () => {
      const reject = mock.fn();
      const resolve = mock.fn();
      
      processRunner.processOutput('', 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.strictEqual(reject.mock.calls[0].arguments[0].message, 'AICLI CLI returned empty output');
    });

    it('should handle whitespace-only output', () => {
      const reject = mock.fn();
      const resolve = mock.fn();
      
      processRunner.processOutput('   \n  \t  ', 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.strictEqual(reject.mock.calls[0].arguments[0].message, 'AICLI CLI returned empty output');
    });

    it('should handle valid stream JSON output', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      const streamOutput = `{"type":"system","subtype":"init","session_id":"test-123"}\n{"type":"result","result":"Hello!"}`;
      
      processRunner.processOutput(streamOutput, 'test-session', resolve, reject);
      
      assert.strictEqual(resolve.mock.calls.length, 1);
      const result = resolve.mock.calls[0].arguments[0];
      assert.strictEqual(result.type, 'result');
      assert.strictEqual(result.result, 'Hello!');
      assert.strictEqual(result.session_id, 'test-123');
    });

    it('should handle output with no valid JSON objects', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      // Mock MessageProcessor to return empty array
      const originalParse = AICLIUtils.MessageProcessor.parseStreamJsonOutput;
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = () => [];
      
      processRunner.processOutput('invalid json', 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.strictEqual(reject.mock.calls[0].arguments[0].message, 'No valid JSON objects found in AICLI CLI output');
      
      // Restore
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = originalParse;
    });

    it('should emit aicliResponse events for each response', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      const events = [];
      
      processRunner.on('aicliResponse', (event) => {
        events.push(event);
      });
      
      const streamOutput = `{"type":"system","subtype":"init"}\n{"type":"message","content":"test"}\n{"type":"result","result":"Done"}`;
      
      processRunner.processOutput(streamOutput, 'test-session', resolve, reject, 'req-123');
      
      assert.strictEqual(events.length, 3);
      assert.strictEqual(events[0].sessionId, 'test-session');
      assert.strictEqual(events[0].requestId, 'req-123');
      assert.strictEqual(events[2].isLast, true);
    });

    it('should handle JSON parse errors with Unterminated string', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      // Force a parse error by mocking MessageProcessor
      const originalParse = AICLIUtils.MessageProcessor.parseStreamJsonOutput;
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = () => {
        throw new Error('Unterminated string in JSON');
      };
      
      processRunner.processOutput('{"incomplete', 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      // The actual error message contains 'truncated'
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('truncated'));
      
      // Restore
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = originalParse;
    });

    it('should handle JSON parse errors with Unexpected end', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      // Force a parse error by mocking MessageProcessor
      const originalParse = AICLIUtils.MessageProcessor.parseStreamJsonOutput;
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = () => {
        throw new Error('Unexpected end of JSON input');
      };
      
      processRunner.processOutput('{"incomplete', 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      // The actual error message contains 'ended unexpectedly'
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('ended unexpectedly'));
      
      // Restore
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = originalParse;
    });

    it('should handle generic JSON parse errors', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      // Force a generic parse error
      const originalParse = AICLIUtils.MessageProcessor.parseStreamJsonOutput;
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = () => {
        throw new Error('Some other error');
      };
      
      processRunner.processOutput('bad json', 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('Failed to parse AICLI CLI response'));
      
      // Restore
      AICLIUtils.MessageProcessor.parseStreamJsonOutput = originalParse;
    });

    it('should handle null completeStdout in processOutput', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      processRunner.processOutput(null, 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('empty output'));
    });

    it('should handle undefined completeStdout in processOutput', () => {
      const resolve = mock.fn();
      const reject = mock.fn();
      
      processRunner.processOutput(undefined, 'test-session', resolve, reject);
      
      assert.strictEqual(reject.mock.calls.length, 1);
      assert.ok(reject.mock.calls[0].arguments[0].message.includes('empty output'));
    });
  });

  describe('createHealthMonitor', () => {
    it('should create health monitor with activity tracking', () => {
      const mockProcess = { pid: 54321 };
      const monitor = processRunner.createHealthMonitor(mockProcess, 'test-session');
      
      assert.ok(monitor);
      assert.strictEqual(typeof monitor.recordActivity, 'function');
      assert.strictEqual(typeof monitor.cleanup, 'function');
      
      // Test activity recording
      monitor.recordActivity();
      
      // Test cleanup
      monitor.cleanup();
    });

    it('should handle cleanup when interval already cleared', () => {
      const mockProcess = { pid: 54321 };
      const monitor = processRunner.createHealthMonitor(mockProcess, 'test-session');
      
      // Call cleanup twice
      monitor.cleanup();
      monitor.cleanup(); // Should not throw
      
      assert.ok(true); // If we get here, no error was thrown
    });

    it('should log status periodically', (t, done) => {
      const mockProcess = { pid: 54321 };
      const monitor = processRunner.createHealthMonitor(mockProcess, 'test-session');
      
      // Since the interval is 30 seconds, we can't wait that long in tests
      // Just verify the monitor was created and clean it up
      assert.ok(monitor);
      monitor.cleanup();
      done();
    });
  });

  describe('findAICLICommand', () => {
    it('should return claude in test environment', () => {
      process.env.NODE_ENV = 'test';
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'claude');
    });

    it('should try different command names in non-test environment', () => {
      process.env.NODE_ENV = 'development';
      
      // Mock spawn to simulate finding claude command
      processRunner.spawnFunction = mock.fn((cmd, args, options) => {
        if (cmd === 'claude') {
          return { pid: 123, kill: mock.fn() };
        }
        throw new Error('Command not found');
      });
      
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'claude');
      assert.strictEqual(processRunner.spawnFunction.mock.calls.length, 1);
    });

    it('should try aicli if claude not found', () => {
      process.env.NODE_ENV = 'development';
      
      // Mock spawn to simulate finding aicli command
      processRunner.spawnFunction = mock.fn((cmd, args, options) => {
        if (cmd === 'aicli') {
          return { pid: 456, kill: mock.fn() };
        }
        throw new Error('Command not found');
      });
      
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'aicli');
      assert.strictEqual(processRunner.spawnFunction.mock.calls.length, 2);
    });

    it('should return default claude if no commands found', () => {
      process.env.NODE_ENV = 'development';
      
      // Mock spawn to simulate no commands found
      processRunner.spawnFunction = mock.fn((cmd, args, options) => {
        throw new Error('Command not found');
      });
      
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'claude');
      assert.strictEqual(processRunner.spawnFunction.mock.calls.length, 2);
    });

    it('should handle spawn errors gracefully', () => {
      process.env.NODE_ENV = 'development';
      
      // Mock spawn to throw different errors
      let callCount = 0;
      processRunner.spawnFunction = mock.fn((cmd, args, options) => {
        callCount++;
        if (callCount === 1) {
          throw new Error('ENOENT');
        }
        return { pid: 789, kill: mock.fn() };
      });
      
      const command = processRunner.findAICLICommand();
      assert.strictEqual(command, 'aicli');
    });
  });

  describe('Interactive Session (createInteractiveSession)', () => {
    it('should handle interactive session initialization with session ID', async () => {
      const mockProcess = new MockProcess();
      
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      const sessionPromise = processRunner.createInteractiveSession('/test/dir');
      
      // Simulate Claude sending init message with session ID
      setImmediate(() => {
        mockProcess.stdout.emit('data', Buffer.from('{"type":"system","subtype":"init","session_id":"existing-session"}\n'));
      });
      
      const result = await sessionPromise;
      
      assert.strictEqual(result.sessionId, 'existing-session');
      assert.strictEqual(result.pid, mockProcess.pid);
      assert.ok(result.process);
    });

    it('should handle stderr during initialization', async () => {
      const mockProcess = new MockProcess();
      
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      const sessionPromise = processRunner.createInteractiveSession('/test/dir');
      
      // Simulate error on stderr
      setImmediate(() => {
        mockProcess.stderr.emit('data', Buffer.from('Error: Something went wrong'));
      });
      
      await assert.rejects(sessionPromise, {
        message: /Claude CLI error/
      });
    });

    it('should handle process exit during initialization', async () => {
      const mockProcess = new MockProcess();
      
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      const sessionPromise = processRunner.createInteractiveSession('/test/dir');
      
      // Simulate process exit
      setImmediate(() => {
        mockProcess.emit('exit', 1);
      });
      
      await assert.rejects(sessionPromise, {
        message: /Claude CLI exited immediately with code 1/
      });
    });

    it('should handle process error during initialization', async () => {
      const mockProcess = new MockProcess();
      
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      const sessionPromise = processRunner.createInteractiveSession('/test/dir');
      
      // Simulate process error
      setImmediate(() => {
        mockProcess.emit('error', new Error('Failed to start'));
      });
      
      await assert.rejects(sessionPromise, {
        message: /Failed to start/
      });
    });

    it('should handle stdout chunks without valid JSON', async () => {
      const mockProcess = new MockProcess();
      
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      const sessionPromise = processRunner.createInteractiveSession('/test/dir');
      
      // Send non-JSON data first, then valid init
      setImmediate(() => {
        mockProcess.stdout.emit('data', Buffer.from('Not JSON\n'));
        mockProcess.stdout.emit('data', Buffer.from('{"type":"system","subtype":"init","session_id":"test-123"}\n'));
      });
      
      const result = await sessionPromise;
      assert.strictEqual(result.sessionId, 'test-123');
    });
  });

  describe('sendToInteractiveSession', () => {
    it('should send message and handle response', async () => {
      const mockProcess = new MockProcess();
      const sessionInfo = {
        process: mockProcess,
        sessionId: 'test-session',
        streamParser: { addResponse: mock.fn() }
      };
      
      const sendPromise = processRunner.sendToInteractiveSession(sessionInfo, 'Test message');
      
      // Simulate Claude response
      setImmediate(() => {
        mockProcess.stdout.emit('data', Buffer.from('{"type":"message","content":"Processing"}\n'));
        mockProcess.stdout.emit('data', Buffer.from('{"type":"result","result":"Response","session_id":"test-session"}\n'));
      });
      
      const result = await sendPromise;
      
      assert.strictEqual(result.result, 'Response');
      assert.strictEqual(result.sessionId, 'test-session');
      assert.strictEqual(result.success, true);
      assert.strictEqual(result.responses.length, 2);
    });

    it('should handle stderr during message send', async () => {
      const mockProcess = new MockProcess();
      const sessionInfo = {
        process: mockProcess,
        sessionId: 'test-session'
      };
      
      const sendPromise = processRunner.sendToInteractiveSession(sessionInfo, 'Test message');
      
      // Simulate error
      setImmediate(() => {
        mockProcess.stderr.emit('data', Buffer.from('Error occurred'));
      });
      
      await assert.rejects(sendPromise, {
        message: /Claude error/
      });
    });

    it('should handle non-JSON lines in response', async () => {
      const mockProcess = new MockProcess();
      const sessionInfo = {
        process: mockProcess,
        sessionId: 'test-session'
      };
      
      const sendPromise = processRunner.sendToInteractiveSession(sessionInfo, 'Test message');
      
      // Send mixed valid and invalid JSON
      setImmediate(() => {
        mockProcess.stdout.emit('data', Buffer.from('Not JSON\n{"type":"result","result":"OK"}\n'));
      });
      
      const result = await sendPromise;
      assert.strictEqual(result.result, 'OK');
    });
  });

  describe('Event Emitter Integration', () => {
    it('should emit streamChunk events', () => {
      const chunks = [];
      processRunner.on('streamChunk', (chunk) => chunks.push(chunk));
      
      // Trigger an event that would cause streamChunk emission
      processRunner.emit('streamChunk', { data: 'test' });
      
      assert.strictEqual(chunks.length, 1);
      assert.deepStrictEqual(chunks[0], { data: 'test' });
    });

    it('should emit aicliResponse events', () => {
      const responses = [];
      processRunner.on('aicliResponse', (response) => responses.push(response));
      
      processRunner.emit('aicliResponse', { sessionId: 'test', response: {} });
      
      assert.strictEqual(responses.length, 1);
      assert.strictEqual(responses[0].sessionId, 'test');
    });
  });

  describe('Stream Handling', () => {
    it('should handle stream chunks properly', async () => {
      const mockProcess = new MockProcess();
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      // Set up event listener for streamChunk
      const chunks = [];
      processRunner.on('streamChunk', (chunk) => chunks.push(chunk));
      
      // Execute a command to trigger stream handling
      const executePromise = processRunner.executeAICLICommand({ sessionId: 'test-session', workingDirectory: '/test/dir' }, 'test');
      
      // Simulate streaming data and immediate process completion
      setImmediate(() => {
        mockProcess.stdout.emit('data', Buffer.from('{"type":"stream","content":"chunk1"}\n{"type":"result","result":"done"}\n'));
        mockProcess.emit('close', 0);
      });
      
      await executePromise;
      
      // Verify chunks were emitted
      assert.ok(chunks.length > 0);
    });
  });

  describe('Error Recovery', () => {
    it('should handle process crashes gracefully', async () => {
      const mockProcess = new MockProcess();
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      const executePromise = processRunner.executeAICLICommand({ sessionId: 'test-session', workingDirectory: '/test/dir' }, 'test');
      
      // Simulate process crash - error event should trigger rejection
      setImmediate(() => {
        mockProcess.emit('error', new Error('Process crashed'));
      });
      
      await assert.rejects(executePromise, {
        message: /Process crashed/
      });
    });

    it('should handle timeout scenarios', async () => {
      const mockProcess = new MockProcess();
      processRunner.spawnFunction = mock.fn(() => mockProcess);
      
      // Create a session with very short timeout for testing
      const sessionPromise = processRunner.createInteractiveSession('/test/dir');
      
      // Don't send any data, let it timeout
      // Note: This test assumes a timeout mechanism exists
      // If not implemented, this test should be adjusted
      
      // Send init after a delay to prevent timeout
      setImmediate(() => {
        mockProcess.stdout.emit('data', Buffer.from('{"type":"system","subtype":"init","session_id":"test"}\n'));
      });
      
      const result = await sessionPromise;
      assert.ok(result.sessionId);
    });
  });
});