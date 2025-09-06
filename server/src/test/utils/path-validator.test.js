/**
 * Tests for path validation utility
 * Ensures protection against path traversal attacks
 */

import { test, describe } from 'node:test';
import assert from 'node:assert';
import { validateProjectPath, isValidFilename } from '../../utils/path-validator.js';
import path from 'path';
import os from 'os';

describe('Path Validator', () => {
  describe('validateProjectPath', () => {
    test('should accept valid paths within home directory', () => {
      const home = os.homedir();
      const validPath = path.join(home, 'projects', 'my-app');
      const result = validateProjectPath('projects/my-app');
      assert.ok(result);
      assert.ok(result.startsWith(home));
    });

    test('should reject path traversal attempts', () => {
      const maliciousInputs = [
        '../../../etc/passwd',
        '../../etc/shadow',
        '../.ssh/id_rsa',
        'projects/../../../etc/hosts',
        '/etc/passwd',
        '~/../../etc/passwd',
        'projects/../../sensitive',
      ];

      maliciousInputs.forEach((input) => {
        const result = validateProjectPath(input);
        assert.strictEqual(result, null, `Should reject malicious path: ${input}`);
      });
    });

    test('should reject null byte injection', () => {
      const maliciousInputs = [
        'projects/app\x00/etc/passwd',
        'projects/app%00/etc/passwd',
        '\x00etc/passwd',
      ];

      maliciousInputs.forEach((input) => {
        const result = validateProjectPath(input);
        assert.strictEqual(result, null, `Should reject null byte injection: ${input}`);
      });
    });

    test('should handle absolute paths correctly', () => {
      const home = os.homedir();
      const validAbsolute = path.join(home, 'projects');
      const result = validateProjectPath(validAbsolute);
      assert.ok(result);
      assert.strictEqual(result, validAbsolute);

      // Should reject absolute paths outside home
      const invalidAbsolute = '/etc/passwd';
      const result2 = validateProjectPath(invalidAbsolute);
      assert.strictEqual(result2, null);
    });

    test('should work with custom base path', () => {
      const customBase = path.join(os.tmpdir(), 'test-base');
      const validPath = 'project/subfolder';
      const result = validateProjectPath(validPath, customBase);
      assert.ok(result);
      assert.ok(result.startsWith(customBase));

      // Should reject traversal outside custom base
      const invalidPath = '../../../etc/passwd';
      const result2 = validateProjectPath(invalidPath, customBase);
      assert.strictEqual(result2, null);
    });

    test('should reject invalid inputs', () => {
      assert.strictEqual(validateProjectPath(null), null);
      assert.strictEqual(validateProjectPath(undefined), null);
      assert.strictEqual(validateProjectPath(''), null);
      assert.strictEqual(validateProjectPath(123), null);
      assert.strictEqual(validateProjectPath({}), null);
    });
  });

  describe('isValidFilename', () => {
    test('should accept valid filenames', () => {
      const validNames = [
        'template.json',
        'README.md',
        'package.json',
        '.gitignore',
        'my-file.txt',
        'file_name.js',
      ];

      validNames.forEach((name) => {
        assert.ok(isValidFilename(name), `Should accept: ${name}`);
      });
    });

    test('should reject filenames with path separators', () => {
      const invalidNames = [
        '../template.json',
        'templates/custom.json',
        'folder\\file.txt',
        '/etc/passwd',
        './file.txt',
      ];

      invalidNames.forEach((name) => {
        assert.strictEqual(isValidFilename(name), false, `Should reject: ${name}`);
      });
    });

    test('should reject special directory names', () => {
      assert.strictEqual(isValidFilename('.'), false);
      assert.strictEqual(isValidFilename('..'), false);
    });

    test('should reject filenames with null bytes', () => {
      assert.strictEqual(isValidFilename('file\x00.txt'), false);
    });

    test('should reject invalid inputs', () => {
      assert.strictEqual(isValidFilename(null), false);
      assert.strictEqual(isValidFilename(undefined), false);
      assert.strictEqual(isValidFilename(''), false);
      assert.strictEqual(isValidFilename(123), false);
    });
  });
});
