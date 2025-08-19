import { describe, it } from 'node:test';
import assert from 'node:assert';
import {
  AICLIValidationService,
  ValidationUtils,
} from '../../services/aicli-validation-service.js';

describe('AICLIValidationService', () => {
  describe('isValidCompleteJSON', () => {
    it('should return false for null or empty input', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(null), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(''), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(undefined), false);
    });

    it('should return true for valid complete JSON objects', () => {
      const validJson = '{"type": "result", "message": "Hello world"}';
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(validJson), true);
    });

    it('should return true for valid complete JSON arrays', () => {
      const validJson = '[{"type": "result"}, {"type": "status"}]';
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(validJson), true);
    });

    it('should return true for simple JSON values', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('"hello"'), true);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('42'), true);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('true'), true);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('null'), true);
    });

    it('should return false for incomplete JSON', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('{"type": "result"'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('[{"type": "result"}'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('"unterminated string'), false);
    });

    it('should return false for malformed JSON', () => {
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('{type: "result"}'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('{"type": result}'), false);
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON('invalid json'), false);
    });

    it('should handle JSON with whitespace', () => {
      const jsonWithWhitespace = '  \n  {"type": "result"}  \n  ';
      assert.strictEqual(AICLIValidationService.isValidCompleteJSON(jsonWithWhitespace), true);
    });
  });

  describe('parseStreamJsonOutput', () => {
    it('should parse empty input', () => {
      const result = AICLIValidationService.parseStreamJsonOutput('');
      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });

    it('should parse single JSON object', () => {
      const input = '{"type": "result", "message": "Hello"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);

      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'result');
      assert.strictEqual(result[0].message, 'Hello');
    });

    it('should parse multiple JSON objects on separate lines', () => {
      const input = '{"type": "status", "stage": "init"}\n{"type": "result", "message": "Done"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);

      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'status');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle empty lines', () => {
      const input = '{"type": "status"}\n\n{"type": "result"}\n';
      const result = AICLIValidationService.parseStreamJsonOutput(input);

      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'status');
      assert.strictEqual(result[1].type, 'result');
    });

    it('should handle lines with only whitespace', () => {
      const input = '{"type": "status"}\n   \n{"type": "result"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);

      assert.strictEqual(result.length, 2);
    });

    it('should fall back to object extraction for malformed lines', () => {
      const input = 'invalid json\n{"type": "result"}';
      const result = AICLIValidationService.parseStreamJsonOutput(input);

      // Should convert invalid line to text object and include valid JSON object
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'text');
      assert.strictEqual(result[0].content, 'invalid json');
      assert.strictEqual(result[1].type, 'result');
    });
  });

  describe('sanitizePrompt', () => {
    it('should sanitize valid string prompt', () => {
      const prompt = 'Hello Claude';
      const result = AICLIValidationService.sanitizePrompt(prompt);
      assert.strictEqual(result, 'Hello Claude');
    });

    it('should remove null bytes', () => {
      const prompt = 'Hello\0Claude';
      const result = AICLIValidationService.sanitizePrompt(prompt);
      assert.strictEqual(result, 'HelloClaude');
    });

    it('should limit length to 50000 characters', () => {
      const longPrompt = 'x'.repeat(60000);
      const result = AICLIValidationService.sanitizePrompt(longPrompt);
      assert.strictEqual(result.length, 50000);
    });

    it('should throw error for non-string prompt', () => {
      assert.throws(() => {
        AICLIValidationService.sanitizePrompt(123);
      }, /Prompt must be a string/);

      assert.throws(() => {
        AICLIValidationService.sanitizePrompt(null);
      }, /Prompt must be a string/);
    });

    it('should throw error for empty prompt after sanitization', () => {
      assert.throws(() => {
        AICLIValidationService.sanitizePrompt('\0\0\0');
      }, /Prompt cannot be empty/);
    });
  });

  describe('validateFormat', () => {
    it('should validate allowed formats', () => {
      assert.strictEqual(AICLIValidationService.validateFormat('json'), 'json');
      assert.strictEqual(AICLIValidationService.validateFormat('text'), 'text');
      assert.strictEqual(AICLIValidationService.validateFormat('markdown'), 'markdown');
      assert.strictEqual(AICLIValidationService.validateFormat('stream-json'), 'stream-json');
    });

    it('should normalize format case', () => {
      assert.strictEqual(AICLIValidationService.validateFormat('JSON'), 'json');
      assert.strictEqual(AICLIValidationService.validateFormat('Text'), 'text');
      assert.strictEqual(AICLIValidationService.validateFormat('MARKDOWN'), 'markdown');
    });

    it('should trim whitespace', () => {
      assert.strictEqual(AICLIValidationService.validateFormat('  json  '), 'json');
    });

    it('should return default for invalid input', () => {
      assert.strictEqual(AICLIValidationService.validateFormat(null), 'json');
      assert.strictEqual(AICLIValidationService.validateFormat(undefined), 'json');
      assert.strictEqual(AICLIValidationService.validateFormat(123), 'json');
    });

    it('should throw error for invalid format string', () => {
      assert.throws(() => {
        AICLIValidationService.validateFormat('invalid');
      }, /Invalid format/);
    });
  });

  describe('extractFinalResult', () => {
    it('should extract result from last response with result field', () => {
      const responses = [
        { type: 'status', message: 'Processing' },
        { type: 'content', content: 'Intermediate' },
        { type: 'result', result: 'Final result' },
      ];

      const result = AICLIValidationService.extractFinalResult(responses);
      assert.strictEqual(result, 'Final result');
    });

    it('should concatenate content responses if no result field', () => {
      const responses = [
        { type: 'content', content: 'First ' },
        { type: 'content', content: 'Second ' },
        { type: 'content', content: 'Third' },
      ];

      const result = AICLIValidationService.extractFinalResult(responses);
      assert.strictEqual(result, 'First Second Third');
    });

    it('should return last response as fallback', () => {
      const responses = [
        { type: 'status', message: 'First' },
        { type: 'status', message: 'Last' },
      ];

      const result = AICLIValidationService.extractFinalResult(responses);
      assert.deepStrictEqual(result, { type: 'status', message: 'Last' });
    });

    it('should handle empty responses array', () => {
      const responses = [];
      const result = AICLIValidationService.extractFinalResult(responses);
      assert.strictEqual(result, undefined);
    });
  });

  describe('extractSessionId', () => {
    it('should extract session ID from response', () => {
      const responses = [
        { type: 'status', message: 'Starting' },
        { type: 'result', result: 'Done', session_id: 'session-123' },
      ];

      const sessionId = AICLIValidationService.extractSessionId(responses);
      assert.strictEqual(sessionId, 'session-123');
    });

    it('should return first session ID found', () => {
      const responses = [
        { type: 'init', session_id: 'first-session' },
        { type: 'result', session_id: 'second-session' },
      ];

      const sessionId = AICLIValidationService.extractSessionId(responses);
      assert.strictEqual(sessionId, 'first-session');
    });

    it('should return null if no session ID', () => {
      const responses = [
        { type: 'status', message: 'No session' },
        { type: 'result', result: 'Done' },
      ];

      const sessionId = AICLIValidationService.extractSessionId(responses);
      assert.strictEqual(sessionId, null);
    });
  });

  describe('parseJSONResponse', () => {
    it('should parse direct JSON response with result', () => {
      const json = '{"result": "Success", "session_id": "sess-123"}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.success, true);
      assert.strictEqual(parsed.result, 'Success');
      assert.strictEqual(parsed.session_id, 'sess-123');
      assert.strictEqual(parsed.metadata.type, 'json');
    });

    it('should parse structured Claude response', () => {
      const json = '{"content": "Claude response", "type": "assistant", "thinking": true}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.success, true);
      assert.strictEqual(parsed.result, 'Claude response');
      assert.strictEqual(parsed.metadata.type, 'assistant');
      assert.strictEqual(parsed.metadata.hasThinking, true);
    });

    it('should handle text field', () => {
      const json = '{"text": "Text response"}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.success, true);
      assert.strictEqual(parsed.result, 'Text response');
    });

    it('should handle message field', () => {
      const json = '{"message": "Message response"}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.success, true);
      assert.strictEqual(parsed.result, 'Message response');
    });

    it('should handle error response', () => {
      const json = '{"error": "Something went wrong", "session_id": "err-sess"}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.success, false);
      assert.strictEqual(parsed.error, 'Something went wrong');
      assert.strictEqual(parsed.session_id, 'err-sess');
      assert.strictEqual(parsed.metadata.type, 'error');
    });

    it('should handle unrecognized structure', () => {
      const json = '{"unknown": "field", "data": "test"}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.success, true);
      assert.deepStrictEqual(parsed.result, { unknown: 'field', data: 'test' });
      assert.strictEqual(parsed.metadata.type, 'unknown');
    });

    it('should handle parse error', () => {
      const invalidJson = '{invalid json}';
      const parsed = AICLIValidationService.parseJSONResponse(invalidJson);

      assert.strictEqual(parsed.success, false);
      assert.ok(parsed.error.includes('Failed to parse JSON'));
      assert.strictEqual(parsed.metadata.type, 'parse_error');
    });

    it('should detect tool use', () => {
      const json = '{"content": "Using tools", "tool_calls": [{"name": "Read"}]}';
      const parsed = AICLIValidationService.parseJSONResponse(json);

      assert.strictEqual(parsed.metadata.hasToolUse, true);
    });
  });

  describe('validatePath', () => {
    it('should reject non-string paths', async () => {
      await assert.rejects(
        AICLIValidationService.validatePath(null),
        /Path must be a non-empty string/
      );

      await assert.rejects(
        AICLIValidationService.validatePath(123),
        /Path must be a non-empty string/
      );

      await assert.rejects(
        AICLIValidationService.validatePath(''),
        /Path must be a non-empty string/
      );
    });

    it('should reject forbidden paths', async () => {
      // Mock the forbidden paths check
      await assert.rejects(AICLIValidationService.validatePath('/etc/passwd'), /not allowed/);
    });

    it('should reject inaccessible paths', async () => {
      await assert.rejects(
        AICLIValidationService.validatePath('/nonexistent/path/that/does/not/exist'),
        /not accessible/
      );
    });
  });

  describe('isValidSessionId', () => {
    it('should validate UUID v4 format', () => {
      const validUuid = '123e4567-e89b-42d3-a456-426614174000';
      assert.strictEqual(AICLIValidationService.isValidSessionId(validUuid), true);
    });

    it('should reject invalid UUID format', () => {
      assert.strictEqual(AICLIValidationService.isValidSessionId('not-a-uuid'), false);
      assert.strictEqual(AICLIValidationService.isValidSessionId('123-456-789'), false);
    });

    it('should reject non-string input', () => {
      assert.strictEqual(AICLIValidationService.isValidSessionId(null), false);
      assert.strictEqual(AICLIValidationService.isValidSessionId(undefined), false);
      assert.strictEqual(AICLIValidationService.isValidSessionId(123), false);
      assert.strictEqual(AICLIValidationService.isValidSessionId(''), false);
    });
  });

  describe('isValidRequestId', () => {
    it('should validate alphanumeric with hyphens', () => {
      assert.strictEqual(AICLIValidationService.isValidRequestId('req-123-ABC'), true);
      assert.strictEqual(AICLIValidationService.isValidRequestId('12345678'), true);
      assert.strictEqual(AICLIValidationService.isValidRequestId('test-request-id'), true);
    });

    it('should reject invalid characters', () => {
      assert.strictEqual(AICLIValidationService.isValidRequestId('req_123'), false);
      assert.strictEqual(AICLIValidationService.isValidRequestId('req.123'), false);
      assert.strictEqual(AICLIValidationService.isValidRequestId('req@123'), false);
    });

    it('should reject too short or too long IDs', () => {
      assert.strictEqual(AICLIValidationService.isValidRequestId('short'), false);
      assert.strictEqual(AICLIValidationService.isValidRequestId('x'.repeat(65)), false);
    });

    it('should reject non-string input', () => {
      assert.strictEqual(AICLIValidationService.isValidRequestId(null), false);
      assert.strictEqual(AICLIValidationService.isValidRequestId(''), false);
      assert.strictEqual(AICLIValidationService.isValidRequestId(123), false);
    });
  });

  describe('sanitizeContent', () => {
    it('should sanitize content string', () => {
      const content = 'Normal content';
      const result = AICLIValidationService.sanitizeContent(content);
      assert.strictEqual(result, 'Normal content');
    });

    it('should remove null bytes', () => {
      const content = 'Content\0with\0null\0bytes';
      const result = AICLIValidationService.sanitizeContent(content);
      assert.strictEqual(result, 'Contentwithnullbytes');
    });

    it('should remove control characters except tab, newline, carriage return', () => {
      const content = 'Text\x00\x01\x02\t\n\r\x0B\x0C\x0E\x1F';
      const result = AICLIValidationService.sanitizeContent(content);
      assert.ok(result.includes('\t'));
      assert.ok(result.includes('\n'));
      assert.ok(result.includes('\r'));
      assert.ok(!result.includes('\x00'));
      assert.ok(!result.includes('\x0B'));
    });

    it('should limit content length', () => {
      const longContent = 'x'.repeat(200000);
      const result = AICLIValidationService.sanitizeContent(longContent);
      assert.strictEqual(result.length, 100000);
    });

    it('should handle non-string input', () => {
      assert.strictEqual(AICLIValidationService.sanitizeContent(null), '');
      assert.strictEqual(AICLIValidationService.sanitizeContent(undefined), '');
      assert.strictEqual(AICLIValidationService.sanitizeContent(123), '');
    });
  });

  describe('validateAttachments', () => {
    it('should validate valid attachments', () => {
      const attachments = [
        { type: 'image', name: 'photo.jpg', size: 1000 },
        { type: 'file', name: 'doc.pdf', size: 2000 },
      ];

      const result = AICLIValidationService.validateAttachments(attachments);
      assert.strictEqual(result.length, 2);
      assert.strictEqual(result[0].type, 'image');
      assert.strictEqual(result[1].type, 'file');
    });

    it('should return empty array for null/undefined', () => {
      assert.deepStrictEqual(AICLIValidationService.validateAttachments(null), []);
      assert.deepStrictEqual(AICLIValidationService.validateAttachments(undefined), []);
    });

    it('should throw for non-array input', () => {
      assert.throws(() => {
        AICLIValidationService.validateAttachments('not array');
      }, /Attachments must be an array/);
    });

    it('should enforce maximum attachments limit', () => {
      const attachments = Array(11).fill({ type: 'file', name: 'test.txt' });

      assert.throws(() => {
        AICLIValidationService.validateAttachments(attachments);
      }, /Maximum 10 attachments allowed/);
    });

    it('should validate attachment types', () => {
      const attachments = [{ type: 'invalid', name: 'test' }];

      assert.throws(() => {
        AICLIValidationService.validateAttachments(attachments);
      }, /invalid type/);
    });

    it('should validate attachment size', () => {
      const attachments = [
        {
          type: 'file',
          name: 'huge.bin',
          size: 11 * 1024 * 1024, // 11MB
        },
      ];

      assert.throws(() => {
        AICLIValidationService.validateAttachments(attachments);
      }, /exceeds maximum size/);
    });

    it('should throw for non-object attachments', () => {
      const attachments = ['string', 123, null];

      assert.throws(() => {
        AICLIValidationService.validateAttachments(attachments);
      }, /must be an object/);
    });

    it('should provide default values for missing fields', () => {
      const attachments = [{ type: 'file' }];

      const result = AICLIValidationService.validateAttachments(attachments);
      assert.strictEqual(result[0].name, 'attachment_0');
      assert.strictEqual(result[0].size, 0);
      assert.strictEqual(result[0].content, '');
    });

    it('should handle code type attachments', () => {
      const attachments = [
        {
          type: 'code',
          name: 'script.js',
          content: 'console.log("test");',
        },
      ];

      const result = AICLIValidationService.validateAttachments(attachments);
      assert.strictEqual(result[0].type, 'code');
      assert.strictEqual(result[0].content, 'console.log("test");');
    });
  });

  describe('ValidationUtils alias', () => {
    it('should export ValidationUtils as alias', () => {
      assert.strictEqual(ValidationUtils, AICLIValidationService);
    });
  });
});
