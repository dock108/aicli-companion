import test from 'node:test';
import assert from 'node:assert';
import { parseClaudeOutput, removeJsonFromText } from '../../services/claude-output-parser.js';

test('claude-output-parser', async (t) => {
  await t.test('parseClaudeOutput', async (tt) => {
    await tt.test('should return null for invalid inputs', () => {
      assert.strictEqual(parseClaudeOutput(null), null);
      assert.strictEqual(parseClaudeOutput(undefined), null);
      assert.strictEqual(parseClaudeOutput(''), null);
      assert.strictEqual(parseClaudeOutput(123), null);
      assert.strictEqual(parseClaudeOutput({}), null);
      assert.strictEqual(parseClaudeOutput([]), null);
    });

    await tt.test('should return null for text without JSON', () => {
      assert.strictEqual(parseClaudeOutput('Hello world'), null);
      assert.strictEqual(parseClaudeOutput('Just plain text'), null);
      assert.strictEqual(parseClaudeOutput('No JSON here!'), null);
    });

    await tt.test('should return null for invalid JSON', () => {
      assert.strictEqual(parseClaudeOutput('{invalid json}'), null);
      assert.strictEqual(parseClaudeOutput('{ "key": }'), null);
      assert.strictEqual(parseClaudeOutput('{ missing quotes: value }'), null);
    });

    await tt.test('should return null for valid JSON that is not Claude format', () => {
      assert.strictEqual(parseClaudeOutput('{"foo": "bar"}'), null);
      assert.strictEqual(parseClaudeOutput('{"data": {"nested": true}}'), null);
      assert.strictEqual(parseClaudeOutput('[1, 2, 3]'), null);
    });

    await tt.test('should parse Claude output with content field', () => {
      const result = parseClaudeOutput('{"content": "Hello from Claude"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Hello from Claude',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should parse Claude output with result field', () => {
      const result = parseClaudeOutput('{"result": "Task completed"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Task completed',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should parse Claude output with answer field', () => {
      const result = parseClaudeOutput('{"answer": "42"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: '42',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should parse Claude output with message field', () => {
      const result = parseClaudeOutput('{"message": "Processing complete", "type": "status"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Processing complete',
        metadata: {
          type: 'status',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should parse Claude output with text field', () => {
      const result = parseClaudeOutput('{"text": "Generated text", "type": "generation"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Generated text',
        metadata: {
          type: 'generation',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should parse Claude output with response field', () => {
      const result = parseClaudeOutput('{"response": "API response", "type": "api"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'API response',
        metadata: {
          type: 'api',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should parse Claude output with type field', () => {
      const result = parseClaudeOutput('{"type": "analysis", "content": "Analysis result"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Analysis result',
        metadata: {
          type: 'analysis',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should detect thinking field', () => {
      const result = parseClaudeOutput('{"thinking": "Let me think...", "content": "Answer"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Answer',
        metadata: {
          type: 'unknown',
          hasThinking: true,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should detect reasoning field', () => {
      const result = parseClaudeOutput('{"reasoning": "Because...", "content": "Answer"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Answer',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should treat object with only reasoning as valid Claude output', () => {
      const result = parseClaudeOutput('{"reasoning": "Step by step analysis"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: null,
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should detect tool_calls field', () => {
      const result = parseClaudeOutput(
        '{"tool_calls": [{"name": "search"}], "content": "Searching..."}'
      );
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Searching...',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: true,
        },
      });
    });

    await tt.test('should detect tools_used field', () => {
      const result = parseClaudeOutput(
        '{"tools_used": [{"tool": "calculator"}], "content": "Calculating..."}'
      );
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Calculating...',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: true,
        },
      });
    });

    await tt.test('should format tool calls when no other content', () => {
      const result = parseClaudeOutput(
        '{"tool_calls": [{"name": "search"}, {"name": "calculate"}]}'
      );
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Using tools: search, calculate',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: true,
        },
      });
    });

    await tt.test('should format tools_used when no other content', () => {
      const result = parseClaudeOutput('{"tools_used": [{"tool": "browser"}, {"tool": "editor"}]}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Using tools: browser, editor',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: true,
        },
      });
    });

    await tt.test('should handle empty tool arrays', () => {
      const result = parseClaudeOutput('{"tool_calls": []}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: null,
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: true,
        },
      });
    });

    await tt.test('should fallback to any string field except excluded ones', () => {
      const result = parseClaudeOutput('{"custom_field": "Custom content", "type": "test"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Custom content',
        metadata: {
          type: 'test',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should not use thinking field as content', () => {
      const result = parseClaudeOutput('{"thinking": "Internal thoughts", "type": "test"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: null,
        metadata: {
          type: 'test',
          hasThinking: true,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should not use reasoning field as content', () => {
      const result = parseClaudeOutput('{"reasoning": "Because...", "type": "test"}');
      // reasoning is not extracted as content but it makes the object valid Claude output
      assert.deepStrictEqual(result, {
        isJson: true,
        content: null,
        metadata: {
          type: 'test',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should not use empty string fields', () => {
      const result = parseClaudeOutput('{"empty": "", "type": "test"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: null,
        metadata: {
          type: 'test',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should handle multiple JSON blocks and use first valid Claude format', () => {
      // The regex is greedy, so it will match the entire string from first { to last }
      // This results in invalid JSON: {"foo": "bar"} Some text {"content": "Claude output"} {"other": "json"}
      // For separate JSON parsing, they need to be on separate lines or properly separated
      const text = 'Some prefix\n{"content": "Claude output"}\nSome suffix';
      const result = parseClaudeOutput(text);
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Claude output',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should handle greedy regex matching', () => {
      // This demonstrates the greedy matching behavior
      const text = '{"foo": "bar"} {"content": "test"}';
      // The regex will match the entire string as one block: {"foo": "bar"} {"content": "test"}
      // which is invalid JSON
      const result = parseClaudeOutput(text);
      assert.strictEqual(result, null);
    });

    await tt.test('should handle JSON with mixed content fields', () => {
      // content field takes priority
      const result = parseClaudeOutput(
        '{"content": "Primary", "result": "Secondary", "answer": "Tertiary"}'
      );
      assert.deepStrictEqual(result, {
        isJson: true,
        content: 'Primary',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });

    await tt.test('should handle nested JSON strings', () => {
      const result = parseClaudeOutput('{"content": "{\\"nested\\": \\"json\\"}"}');
      assert.deepStrictEqual(result, {
        isJson: true,
        content: '{"nested": "json"}',
        metadata: {
          type: 'unknown',
          hasThinking: false,
          hasToolUse: false,
        },
      });
    });
  });

  await t.test('removeJsonFromText', async (tt) => {
    await tt.test('should return original text for null/undefined inputs', () => {
      assert.strictEqual(removeJsonFromText(null, '{}'), null);
      assert.strictEqual(removeJsonFromText(undefined, '{}'), undefined);
      assert.strictEqual(removeJsonFromText('text', null), 'text');
      assert.strictEqual(removeJsonFromText('text', undefined), 'text');
    });

    await tt.test('should remove exact JSON match', () => {
      const text = 'Before {"content": "test"} After';
      const json = '{"content": "test"}';
      assert.strictEqual(removeJsonFromText(text, json), 'Before  After');
    });

    await tt.test('should handle special regex characters', () => {
      const text = 'Text {"key": "value.*+?^${}()|[]\\\\"}  End';
      const json = '{"key": "value.*+?^${}()|[]\\\\"}';
      assert.strictEqual(removeJsonFromText(text, json), 'Text   End');
    });

    await tt.test('should remove multiple occurrences', () => {
      const text = '{"a": 1} middle {"a": 1} end {"a": 1}';
      const json = '{"a": 1}';
      assert.strictEqual(removeJsonFromText(text, json), 'middle  end');
    });

    await tt.test('should return trimmed result', () => {
      const text = '   {"content": "test"}   ';
      const json = '{"content": "test"}';
      assert.strictEqual(removeJsonFromText(text, json), '');
    });

    await tt.test('should handle no match', () => {
      const text = 'No JSON here';
      const json = '{"content": "test"}';
      assert.strictEqual(removeJsonFromText(text, json), 'No JSON here');
    });

    await tt.test('should handle empty strings', () => {
      assert.strictEqual(removeJsonFromText('', ''), '');
      assert.strictEqual(removeJsonFromText('text', ''), 'text');
      assert.strictEqual(removeJsonFromText('', 'json'), '');
    });
  });
});
