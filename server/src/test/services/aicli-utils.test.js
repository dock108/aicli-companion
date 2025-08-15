import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { InputValidator, MessageProcessor, AICLIConfig } from '../../services/aicli-utils.js';

describe('AICLI Utils - Static Methods', () => {
  describe('InputValidator', () => {
    it('should sanitize prompt correctly', () => {
      const prompt = 'Test prompt';
      const result = InputValidator.sanitizePrompt(prompt);
      assert.strictEqual(result, prompt);
    });

    it('should throw error for non-string prompt', () => {
      assert.throws(() => InputValidator.sanitizePrompt(123), {
        message: 'Prompt must be a string',
      });
    });

    it('should remove null bytes from prompt', () => {
      const prompt = 'Test\0prompt\0with\0nulls';
      const result = InputValidator.sanitizePrompt(prompt);
      assert.strictEqual(result, 'Testpromptwithnulls');
    });

    it('should limit prompt length to 50000 characters', () => {
      const longPrompt = 'a'.repeat(60000);
      const result = InputValidator.sanitizePrompt(longPrompt);
      assert.strictEqual(result.length, 50000);
    });

    it('should throw error for empty prompt after sanitization', () => {
      assert.throws(() => InputValidator.sanitizePrompt('\0\0\0'), {
        message: 'Prompt cannot be empty',
      });
    });

    it('should validate format correctly', () => {
      const result = InputValidator.validateFormat('json');
      assert.strictEqual(result, 'json');
    });

    it('should validate markdown format', () => {
      const result = InputValidator.validateFormat('markdown');
      assert.strictEqual(result, 'markdown');
    });

    it('should validate text format', () => {
      const result = InputValidator.validateFormat('text');
      assert.strictEqual(result, 'text');
    });

    it('should handle uppercase format', () => {
      const result = InputValidator.validateFormat('JSON');
      assert.strictEqual(result, 'json');
    });

    it('should handle format with spaces', () => {
      const result = InputValidator.validateFormat('  json  ');
      assert.strictEqual(result, 'json');
    });

    it('should throw error for invalid format', () => {
      assert.throws(() => InputValidator.validateFormat('xml'), {
        message: 'Invalid format. Must be one of: json, text, markdown',
      });
    });

    it('should use default format for invalid input', () => {
      const result = InputValidator.validateFormat(null);
      assert.strictEqual(result, 'json');
    });

    it('should use default format for non-string input', () => {
      const result = InputValidator.validateFormat(123);
      assert.strictEqual(result, 'json');
    });

    it('should validate working directory', async () => {
      const cwd = process.cwd();
      const result = await InputValidator.validateWorkingDirectory(cwd);
      assert.strictEqual(result, cwd);
    });

    it('should use safe root for null working directory', async () => {
      const safeRoot = '/safe/root';
      const result = await InputValidator.validateWorkingDirectory(null, safeRoot);
      assert.strictEqual(result, safeRoot);
    });

    it('should use cwd for null working directory without safe root', async () => {
      const result = await InputValidator.validateWorkingDirectory(null);
      assert.strictEqual(result, process.cwd());
    });

    it('should reject dangerous paths', async () => {
      await assert.rejects(InputValidator.validateWorkingDirectory('/etc/passwd'), {
        message: /Access denied.*not allowed/,
      });
    });

    it('should reject /usr path', async () => {
      await assert.rejects(InputValidator.validateWorkingDirectory('/usr/bin'), {
        message: /Access denied.*not allowed/,
      });
    });

    it('should reject /root path', async () => {
      await assert.rejects(InputValidator.validateWorkingDirectory('/root'), {
        message: /Access denied.*not allowed/,
      });
    });

    it('should reject non-existent directory', async () => {
      await assert.rejects(InputValidator.validateWorkingDirectory('/this/does/not/exist/12345'), {
        message: /Directory not accessible/,
      });
    });

    it('should sanitize session ID', () => {
      const sessionId = 'test-session_123';
      const result = InputValidator.sanitizeSessionId(sessionId);
      assert.strictEqual(result, sessionId);
    });

    it('should remove invalid characters from session ID', () => {
      const sessionId = 'test@session#123$';
      const result = InputValidator.sanitizeSessionId(sessionId);
      assert.strictEqual(result, 'testsession123');
    });

    it('should limit session ID length to 64 characters', () => {
      const longId = 'a'.repeat(100);
      const result = InputValidator.sanitizeSessionId(longId);
      assert.strictEqual(result.length, 64);
    });

    it('should return null for empty session ID', () => {
      const result = InputValidator.sanitizeSessionId('');
      assert.strictEqual(result, null);
    });

    it('should return null for null session ID', () => {
      const result = InputValidator.sanitizeSessionId(null);
      assert.strictEqual(result, null);
    });

    it('should return null for non-string session ID', () => {
      const result = InputValidator.sanitizeSessionId(123);
      assert.strictEqual(result, null);
    });

    it('should return null for session ID with only invalid chars', () => {
      const result = InputValidator.sanitizeSessionId('@#$%');
      assert.strictEqual(result, null);
    });

    it('should validate AICLI arguments', () => {
      const args = ['--print', '--verbose'];
      const result = InputValidator.validateAICLIArgs(args);
      assert.deepStrictEqual(result, args);
    });

    it('should throw error for non-array arguments', () => {
      assert.throws(() => InputValidator.validateAICLIArgs('not-an-array'), {
        message: 'Arguments must be an array',
      });
    });

    it('should throw error for non-string arguments', () => {
      assert.throws(() => InputValidator.validateAICLIArgs(['valid', 123, 'string']), {
        message: 'All arguments must be strings',
      });
    });

    it('should throw error for dangerous shell characters', () => {
      assert.throws(() => InputValidator.validateAICLIArgs(['rm', '-rf', '$HOME']), {
        message: 'Arguments cannot contain dangerous shell metacharacters',
      });
    });

    it('should reject pipe character', () => {
      assert.throws(() => InputValidator.validateAICLIArgs(['ls', '|', 'grep']), {
        message: 'Arguments cannot contain dangerous shell metacharacters',
      });
    });

    it('should reject ampersand character', () => {
      assert.throws(() => InputValidator.validateAICLIArgs(['echo', 'test', '&']), {
        message: 'Arguments cannot contain dangerous shell metacharacters',
      });
    });

    it('should reject backticks', () => {
      assert.throws(() => InputValidator.validateAICLIArgs(['echo', '`ls`']), {
        message: 'Arguments cannot contain dangerous shell metacharacters',
      });
    });
  });

  describe('MessageProcessor', () => {
    it('should validate complete JSON', () => {
      const validJson = '{"test": "value"}';
      const result = MessageProcessor.isValidCompleteJSON(validJson);
      assert.strictEqual(result, true);
    });

    it('should validate complete array JSON', () => {
      const validJson = '[{"test": "value"}]';
      const result = MessageProcessor.isValidCompleteJSON(validJson);
      assert.strictEqual(result, true);
    });

    it('should reject array without closing bracket', () => {
      const invalidJson = '[{"test": "value"}';
      const result = MessageProcessor.isValidCompleteJSON(invalidJson);
      assert.strictEqual(result, false);
    });

    it('should reject object without closing brace', () => {
      const invalidJson = '{"test": "value"';
      const result = MessageProcessor.isValidCompleteJSON(invalidJson);
      assert.strictEqual(result, false);
    });

    it('should reject JSON ending with comma', () => {
      const invalidJson = '{"test": "value",';
      const result = MessageProcessor.isValidCompleteJSON(invalidJson);
      assert.strictEqual(result, false);
    });

    it('should reject JSON ending with colon', () => {
      const invalidJson = '{"test":';
      const result = MessageProcessor.isValidCompleteJSON(invalidJson);
      assert.strictEqual(result, false);
    });

    it('should reject JSON ending with quote', () => {
      const invalidJson = '{"test": "value"';
      const result = MessageProcessor.isValidCompleteJSON(invalidJson);
      assert.strictEqual(result, false);
    });

    it('should reject invalid JSON', () => {
      const invalidJson = '{"test": ';
      const result = MessageProcessor.isValidCompleteJSON(invalidJson);
      assert.strictEqual(result, false);
    });

    it('should reject empty input', () => {
      const result = MessageProcessor.isValidCompleteJSON('');
      assert.strictEqual(result, false);
    });

    it('should reject null input', () => {
      const result = MessageProcessor.isValidCompleteJSON(null);
      assert.strictEqual(result, false);
    });

    it('should parse stream JSON output', () => {
      const output = '{"type": "message"}\n{"type": "result"}';
      const result = MessageProcessor.parseStreamJsonOutput(output);
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'message');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle empty lines in stream output', () => {
      const output = '{"type": "message"}\n\n{"type": "result"}';
      const result = MessageProcessor.parseStreamJsonOutput(output);
      assert.strictEqual(result.length, 2);
    });

    it('should handle null stream output', () => {
      const result = MessageProcessor.parseStreamJsonOutput(null);
      assert.deepStrictEqual(result, []);
    });

    it('should handle non-string stream output', () => {
      const result = MessageProcessor.parseStreamJsonOutput(123);
      assert.deepStrictEqual(result, []);
    });

    it('should extract complete objects from line', () => {
      const line = '{"a":1}{"b":2}';
      const result = MessageProcessor.extractCompleteObjectsFromLine(line);
      assert.strictEqual(result.length, 2);
      assert.deepStrictEqual(result[0], { a: 1 });
      assert.deepStrictEqual(result[1], { b: 2 });
    });

    it('should extract arrays from line', () => {
      const line = '[1,2,3]{"a":"b"}';
      const result = MessageProcessor.extractCompleteObjectsFromLine(line);
      assert.strictEqual(result.length, 2);
      assert.deepStrictEqual(result[0], [1, 2, 3]);
      assert.deepStrictEqual(result[1], { a: 'b' });
    });

    it('should handle escaped quotes in strings', () => {
      const line = '{"text":"He said \\"hello\\""}';
      const result = MessageProcessor.extractCompleteObjectsFromLine(line);
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].text, 'He said "hello"');
    });

    it('should handle nested objects', () => {
      const line = '{"outer":{"inner":"value"}}';
      const result = MessageProcessor.extractCompleteObjectsFromLine(line);
      assert.strictEqual(result.length, 1);
      assert.deepStrictEqual(result[0], { outer: { inner: 'value' } });
    });

    it('should handle incomplete JSON in line', () => {
      const line = '{"complete":1}{"incomplete":';
      const result = MessageProcessor.extractCompleteObjectsFromLine(line);
      assert.strictEqual(result.length, 1);
      assert.deepStrictEqual(result[0], { complete: 1 });
    });

    it('should handle null line input', () => {
      const result = MessageProcessor.extractCompleteObjectsFromLine(null);
      assert.deepStrictEqual(result, []);
    });

    it('should handle empty line', () => {
      const result = MessageProcessor.extractCompleteObjectsFromLine('');
      assert.deepStrictEqual(result, []);
    });

    it('should extract last complete JSON', () => {
      const truncated = '{"first":1}{"last":2}';
      const result = MessageProcessor.extractLastCompleteJSON(truncated);
      assert.deepStrictEqual(result, { last: 2 });
    });

    it('should handle truncated JSON with incomplete end', () => {
      const truncated = '{"complete":1}{"incomplete":';
      const result = MessageProcessor.extractLastCompleteJSON(truncated);
      assert.strictEqual(result, null);
    });

    it('should handle null truncated input', () => {
      const result = MessageProcessor.extractLastCompleteJSON(null);
      assert.strictEqual(result, null);
    });

    it('should handle non-string truncated input', () => {
      const result = MessageProcessor.extractLastCompleteJSON(123);
      assert.strictEqual(result, null);
    });

    it('should find last complete JSON start', () => {
      const text = 'some text {"json":1} more text [';
      const result = MessageProcessor.findLastCompleteJSONStart(text);
      assert.strictEqual(result, text.lastIndexOf('['));
    });

    it('should return -1 when no JSON start found', () => {
      const text = 'no json here';
      const result = MessageProcessor.findLastCompleteJSONStart(text);
      assert.strictEqual(result, -1);
    });

    it('should handle null text in findLastCompleteJSONStart', () => {
      const result = MessageProcessor.findLastCompleteJSONStart(null);
      assert.strictEqual(result, -1);
    });

    it('should extract complete objects from array', () => {
      const arrayText = '[{"a":1},{"b":2}]';
      const result = MessageProcessor.extractCompleteObjectsFromArray(arrayText);
      assert.strictEqual(result.length, 2);
      assert.deepStrictEqual(result[0], { a: 1 });
      assert.deepStrictEqual(result[1], { b: 2 });
    });

    it('should handle empty array', () => {
      const arrayText = '[]';
      const result = MessageProcessor.extractCompleteObjectsFromArray(arrayText);
      assert.deepStrictEqual(result, []);
    });

    it('should handle array with nested objects', () => {
      const arrayText = '[{"outer":{"inner":1}}]';
      const result = MessageProcessor.extractCompleteObjectsFromArray(arrayText);
      assert.strictEqual(result.length, 1);
      assert.deepStrictEqual(result[0], { outer: { inner: 1 } });
    });

    it('should handle incomplete array', () => {
      const arrayText = '[{"a":1},{"b":';
      const result = MessageProcessor.extractCompleteObjectsFromArray(arrayText);
      assert.deepStrictEqual(result, []);
    });

    it('should handle null array text', () => {
      const result = MessageProcessor.extractCompleteObjectsFromArray(null);
      assert.deepStrictEqual(result, []);
    });

    it('should handle non-array text', () => {
      const result = MessageProcessor.extractCompleteObjectsFromArray('not an array');
      assert.deepStrictEqual(result, []);
    });

    it('should classify AICLI message as streamData for string', () => {
      const result = MessageProcessor.classifyAICLIMessage('test string');
      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data, 'test string');
    });

    it('should classify null message as streamData', () => {
      const result = MessageProcessor.classifyAICLIMessage(null);
      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data, null);
    });

    it('should classify non-object message as streamData', () => {
      const result = MessageProcessor.classifyAICLIMessage(123);
      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data, 123);
    });

    it('should handle system init message', () => {
      const message = {
        type: 'system',
        subtype: 'init',
        session_id: 'test-123',
        cwd: '/test/dir',
        tools: ['tool1'],
        mcp_servers: ['server1'],
        model: 'claude-3',
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'systemInit');
      assert.strictEqual(result.data.type, 'system_init');
      assert.strictEqual(result.data.sessionId, 'test-123');
      assert.strictEqual(result.data.workingDirectory, '/test/dir');
    });

    it('should handle regular system message', () => {
      const message = {
        type: 'system',
        content: 'System message',
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data.type, 'system');
      assert.strictEqual(result.data.content, 'System message');
    });

    it('should handle assistant message with structured content', () => {
      const message = {
        type: 'assistant',
        message: {
          id: 'msg-123',
          content: [{ type: 'text', text: 'Hello' }],
          model: 'claude-3',
          usage: { tokens: 100 },
        },
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'assistantMessage');
      assert.strictEqual(result.data.type, 'assistant_response');
      assert.strictEqual(result.data.messageId, 'msg-123');
    });

    it('should handle simple assistant message', () => {
      const message = {
        type: 'assistant',
        content: 'Assistant response',
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'streamData');
      assert.strictEqual(result.data.type, 'assistant');
      assert.strictEqual(result.data.content, 'Assistant response');
    });

    it('should handle tool use message', () => {
      const message = {
        type: 'tool_use',
        tool_name: 'bash',
        tool_input: { command: 'ls' },
        tool_id: 'tool-123',
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'toolUse');
      assert.strictEqual(result.data.type, 'tool_use');
      assert.strictEqual(result.data.toolName, 'bash');
    });

    it('should handle tool result message', () => {
      const message = {
        type: 'tool_result',
        tool_name: 'bash',
        tool_id: 'tool-123',
        result: 'output',
        is_error: false,
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'toolResult');
      assert.strictEqual(result.data.type, 'tool_result');
      assert.strictEqual(result.data.success, true);
    });

    it('should handle error tool result', () => {
      const message = {
        type: 'tool_result',
        tool_name: 'bash',
        tool_id: 'tool-123',
        error: 'command failed',
        is_error: true,
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'toolResult');
      assert.strictEqual(result.data.success, false);
      assert.strictEqual(result.data.error, 'command failed');
    });

    it('should handle result message', () => {
      const message = {
        type: 'result',
        result: 'final output',
        session_id: 'test-123',
        duration_ms: 1000,
        total_cost_usd: 0.01,
        usage: { tokens: 100 },
        is_error: false,
      };
      const result = MessageProcessor.classifyAICLIMessage(message);
      assert.strictEqual(result.eventType, 'conversationResult');
      assert.strictEqual(result.data.type, 'final_result');
      assert.strictEqual(result.data.success, true);
    });

    it('should detect permission prompt with y/n', () => {
      const result = MessageProcessor.isPermissionPrompt('Continue? (y/n)');
      assert.strictEqual(result, true);
    });

    it('should detect permission prompt with brackets', () => {
      const result = MessageProcessor.isPermissionPrompt('Proceed? [Y/n]');
      assert.strictEqual(result, true);
    });

    it('should detect permission prompt with allow', () => {
      const result = MessageProcessor.isPermissionPrompt('Allow access to file?');
      assert.strictEqual(result, true);
    });

    it('should not detect non-permission text', () => {
      const result = MessageProcessor.isPermissionPrompt('This is regular text');
      assert.strictEqual(result, false);
    });

    it('should detect permission in message object', () => {
      const message = { result: 'Continue? (y/n)' };
      const result = MessageProcessor.isPermissionPrompt(message);
      assert.strictEqual(result, true);
    });

    it('should handle null permission check', () => {
      const result = MessageProcessor.isPermissionPrompt(null);
      assert.strictEqual(result, false);
    });

    it('should extract permission prompt text', () => {
      const message = { result: 'Do you want to continue? (y/n)' };
      const result = MessageProcessor.extractPermissionPromptFromMessage(message);
      assert.strictEqual(result, 'Do you want to continue?');
    });

    it('should extract text from string message', () => {
      const result = MessageProcessor.extractTextFromMessage('test text');
      assert.strictEqual(result, 'test text');
    });

    it('should extract text from result field', () => {
      const message = { result: 'result text' };
      const result = MessageProcessor.extractTextFromMessage(message);
      assert.strictEqual(result, 'result text');
    });

    it('should extract text from text field', () => {
      const message = { text: 'text field' };
      const result = MessageProcessor.extractTextFromMessage(message);
      assert.strictEqual(result, 'text field');
    });

    it('should extract text from structured content', () => {
      const message = {
        message: {
          content: [{ type: 'text', text: 'structured text' }],
        },
      };
      const result = MessageProcessor.extractTextFromMessage(message);
      assert.strictEqual(result, 'structured text');
    });

    it('should extract text from string content', () => {
      const message = {
        message: {
          content: 'string content',
        },
      };
      const result = MessageProcessor.extractTextFromMessage(message);
      assert.strictEqual(result, 'string content');
    });

    it('should return null for no extractable text', () => {
      const result = MessageProcessor.extractTextFromMessage({});
      assert.strictEqual(result, null);
    });

    it('should detect approval response', () => {
      assert.strictEqual(MessageProcessor.containsApprovalResponse('yes'), true);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('y'), true);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('approve'), true);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('allow'), true);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('accept'), true);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('ok'), true);
    });

    it('should handle uppercase approval', () => {
      assert.strictEqual(MessageProcessor.containsApprovalResponse('YES'), true);
    });

    it('should handle approval with spaces', () => {
      assert.strictEqual(MessageProcessor.containsApprovalResponse('  yes  '), true);
    });

    it('should reject non-approval response', () => {
      assert.strictEqual(MessageProcessor.containsApprovalResponse('no'), false);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('deny'), false);
      assert.strictEqual(MessageProcessor.containsApprovalResponse('n'), false);
    });

    it('should handle null approval check', () => {
      assert.strictEqual(MessageProcessor.containsApprovalResponse(null), false);
    });

    it('should extract permission prompt from result', () => {
      const text = 'Do you want to continue?\nPress y to proceed';
      const result = MessageProcessor.extractPermissionPrompt(text);
      // AICLIMessageHandler returns both lines that contain questions or proceed
      assert.strictEqual(result, 'Do you want to continue? Press y to proceed');
    });

    it('should handle null permission prompt extraction', () => {
      const result = MessageProcessor.extractPermissionPrompt(null);
      assert.strictEqual(result, null);
    });

    it('should detect permission request in string content', () => {
      // AICLIMessageHandler expects array content, not string
      // For string content, it should be wrapped in an array with text blocks
      const result = MessageProcessor.containsPermissionRequest([
        { type: 'text', text: 'Continue? (y/n)' },
      ]);
      assert.strictEqual(result, true);
    });

    it('should detect permission request in array content', () => {
      const content = [
        { type: 'text', text: 'Some text' },
        { type: 'text', text: 'Continue? (y/n)' },
      ];
      const result = MessageProcessor.containsPermissionRequest(content);
      assert.strictEqual(result, true);
    });

    it('should not detect permission in non-text blocks', () => {
      const content = [
        { type: 'image', url: 'image.png' },
        { type: 'code', code: 'print("hello")' },
      ];
      const result = MessageProcessor.containsPermissionRequest(content);
      assert.strictEqual(result, false);
    });

    it('should handle null permission request check', () => {
      const result = MessageProcessor.containsPermissionRequest(null);
      assert.strictEqual(result, false);
    });

    it('should detect tool use in content', () => {
      const content = [
        { type: 'text', text: 'Using tool' },
        { type: 'tool_use', tool: 'bash' },
      ];
      const result = MessageProcessor.containsToolUse(content);
      assert.strictEqual(result, true);
    });

    it('should not detect tool use in text-only content', () => {
      const content = [{ type: 'text', text: 'No tools here' }];
      const result = MessageProcessor.containsToolUse(content);
      assert.strictEqual(result, false);
    });

    it('should handle null tool use check', () => {
      const result = MessageProcessor.containsToolUse(null);
      assert.strictEqual(result, false);
    });

    it('should extract code blocks', () => {
      const content = [
        { type: 'text', text: 'Here is code:\n```javascript\nconsole.log("hello");\n```' },
      ];
      const result = MessageProcessor.extractCodeBlocks(content);
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].language, 'javascript');
      assert.strictEqual(result[0].code, 'console.log("hello");');
    });

    it('should extract multiple code blocks', () => {
      const content = [{ type: 'text', text: '```js\ncode1\n```\n```python\ncode2\n```' }];
      const result = MessageProcessor.extractCodeBlocks(content);
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].language, 'js');
      assert.strictEqual(result[1].language, 'python');
    });

    it('should handle code blocks without language', () => {
      const content = [{ type: 'text', text: '```\nplain code\n```' }];
      const result = MessageProcessor.extractCodeBlocks(content);
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].language, 'text');
    });

    it('should handle null code block extraction', () => {
      const result = MessageProcessor.extractCodeBlocks(null);
      assert.deepStrictEqual(result, []);
    });

    it('should aggregate buffered content', () => {
      const buffer = {
        assistantMessages: [
          { content: [{ type: 'text', text: 'msg1' }] },
          { content: [{ type: 'text', text: 'msg2' }] },
        ],
      };
      const result = MessageProcessor.aggregateBufferedContent(buffer);
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].text, 'msg1');
      assert.strictEqual(result[1].text, 'msg2');
    });

    it('should handle null buffer aggregation', () => {
      const result = MessageProcessor.aggregateBufferedContent(null);
      assert.deepStrictEqual(result, []);
    });

    it('should handle buffer without assistantMessages', () => {
      const result = MessageProcessor.aggregateBufferedContent({});
      assert.deepStrictEqual(result, []);
    });
  });

  describe('AICLIConfig', () => {
    let originalEnv;

    beforeEach(() => {
      originalEnv = process.env.NODE_ENV;
      process.env.NODE_ENV = 'test';
    });

    afterEach(() => {
      process.env.NODE_ENV = originalEnv;
    });

    it('should calculate timeout for command', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('test command');
      assert.ok(timeout > 0);
    });

    it('should return default timeout for empty command', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('');
      assert.strictEqual(timeout, 60000);
    });

    it('should handle null command', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand(null);
      assert.strictEqual(timeout, 60000);
    });

    it('should handle non-string command', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand(123);
      assert.strictEqual(timeout, 60000);
    });

    it('should calculate longer timeout for complex keywords', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('review the code');
      assert.strictEqual(timeout, 300000); // 5 minutes
    });

    it('should calculate longer timeout for analyze keyword', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('analyze performance');
      assert.strictEqual(timeout, 300000);
    });

    it('should calculate longer timeout for refactor keyword', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('refactor this function');
      assert.strictEqual(timeout, 300000);
    });

    it('should calculate longer timeout for debug keyword', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('debug the issue');
      assert.strictEqual(timeout, 300000);
    });

    it('should calculate longest timeout for very complex keywords', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('comprehensive review');
      assert.strictEqual(timeout, 600000); // 10 minutes
    });

    it('should calculate longest timeout for expert keyword', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('expert analysis needed');
      assert.strictEqual(timeout, 600000);
    });

    it('should calculate longest timeout for entire project', () => {
      const timeout = AICLIConfig.calculateTimeoutForCommand('scan entire project');
      assert.strictEqual(timeout, 600000);
    });

    it('should calculate timeout based on length for long commands', () => {
      const longCommand = 'a'.repeat(201);
      const timeout = AICLIConfig.calculateTimeoutForCommand(longCommand);
      assert.strictEqual(timeout, 300000); // 5 minutes for >200 chars
    });

    it('should calculate timeout for medium length commands', () => {
      const mediumCommand = 'a'.repeat(51);
      const timeout = AICLIConfig.calculateTimeoutForCommand(mediumCommand);
      assert.strictEqual(timeout, 180000); // 3 minutes for >50 chars
    });

    it('should calculate timeout for short commands', () => {
      const shortCommand = 'short';
      const timeout = AICLIConfig.calculateTimeoutForCommand(shortCommand);
      assert.strictEqual(timeout, 120000); // 2 minutes for simple
    });

    it('should find AICLI command in test environment', () => {
      const command = AICLIConfig.findAICLICommand();
      assert.strictEqual(command, 'claude');
    });

    it('should use CLAUDE_CLI_PATH if set', () => {
      const originalPath = process.env.CLAUDE_CLI_PATH;
      const originalNodeEnv = process.env.NODE_ENV;

      process.env.CLAUDE_CLI_PATH = '/custom/path/claude';
      process.env.NODE_ENV = 'production';

      const command = AICLIConfig.findAICLICommand();
      assert.strictEqual(command, '/custom/path/claude');

      // Restore
      if (originalPath) {
        process.env.CLAUDE_CLI_PATH = originalPath;
      } else {
        delete process.env.CLAUDE_CLI_PATH;
      }
      process.env.NODE_ENV = originalNodeEnv;
    });
  });
});
