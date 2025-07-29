import { describe, it, expect, beforeEach } from 'vitest';
import { ClaudeStreamParser } from '../../services/stream-parser.js';

describe('ClaudeStreamParser', () => {
  let parser;

  beforeEach(() => {
    parser = new ClaudeStreamParser();
  });

  describe('Basic parsing', () => {
    it('should parse simple text', () => {
      const chunks = parser.parseData('Hello world', true);
      expect(chunks).toHaveLength(1);
      expect(chunks[0]).toMatchObject({
        type: 'text',
        content: 'Hello world',
        isFinal: true,
      });
    });

    it('should handle multi-line text', () => {
      const chunks = parser.parseData('Line 1\nLine 2\nLine 3', true);
      expect(chunks).toHaveLength(1);
      expect(chunks[0].content).toBe('Line 1\nLine 2\nLine 3');
    });

    it('should split on empty lines', () => {
      const chunks = parser.parseData('Paragraph 1\n\nParagraph 2', true);
      expect(chunks).toHaveLength(2);
      expect(chunks[0].content).toBe('Paragraph 1');
      expect(chunks[1].content).toBe('Paragraph 2');
      expect(chunks[1].isFinal).toBe(true);
    });
  });

  describe('Section headers', () => {
    it('should detect Plan section', () => {
      const chunks = parser.parseData('Plan:\nStep 1\nStep 2', true);
      expect(chunks).toHaveLength(2);
      expect(chunks[0]).toMatchObject({
        type: 'section',
        content: 'Plan',
        level: 1,
      });
      expect(chunks[1]).toMatchObject({
        type: 'text',
        content: 'Step 1\nStep 2',
      });
    });

    it('should detect Code section', () => {
      const chunks = parser.parseData('Code:\nfunction test() {}', true);
      expect(chunks).toHaveLength(2);
      expect(chunks[0].type).toBe('section');
      expect(chunks[0].content).toBe('Code');
    });

    it('should handle sections without colons', () => {
      const chunks = parser.parseData('Summary\nThis is the summary', true);
      expect(chunks).toHaveLength(2);
      expect(chunks[0].content).toBe('Summary');
    });
  });

  describe('Code blocks', () => {
    it('should parse code blocks', () => {
      const input = '```javascript\nconst x = 1;\n```';
      const chunks = parser.parseData(input, true);
      expect(chunks).toHaveLength(1);
      expect(chunks[0]).toMatchObject({
        type: 'code',
        content: 'const x = 1;',
        language: 'javascript',
      });
    });

    it('should handle code blocks without language', () => {
      const input = '```\nplain text\n```';
      const chunks = parser.parseData(input, true);
      expect(chunks[0].language).toBe('text');
    });

    it('should emit text before code block', () => {
      const input = 'Here is some code:\n```js\ncode\n```';
      const chunks = parser.parseData(input, true);
      expect(chunks).toHaveLength(2);
      expect(chunks[0].type).toBe('text');
      expect(chunks[1].type).toBe('code');
    });
  });

  describe('Markdown headers', () => {
    it('should parse markdown headers', () => {
      const chunks = parser.parseData('# Header 1\n## Header 2', true);
      expect(chunks).toHaveLength(2);
      expect(chunks[0]).toMatchObject({
        type: 'header',
        content: 'Header 1',
        level: 1,
      });
      expect(chunks[1]).toMatchObject({
        type: 'header',
        content: 'Header 2',
        level: 2,
      });
    });
  });

  describe('Lists', () => {
    it('should group bullet lists', () => {
      const input = '- Item 1\n- Item 2\n- Item 3';
      const chunks = parser.parseData(input, true);
      expect(chunks).toHaveLength(1);
      expect(chunks[0]).toMatchObject({
        type: 'list',
        content: '- Item 1\n- Item 2\n- Item 3',
      });
    });

    it('should group numbered lists', () => {
      const input = '1. First\n2. Second\n3. Third';
      const chunks = parser.parseData(input, true);
      expect(chunks).toHaveLength(1);
      expect(chunks[0].type).toBe('list');
    });

    it('should separate lists from other content', () => {
      const input = 'Text before\n\n- List item\n\nText after';
      const chunks = parser.parseData(input, true);
      expect(chunks).toHaveLength(3);
      expect(chunks[0].type).toBe('text');
      expect(chunks[1].type).toBe('list');
      expect(chunks[2].type).toBe('text');
    });
  });

  describe('Streaming behavior', () => {
    it('should handle partial data', () => {
      const chunks1 = parser.parseData('Hello ', false);
      expect(chunks1).toHaveLength(0); // Buffered

      const chunks2 = parser.parseData('world\n', true);
      expect(chunks2).toHaveLength(1);
      expect(chunks2[0].content).toBe('Hello world');
    });

    it('should buffer incomplete lines', () => {
      const chunks1 = parser.parseData('Line 1\nLine 2 partial', false);
      expect(chunks1).toHaveLength(1);
      expect(chunks1[0].content).toBe('Line 1');

      const chunks2 = parser.parseData(' complete', true);
      expect(chunks2).toHaveLength(1);
      expect(chunks2[0].content).toBe('Line 2 partial complete');
    });

    it('should mark final chunk', () => {
      parser.parseData('Chunk 1\n\n', false);
      const chunks = parser.parseData('Chunk 2', true);
      expect(chunks[chunks.length - 1].isFinal).toBe(true);
    });
  });

  describe('Horizontal rules', () => {
    it('should detect horizontal rules', () => {
      const chunks = parser.parseData('Text\n---\nMore text', true);
      expect(chunks).toHaveLength(3);
      expect(chunks[1]).toMatchObject({
        type: 'divider',
        content: '',
      });
    });
  });

  describe('Complex scenarios', () => {
    it('should handle mixed content', () => {
      const input = `Plan:
1. First step
2. Second step

Code:
\`\`\`python
def hello():
    print("Hello")
\`\`\`

Summary:
Everything worked!`;

      const chunks = parser.parseData(input, true);
      expect(chunks.map((c) => c.type)).toEqual([
        'section',
        'list',
        'section',
        'code',
        'section',
        'text',
      ]);
      expect(chunks[chunks.length - 1].isFinal).toBe(true);
    });
  });
});
