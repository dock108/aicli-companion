import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { ValidationUtils } from '../../utils/validation.js';

describe('ValidationUtils', () => {
  beforeEach(() => {
    // Mock console to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('sanitizePrompt', () => {
    it('should accept valid string prompts', () => {
      const prompt = 'This is a valid prompt';
      const result = ValidationUtils.sanitizePrompt(prompt);

      assert.strictEqual(result, prompt);
    });

    it('should remove null bytes from prompts', () => {
      const prompt = 'This\0has\0null\0bytes';
      const result = ValidationUtils.sanitizePrompt(prompt);

      assert.strictEqual(result, 'Thishasnullbytes');
    });

    it('should limit prompt length to 50000 characters', () => {
      const longPrompt = 'a'.repeat(60000);
      const result = ValidationUtils.sanitizePrompt(longPrompt);

      assert.strictEqual(result.length, 50000);
      assert.strictEqual(result, 'a'.repeat(50000));
    });

    it('should throw error for non-string prompts', () => {
      assert.throws(() => {
        ValidationUtils.sanitizePrompt(123);
      }, /Prompt must be a string/);

      assert.throws(() => {
        ValidationUtils.sanitizePrompt(null);
      }, /Prompt must be a string/);

      assert.throws(() => {
        ValidationUtils.sanitizePrompt(undefined);
      }, /Prompt must be a string/);

      assert.throws(() => {
        ValidationUtils.sanitizePrompt({});
      }, /Prompt must be a string/);
    });

    it('should throw error for empty prompts after sanitization', () => {
      assert.throws(() => {
        ValidationUtils.sanitizePrompt('');
      }, /Prompt cannot be empty/);

      assert.throws(() => {
        ValidationUtils.sanitizePrompt('\0\0\0');
      }, /Prompt cannot be empty/);
    });
  });

  describe('validateFormat', () => {
    it('should return default format for invalid input', () => {
      assert.strictEqual(ValidationUtils.validateFormat(null), 'json');
      assert.strictEqual(ValidationUtils.validateFormat(undefined), 'json');
      assert.strictEqual(ValidationUtils.validateFormat(123), 'json');
      assert.strictEqual(ValidationUtils.validateFormat({}), 'json');
    });

    it('should normalize valid formats to lowercase', () => {
      assert.strictEqual(ValidationUtils.validateFormat('JSON'), 'json');
      assert.strictEqual(ValidationUtils.validateFormat('TEXT'), 'text');
      assert.strictEqual(ValidationUtils.validateFormat('MARKDOWN'), 'markdown');
      assert.strictEqual(ValidationUtils.validateFormat(' json '), 'json');
    });

    it('should accept all valid formats', () => {
      assert.strictEqual(ValidationUtils.validateFormat('json'), 'json');
      assert.strictEqual(ValidationUtils.validateFormat('text'), 'text');
      assert.strictEqual(ValidationUtils.validateFormat('markdown'), 'markdown');
    });

    it('should throw error for invalid formats', () => {
      assert.throws(() => {
        ValidationUtils.validateFormat('xml');
      }, /Invalid format. Must be one of: json, text, markdown/);

      assert.throws(() => {
        ValidationUtils.validateFormat('html');
      }, /Invalid format. Must be one of: json, text, markdown/);

      assert.throws(() => {
        ValidationUtils.validateFormat('yaml');
      }, /Invalid format. Must be one of: json, text, markdown/);
    });
  });

  describe('validateWorkingDirectory', () => {
    it('should return current working directory for invalid input', async () => {
      const result = await ValidationUtils.validateWorkingDirectory(null);
      assert.strictEqual(result, process.cwd());

      const result2 = await ValidationUtils.validateWorkingDirectory(undefined);
      assert.strictEqual(result2, process.cwd());

      const result3 = await ValidationUtils.validateWorkingDirectory(123);
      assert.strictEqual(result3, process.cwd());
    });

    it('should reject forbidden paths', async () => {
      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('/etc/passwd'),
        /Access to system directories is not allowed|Working directory is not accessible/
      );

      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('/usr/bin/python'),
        /Access to system directories is not allowed|Working directory is not accessible/
      );

      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('/root/secret'),
        /Access to system directories is not allowed|Working directory is not accessible/
      );
    });

    it('should reject path traversal attempts', async () => {
      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('../../../etc/passwd'),
        /Access to system directories is not allowed|Path traversal is not allowed|Working directory is not accessible/
      );

      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('~/../../etc/shadow'),
        /Access to system directories is not allowed|Path traversal is not allowed|Working directory is not accessible/
      );

      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('/home/user/../../root'),
        /Access to system directories is not allowed|Path traversal is not allowed|Working directory is not accessible/
      );
    });

    it('should reject non-existent directories', async () => {
      await assert.rejects(
        () => ValidationUtils.validateWorkingDirectory('/non/existent/directory'),
        /Working directory is not accessible/
      );
    });

    it('should accept valid accessible directories', async () => {
      // Test with current directory
      const result = await ValidationUtils.validateWorkingDirectory(process.cwd());
      assert.ok(result.includes(process.cwd()));
    });
  });

  describe('sanitizeSessionId', () => {
    it('should return null for invalid input', () => {
      assert.strictEqual(ValidationUtils.sanitizeSessionId(null), null);
      assert.strictEqual(ValidationUtils.sanitizeSessionId(undefined), null);
      assert.strictEqual(ValidationUtils.sanitizeSessionId(123), null);
      assert.strictEqual(ValidationUtils.sanitizeSessionId({}), null);
    });

    it('should sanitize valid session IDs', () => {
      assert.strictEqual(ValidationUtils.sanitizeSessionId('abc123'), 'abc123');
      assert.strictEqual(ValidationUtils.sanitizeSessionId('session-id_123'), 'session-id_123');
      assert.strictEqual(ValidationUtils.sanitizeSessionId('test_session-456'), 'test_session-456');
    });

    it('should remove invalid characters', () => {
      assert.strictEqual(ValidationUtils.sanitizeSessionId('abc@123!'), 'abc123');
      assert.strictEqual(ValidationUtils.sanitizeSessionId('session.id*123'), 'sessionid123');
      assert.strictEqual(ValidationUtils.sanitizeSessionId('test session'), 'testsession');
    });

    it('should limit length to 64 characters', () => {
      const longId = 'a'.repeat(100);
      const result = ValidationUtils.sanitizeSessionId(longId);
      assert.strictEqual(result.length, 64);
    });

    it('should return null for empty results after sanitization', () => {
      assert.strictEqual(ValidationUtils.sanitizeSessionId(''), null);
      assert.strictEqual(ValidationUtils.sanitizeSessionId('!@#$%'), null);
      assert.strictEqual(ValidationUtils.sanitizeSessionId('    '), null);
    });
  });

  describe('sanitizeToken', () => {
    it('should return null for non-string input', () => {
      assert.strictEqual(ValidationUtils.sanitizeToken(null), null);
      assert.strictEqual(ValidationUtils.sanitizeToken(undefined), null);
      assert.strictEqual(ValidationUtils.sanitizeToken(123), null);
      assert.strictEqual(ValidationUtils.sanitizeToken({}), null);
    });

    it('should sanitize valid tokens', () => {
      assert.strictEqual(ValidationUtils.sanitizeToken('abc123'), 'abc123');
      assert.strictEqual(ValidationUtils.sanitizeToken('token_123-456'), 'token_123-456');
      assert.strictEqual(ValidationUtils.sanitizeToken('Base64Token=='), 'Base64Token==');
      assert.strictEqual(ValidationUtils.sanitizeToken('jwt+token/here'), 'jwt+token/here');
    });

    it('should remove control characters', () => {
      const tokenWithControl = 'token\x01with\x1fcontrol\x7fchars';
      const result = ValidationUtils.sanitizeToken(tokenWithControl);
      assert.strictEqual(result, 'tokenwithcontrolchars');
    });

    it('should limit length to 1024 characters', () => {
      const longToken = 'a'.repeat(2000);
      const result = ValidationUtils.sanitizeToken(longToken);
      assert.strictEqual(result.length, 1024);
    });

    it('should return null for tokens with invalid characters', () => {
      assert.strictEqual(ValidationUtils.sanitizeToken('token with spaces'), null);
      assert.strictEqual(ValidationUtils.sanitizeToken('token@domain.com'), null);
      assert.strictEqual(ValidationUtils.sanitizeToken('token#hashtag'), null);
      assert.strictEqual(ValidationUtils.sanitizeToken('token%encoded'), null);
    });

    it('should accept tokens with allowed special characters', () => {
      assert.strictEqual(ValidationUtils.sanitizeToken('token_123'), 'token_123');
      assert.strictEqual(ValidationUtils.sanitizeToken('token-456'), 'token-456');
      assert.strictEqual(ValidationUtils.sanitizeToken('token=equal'), 'token=equal');
      assert.strictEqual(ValidationUtils.sanitizeToken('token+plus'), 'token+plus');
      assert.strictEqual(ValidationUtils.sanitizeToken('token/slash'), 'token/slash');
    });
  });

  describe('validateRequestId', () => {
    it('should return null for invalid input', () => {
      assert.strictEqual(ValidationUtils.validateRequestId(null), null);
      assert.strictEqual(ValidationUtils.validateRequestId(undefined), null);
      assert.strictEqual(ValidationUtils.validateRequestId(123), null);
      assert.strictEqual(ValidationUtils.validateRequestId({}), null);
    });

    it('should sanitize valid request IDs', () => {
      assert.strictEqual(ValidationUtils.validateRequestId('request-123'), 'request-123');
      assert.strictEqual(ValidationUtils.validateRequestId('abc123'), 'abc123');
    });

    it('should limit length to 100 characters', () => {
      const longId = 'a'.repeat(200);
      const result = ValidationUtils.validateRequestId(longId);
      assert.strictEqual(result.length, 100);
    });

    it('should preserve all characters within length limit', () => {
      const specialId = 'request-123!@#$%^&*()';
      const result = ValidationUtils.validateRequestId(specialId);
      assert.strictEqual(result, specialId);
    });
  });
});
