import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { UnifiedMessageParser } from '../../services/message-parser.js';

describe('UnifiedMessageParser', () => {
  let parser;

  beforeEach(() => {
    parser = new UnifiedMessageParser();
  });

  describe('Constructor', () => {
    it('should initialize with default values', () => {
      assert.strictEqual(parser.buffer, '');
      assert.strictEqual(parser.chunkId, 0);
      assert.strictEqual(parser.inCodeBlock, false);
      assert.strictEqual(parser.codeBlockBuffer, '');
      assert.strictEqual(parser.codeBlockLanguage, '');
      assert.strictEqual(parser.jsonBuffer, '');
      assert.strictEqual(parser.lastStatusMessage, null);
      assert.strictEqual(parser.thinkingStartTime, null);
      assert.strictEqual(parser.currentActivity, null);
      assert.strictEqual(parser.tokenCount, 0);
    });
  });

  describe('parse()', () => {
    it('should parse simple text data', () => {
      const result = parser.parse('Hello, world!');
      assert.ok(Array.isArray(result));
      assert.ok(result.length > 0);
    });

    it('should handle empty data', () => {
      const result = parser.parse('');
      assert.ok(Array.isArray(result));
    });

    it('should parse complete messages', () => {
      const result = parser.parse('Complete message', true);
      assert.ok(Array.isArray(result));
    });
  });

  describe('parseStreamData()', () => {
    it('should accumulate data in buffer', () => {
      parser.parseStreamData('Part 1');
      assert.strictEqual(parser.buffer, 'Part 1');

      parser.parseStreamData(' Part 2');
      assert.strictEqual(parser.buffer, 'Part 1 Part 2');
    });

    it('should handle stream completion', () => {
      parser.parseStreamData('Some data');
      const result = parser.parseStreamData('', true);
      assert.ok(Array.isArray(result));
    });
  });

  describe('parseStreamJson()', () => {
    it('should parse valid JSON lines', () => {
      parser.buffer = '{"type":"text","content":"Hello"}\n{"type":"text","content":"World"}\n';
      const result = parser.parseStreamJson(true);
      assert.ok(Array.isArray(result));
      assert.ok(result.length >= 2);
    });

    it('should handle partial JSON lines', () => {
      parser.buffer = '{"type":"text","content":"Complete"}\n{"type":"text","content":"Partial';
      const result = parser.parseStreamJson(false);
      assert.ok(Array.isArray(result));
      // Should keep partial line in buffer
      assert.ok(parser.buffer.includes('Partial'));
    });

    it('should handle invalid JSON gracefully', () => {
      parser.buffer = 'Not JSON\n{"valid":"json"}\nAlso not JSON\n';
      const result = parser.parseStreamJson(true);
      assert.ok(Array.isArray(result));
      // Should process both valid and invalid lines
      assert.ok(result.length > 0);
    });

    it('should handle empty lines', () => {
      parser.buffer = '\n\n{"type":"text","content":"Data"}\n\n';
      const result = parser.parseStreamJson(true);
      assert.ok(Array.isArray(result));
    });
  });

  describe('processJsonChunk()', () => {
    it('should process text chunks', () => {
      const chunk = { type: 'text', content: 'Hello' };
      const result = parser.processJsonChunk(chunk);
      assert.ok(result);
      assert.strictEqual(result.type, 'text');
      assert.ok(result.id !== undefined);
    });

    it('should process thinking indicator', () => {
      const chunk = { type: 'thinking_indicator' };
      const result = parser.processJsonChunk(chunk);
      assert.ok(result);
      assert.strictEqual(result.type, 'thinking_indicator');
    });

    it('should process status messages', () => {
      const chunk = { type: 'status', message: 'Processing...' };
      const result = parser.processJsonChunk(chunk);
      assert.ok(result);
      assert.strictEqual(result.type, 'status');
    });

    it('should handle unknown chunk types', () => {
      const chunk = { type: 'unknown', data: 'test' };
      const result = parser.processJsonChunk(chunk);
      assert.ok(result);
    });
  });

  describe('parseTextStream()', () => {
    it('should parse plain text', () => {
      parser.buffer = 'Plain text message';
      const result = parser.parseTextStream(true);
      assert.ok(Array.isArray(result));
    });

    it('should handle code blocks', () => {
      parser.buffer = '```javascript\nconst x = 1;\n```';
      const result = parser.parseTextStream(true);
      assert.ok(Array.isArray(result));
    });
  });

  describe('looksLikeStreamJson()', () => {
    it('should detect stream JSON format', () => {
      const jsonData = '{"type":"text","content":"test"}\n{"type":"status"}';
      assert.strictEqual(parser.looksLikeStreamJson(jsonData), true);
    });

    it('should reject non-JSON data', () => {
      const textData = 'This is not JSON';
      assert.strictEqual(parser.looksLikeStreamJson(textData), false);
    });

    it('should handle empty data', () => {
      assert.strictEqual(parser.looksLikeStreamJson(''), false);
    });
  });

  describe('parseStructuredOutput()', () => {
    it('should parse valid JSON object', () => {
      const jsonStr = '{"result":"success","data":"test"}';
      const result = parser.parseStructuredOutput(jsonStr);
      assert.ok(result);
    });

    it('should return null for non-JSON', () => {
      const result = parser.parseStructuredOutput('Not JSON');
      assert.strictEqual(result, null);
    });

    it('should handle arrays', () => {
      const jsonStr = '[{"item":1},{"item":2}]';
      const result = parser.parseStructuredOutput(jsonStr);
      assert.ok(result);
    });
  });

  describe('extractCodeBlocks()', () => {
    it('should extract code blocks from text', () => {
      const text = 'Text before\n```js\ncode here\n```\nText after';
      const result = parser.extractCodeBlocks(text);
      assert.ok(result);
      assert.ok(Array.isArray(result.blocks));
    });

    it('should handle text without code blocks', () => {
      const text = 'Just plain text';
      const result = parser.extractCodeBlocks(text);
      assert.ok(result);
      assert.strictEqual(result.blocks.length, 0);
    });
  });

  describe('reset()', () => {
    it('should reset all parser state', () => {
      parser.buffer = 'some data';
      parser.chunkId = 10;
      parser.inCodeBlock = true;
      parser.reset();

      assert.strictEqual(parser.buffer, '');
      assert.strictEqual(parser.chunkId, 0);
      assert.strictEqual(parser.inCodeBlock, false);
    });
  });
});
