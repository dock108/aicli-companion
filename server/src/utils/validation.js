import { resolve } from 'path';
import { access, constants } from 'fs/promises';
import { FORBIDDEN_PATHS } from '../constants/index.js';

/**
 * Input validation and sanitization utilities
 */
export class ValidationUtils {
  /**
   * Sanitize and validate prompt input
   * @param {any} prompt - Prompt to validate
   * @returns {string} Sanitized prompt
   * @throws {AppError} If prompt is invalid
   */
  static sanitizePrompt(prompt) {
    if (typeof prompt !== 'string') {
      throw new Error('Prompt must be a string');
    }

    // Remove null bytes and limit length
    const sanitized = prompt.replace(/\0/g, '').substring(0, 50000);

    if (sanitized.length === 0) {
      throw new Error('Prompt cannot be empty');
    }

    return sanitized;
  }

  /**
   * Validate message size and content
   * @param {string} message - Message to validate
   * @param {Object} options - Validation options
   * @returns {Object} Validation result with sanitized message and warnings
   */
  static validateMessageContent(message, options = {}) {
    const MAX_MESSAGE_SIZE = options.maxSize || parseInt(process.env.MAX_MESSAGE_SIZE || '100000');
    const WARN_MESSAGE_SIZE =
      options.warnSize || parseInt(process.env.WARN_MESSAGE_SIZE || '50000');

    const result = {
      valid: true,
      message,
      warnings: [],
      errors: [],
    };

    // Check if message is a string
    if (typeof message !== 'string') {
      result.valid = false;
      result.errors.push('Message must be a string');
      return result;
    }

    // Check message size in bytes (not just character count)
    const messageBytes = Buffer.byteLength(message, 'utf8');

    if (messageBytes > MAX_MESSAGE_SIZE) {
      result.valid = false;
      result.errors.push(
        `Message size (${messageBytes} bytes) exceeds maximum allowed size of ${MAX_MESSAGE_SIZE} bytes`
      );
      return result;
    }

    if (messageBytes > WARN_MESSAGE_SIZE) {
      result.warnings.push(
        `Large message detected: ${messageBytes} bytes. Consider breaking into smaller messages.`
      );
    }

    // Check for null bytes and control characters
    if (message.includes('\0')) {
      result.message = message.replace(/\0/g, '');
      result.warnings.push('Null bytes removed from message');
    }

    // Check for excessive control characters that might cause issues
    // eslint-disable-next-line no-control-regex
    const controlCharCount = (message.match(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g) || []).length;
    if (controlCharCount > 10) {
      result.warnings.push(
        `Message contains ${controlCharCount} control characters which may cause display issues`
      );
    }

    // Validate Unicode characters
    try {
      // Test if message can be properly encoded/decoded
      const encoded = Buffer.from(message, 'utf8');
      const decoded = encoded.toString('utf8');

      if (decoded !== message) {
        result.warnings.push('Message contains invalid UTF-8 sequences that were normalized');
        result.message = decoded;
      }
    } catch (error) {
      result.valid = false;
      result.errors.push(`Invalid character encoding: ${error.message}`);
      return result;
    }

    // Check for special characters that might break JSON encoding
    if (message.includes('\\') || message.includes('"')) {
      const unescapedBackslashes = (message.match(/(?<!\\)\\(?!["\\/bfnrt])/g) || []).length;
      const unescapedQuotes = (message.match(/(?<!\\)"/g) || []).length;

      if (unescapedBackslashes > 0 || unescapedQuotes > 0) {
        result.warnings.push(
          'Message contains unescaped special characters that may need escaping for JSON'
        );
      }
    }

    return result;
  }

  /**
   * Validate and normalize format parameter
   * @param {any} format - Format to validate
   * @returns {string} Validated format
   * @throws {AppError} If format is invalid
   */
  static validateFormat(format) {
    const allowedFormats = ['json', 'text', 'markdown'];

    if (!format || typeof format !== 'string') {
      return 'json'; // default
    }

    const cleanFormat = format.toLowerCase().trim();

    if (!allowedFormats.includes(cleanFormat)) {
      throw new Error(`Invalid format. Must be one of: ${allowedFormats.join(', ')}`);
    }

    return cleanFormat;
  }

  /**
   * Validate and sanitize working directory
   * @param {any} workingDir - Working directory to validate
   * @returns {Promise<string>} Validated working directory path
   * @throws {AppError} If directory is invalid or inaccessible
   */
  static async validateWorkingDirectory(workingDir) {
    if (!workingDir || typeof workingDir !== 'string') {
      return process.cwd();
    }

    // Resolve to absolute path
    const resolvedPath = resolve(workingDir);

    // Security checks for forbidden paths
    for (const forbidden of FORBIDDEN_PATHS) {
      if (resolvedPath.toLowerCase().includes(forbidden.toLowerCase())) {
        throw new Error('Access to system directories is not allowed');
      }
    }

    // Prevent path traversal attacks
    if (resolvedPath.includes('..') || resolvedPath.includes('~')) {
      throw new Error('Path traversal is not allowed');
    }

    try {
      // Check if directory exists and is accessible
      await access(resolvedPath, constants.F_OK | constants.R_OK);
      return resolvedPath;
    } catch (error) {
      throw new Error(`Working directory is not accessible: ${resolvedPath}`);
    }
  }

  /**
   * Sanitize and validate session ID
   * @param {any} sessionId - Session ID to validate
   * @returns {string|null} Sanitized session ID or null if invalid
   */
  static sanitizeSessionId(sessionId) {
    if (!sessionId || typeof sessionId !== 'string') {
      return null;
    }

    // Only allow alphanumeric characters, hyphens, and underscores
    const sanitized = sessionId.replace(/[^a-zA-Z0-9_-]/g, '').substring(0, 64);

    if (sanitized.length === 0) {
      return null;
    }

    return sanitized;
  }

  /**
   * Sanitize and validate authentication token
   * @param {any} token - Token to validate
   * @returns {string|null} Sanitized token or null if invalid
   */
  static sanitizeToken(token) {
    if (typeof token !== 'string') {
      return null;
    }

    // Remove any control characters and limit length
    // eslint-disable-next-line no-control-regex
    const sanitized = token.replace(/[\x00-\x1F\x7F]/g, '').substring(0, 1024);

    // Basic validation - must be alphanumeric with allowed special chars
    if (!/^[a-zA-Z0-9_\-=+/]+$/.test(sanitized)) {
      return null;
    }

    return sanitized;
  }

  /**
   * Validate request ID
   * @param {any} requestId - Request ID to validate
   * @returns {string|null} Validated request ID
   */
  static validateRequestId(requestId) {
    if (!requestId || typeof requestId !== 'string') {
      return null;
    }

    // Basic sanitization
    return requestId.substring(0, 100);
  }
}
