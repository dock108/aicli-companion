import test from 'node:test';
import assert from 'node:assert';
import { ClaudeStreamParser } from '../../services/stream-parser.js';

test('ClaudeStreamParser', async (t) => {
  await t.test('Basic parsing', async (t) => {
    await t.test('should parse simple text', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('Hello world', true);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].type, 'text');
      assert.strictEqual(chunks[0].content, 'Hello world');
      assert.strictEqual(chunks[0].isFinal, true);
    });

    await t.test('should handle multi-line text', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('Line 1\nLine 2\nLine 3', true);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].content, 'Line 1\nLine 2\nLine 3');
    });

    await t.test('should split on empty lines', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('Paragraph 1\n\nParagraph 2', true);
      assert.strictEqual(chunks.length, 2);
      assert.strictEqual(chunks[0].content, 'Paragraph 1');
      assert.strictEqual(chunks[1].content, 'Paragraph 2');
    });
  });

  await t.test('Code block handling', async (t) => {
    await t.test('should detect code blocks with language', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('```javascript\nconst x = 1;\n```', true);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].type, 'code');
      assert.strictEqual(chunks[0].language, 'javascript');
      assert.strictEqual(chunks[0].content, 'const x = 1;');
    });

    await t.test('should handle code blocks without language', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('```\ncode here\n```', true);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].type, 'code');
      assert.strictEqual(chunks[0].language, 'text'); // Defaults to 'text' when no language specified
      assert.strictEqual(chunks[0].content, 'code here');
    });

    await t.test('should handle incomplete code blocks', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('```javascript\nconst x = 1;', false);
      assert.strictEqual(chunks.length, 0); // Buffer should hold incomplete block
      
      const finalChunks = parser.parseData('\n```', true);
      assert.strictEqual(finalChunks.length, 1);
      assert.strictEqual(finalChunks[0].type, 'code');
      assert.strictEqual(finalChunks[0].content, 'const x = 1;');
    });
  });

  await t.test('Buffer management', async (t) => {
    await t.test('should accumulate data in buffer', () => {
      const parser = new ClaudeStreamParser();
      
      parser.parseData('Hello ', false);
      parser.parseData('world', false);
      const chunks = parser.parseData('!', true);
      
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].content, 'Hello world!');
    });

    await t.test('should clear buffer after final chunk', () => {
      const parser = new ClaudeStreamParser();
      
      parser.parseData('First message', true);
      const chunks = parser.parseData('Second message', true);
      
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].content, 'Second message');
    });
  });

  await t.test('Mixed content handling', async (t) => {
    await t.test('should handle text followed by code', () => {
      const parser = new ClaudeStreamParser();
      const content = 'Here is some code:\n\n```python\nprint("hello")\n```';
      const chunks = parser.parseData(content, true);
      
      assert.strictEqual(chunks.length, 2);
      assert.strictEqual(chunks[0].type, 'text');
      assert.strictEqual(chunks[0].content, 'Here is some code:');
      assert.strictEqual(chunks[1].type, 'code');
      assert.strictEqual(chunks[1].language, 'python');
      assert.strictEqual(chunks[1].content, 'print("hello")');
    });

    await t.test('should handle code followed by text', () => {
      const parser = new ClaudeStreamParser();
      const content = '```js\ncode\n```\n\nMore text here';
      const chunks = parser.parseData(content, true);
      
      assert.strictEqual(chunks.length, 2);
      assert.strictEqual(chunks[0].type, 'code');
      assert.strictEqual(chunks[1].type, 'text');
      assert.strictEqual(chunks[1].content, 'More text here');
    });
  });

  await t.test('Incremental parsing', async (t) => {
    await t.test('should handle incremental code block parsing', () => {
      const parser = new ClaudeStreamParser();
      
      // First part
      let chunks = parser.parseData('Text before\n\n```java', false);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].content, 'Text before');
      
      // Middle part
      chunks = parser.parseData('script\nclass Test {}', false);
      assert.strictEqual(chunks.length, 0);
      
      // Final part
      chunks = parser.parseData('\n```\n\nText after', true);
      assert.strictEqual(chunks.length, 2);
      assert.strictEqual(chunks[0].type, 'code');
      assert.strictEqual(chunks[0].language, 'javascript');
      assert.strictEqual(chunks[1].content, 'Text after');
    });
  });

  await t.test('Edge cases', async (t) => {
    await t.test('should handle empty input', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('', true);
      // Empty input with isComplete=true creates a complete chunk
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].type, 'complete');
      assert.strictEqual(chunks[0].content, '');
      assert.strictEqual(chunks[0].isFinal, true);
    });

    await t.test('should handle only whitespace', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('   \n  \n   ', true);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].content.trim(), '');
    });

    await t.test('should handle multiple empty lines', () => {
      const parser = new ClaudeStreamParser();
      const chunks = parser.parseData('Text\n\n\n\nMore text', true);
      assert.strictEqual(chunks.length, 2);
      assert.strictEqual(chunks[0].content, 'Text');
      assert.strictEqual(chunks[1].content, 'More text');
    });
  });

  await t.test('Reset functionality', async (t) => {
    await t.test('should reset parser state', () => {
      const parser = new ClaudeStreamParser();
      
      // Add some data
      parser.parseData('Incomplete data', false);
      parser.parseData('```python\nincomplete', false);
      
      // Reset
      parser.reset();
      
      // New data should work normally
      const chunks = parser.parseData('Fresh start', true);
      assert.strictEqual(chunks.length, 1);
      assert.strictEqual(chunks[0].content, 'Fresh start');
    });
  });
});