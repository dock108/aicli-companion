import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { PushNotificationService } from '../../services/push-notification.js';

describe('PushNotificationService - Markdown Stripping', () => {
  let service;

  beforeEach(() => {
    service = new PushNotificationService();
  });

  describe('stripMarkdown', () => {
    it('should remove code blocks', () => {
      const input = 'Here is some text\n```javascript\nconst x = 1;\n```\nMore text';
      const expected = 'Here is some text\n[code block]\nMore text';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should remove inline code', () => {
      const input = 'Use the `npm install` command';
      const expected = 'Use the npm install command';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should remove headers', () => {
      const input = '# Header 1\n## Header 2\n### Header 3\nNormal text';
      const expected = 'Header 1\nHeader 2\nHeader 3\nNormal text';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should remove bold and italic markers', () => {
      const input = 'This is **bold** and this is *italic* and this is ***both***';
      const expected = 'This is bold and this is italic and this is both';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should remove links but keep text', () => {
      const input = 'Check out [this link](https://example.com) for more info';
      const expected = 'Check out this link for more info';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should handle images', () => {
      const input = 'Here is an image: ![alt text](image.png)';
      const expected = 'Here is an image: [image: alt text]';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should remove list markers', () => {
      const input = '- Item 1\n- Item 2\n1. First\n2. Second';
      const expected = 'Item 1\nItem 2\nFirst\nSecond';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should remove blockquotes', () => {
      const input = '> This is a quote\nNormal text';
      const expected = 'This is a quote\nNormal text';
      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should handle complex markdown', () => {
      const input = `# Welcome to **Claude**

Here's what I can do:
- **Code generation** with \`JavaScript\`
- *Analysis* of your [documentation](docs.md)

\`\`\`python
def hello():
    print("Hello, World!")
\`\`\`

> Remember: Always test your code!`;

      const expected = `Welcome to Claude

Here's what I can do:
Code generation with JavaScript
Analysis of your documentation

[code block]

Remember: Always test your code!`;

      assert.strictEqual(service.stripMarkdown(input), expected);
    });

    it('should handle empty or null input', () => {
      assert.strictEqual(service.stripMarkdown(''), '');
      assert.strictEqual(service.stripMarkdown(null), '');
      assert.strictEqual(service.stripMarkdown(undefined), '');
    });
  });

  describe('truncateMessage', () => {
    it('should strip markdown before truncating', () => {
      const input = '**This is bold** and `this is code` and it continues for a very long time with lots of text that needs to be truncated because it is too long for a notification';
      const result = service.truncateMessage(input, 50);
      
      // Should not contain markdown formatting
      assert.ok(!result.includes('**'));
      assert.ok(!result.includes('`'));
      assert.ok(result.includes('This is bold'));
      assert.ok(result.endsWith('...'));
    });

    it('should truncate at word boundary when possible', () => {
      const input = 'This is a long message that needs to be truncated at a sensible word boundary';
      const result = service.truncateMessage(input, 40);
      
      // Should end with ... and not cut off in middle of word
      assert.ok(result.endsWith('...'));
      assert.ok(result.length <= 43); // 40 + '...'
      
      // Should not end with partial word
      const lastWord = result.replace('...', '').trim().split(' ').pop();
      assert.ok(input.includes(lastWord + ' ') || input.endsWith(lastWord));
    });

    it('should handle messages shorter than max length', () => {
      const input = '**Short** message';
      const result = service.truncateMessage(input, 50);
      assert.strictEqual(result, 'Short message');
    });

    it('should handle empty input', () => {
      assert.strictEqual(service.truncateMessage('', 50), '');
      assert.strictEqual(service.truncateMessage(null, 50), '');
      assert.strictEqual(service.truncateMessage(undefined, 50), '');
    });

    it('should handle markdown with code blocks', () => {
      const input = `Here is a response:

\`\`\`javascript
function longFunctionName() {
  return "This is a very long function that does many things";
}
\`\`\`

And more text after the code block that continues for quite a while`;
      
      const result = service.truncateMessage(input, 100);
      assert.ok(result.includes('[code block]'));
      assert.ok(!result.includes('```'));
      assert.ok(result.endsWith('...'));
    });
  });
});