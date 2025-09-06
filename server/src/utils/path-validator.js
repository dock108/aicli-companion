/**
 * Path validation and sanitization utilities
 * Prevents path traversal attacks
 */

import path from 'path';
import os from 'os';

/**
 * Validates and sanitizes a project path
 * @param {string} inputPath - The path to validate
 * @param {string} basePath - Optional base path to restrict to (defaults to home directory)
 * @returns {string|null} - Sanitized absolute path or null if invalid
 */
function validateProjectPath(inputPath, basePath = null) {
  if (!inputPath || typeof inputPath !== 'string') {
    return null;
  }

  // Check for null bytes (both literal and URL-encoded)
  if (inputPath.includes('\x00') || inputPath.includes('%00')) {
    return null;
  }

  // Remove any remaining control characters
  const cleanPath = inputPath.replace(/[\x00-\x1f\x7f]/g, '');

  // If cleaning changed the path, it was malicious
  if (cleanPath !== inputPath) {
    return null;
  }

  // If no base path provided, use home directory
  const allowedBase = basePath || os.homedir();

  // Resolve to absolute path
  const resolvedPath = path.resolve(allowedBase, cleanPath);

  // Ensure the resolved path is within the allowed base
  // This prevents path traversal attacks like ../../etc/passwd
  if (!resolvedPath.startsWith(allowedBase)) {
    return null;
  }

  // Additional checks for dangerous patterns
  const dangerous = [
    '..',
    '~',
    '\x00', // null byte
    '%00', // URL encoded null byte
  ];

  // Check each segment of the path
  const segments = resolvedPath.split(path.sep);
  for (const segment of segments) {
    if (dangerous.some((pattern) => segment.includes(pattern))) {
      return null;
    }
  }

  return resolvedPath;
}

/**
 * Validates a filename (no path components allowed)
 * @param {string} filename - The filename to validate
 * @returns {boolean} - True if valid filename
 */
function isValidFilename(filename) {
  if (!filename || typeof filename !== 'string') {
    return false;
  }

  // Should not contain path separators
  if (filename.includes('/') || filename.includes('\\')) {
    return false;
  }

  // Should not be special directories
  if (filename === '.' || filename === '..') {
    return false;
  }

  // Should not contain null bytes
  if (filename.includes('\x00')) {
    return false;
  }

  return true;
}

export { validateProjectPath, isValidFilename };
