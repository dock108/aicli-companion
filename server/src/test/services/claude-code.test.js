import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { ClaudeCodeService } from '../../services/claude-code.js';

describe('ClaudeCodeService', () => {
  let service;

  beforeEach(() => {
    service = new ClaudeCodeService();
  });

  afterEach(() => {
    // Clean up any active sessions
    service.activeSessions.forEach((session, id) => {
      service.endStreamingSession(id);
    });
  });

  describe('constructor', () => {
    it('should initialize with empty active sessions', () => {
      assert.strictEqual(service.activeSessions.size, 0);
      assert.ok(service.defaultWorkingDirectory);
    });
  });

  describe('classifyClaudeMessage', () => {
    it('should classify system messages', () => {
      const message = { type: 'system', content: 'System message' };
      const result = service.classifyClaudeMessage(message);

      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data.type, 'system');
    });

    it('should classify assistant messages', () => {
      const message = { type: 'assistant', content: 'Hello' };
      const result = service.classifyClaudeMessage(message);

      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data.type, 'assistant');
    });

    it('should classify tool use messages', () => {
      const message = {
        type: 'tool_use',
        tool: 'Read',
        args: { file_path: '/test.txt' },
      };
      const result = service.classifyClaudeMessage(message);

      assert.strictEqual(result.eventType, 'toolUse');
      assert.strictEqual(result.data.type, 'tool_use');
    });

    it('should classify tool result messages', () => {
      const message = {
        type: 'tool_result',
        result: 'File contents',
      };
      const result = service.classifyClaudeMessage(message);

      assert.strictEqual(result.eventType, 'toolResult');
      assert.strictEqual(result.data.type, 'tool_result');
    });

    it('should handle unknown message types', () => {
      const message = { type: 'unknown', data: 'test' };
      const result = service.classifyClaudeMessage(message);

      assert.deepStrictEqual(result, message);
    });
  });

  describe('parseToolActivityFromMessage', () => {
    it('should parse tool activity from tool use messages', () => {
      const message = {
        type: 'tool_use',
        tool: 'Read',
        args: { file_path: '/test.txt' },
      };

      const activity = service.parseToolActivityFromMessage(message);

      assert.ok(activity);
      assert.strictEqual(activity.toolName, 'Read');
      assert.deepStrictEqual(activity.parameters, { file_path: '/test.txt' });
      assert.strictEqual(activity.status, 'active');
    });

    it('should return null for non-tool messages', () => {
      const message = { type: 'assistant', content: 'Hello' };
      const activity = service.parseToolActivityFromMessage(message);

      assert.strictEqual(activity, null);
    });
  });

  describe('session management', () => {
    it('should track active sessions', () => {
      const sessionId = 'test-session';
      const session = {
        process: { stdin: { write: mock.fn() }, kill: mock.fn() },
        buffer: '',
      };

      service.activeSessions.set(sessionId, session);

      assert.ok(service.activeSessions.has(sessionId));
      assert.strictEqual(service.activeSessions.get(sessionId), session);
    });

    it('should handle sending messages to non-existent sessions', () => {
      assert.throws(() => {
        service.sendStreamingMessage('non-existent', 'message');
      }, /No active session found/);
    });
  });
});
