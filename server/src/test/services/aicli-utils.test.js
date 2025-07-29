import { describe, it } from 'node:test';
import assert from 'node:assert';
import { InputValidator, MessageProcessor, AICLIConfig } from '../../services/aicli-utils.js';

describe('AICLI Utils Unit Tests', () => {
  describe('InputValidator', () => {
    describe('sanitizePrompt', () => {
      it('should sanitize valid string prompts', () => {
        const result = InputValidator.sanitizePrompt('Hello world');
        assert.strictEqual(result, 'Hello world');
      });

      it('should remove null bytes', () => {
        const result = InputValidator.sanitizePrompt('Hello\x00world');
        assert.strictEqual(result, 'Helloworld');
      });

      it('should limit length to 50000 characters', () => {
        const longPrompt = 'a'.repeat(60000);
        const result = InputValidator.sanitizePrompt(longPrompt);
        assert.strictEqual(result.length, 50000);
      });

      it('should throw error for non-string input', () => {
        assert.throws(() => InputValidator.sanitizePrompt(123), /Prompt must be a string/);
        assert.throws(() => InputValidator.sanitizePrompt(null), /Prompt must be a string/);
        assert.throws(() => InputValidator.sanitizePrompt(undefined), /Prompt must be a string/);
      });

      it('should throw error for empty string after sanitization', () => {
        assert.throws(() => InputValidator.sanitizePrompt(''), /Prompt cannot be empty/);
        assert.throws(() => InputValidator.sanitizePrompt('\x00\x00'), /Prompt cannot be empty/);
      });
    });

    describe('validateFormat', () => {
      it('should return default format for invalid input', () => {
        assert.strictEqual(InputValidator.validateFormat(null), 'json');
        assert.strictEqual(InputValidator.validateFormat(undefined), 'json');
        assert.strictEqual(InputValidator.validateFormat(123), 'json');
        assert.strictEqual(InputValidator.validateFormat(''), 'json');
      });

      it('should normalize valid formats to lowercase', () => {
        assert.strictEqual(InputValidator.validateFormat('JSON'), 'json');
        assert.strictEqual(InputValidator.validateFormat('TEXT'), 'text');
        assert.strictEqual(InputValidator.validateFormat('MARKDOWN'), 'markdown');
      });

      it('should trim whitespace', () => {
        assert.strictEqual(InputValidator.validateFormat('  json  '), 'json');
      });

      it('should accept all valid formats', () => {
        assert.strictEqual(InputValidator.validateFormat('json'), 'json');
        assert.strictEqual(InputValidator.validateFormat('text'), 'text');
        assert.strictEqual(InputValidator.validateFormat('markdown'), 'markdown');
      });

      it('should throw error for invalid formats', () => {
        assert.throws(() => InputValidator.validateFormat('xml'), /Invalid format/);
        assert.throws(() => InputValidator.validateFormat('yaml'), /Invalid format/);
      });
    });

    describe('validateWorkingDirectory', () => {
      it('should return default directory for invalid input', async () => {
        const result1 = await InputValidator.validateWorkingDirectory(null);
        assert.strictEqual(result1, process.cwd());

        const result2 = await InputValidator.validateWorkingDirectory('', '/safe/root');
        assert.strictEqual(result2, '/safe/root');
      });

      it('should reject forbidden paths', async () => {
        const forbiddenPaths = ['/etc', '/usr', '/bin', '/sbin', '/sys', '/proc', '/root'];

        for (const path of forbiddenPaths) {
          await assert.rejects(
            () => InputValidator.validateWorkingDirectory(path),
            /Access denied/
          );
        }
      });

      it('should reject path traversal attempts', async () => {
        await assert.rejects(
          () => InputValidator.validateWorkingDirectory('/etc/passwd'),
          /Access denied/
        );
      });

      it('should reject non-existent directories', async () => {
        await assert.rejects(
          () => InputValidator.validateWorkingDirectory('/nonexistent/directory'),
          /Directory not accessible/
        );
      });

      it('should accept valid accessible directories', async () => {
        // Use current working directory as a known accessible directory
        const result = await InputValidator.validateWorkingDirectory(process.cwd());
        assert.strictEqual(result, process.cwd());
      });
    });

    describe('sanitizeSessionId', () => {
      it('should return null for invalid input', () => {
        assert.strictEqual(InputValidator.sanitizeSessionId(null), null);
        assert.strictEqual(InputValidator.sanitizeSessionId(undefined), null);
        assert.strictEqual(InputValidator.sanitizeSessionId(123), null);
        assert.strictEqual(InputValidator.sanitizeSessionId(''), null);
      });

      it('should sanitize valid session IDs', () => {
        assert.strictEqual(InputValidator.sanitizeSessionId('session-123'), 'session-123');
        assert.strictEqual(InputValidator.sanitizeSessionId('test_session'), 'test_session');
      });

      it('should remove invalid characters', () => {
        assert.strictEqual(InputValidator.sanitizeSessionId('session@#$%'), 'session');
        assert.strictEqual(InputValidator.sanitizeSessionId('test session'), 'testsession');
      });

      it('should limit length to 64 characters', () => {
        const longId = 'a'.repeat(100);
        const result = InputValidator.sanitizeSessionId(longId);
        assert.strictEqual(result.length, 64);
      });

      it('should return null for empty results after sanitization', () => {
        assert.strictEqual(InputValidator.sanitizeSessionId('@#$%'), null);
      });
    });

    describe('validateAICLIArgs', () => {
      it('should throw error for non-array input', () => {
        assert.throws(
          () => InputValidator.validateAICLIArgs('string'),
          /Arguments must be an array/
        );
        assert.throws(() => InputValidator.validateAICLIArgs(null), /Arguments must be an array/);
      });

      it('should validate array of strings', () => {
        const args = ['--format', 'json', '--help'];
        const result = InputValidator.validateAICLIArgs(args);
        assert.deepStrictEqual(result, args);
      });

      it('should throw error for non-string elements', () => {
        assert.throws(
          () => InputValidator.validateAICLIArgs([123, 'string']),
          /All arguments must be strings/
        );
      });

      it('should reject shell operators', () => {
        assert.throws(
          () => InputValidator.validateAICLIArgs(['arg1', 'arg2 && rm -rf']),
          /dangerous shell metacharacters/
        );
        assert.throws(
          () => InputValidator.validateAICLIArgs(['arg1', 'arg2||dangerous']),
          /dangerous shell metacharacters/
        );
        assert.throws(
          () => InputValidator.validateAICLIArgs(['arg1;dangerous']),
          /dangerous shell metacharacters/
        );
        assert.throws(
          () => InputValidator.validateAICLIArgs(['arg1|pipe']),
          /dangerous shell metacharacters/
        );
      });
    });
  });

  describe('MessageProcessor', () => {
    describe('isValidCompleteJSON', () => {
      it('should return false for empty or null input', () => {
        assert.strictEqual(MessageProcessor.isValidCompleteJSON(''), false);
        assert.strictEqual(MessageProcessor.isValidCompleteJSON(null), false);
        assert.strictEqual(MessageProcessor.isValidCompleteJSON(undefined), false);
      });

      it('should validate complete JSON objects', () => {
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('{"key": "value"}'), true);
        assert.strictEqual(
          MessageProcessor.isValidCompleteJSON('{"nested": {"key": "value"}}'),
          true
        );
      });

      it('should validate complete JSON arrays', () => {
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('[1, 2, 3]'), true);
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('[{"key": "value"}]'), true);
      });

      it('should reject incomplete JSON', () => {
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('{"key": "value"'), false);
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('[1, 2, 3'), false);
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('{"key":'), false);
      });

      it('should reject malformed JSON', () => {
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('not json'), false);
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('{"key": }'), false);
      });

      it('should handle edge cases', () => {
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('true'), false); // Not object/array
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('123'), false); // Not object/array
        assert.strictEqual(MessageProcessor.isValidCompleteJSON('"string"'), false); // Not object/array
      });
    });

    describe('parseStreamJsonOutput', () => {
      it('should return empty array for invalid input', () => {
        assert.deepStrictEqual(MessageProcessor.parseStreamJsonOutput(''), []);
        assert.deepStrictEqual(MessageProcessor.parseStreamJsonOutput(null), []);
        assert.deepStrictEqual(MessageProcessor.parseStreamJsonOutput(undefined), []);
      });

      it('should parse single JSON object per line', () => {
        const input = '{"type": "message", "content": "hello"}';
        const result = MessageProcessor.parseStreamJsonOutput(input);
        assert.strictEqual(result.length, 1);
        assert.deepStrictEqual(result[0], { type: 'message', content: 'hello' });
      });

      it('should parse multiple JSON objects from multiple lines', () => {
        const input = '{"type": "message1"}\n{"type": "message2"}';
        const result = MessageProcessor.parseStreamJsonOutput(input);
        assert.strictEqual(result.length, 2);
        assert.strictEqual(result[0].type, 'message1');
        assert.strictEqual(result[1].type, 'message2');
      });

      it('should skip empty lines', () => {
        const input = '{"type": "message1"}\n\n{"type": "message2"}\n';
        const result = MessageProcessor.parseStreamJsonOutput(input);
        assert.strictEqual(result.length, 2);
      });

      it('should skip malformed JSON lines', () => {
        const input = '{"type": "message1"}\nmalformed\n{"type": "message2"}';
        const result = MessageProcessor.parseStreamJsonOutput(input);
        assert.strictEqual(result.length, 2);
      });
    });

    describe('extractCompleteObjectsFromLine', () => {
      it('should return empty array for invalid input', () => {
        assert.deepStrictEqual(MessageProcessor.extractCompleteObjectsFromLine(''), []);
        assert.deepStrictEqual(MessageProcessor.extractCompleteObjectsFromLine(null), []);
      });

      it('should extract single JSON object', () => {
        const result = MessageProcessor.extractCompleteObjectsFromLine('{"key": "value"}');
        assert.strictEqual(result.length, 1);
        assert.deepStrictEqual(result[0], { key: 'value' });
      });

      it('should extract multiple JSON objects from one line', () => {
        const result = MessageProcessor.extractCompleteObjectsFromLine('{"a": 1}{"b": 2}');
        assert.strictEqual(result.length, 2);
        assert.deepStrictEqual(result[0], { a: 1 });
        assert.deepStrictEqual(result[1], { b: 2 });
      });

      it('should handle mixed objects and arrays', () => {
        const result = MessageProcessor.extractCompleteObjectsFromLine('{"obj": true}[1, 2, 3]');
        assert.strictEqual(result.length, 2);
        assert.deepStrictEqual(result[0], { obj: true });
        assert.deepStrictEqual(result[1], [1, 2, 3]);
      });

      it('should skip incomplete JSON', () => {
        const result = MessageProcessor.extractCompleteObjectsFromLine(
          '{"complete": true}{"incomplete":'
        );
        assert.strictEqual(result.length, 1);
        assert.deepStrictEqual(result[0], { complete: true });
      });
    });

    describe('classifyAICLIMessage', () => {
      it('should handle string messages', () => {
        const result = MessageProcessor.classifyAICLIMessage('simple string');
        assert.strictEqual(result.eventType, 'streamData');
        assert.strictEqual(result.data, 'simple string');
      });

      it('should handle null/undefined messages', () => {
        const result1 = MessageProcessor.classifyAICLIMessage(null);
        assert.strictEqual(result1.eventType, 'streamData');
        assert.strictEqual(result1.data, null);

        const result2 = MessageProcessor.classifyAICLIMessage(undefined);
        assert.strictEqual(result2.eventType, 'streamData');
        assert.strictEqual(result2.data, undefined);
      });

      it('should classify system messages', () => {
        const message = { type: 'system', content: 'System message' };
        const result = MessageProcessor.classifyAICLIMessage(message);
        assert.strictEqual(result.eventType, 'streamData');
        assert.strictEqual(result.data.type, 'system');
      });

      it('should classify system init messages', () => {
        const message = {
          type: 'system',
          subtype: 'init',
          session_id: 'test-session',
          cwd: '/test/dir',
          tools: ['Read', 'Write'],
          mcp_servers: ['server1'],
          model: 'claude-3',
        };
        const result = MessageProcessor.classifyAICLIMessage(message);
        assert.strictEqual(result.eventType, 'systemInit');
        assert.strictEqual(result.data.type, 'system_init');
        assert.strictEqual(result.data.sessionId, 'test-session');
      });

      it('should classify assistant messages with array content', () => {
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

      it('should classify tool use messages', () => {
        const message = {
          type: 'tool_use',
          tool_name: 'Read',
          tool_input: { file_path: '/test.txt' },
          tool_id: 'tool-123',
        };
        const result = MessageProcessor.classifyAICLIMessage(message);
        assert.strictEqual(result.eventType, 'toolUse');
        assert.strictEqual(result.data.type, 'tool_use');
        assert.strictEqual(result.data.toolName, 'Read');
      });

      it('should classify tool result messages', () => {
        const message = {
          type: 'tool_result',
          result: 'File contents',
          tool_name: 'Read',
          tool_id: 'tool-123',
          is_error: false,
        };
        const result = MessageProcessor.classifyAICLIMessage(message);
        assert.strictEqual(result.eventType, 'toolResult');
        assert.strictEqual(result.data.type, 'tool_result');
        assert.strictEqual(result.data.success, true);
      });

      it('should classify result messages', () => {
        const message = {
          type: 'result',
          is_error: false,
          result: 'Success',
          session_id: 'test-session',
          duration_ms: 1000,
          total_cost_usd: 0.01,
          usage: { tokens: 200 },
        };
        const result = MessageProcessor.classifyAICLIMessage(message);
        assert.strictEqual(result.eventType, 'conversationResult');
        assert.strictEqual(result.data.type, 'final_result');
        assert.strictEqual(result.data.success, true);
      });
    });

    describe('isPermissionPrompt', () => {
      it('should detect permission prompts with y/n pattern', () => {
        assert.strictEqual(
          MessageProcessor.isPermissionPrompt('Do you want to continue? (y/n)'),
          true
        );
        assert.strictEqual(MessageProcessor.isPermissionPrompt('Proceed? [Y/n]'), true);
      });

      it('should detect permission prompts with allow pattern', () => {
        assert.strictEqual(MessageProcessor.isPermissionPrompt('Allow access to file?'), true);
      });

      it('should detect permission prompts with continue pattern', () => {
        assert.strictEqual(MessageProcessor.isPermissionPrompt('Do you want to continue?'), true);
        assert.strictEqual(MessageProcessor.isPermissionPrompt('Should I proceed?'), true);
      });

      it('should not detect non-permission messages', () => {
        assert.strictEqual(
          MessageProcessor.isPermissionPrompt('This is just a regular message'),
          false
        );
        assert.strictEqual(MessageProcessor.isPermissionPrompt('No questions here'), false);
      });

      it('should handle object messages', () => {
        const message = { result: 'Do you want to continue? (y/n)' };
        assert.strictEqual(MessageProcessor.isPermissionPrompt(message), true);
      });

      it('should handle null/undefined messages', () => {
        assert.strictEqual(MessageProcessor.isPermissionPrompt(null), false);
        assert.strictEqual(MessageProcessor.isPermissionPrompt(undefined), false);
      });
    });

    describe('extractTextFromMessage', () => {
      it('should extract text from string message', () => {
        assert.strictEqual(MessageProcessor.extractTextFromMessage('Hello world'), 'Hello world');
      });

      it('should extract text from result property', () => {
        const message = { result: 'Result text' };
        assert.strictEqual(MessageProcessor.extractTextFromMessage(message), 'Result text');
      });

      it('should extract text from text property', () => {
        const message = { text: 'Text property' };
        assert.strictEqual(MessageProcessor.extractTextFromMessage(message), 'Text property');
      });

      it('should extract text from message content blocks', () => {
        const message = {
          message: {
            content: [
              { type: 'text', text: 'Block text' },
              { type: 'tool_use', tool: 'Read' },
            ],
          },
        };
        assert.strictEqual(MessageProcessor.extractTextFromMessage(message), 'Block text');
      });

      it('should extract text from string content', () => {
        const message = { message: { content: 'String content' } };
        assert.strictEqual(MessageProcessor.extractTextFromMessage(message), 'String content');
      });

      it('should return null for unrecognized format', () => {
        assert.strictEqual(MessageProcessor.extractTextFromMessage({ unknown: 'format' }), null);
        assert.strictEqual(MessageProcessor.extractTextFromMessage(null), null);
      });
    });

    describe('containsApprovalResponse', () => {
      it('should detect positive responses', () => {
        const positiveResponses = [
          'y',
          'Y',
          'yes',
          'YES',
          'Yes',
          'approve',
          'allow',
          'accept',
          'ok',
        ];
        positiveResponses.forEach((response) => {
          assert.strictEqual(
            MessageProcessor.containsApprovalResponse(response),
            true,
            `Should approve: ${response}`
          );
        });
      });

      it('should not detect negative or unrelated responses', () => {
        const negativeResponses = ['n', 'no', 'deny', 'reject', 'maybe', 'later', 'unknown'];
        negativeResponses.forEach((response) => {
          assert.strictEqual(
            MessageProcessor.containsApprovalResponse(response),
            false,
            `Should not approve: ${response}`
          );
        });
      });

      it('should handle whitespace', () => {
        assert.strictEqual(MessageProcessor.containsApprovalResponse('  yes  '), true);
        assert.strictEqual(MessageProcessor.containsApprovalResponse('  no  '), false);
      });

      it('should handle null/undefined input', () => {
        assert.strictEqual(MessageProcessor.containsApprovalResponse(null), false);
        assert.strictEqual(MessageProcessor.containsApprovalResponse(undefined), false);
      });
    });

    describe('containsPermissionRequest', () => {
      it('should detect permission requests in strings', () => {
        assert.strictEqual(MessageProcessor.containsPermissionRequest('Allow access? (y/n)'), true);
        assert.strictEqual(MessageProcessor.containsPermissionRequest('Regular text'), false);
      });

      it('should detect permission requests in content arrays', () => {
        const content = [
          { type: 'text', text: 'Do you want to continue? (y/n)' },
          { type: 'tool_use', name: 'Read' },
        ];
        assert.strictEqual(MessageProcessor.containsPermissionRequest(content), true);
      });

      it('should handle empty/null content', () => {
        assert.strictEqual(MessageProcessor.containsPermissionRequest(null), false);
        assert.strictEqual(MessageProcessor.containsPermissionRequest([]), false);
      });
    });

    describe('containsToolUse', () => {
      it('should detect tool use in content arrays', () => {
        const content = [
          { type: 'text', text: 'Some text' },
          { type: 'tool_use', name: 'Read' },
        ];
        assert.strictEqual(MessageProcessor.containsToolUse(content), true);
      });

      it('should not detect tool use when not present', () => {
        const content = [
          { type: 'text', text: 'Some text' },
          { type: 'image', url: 'http://example.com' },
        ];
        assert.strictEqual(MessageProcessor.containsToolUse(content), false);
      });

      it('should handle empty/null content', () => {
        assert.strictEqual(MessageProcessor.containsToolUse(null), false);
        assert.strictEqual(MessageProcessor.containsToolUse([]), false);
      });
    });

    describe('extractCodeBlocks', () => {
      it('should extract code blocks from text content', () => {
        const content = [
          { type: 'text', text: 'Here is some code:\n```javascript\nconsole.log("hello");\n```' },
        ];
        const result = MessageProcessor.extractCodeBlocks(content);
        assert.strictEqual(result.length, 1);
        assert.strictEqual(result[0].language, 'javascript');
        assert.strictEqual(result[0].code, 'console.log("hello");');
      });

      it('should extract multiple code blocks', () => {
        const content = [
          { type: 'text', text: '```js\ncode1\n```\nsome text\n```python\ncode2\n```' },
        ];
        const result = MessageProcessor.extractCodeBlocks(content);
        assert.strictEqual(result.length, 2);
        assert.strictEqual(result[0].language, 'js');
        assert.strictEqual(result[1].language, 'python');
      });

      it('should handle content without code blocks', () => {
        const content = [{ type: 'text', text: 'Just regular text here' }];
        const result = MessageProcessor.extractCodeBlocks(content);
        assert.strictEqual(result.length, 0);
      });

      it('should handle empty/null content', () => {
        assert.deepStrictEqual(MessageProcessor.extractCodeBlocks(null), []);
        assert.deepStrictEqual(MessageProcessor.extractCodeBlocks([]), []);
      });
    });
  });

  describe('AICLIConfig', () => {
    describe('calculateTimeoutForCommand', () => {
      it('should return default timeout for invalid input', () => {
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(null), 60000);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(undefined), 60000);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(123), 60000);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(''), 60000);
      });

      it('should return basic timeout for simple commands', () => {
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand('hello'), 120000);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand('simple command'), 120000);
      });

      it('should return medium timeout for medium-length commands', () => {
        const mediumCommand = 'a'.repeat(100);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(mediumCommand), 180000);
      });

      it('should return long timeout for long commands', () => {
        const longCommand = 'a'.repeat(250);
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(longCommand), 300000);
      });

      it('should return complex timeout for commands with complex keywords', () => {
        const complexCommands = [
          'review this code',
          'analyze the performance',
          'audit security issues',
          'debug this problem',
          'test the feature',
          'document the API',
        ];

        complexCommands.forEach((command) => {
          assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(command), 300000);
        });
      });

      it('should return very complex timeout for commands with very complex keywords', () => {
        const veryComplexCommands = [
          'expert analysis of entire project',
          'comprehensive review',
          'thorough examination',
          'complete audit of whole codebase',
          'full analysis of all files',
        ];

        veryComplexCommands.forEach((command) => {
          assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(command), 600000);
        });
      });

      it('should prioritize very complex keywords over complex keywords', () => {
        const command = 'expert review this code comprehensively';
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(command), 600000);
      });

      it('should prioritize complex keywords over length', () => {
        const command = 'review';
        assert.strictEqual(AICLIConfig.calculateTimeoutForCommand(command), 300000);
      });
    });

    describe('findAICLICommand', () => {
      it('should be a function', () => {
        assert.strictEqual(typeof AICLIConfig.findAICLICommand, 'function');
      });

      it('should return a string path', () => {
        const result = AICLIConfig.findAICLICommand();
        assert.strictEqual(typeof result, 'string');
        assert.ok(result.length > 0);
      });

      it('should prefer CLAUDE_CLI_PATH environment variable', () => {
        const originalPath = process.env.CLAUDE_CLI_PATH;
        process.env.CLAUDE_CLI_PATH = '/custom/path/to/claude';

        try {
          const result = AICLIConfig.findAICLICommand();
          assert.strictEqual(result, '/custom/path/to/claude');
        } finally {
          if (originalPath) {
            process.env.CLAUDE_CLI_PATH = originalPath;
          } else {
            delete process.env.CLAUDE_CLI_PATH;
          }
        }
      });

      it('should fallback to claude when not found', () => {
        const originalPath = process.env.CLAUDE_CLI_PATH;
        delete process.env.CLAUDE_CLI_PATH;

        try {
          const result = AICLIConfig.findAICLICommand();
          // Should return either a found path or 'claude' as fallback
          assert.ok(result === 'claude' || result.includes('claude'));
        } finally {
          if (originalPath) {
            process.env.CLAUDE_CLI_PATH = originalPath;
          }
        }
      });
    });
  });
});
