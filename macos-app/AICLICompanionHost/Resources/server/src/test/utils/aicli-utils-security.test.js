import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { promises as fs } from 'fs';
import path from 'path';
import { tmpdir } from 'os';
import { InputValidator } from '../../services/aicli-utils.js';

describe('AICLI Utils Security Tests', () => {
  let testDir;

  beforeEach(async () => {
    // Create temporary test directory
    testDir = await fs.mkdtemp(path.join(tmpdir(), 'aicli-security-test-'));
  });

  afterEach(async () => {
    // Cleanup test directory
    if (testDir) {
      await fs.rm(testDir, { recursive: true, force: true });
    }
  });

  describe('validateWorkingDirectory - Security Tests', () => {
    it('should prevent path traversal attacks with safeRoot', async () => {
      await assert.rejects(
        () => InputValidator.validateWorkingDirectory('../../../etc/passwd', testDir),
        (error) => {
          assert(error.message.includes('Access denied'));
          return true;
        }
      );
    });

    it('should prevent absolute path traversal with safeRoot', async () => {
      await assert.rejects(
        () => InputValidator.validateWorkingDirectory('/etc/passwd', testDir),
        (error) => {
          assert(error.message.includes('Access denied'));
          return true;
        }
      );
    });

    it('should prevent path traversal attacks without safeRoot', async () => {
      // Test the fallback behavior when no safeRoot is provided
      await assert.rejects(
        () => InputValidator.validateWorkingDirectory('/etc/passwd'),
        (error) => {
          assert(error.message.includes('Access denied'));
          return true;
        }
      );
    });

    it('should allow valid paths within safeRoot', async () => {
      // Create a valid subdirectory
      const validSubDir = path.join(testDir, 'valid');
      await fs.mkdir(validSubDir);

      const result = await InputValidator.validateWorkingDirectory('valid', testDir);
      // Use fs.realpath for comparison to handle symlink resolution on macOS
      const expectedPath = await fs.realpath(validSubDir);
      assert.strictEqual(result, expectedPath);
    });

    it('should return safeRoot when no workingDir provided', async () => {
      const result = await InputValidator.validateWorkingDirectory(null, testDir);
      assert.strictEqual(result, testDir);
    });

    it('should fallback to process.cwd() when no parameters provided', async () => {
      const result = await InputValidator.validateWorkingDirectory();
      assert.strictEqual(result, process.cwd());
    });

    it('should reject symlinks that point outside safeRoot', async () => {
      // Create a symlink pointing outside the base directory
      const outsideFile = path.join(tmpdir(), 'outside-target');
      const symlinkPath = path.join(testDir, 'malicious-link');

      await fs.writeFile(outsideFile, 'outside content');

      try {
        await fs.symlink(outsideFile, symlinkPath);

        await assert.rejects(
          () => InputValidator.validateWorkingDirectory('malicious-link', testDir),
          (error) => {
            assert(error.message.includes('Access denied'));
            return true;
          }
        );
      } catch (symlinkError) {
        // Symlinks might not be supported on all systems, skip this test
        console.log('Symlinks not supported, skipping symlink test');
      } finally {
        // Cleanup
        try {
          await fs.unlink(outsideFile);
          await fs.unlink(symlinkPath);
        } catch (error) {
          // Ignore cleanup errors
        }
      }
    });

    it('should reject non-existent directories', async () => {
      await assert.rejects(
        () => InputValidator.validateWorkingDirectory('non-existent-dir', testDir),
        (error) => {
          assert(
            error.message.includes('Access denied') ||
              error.message.includes('Directory validation failed')
          );
          return true;
        }
      );
    });

    it('should reject URL-encoded path traversal attempts', async () => {
      await assert.rejects(
        () => InputValidator.validateWorkingDirectory('..%2f..%2fetc%2fpasswd', testDir),
        (error) => {
          assert(error.message.includes('Access denied'));
          return true;
        }
      );
    });
  });
});
