import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { MessageOptimizer, messageOptimizer } from '../../utils/message-optimizer.js';

describe('MessageOptimizer', () => {
  let optimizer;

  beforeEach(() => {
    optimizer = new MessageOptimizer();
  });

  describe('Constructor', () => {
    it('should initialize with default values', () => {
      assert.ok(optimizer.messageCache instanceof Map);
      assert.strictEqual(optimizer.cacheMaxSize, 1000);
      assert.strictEqual(optimizer.cacheHits, 0);
      assert.strictEqual(optimizer.cacheMisses, 0);
    });
  });

  describe('optimizeMessage', () => {
    it('should optimize a basic message', () => {
      const message = {
        content: 'Hello World',
        type: 'text',
        sender: 'user',
      };

      const optimized = optimizer.optimizeMessage(message);

      assert.ok(optimized.id);
      assert.strictEqual(optimized.content, 'Hello World');
      assert.strictEqual(optimized.type, 'text');
      assert.strictEqual(optimized.sender, 'user');
      assert.ok(optimized.timestamp);
    });

    it('should generate ID for message without one', () => {
      const message = {
        content: 'Test',
        sender: 'user',
      };

      const optimized = optimizer.optimizeMessage(message);

      assert.ok(optimized.id);
      assert.ok(optimized.id.startsWith('msg_'));
    });

    it('should use existing message ID', () => {
      const message = {
        id: 'existing-id',
        content: 'Test',
        sender: 'user',
      };

      const optimized = optimizer.optimizeMessage(message);

      assert.strictEqual(optimized.id, 'existing-id');
    });

    it('should include metadata when present', () => {
      const message = {
        content: 'Test',
        sender: 'user',
        metadata: {
          sessionId: 'session-123',
          requestId: 'req-456',
        },
      };

      const optimized = optimizer.optimizeMessage(message);

      assert.ok(optimized.metadata);
      assert.strictEqual(optimized.metadata.sessionId, 'session-123');
      assert.strictEqual(optimized.metadata.requestId, 'req-456');
    });

    it('should not include metadata when empty', () => {
      const message = {
        content: 'Test',
        sender: 'user',
        metadata: {},
      };

      const optimized = optimizer.optimizeMessage(message);

      assert.strictEqual(optimized.metadata, undefined);
    });

    it('should use cache for repeated messages', () => {
      const message = {
        id: 'test-id',
        content: 'Test message',
        timestamp: 12345,
      };

      // First call - cache miss
      const result1 = optimizer.optimizeMessage(message);
      assert.strictEqual(optimizer.cacheMisses, 1);
      assert.strictEqual(optimizer.cacheHits, 0);

      // Second call - cache hit
      const result2 = optimizer.optimizeMessage(message);
      assert.strictEqual(optimizer.cacheMisses, 1);
      assert.strictEqual(optimizer.cacheHits, 1);

      assert.deepStrictEqual(result1, result2);
    });
  });

  describe('compressContent', () => {
    it('should compress whitespace in content', () => {
      const content = '  Hello    World   \n\n  Test  ';
      const compressed = optimizer.compressContent(content);

      assert.strictEqual(compressed, 'Hello World Test');
    });

    it('should truncate very long content', () => {
      const longContent = 'x'.repeat(15000);
      const compressed = optimizer.compressContent(longContent);

      assert.ok(compressed.length < 15000);
      assert.ok(compressed.endsWith('... [truncated]'));
    });

    it('should handle non-string content', () => {
      assert.strictEqual(optimizer.compressContent(null), null);
      assert.strictEqual(optimizer.compressContent(undefined), undefined);
      assert.strictEqual(optimizer.compressContent(123), 123);
      assert.deepStrictEqual(optimizer.compressContent({ obj: true }), { obj: true });
    });

    it('should handle empty string', () => {
      assert.strictEqual(optimizer.compressContent(''), '');
    });
  });

  describe('optimizeMetadata', () => {
    it('should keep only essential fields', () => {
      const metadata = {
        sessionId: 'session-123',
        requestId: 'req-456',
        projectPath: '/path/to/project',
        isFinal: true,
        extraField: 'should be removed',
        anotherExtra: 'also removed',
      };

      const optimized = optimizer.optimizeMetadata(metadata);

      assert.strictEqual(optimized.sessionId, 'session-123');
      assert.strictEqual(optimized.requestId, 'req-456');
      assert.strictEqual(optimized.projectPath, '/path/to/project');
      assert.strictEqual(optimized.isFinal, true);
      assert.strictEqual(optimized.extraField, undefined);
      assert.strictEqual(optimized.anotherExtra, undefined);
    });

    it('should handle undefined fields', () => {
      const metadata = {
        sessionId: 'session-123',
        requestId: undefined,
        projectPath: null,
      };

      const optimized = optimizer.optimizeMetadata(metadata);

      assert.strictEqual(optimized.sessionId, 'session-123');
      assert.strictEqual(optimized.requestId, undefined);
      assert.strictEqual(optimized.projectPath, undefined);
    });

    it('should handle empty metadata', () => {
      const optimized = optimizer.optimizeMetadata({});

      assert.deepStrictEqual(optimized, {});
    });
  });

  describe('optimizeBatch', () => {
    it('should optimize multiple messages', () => {
      // Clear cache before this test to avoid interference
      optimizer.clearCache();

      const messages = [
        { id: 'msg1', content: 'Message 1', sender: 'user', timestamp: 1001 },
        { id: 'msg2', content: 'Message 2', sender: 'assistant', timestamp: 1002 },
        { id: 'msg3', content: 'Message 3', sender: 'user', timestamp: 1003 },
      ];

      const optimized = optimizer.optimizeBatch(messages);

      assert.strictEqual(optimized.length, 3);
      optimized.forEach((msg, index) => {
        assert.ok(msg.id);
        assert.strictEqual(msg.content, `Message ${index + 1}`);
        assert.ok(msg.timestamp);
      });
    });

    it('should handle empty array', () => {
      const optimized = optimizer.optimizeBatch([]);

      assert.deepStrictEqual(optimized, []);
    });

    it('should handle non-array input', () => {
      assert.deepStrictEqual(optimizer.optimizeBatch(null), []);
      assert.deepStrictEqual(optimizer.optimizeBatch(undefined), []);
      assert.deepStrictEqual(optimizer.optimizeBatch('not array'), []);
    });
  });

  describe('getCacheKey', () => {
    it('should generate cache key from message', () => {
      const message = {
        id: 'msg-123',
        timestamp: 12345,
        content: 'Hello',
      };

      const key = optimizer.getCacheKey(message);

      assert.strictEqual(key, 'msg-123-12345-5');
    });

    it('should handle missing fields', () => {
      const message = {};
      const key = optimizer.getCacheKey(message);

      assert.strictEqual(key, 'undefined-undefined-0');
    });

    it('should handle null content', () => {
      const message = {
        id: 'msg-123',
        timestamp: 12345,
        content: null,
      };

      const key = optimizer.getCacheKey(message);

      assert.strictEqual(key, 'msg-123-12345-0');
    });
  });

  describe('addToCache', () => {
    it('should add items to cache', () => {
      optimizer.addToCache('key1', 'value1');
      optimizer.addToCache('key2', 'value2');

      assert.strictEqual(optimizer.messageCache.size, 2);
      assert.strictEqual(optimizer.messageCache.get('key1'), 'value1');
      assert.strictEqual(optimizer.messageCache.get('key2'), 'value2');
    });

    it('should enforce cache size limit', () => {
      // Set a small cache size for testing
      optimizer.cacheMaxSize = 3;

      optimizer.addToCache('key1', 'value1');
      optimizer.addToCache('key2', 'value2');
      optimizer.addToCache('key3', 'value3');
      optimizer.addToCache('key4', 'value4'); // Should evict key1

      assert.strictEqual(optimizer.messageCache.size, 3);
      assert.strictEqual(optimizer.messageCache.has('key1'), false);
      assert.strictEqual(optimizer.messageCache.has('key4'), true);
    });
  });

  describe('generateId', () => {
    it('should generate unique IDs', () => {
      const id1 = optimizer.generateId();
      const id2 = optimizer.generateId();

      assert.ok(id1.startsWith('msg_'));
      assert.ok(id2.startsWith('msg_'));
      assert.notStrictEqual(id1, id2);
    });

    it('should include timestamp in ID', () => {
      const beforeTime = Date.now();
      const id = optimizer.generateId();
      const afterTime = Date.now();

      // Extract timestamp from ID
      const match = id.match(/msg_(\d+)_/);
      assert.ok(match);

      const timestamp = parseInt(match[1]);
      assert.ok(timestamp >= beforeTime);
      assert.ok(timestamp <= afterTime);
    });
  });

  describe('getCacheStats', () => {
    it('should return cache statistics', () => {
      const stats = optimizer.getCacheStats();

      assert.strictEqual(stats.size, 0);
      assert.strictEqual(stats.hits, 0);
      assert.strictEqual(stats.misses, 0);
      assert.strictEqual(stats.hitRate, '0%');
    });

    it('should calculate hit rate correctly', () => {
      // Create some cache activity
      const message1 = { id: 'msg1', content: 'Test 1', timestamp: 1 };
      const message2 = { id: 'msg2', content: 'Test 2', timestamp: 2 };

      optimizer.optimizeMessage(message1); // Miss
      optimizer.optimizeMessage(message1); // Hit
      optimizer.optimizeMessage(message2); // Miss
      optimizer.optimizeMessage(message1); // Hit

      const stats = optimizer.getCacheStats();

      assert.strictEqual(stats.size, 2);
      assert.strictEqual(stats.hits, 2);
      assert.strictEqual(stats.misses, 2);
      assert.strictEqual(stats.hitRate, '50.00%');
    });
  });

  describe('clearCache', () => {
    it('should clear cache and reset counters', () => {
      // Add some data
      optimizer.addToCache('key1', 'value1');
      optimizer.addToCache('key2', 'value2');
      optimizer.cacheHits = 5;
      optimizer.cacheMisses = 3;

      optimizer.clearCache();

      assert.strictEqual(optimizer.messageCache.size, 0);
      assert.strictEqual(optimizer.cacheHits, 0);
      assert.strictEqual(optimizer.cacheMisses, 0);
    });
  });

  describe('createStreamOptimizer', () => {
    it('should create stream optimizer', () => {
      const streamOptimizer = optimizer.createStreamOptimizer();

      assert.ok(streamOptimizer);
      assert.strictEqual(typeof streamOptimizer.addChunk, 'function');
      assert.strictEqual(typeof streamOptimizer.flush, 'function');
    });

    it('should buffer chunks until threshold', () => {
      const streamOptimizer = optimizer.createStreamOptimizer();

      // Add small chunks - should buffer
      let result = streamOptimizer.addChunk('Hello ');
      assert.strictEqual(result, null);

      result = streamOptimizer.addChunk('World');
      assert.strictEqual(result, null);

      // Flush manually
      result = streamOptimizer.flush();
      assert.ok(result);
      assert.strictEqual(result.content, 'Hello World');
      assert.strictEqual(result.type, 'stream');
    });

    it('should auto-flush on large buffer', () => {
      const streamOptimizer = optimizer.createStreamOptimizer();

      // Add large chunk that exceeds buffer size
      const largeChunk = 'x'.repeat(1500);
      const result = streamOptimizer.addChunk(largeChunk);

      assert.ok(result);
      assert.ok(result.content);
      assert.strictEqual(result.type, 'stream');
    });

    it('should auto-flush after many chunks', () => {
      const streamOptimizer = optimizer.createStreamOptimizer();

      let result;
      // Add 11 small chunks (threshold is 10)
      for (let i = 0; i < 11; i++) {
        result = streamOptimizer.addChunk(`chunk${i} `);
      }

      assert.ok(result);
      assert.ok(result.content);
      assert.strictEqual(result.type, 'stream');
    });

    it('should handle empty flush', () => {
      const streamOptimizer = optimizer.createStreamOptimizer();

      const result = streamOptimizer.flush();
      assert.strictEqual(result, null);
    });
  });

  describe('optimizeStreamChunk', () => {
    it('should optimize stream chunk', () => {
      const chunk = '  Hello   World  ';
      const optimized = optimizer.optimizeStreamChunk(chunk);

      assert.strictEqual(optimized.content, 'Hello World');
      assert.strictEqual(optimized.type, 'stream');
      assert.ok(optimized.timestamp);
    });

    it('should handle empty chunk', () => {
      const optimized = optimizer.optimizeStreamChunk('');

      assert.strictEqual(optimized.content, '');
      assert.strictEqual(optimized.type, 'stream');
      assert.ok(optimized.timestamp);
    });
  });

  describe('Singleton instance', () => {
    it('should export singleton instance', () => {
      assert.ok(messageOptimizer);
      assert.ok(messageOptimizer instanceof MessageOptimizer);
    });

    it('should maintain state across uses', () => {
      // Clear any existing state
      messageOptimizer.clearCache();

      const message = { id: 'singleton-test', content: 'Test', timestamp: 999 };

      // First use - miss
      messageOptimizer.optimizeMessage(message);
      assert.strictEqual(messageOptimizer.cacheMisses, 1);

      // Second use - hit
      messageOptimizer.optimizeMessage(message);
      assert.strictEqual(messageOptimizer.cacheHits, 1);
    });
  });
});
