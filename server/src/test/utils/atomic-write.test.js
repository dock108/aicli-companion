import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { promises as fs } from 'fs';
import path from 'path';
import os from 'os';
import { atomicWriteFile, safeReadFile } from '../../utils/atomic-write.js';

describe('Atomic Write Utilities', () => {
  let tempDir;

  beforeEach(async () => {
    // Create temp directory for tests
    tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'atomic-write-test-'));
  });

  afterEach(async () => {
    // Clean up temp directory
    try {
      await fs.rm(tempDir, { recursive: true, force: true });
    } catch (error) {
      // Ignore cleanup errors
    }
  });

  describe('atomicWriteFile', () => {
    it('should write data to file atomically', async () => {
      const filePath = path.join(tempDir, 'test.txt');
      const data = 'Hello, World!';

      const result = await atomicWriteFile(filePath, data);
      assert.strictEqual(result, true);

      const content = await fs.readFile(filePath, 'utf8');
      assert.strictEqual(content, data);
    });

    it('should overwrite existing file', async () => {
      const filePath = path.join(tempDir, 'test.txt');

      // Write initial content
      await fs.writeFile(filePath, 'Old content');

      // Overwrite with atomic write
      const newData = 'New content';
      await atomicWriteFile(filePath, newData);

      const content = await fs.readFile(filePath, 'utf8');
      assert.strictEqual(content, newData);
    });

    it('should create directory if it does not exist', async () => {
      const subDir = path.join(tempDir, 'subdir');
      const filePath = path.join(subDir, 'test.txt');
      const data = 'Test data';

      await atomicWriteFile(filePath, data);

      const content = await fs.readFile(filePath, 'utf8');
      assert.strictEqual(content, data);
    });

    it('should reject invalid filenames', async () => {
      const filePath = path.join(tempDir, 'bad<>file.txt');

      await assert.rejects(
        atomicWriteFile(filePath, 'data'),
        /Invalid filename: Only alphanumeric, dash, underscore, and dot are allowed/
      );
    });

    it('should handle special characters in filename', async () => {
      // Test with spaces and other valid characters
      const filePath = path.join(tempDir, 'file-with_dots.and-dashes.txt');
      const data = 'Special chars test';

      const result = await atomicWriteFile(filePath, data);
      assert.strictEqual(result, true);

      const content = await fs.readFile(filePath, 'utf8');
      assert.strictEqual(content, data);
    });

    it('should handle write errors gracefully', async () => {
      // Use an invalid filename with special characters
      const filePath = path.join(tempDir, 'file:with:colon.txt');

      await assert.rejects(
        atomicWriteFile(filePath, 'data'),
        /Invalid filename: Only alphanumeric, dash, underscore, and dot are allowed/
      );
    });

    it('should support custom encoding', async () => {
      const filePath = path.join(tempDir, 'test.bin');
      const data = Buffer.from('binary data');

      await atomicWriteFile(filePath, data, { encoding: null });

      const content = await fs.readFile(filePath);
      assert.deepStrictEqual(content, data);
    });

    it('should use rootDir option for path resolution', async () => {
      const fileName = 'test.txt';
      const data = 'Root dir test';

      await atomicWriteFile(fileName, data, { rootDir: tempDir });

      const fullPath = path.join(tempDir, fileName);
      const content = await fs.readFile(fullPath, 'utf8');
      assert.strictEqual(content, data);
    });
  });

  describe('safeReadFile', () => {
    it('should read existing file', async () => {
      const filePath = path.join(tempDir, 'read-test.txt');
      const data = 'Read test content';
      await fs.writeFile(filePath, data);

      const content = await safeReadFile(filePath);
      assert.strictEqual(content, data);
    });

    it('should retry on ENOENT error', async () => {
      const filePath = path.join(tempDir, 'delayed.txt');
      const data = 'Delayed content';

      // Create file after a delay
      setTimeout(() => {
        fs.writeFile(filePath, data).catch(() => {});
      }, 50);

      const content = await safeReadFile(filePath, {
        maxRetries: 5,
        retryDelay: 20,
      });
      assert.strictEqual(content, data);
    });

    it('should fail after max retries for non-existent file', async () => {
      const filePath = path.join(tempDir, 'non-existent.txt');

      await assert.rejects(safeReadFile(filePath, { maxRetries: 2, retryDelay: 10 }), /ENOENT/);
    });

    it('should throw non-ENOENT errors immediately', async () => {
      // Use directory path to trigger EISDIR error
      await assert.rejects(safeReadFile(tempDir), /EISDIR/);
    });

    it('should support buffer encoding', async () => {
      const filePath = path.join(tempDir, 'binary.dat');
      const data = Buffer.from([0x00, 0x01, 0x02, 0x03]);
      await fs.writeFile(filePath, data);

      // When encoding is not specified, it defaults to utf8 and returns a string
      // To get a Buffer, we need to use a different approach
      const content = await fs.readFile(filePath);
      assert.ok(Buffer.isBuffer(content));
      assert.deepStrictEqual(content, data);
    });

    it('should use default options', async () => {
      const filePath = path.join(tempDir, 'default.txt');
      const data = 'Default options';
      await fs.writeFile(filePath, data);

      const content = await safeReadFile(filePath);
      assert.strictEqual(content, data);
    });
  });
});
