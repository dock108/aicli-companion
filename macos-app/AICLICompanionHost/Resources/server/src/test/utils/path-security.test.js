import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { promises as fs } from 'fs';
import path from 'path';
import { tmpdir } from 'os';
import {
  validateSecurePath,
  validateProjectPath,
  createSafeProjectPath,
  PathSecurityError,
} from '../../utils/path-security.js';

describe('PathSecurity', () => {
  let testDir;
  let subDir;
  let testFile;
  let symlinkFile;

  beforeEach(async () => {
    // Create temporary test directory
    testDir = await fs.mkdtemp(path.join(tmpdir(), 'path-security-test-'));
    subDir = path.join(testDir, 'subdir');
    testFile = path.join(subDir, 'test.txt');
    symlinkFile = path.join(testDir, 'symlink.txt');

    await fs.mkdir(subDir);
    await fs.writeFile(testFile, 'test content');

    // Create a symlink that points outside the base directory
    const outsideFile = path.join(tmpdir(), 'outside.txt');
    await fs.writeFile(outsideFile, 'outside content');
    try {
      await fs.symlink(outsideFile, symlinkFile);
    } catch (error) {
      // Symlinks might not be supported on all systems
      symlinkFile = null;
    }
  });

  afterEach(async () => {
    // Cleanup test directory
    if (testDir) {
      await fs.rm(testDir, { recursive: true, force: true });
    }

    // Cleanup outside file
    try {
      await fs.unlink(path.join(tmpdir(), 'outside.txt'));
    } catch (error) {
      // Ignore cleanup errors
    }
  });

  describe('validateSecurePath', () => {
    it('should allow valid paths within base directory', async () => {
      const result = await validateSecurePath(testDir, 'subdir/test.txt', {
        mustExist: true,
      });
      // Compare normalized/resolved paths since different systems may have different symlink setups
      const expectedPath = await fs.realpath(testFile);
      assert.strictEqual(result, expectedPath);
    });

    it('should prevent directory traversal with ../', async () => {
      await assert.rejects(
        () => validateSecurePath(testDir, '../../../etc/passwd'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should prevent absolute paths that escape base directory', async () => {
      await assert.rejects(
        () => validateSecurePath(testDir, '/etc/passwd'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should handle URL encoded path traversal attempts', async () => {
      await assert.rejects(
        () => validateSecurePath(testDir, '..%2f..%2fetc%2fpasswd'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should detect null byte injection', async () => {
      await assert.rejects(
        () => validateSecurePath(testDir, 'file.txt\0.exe'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'NULL_BYTE_ATTACK');
          return true;
        }
      );
    });

    it('should reject non-existent paths when mustExist is true', async () => {
      await assert.rejects(
        () =>
          validateSecurePath(testDir, 'nonexistent.txt', {
            mustExist: true,
          }),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_NOT_FOUND');
          return true;
        }
      );
    });

    it('should allow non-existent paths when mustExist is false', async () => {
      const result = await validateSecurePath(testDir, 'nonexistent.txt', {
        mustExist: false,
      });
      assert.strictEqual(result, path.join(testDir, 'nonexistent.txt'));
    });

    it('should reject files when mustBeDirectory is true', async () => {
      await assert.rejects(
        () =>
          validateSecurePath(testDir, 'subdir/test.txt', {
            mustExist: true,
            mustBeDirectory: true,
          }),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'NOT_DIRECTORY');
          return true;
        }
      );
    });

    it('should allow directories when mustBeDirectory is true', async () => {
      const result = await validateSecurePath(testDir, 'subdir', {
        mustExist: true,
        mustBeDirectory: true,
      });
      // Compare normalized/resolved paths
      const expectedPath = await fs.realpath(subDir);
      assert.strictEqual(result, expectedPath);
    });

    it('should reject symlinks by default', async function () {
      if (!symlinkFile) {
        this.skip('Symlinks not supported on this system');
        return;
      }

      await assert.rejects(
        () =>
          validateSecurePath(testDir, 'symlink.txt', {
            mustExist: true,
            allowSymlinks: false,
          }),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert(error.code === 'SYMLINK_ATTACK' || error.code === 'REAL_PATH_OUTSIDE_BASE');
          return true;
        }
      );
    });

    it('should validate input parameters', async () => {
      // Invalid base path
      await assert.rejects(
        () => validateSecurePath('', 'file.txt'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_BASE_PATH');
          return true;
        }
      );

      // Invalid target path
      await assert.rejects(
        () => validateSecurePath(testDir, ''),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_TARGET_PATH');
          return true;
        }
      );

      // Null parameters
      await assert.rejects(
        () => validateSecurePath(null, 'file.txt'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_BASE_PATH');
          return true;
        }
      );
    });
  });

  describe('validateProjectPath', () => {
    it('should allow valid project names', () => {
      const result = validateProjectPath(testDir, 'my-project');
      assert.strictEqual(result, path.join(testDir, 'my-project'));
    });

    it('should reject project names with path traversal', () => {
      assert.throws(
        () => validateProjectPath(testDir, '../evil'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should reject project names with slashes', () => {
      assert.throws(
        () => validateProjectPath(testDir, 'project/evil'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should reject project names with null bytes', () => {
      assert.throws(
        () => validateProjectPath(testDir, 'project\0'),
        (error) => {
          assert(error instanceof PathSecurityError);
          assert(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should validate input parameters', () => {
      assert.throws(() => validateProjectPath('', 'project'), PathSecurityError);

      assert.throws(() => validateProjectPath(testDir, ''), PathSecurityError);

      assert.throws(() => validateProjectPath(null, 'project'), PathSecurityError);
    });
  });

  describe('createSafeProjectPath', () => {
    it('should create safe project paths', () => {
      const result = createSafeProjectPath(testDir, 'safe-project');
      assert.strictEqual(result, path.join(testDir, 'safe-project'));
    });

    it('should reject unsafe project names', () => {
      assert.throws(() => createSafeProjectPath(testDir, '../unsafe'), PathSecurityError);
    });
  });

  describe('PathSecurityError', () => {
    it('should create error with message and code', () => {
      const error = new PathSecurityError('Test message', 'TEST_CODE');
      assert.strictEqual(error.name, 'PathSecurityError');
      assert.strictEqual(error.message, 'Test message');
      assert.strictEqual(error.code, 'TEST_CODE');
    });

    it('should have default error code', () => {
      const error = new PathSecurityError('Test message');
      assert.strictEqual(error.code, 'PATH_SECURITY_ERROR');
    });
  });

  describe('edge cases and advanced attacks', () => {
    it('should handle directory traversal attempts', async () => {
      // Test genuinely malicious paths that escape the base directory
      await assert.rejects(
        () => validateSecurePath(testDir, 'subdir/../../../etc/passwd'),
        PathSecurityError
      );
    });

    it('should handle very long paths with traversal attempts', async () => {
      const longPath = `${'a'.repeat(1000)}/../../../etc/passwd`;
      await assert.rejects(() => validateSecurePath(testDir, longPath), PathSecurityError);
    });

    it('should safely handle normal file paths', async () => {
      // Test normal paths that should work fine
      const normalPaths = ['normal-file.txt', 'file.ext'];

      for (const normalPath of normalPaths) {
        const result = await validateSecurePath(testDir, normalPath, {
          mustExist: false,
        });
        // Should be a valid path
        assert.ok(result);
        assert(typeof result === 'string');
      }
    });
  });
});
