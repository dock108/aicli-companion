import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { MessageBufferManager } from '../../../services/aicli-session-manager/message-buffer-manager.js';
import { AICLIMessageHandler } from '../../../services/aicli-message-handler.js';

describe('MessageBufferManager', () => {
  let manager;
  let mockStorage;
  let mockBuffer;

  beforeEach(() => {
    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});

    // Mock AICLIMessageHandler.createSessionBuffer
    mock.method(AICLIMessageHandler, 'createSessionBuffer', () => ({
      assistantMessages: [],
      userMessages: [],
      systemMessages: [],
      messages: [],
      toolUseInProgress: false,
      permissionRequests: [],
      deliverables: [],
      permissionRequestSent: false,
      systemInit: null,
      pendingFinalResponse: null,
      claudeSessionId: null,
      chunks: new Map(),
      lastActivity: Date.now(),
      isActive: true,
    }));

    // Create mock buffer (matching AICLIMessageHandler.createSessionBuffer())
    mockBuffer = {
      assistantMessages: [],
      userMessages: [],
      systemMessages: [],
      messages: [],
      toolUseInProgress: false,
      permissionRequests: [],
      deliverables: [],
      permissionRequestSent: false,
      systemInit: null,
      pendingFinalResponse: null,
      claudeSessionId: null,
      chunks: new Map(),
      lastActivity: Date.now(),
      isActive: true,
      thinkingMetadata: {},
    };

    // Create mock storage
    mockStorage = {
      buffers: new Map(),
      sessions: new Map(),

      getMessageBuffer: mock.fn((sessionId) => {
        return mockStorage.buffers.get(sessionId);
      }),

      addMessageBuffer: mock.fn((sessionId, buffer) => {
        mockStorage.buffers.set(sessionId, buffer);
      }),

      removeMessageBuffer: mock.fn((sessionId) => {
        mockStorage.buffers.delete(sessionId);
      }),

      getSession: mock.fn((sessionId) => {
        return mockStorage.sessions.get(sessionId);
      }),
    };

    // Create manager instance
    manager = new MessageBufferManager(mockStorage);
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('getBuffer', () => {
    it('should return existing buffer', () => {
      mockStorage.buffers.set('session1', mockBuffer);

      const buffer = manager.getBuffer('session1');

      assert.strictEqual(buffer, mockBuffer);
      assert.strictEqual(mockStorage.getMessageBuffer.mock.callCount(), 1);
      assert.strictEqual(mockStorage.addMessageBuffer.mock.callCount(), 0);
    });

    it('should create new buffer if not exists', () => {
      const buffer = manager.getBuffer('session1');

      assert(buffer);
      assert(buffer.messages);
      assert(buffer.userMessages);
      assert(buffer.assistantMessages);
      assert.strictEqual(mockStorage.getMessageBuffer.mock.callCount(), 1);
      assert.strictEqual(mockStorage.addMessageBuffer.mock.callCount(), 1);
    });

    it('should handle concurrent buffer creation', () => {
      const buffer1 = manager.getBuffer('session1');
      const buffer2 = manager.getBuffer('session1');

      // Should get the same buffer instance
      assert.strictEqual(buffer1, buffer2);
      // Should only create once
      assert.strictEqual(mockStorage.addMessageBuffer.mock.callCount(), 1);
    });

    it('should create separate buffers for different sessions', () => {
      const buffer1 = manager.getBuffer('session1');
      const buffer2 = manager.getBuffer('session2');

      assert.notStrictEqual(buffer1, buffer2);
      assert.strictEqual(mockStorage.addMessageBuffer.mock.callCount(), 2);
    });
  });

  describe('storeMessage', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
    });

    it('should store user message', () => {
      const content = 'User message content';
      const metadata = { requestId: 'req123' };

      const result = manager.storeMessage('session1', 'user', content, metadata);

      assert.strictEqual(result, true);
      assert.strictEqual(mockBuffer.userMessages.length, 1);
      assert.strictEqual(mockBuffer.userMessages[0].content, content);
      assert.strictEqual(mockBuffer.userMessages[0].role, 'user');
      assert.strictEqual(mockBuffer.userMessages[0].requestId, 'req123');
      assert(mockBuffer.userMessages[0].timestamp);
    });

    it('should store assistant message', () => {
      const content = 'Assistant response';

      const result = manager.storeMessage('session1', 'assistant', content);

      assert.strictEqual(result, true);
      assert.strictEqual(mockBuffer.assistantMessages.length, 1);
      assert.strictEqual(mockBuffer.assistantMessages[0].content, content);
      assert.strictEqual(mockBuffer.assistantMessages[0].role, 'assistant');
    });

    it('should handle unknown role', () => {
      const content = 'Unknown role message';

      const result = manager.storeMessage('session1', 'unknown', content);

      // Should return false for unknown roles
      assert.strictEqual(result, false);
      assert.strictEqual(mockBuffer.userMessages.length, 0);
      assert.strictEqual(mockBuffer.assistantMessages.length, 0);
    });

    it('should create buffer if not exists', () => {
      const content = 'Message for new session';
      mockStorage.sessions.set('session2', { sessionId: 'session2', lastActivity: Date.now() });

      const result = manager.storeMessage('session2', 'user', content);

      assert.strictEqual(result, true);
      const buffer = mockStorage.buffers.get('session2');
      assert(buffer);
      assert.strictEqual(buffer.userMessages.length, 1);
    });

    it('should update session activity timestamp', () => {
      const beforeTime = Date.now();
      const session = mockStorage.sessions.get('session1');

      manager.storeMessage('session1', 'user', 'test');

      assert(session.lastActivity >= beforeTime);
    });

    it('should handle null content', () => {
      const result = manager.storeMessage('session1', 'user', null);

      assert.strictEqual(result, true);
      assert.strictEqual(mockBuffer.userMessages.length, 1);
      assert.strictEqual(mockBuffer.userMessages[0].content, null);
    });

    it('should handle empty metadata', () => {
      const result = manager.storeMessage('session1', 'user', 'test', {});

      assert.strictEqual(result, true);
      assert.strictEqual(mockBuffer.userMessages.length, 1);
      assert(mockBuffer.userMessages[0].timestamp);
    });

    it('should update thinking metadata', () => {
      const metadata = { thinkingMetadata: { key: 'value' } };

      const result = manager.storeMessage('session1', 'user', 'test', metadata);

      assert.strictEqual(result, true);
      assert.deepStrictEqual(mockBuffer.thinkingMetadata, { key: 'value' });
    });
  });

  describe('getMessages', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
    });

    it('should return messages with default limit', () => {
      // Add messages to userMessages and assistantMessages
      for (let i = 0; i < 20; i++) {
        if (i % 2 === 0) {
          mockBuffer.userMessages.push({
            role: 'user',
            content: `Message ${i}`,
            timestamp: new Date(Date.now() + i * 1000).toISOString(),
          });
        } else {
          mockBuffer.assistantMessages.push({
            role: 'assistant',
            content: `Message ${i}`,
            timestamp: new Date(Date.now() + i * 1000).toISOString(),
          });
        }
      }

      const recent = manager.getMessages('session1');

      assert(recent.length <= 50); // Default limit is 50
      assert(recent.length === 20); // We added 20 messages
    });

    it('should return messages with custom limit', () => {
      for (let i = 0; i < 10; i++) {
        mockBuffer.userMessages.push({
          role: 'user',
          content: `Message ${i}`,
          timestamp: new Date(Date.now() + i * 1000).toISOString(),
        });
      }

      const recent = manager.getMessages('session1', 5);

      assert.strictEqual(recent.length, 5);
      assert.strictEqual(recent[0].content, 'Message 0');
    });

    it('should return empty array for non-existent session', () => {
      const recent = manager.getMessages('nonexistent');

      assert(Array.isArray(recent));
      assert.strictEqual(recent.length, 0);
    });

    it('should handle empty message buffer', () => {
      const recent = manager.getMessages('session1');

      assert(Array.isArray(recent));
      assert.strictEqual(recent.length, 0);
    });

    it('should handle limit larger than messages', () => {
      mockBuffer.userMessages.push({
        content: 'Message 1',
        timestamp: new Date().toISOString(),
      });
      mockBuffer.assistantMessages.push({
        content: 'Message 2',
        timestamp: new Date().toISOString(),
      });

      const recent = manager.getMessages('session1', 10);

      assert.strictEqual(recent.length, 2);
    });
  });

  describe('clearBuffer', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
      mockBuffer.messages = ['msg1', 'msg2'];
      mockBuffer.userMessages = ['user1'];
      mockBuffer.assistantMessages = ['assistant1'];
      mockBuffer.chunks.set('chunk1', 'data');
    });

    it('should clear all buffer content', () => {
      const result = manager.clearBuffer('session1');

      assert.strictEqual(result, true);
      assert.strictEqual(mockBuffer.userMessages.length, 0);
      assert.strictEqual(mockBuffer.assistantMessages.length, 0);
      assert.deepStrictEqual(mockBuffer.thinkingMetadata, {});
    });

    it('should return false for non-existent session', () => {
      const result = manager.clearBuffer('nonexistent');

      assert.strictEqual(result, false);
    });
  });

  /* Tests for methods that don't exist in the implementation
  describe('aggregateChunk', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
    });

    it('should aggregate message chunks', () => {
      manager.aggregateChunk('session1', 0, 'Part 1', 3);
      manager.aggregateChunk('session1', 1, 'Part 2', 3);
      manager.aggregateChunk('session1', 2, 'Part 3', 3);

      assert.strictEqual(mockBuffer.chunks.size, 3);
      assert.strictEqual(mockBuffer.chunks.get(0), 'Part 1');
      assert.strictEqual(mockBuffer.chunks.get(1), 'Part 2');
      assert.strictEqual(mockBuffer.chunks.get(2), 'Part 3');
    });

    it('should detect when all chunks received', () => {
      manager.aggregateChunk('session1', 0, 'Part 1', 2);
      const complete1 = manager.aggregateChunk('session1', 1, 'Part 2', 2);

      assert(complete1.isComplete);
      assert.strictEqual(complete1.message, 'Part 1Part 2');
    });

    it('should clear chunks after aggregation', () => {
      manager.aggregateChunk('session1', 0, 'Part 1', 2);
      manager.aggregateChunk('session1', 1, 'Part 2', 2);

      assert.strictEqual(mockBuffer.chunks.size, 0);
    });

    it('should handle out-of-order chunks', () => {
      manager.aggregateChunk('session1', 2, 'Part 3', 3);
      manager.aggregateChunk('session1', 0, 'Part 1', 3);
      manager.aggregateChunk('session1', 1, 'Part 2', 3);

      const lastResult = manager.aggregateChunk('session1', 1, 'Part 2', 3);
      assert(lastResult.isComplete);
      assert.strictEqual(lastResult.message, 'Part 1Part 2Part 3');
    });

    it('should handle single chunk', () => {
      const result = manager.aggregateChunk('session1', 0, 'Complete message', 1);

      assert(result.isComplete);
      assert.strictEqual(result.message, 'Complete message');
    });

    it('should create buffer if not exists', () => {
      const result = manager.aggregateChunk('session2', 0, 'Test', 1);

      assert(result.isComplete);
      assert(mockStorage.buffers.has('session2'));
    });
  });

  describe('getBufferStats', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
    });

    it('should return buffer statistics', () => {
      mockBuffer.messages = ['msg1', 'msg2', 'msg3'];
      mockBuffer.userMessages = ['user1', 'user2'];
      mockBuffer.assistantMessages = ['assistant1'];
      mockBuffer.chunks.set(0, 'chunk0');
      mockBuffer.chunks.set(1, 'chunk1');

      const stats = manager.getBufferStats('session1');

      assert.strictEqual(stats.totalMessages, 3);
      assert.strictEqual(stats.userMessages, 2);
      assert.strictEqual(stats.assistantMessages, 1);
      assert.strictEqual(stats.pendingChunks, 2);
      assert.strictEqual(stats.isActive, true);
      assert(stats.lastActivity);
    });

    it('should return null for non-existent session', () => {
      const stats = manager.getBufferStats('nonexistent');

      assert.strictEqual(stats, null);
    });

    it('should handle empty buffer', () => {
      const stats = manager.getBufferStats('session1');

      assert.strictEqual(stats.totalMessages, 0);
      assert.strictEqual(stats.userMessages, 0);
      assert.strictEqual(stats.assistantMessages, 0);
      assert.strictEqual(stats.pendingChunks, 0);
    });
  });

  describe('removeBuffer', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
    });

    it('should remove buffer from storage', () => {
      manager.removeBuffer('session1');

      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 1);
      assert(!mockStorage.buffers.has('session1'));
    });

    it('should handle non-existent session', () => {
      manager.removeBuffer('nonexistent');

      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 1);
    });

    it('should be idempotent', () => {
      manager.removeBuffer('session1');
      manager.removeBuffer('session1');

      assert.strictEqual(mockStorage.removeMessageBuffer.mock.callCount(), 2);
    });
  });

  describe('markInactive', () => {
    beforeEach(() => {
      mockStorage.buffers.set('session1', mockBuffer);
      mockStorage.sessions.set('session1', { sessionId: 'session1', lastActivity: Date.now() });
    });

    it('should mark buffer as inactive', () => {
      mockBuffer.isActive = true;

      manager.markInactive('session1');

      assert.strictEqual(mockBuffer.isActive, false);
    });

    it('should handle non-existent session', () => {
      // Should not throw
      assert.doesNotThrow(() => {
        manager.markInactive('nonexistent');
      });
    });

    it('should create buffer if not exists', () => {
      manager.markInactive('session2');

      const buffer = mockStorage.buffers.get('session2');
      assert(buffer);
      assert.strictEqual(buffer.isActive, false);
    });
  });

  */
});
