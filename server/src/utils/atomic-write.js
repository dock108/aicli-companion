import { promises as fs } from 'fs';
import path from 'path';
import crypto from 'crypto';

/**
 * Atomically write data to a file
 * This implementation ensures data integrity by writing to a temporary file
 * and then atomically renaming it to the target file.
 */
export async function atomicWriteFile(filePath, data, options = {}) {
  const encoding = options.encoding || 'utf8';

  // Generate unique temp file name with random suffix to avoid collisions
  const tempFile = `${filePath}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;

  try {
    // Ensure directory exists
    const dir = path.dirname(filePath);
    await fs.mkdir(dir, { recursive: true });

    // Write to temp file with fsync to ensure data is flushed to disk
    const fd = await fs.open(tempFile, 'w');
    try {
      await fd.writeFile(data, encoding);
      await fd.sync(); // Force flush to disk
    } finally {
      await fd.close();
    }

    // Verify temp file exists and has content
    try {
      const stats = await fs.stat(tempFile);
      if (stats.size === 0) {
        throw new Error('Temporary file is empty');
      }
    } catch (statError) {
      throw new Error(`Temp file verification failed: ${statError.message}`);
    }

    // Atomic rename - this is atomic on POSIX systems
    try {
      await fs.rename(tempFile, filePath);
    } catch (renameError) {
      // On Windows, rename might fail if target exists, try unlink + rename
      if (renameError.code === 'EEXIST' || renameError.code === 'EPERM') {
        try {
          await fs.unlink(filePath);
          await fs.rename(tempFile, filePath);
        } catch (retryError) {
          throw new Error(`Rename failed after unlink: ${retryError.message}`);
        }
      } else {
        throw renameError;
      }
    }

    return true;
  } catch (error) {
    // Clean up temp file on error
    try {
      await fs.unlink(tempFile);
    } catch (cleanupError) {
      // Ignore cleanup errors
    }

    // Re-throw the original error
    throw error;
  }
}

/**
 * Read file with automatic retry on ENOENT
 */
export async function safeReadFile(filePath, options = {}) {
  const encoding = options.encoding || 'utf8';
  const maxRetries = options.maxRetries || 3;
  const retryDelay = options.retryDelay || 100;

  let lastError;

  for (let i = 0; i < maxRetries; i++) {
    try {
      return await fs.readFile(filePath, encoding);
    } catch (error) {
      lastError = error;

      if (error.code === 'ENOENT' && i < maxRetries - 1) {
        // File doesn't exist, wait and retry
        await new Promise((resolve) => setTimeout(resolve, retryDelay));
      } else {
        // Other error or final retry
        throw error;
      }
    }
  }

  throw lastError;
}
