import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import path from 'path';
import { mkdir, writeFile, symlink, rm, realpath } from 'fs/promises';
import { existsSync } from 'fs';
import os from 'os';
import {
  PathValidator,
  PathSecurityError,
  validateSecurePath,
  validateProjectPath,
  createSafeProjectPath
} from '../../utils/path-security.js';

describe('PathSecurity', () => {
  let testDir;
  let baseDir;

  beforeEach(async () => {
    // Mock console methods
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');

    // Create a temporary test directory
    testDir = path.join(os.tmpdir(), `path-security-test-${Date.now()}`);
    baseDir = path.join(testDir, 'base');
    
    await mkdir(baseDir, { recursive: true });
    await mkdir(path.join(baseDir, 'subdirectory'), { recursive: true });
    await writeFile(path.join(baseDir, 'test.txt'), 'test content');
    await writeFile(path.join(baseDir, 'subdirectory', 'file.txt'), 'file content');
  });

  afterEach(async () => {
    mock.restoreAll();
    
    // Clean up test directory
    if (existsSync(testDir)) {
      await rm(testDir, { recursive: true, force: true });
    }
  });

  describe('PathSecurityError', () => {
    it('should create error with message and code', () => {
      const error = new PathSecurityError('Test error', 'TEST_CODE');
      assert.strictEqual(error.name, 'PathSecurityError');
      assert.strictEqual(error.message, 'Test error');
      assert.strictEqual(error.code, 'TEST_CODE');
    });

    it('should use default code if not provided', () => {
      const error = new PathSecurityError('Test error');
      assert.strictEqual(error.code, 'PATH_SECURITY_ERROR');
    });
  });

  describe('PathValidator.validatePath', () => {
    it('should validate a simple file path within base directory', async () => {
      const result = await PathValidator.validatePath(baseDir, 'test.txt');
      // Use realpath to handle symlink resolution on macOS (/var -> /private/var)
      const expectedPath = await realpath(path.join(baseDir, 'test.txt'));
      assert.strictEqual(result, expectedPath);
    });

    it('should validate a subdirectory path', async () => {
      const result = await PathValidator.validatePath(baseDir, 'subdirectory');
      const expectedPath = await realpath(path.join(baseDir, 'subdirectory'));
      assert.strictEqual(result, expectedPath);
    });

    it('should validate nested file path', async () => {
      const result = await PathValidator.validatePath(baseDir, 'subdirectory/file.txt');
      const expectedPath = await realpath(path.join(baseDir, 'subdirectory', 'file.txt'));
      assert.strictEqual(result, expectedPath);
    });

    it('should reject path traversal attempts with ../', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, '../outside'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should reject multiple path traversal attempts', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, '../../outside'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should reject path traversal in middle of path', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, 'subdirectory/../../outside'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should reject null byte injection', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, 'test\0.txt'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'NULL_BYTE_ATTACK');
          return true;
        }
      );
    });

    it('should reject null byte in base path', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath('base\0dir', 'test.txt'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'NULL_BYTE_ATTACK');
          return true;
        }
      );
    });

    it('should handle URL encoded path traversal', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, '..%2F..%2Foutside'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should validate with mustExist option', async () => {
      const result = await PathValidator.validatePath(baseDir, 'test.txt', { mustExist: true });
      const expectedPath = await realpath(path.join(baseDir, 'test.txt'));
      assert.strictEqual(result, expectedPath);
    });

    it('should reject non-existent path with mustExist option', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, 'nonexistent.txt', { mustExist: true }),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_NOT_FOUND');
          return true;
        }
      );
    });

    it('should validate directory with mustBeDirectory option', async () => {
      const result = await PathValidator.validatePath(baseDir, 'subdirectory', { 
        mustExist: true, 
        mustBeDirectory: true 
      });
      const expectedPath = await realpath(path.join(baseDir, 'subdirectory'));
      assert.strictEqual(result, expectedPath);
    });

    it('should reject file when mustBeDirectory is true', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, 'test.txt', { 
          mustExist: true, 
          mustBeDirectory: true 
        }),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'NOT_DIRECTORY');
          return true;
        }
      );
    });

    it('should detect symlink attacks when allowSymlinks is false', async () => {
      // Create a symlink pointing outside the base directory
      const outsideDir = path.join(testDir, 'outside');
      await mkdir(outsideDir, { recursive: true });
      await writeFile(path.join(outsideDir, 'secret.txt'), 'secret content');
      
      const symlinkPath = path.join(baseDir, 'link');
      await symlink(outsideDir, symlinkPath);

      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, 'link', { 
          allowSymlinks: false,
          mustExist: true 
        }),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'SYMLINK_ATTACK');
          return true;
        }
      );
    });

    it('should allow symlinks when allowSymlinks is true', async () => {
      // Create a symlink within the base directory
      const targetPath = path.join(baseDir, 'subdirectory');
      const symlinkPath = path.join(baseDir, 'link');
      await symlink(targetPath, symlinkPath);

      const result = await PathValidator.validatePath(baseDir, 'link', { 
        allowSymlinks: true,
        mustExist: true 
      });
      assert.ok(result);
    });

    it('should reject invalid base path', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(null, 'test.txt'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_BASE_PATH');
          return true;
        }
      );

      await assert.rejects(
        async () => await PathValidator.validatePath('', 'test.txt'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_BASE_PATH');
          return true;
        }
      );
    });

    it('should reject invalid target path', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, null),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_TARGET_PATH');
          return true;
        }
      );

      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, ''),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'INVALID_TARGET_PATH');
          return true;
        }
      );
    });

    it('should handle absolute paths in target', async () => {
      await assert.rejects(
        async () => await PathValidator.validatePath(baseDir, '/etc/passwd'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.strictEqual(error.code, 'PATH_TRAVERSAL_ATTEMPT');
          return true;
        }
      );
    });

    it('should allow non-existent paths when mustExist is false', async () => {
      const result = await PathValidator.validatePath(baseDir, 'new-file.txt', { mustExist: false });
      assert.strictEqual(result, path.join(baseDir, 'new-file.txt'));
    });
  });

  describe('PathValidator.validateProjectPath', () => {
    it('should validate simple project name', () => {
      const result = PathValidator.validateProjectPath(baseDir, 'my-project');
      assert.strictEqual(result, path.join(baseDir, 'my-project'));
    });

    it('should reject project name with slashes', () => {
      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, 'my/project'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should reject project name with backslashes', () => {
      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, 'my\\project'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should reject project name with ..', () => {
      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, '..project'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('invalid characters'));
          return true;
        }
      );

      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, 'project..'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should reject project name with null bytes', () => {
      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, 'project\0name'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('invalid characters'));
          return true;
        }
      );
    });

    it('should reject invalid base path', () => {
      assert.throws(
        () => PathValidator.validateProjectPath(null, 'project'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('Base path must be'));
          return true;
        }
      );

      assert.throws(
        () => PathValidator.validateProjectPath('', 'project'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('Base path must be'));
          return true;
        }
      );
    });

    it('should reject invalid project name', () => {
      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, null),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('Project name must be'));
          return true;
        }
      );

      assert.throws(
        () => PathValidator.validateProjectPath(baseDir, ''),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          assert.ok(error.message.includes('Project name must be'));
          return true;
        }
      );
    });
  });

  describe('PathValidator.createSafeProjectPath', () => {
    it('should create safe project path', () => {
      const result = PathValidator.createSafeProjectPath(baseDir, 'my-project');
      assert.strictEqual(result, path.join(baseDir, 'my-project'));
    });

    it('should reject invalid project names', () => {
      assert.throws(
        () => PathValidator.createSafeProjectPath(baseDir, '../evil'),
        (error) => {
          assert.ok(error instanceof PathSecurityError);
          return true;
        }
      );
    });
  });

  describe('Convenience functions', () => {
    it('validateSecurePath should work as async validator', async () => {
      const result = await validateSecurePath(baseDir, 'test.txt');
      const expectedPath = await realpath(path.join(baseDir, 'test.txt'));
      assert.strictEqual(result, expectedPath);
    });

    it('validateProjectPath should work as sync validator', () => {
      const result = validateProjectPath(baseDir, 'project');
      assert.strictEqual(result, path.join(baseDir, 'project'));
    });

    it('createSafeProjectPath should create safe paths', () => {
      const result = createSafeProjectPath(baseDir, 'project');
      assert.strictEqual(result, path.join(baseDir, 'project'));
    });
  });

  describe('Edge cases', () => {
    it('should handle dots in filenames', async () => {
      await writeFile(path.join(baseDir, 'file.with.dots.txt'), 'content');
      const result = await PathValidator.validatePath(baseDir, 'file.with.dots.txt', { mustExist: true });
      const expectedPath = await realpath(path.join(baseDir, 'file.with.dots.txt'));
      assert.strictEqual(result, expectedPath);
    });

    it('should handle spaces in filenames', async () => {
      const filename = 'file with spaces.txt';
      await writeFile(path.join(baseDir, filename), 'content');
      const result = await PathValidator.validatePath(baseDir, filename, { mustExist: true });
      const expectedPath = await realpath(path.join(baseDir, filename));
      assert.strictEqual(result, expectedPath);
    });

    it('should handle current directory reference', async () => {
      const result = await PathValidator.validatePath(baseDir, './test.txt');
      const expectedPath = await realpath(path.join(baseDir, 'test.txt'));
      assert.strictEqual(result, expectedPath);
    });

    it('should validate base directory itself', async () => {
      const result = await PathValidator.validatePath(baseDir, '.');
      const expectedPath = await realpath(baseDir);
      assert.strictEqual(result, expectedPath);
    });

    it('should handle relative path that stays within bounds', async () => {
      const result = await PathValidator.validatePath(baseDir, 'subdirectory/../test.txt');
      const expectedPath = await realpath(path.join(baseDir, 'test.txt'));
      assert.strictEqual(result, expectedPath);
    });
  });
});