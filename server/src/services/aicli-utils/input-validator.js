/**
 * Input Validation and Sanitization Utilities
 * Handles validation of prompts, formats, directories, and security checks
 */

import { resolve } from 'path';
import { access, constants } from 'fs/promises';

export class InputValidator {
  static validateInput(prompt) {
    try {
      const processedPrompt = this.sanitizePrompt(prompt);
      return {
        isValid: true,
        processedPrompt,
      };
    } catch (error) {
      return {
        isValid: false,
        error: error.message,
      };
    }
  }

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

  static async validateWorkingDirectory(workingDir, safeRoot = null) {
    if (!workingDir || typeof workingDir !== 'string') {
      // If no working directory provided, use safe root or current directory
      return safeRoot || process.cwd();
    }

    // Resolve to absolute path
    const resolvedPath = resolve(workingDir);

    // Security check: prevent path traversal attacks
    const forbiddenPaths = ['/etc', '/usr', '/bin', '/sbin', '/sys', '/proc', '/root'];
    const isDangerous = forbiddenPaths.some(
      (forbidden) => resolvedPath === forbidden || resolvedPath.startsWith(`${forbidden}/`)
    );

    if (isDangerous) {
      throw new Error(`Access denied: Directory ${resolvedPath} is not allowed`);
    }

    // Check if directory exists and is accessible
    try {
      await access(resolvedPath, constants.R_OK);
      return resolvedPath;
    } catch (error) {
      throw new Error(`Directory not accessible: ${resolvedPath}`);
    }
  }

  static sanitizeSessionId(sessionId) {
    if (!sessionId || typeof sessionId !== 'string') {
      return null;
    }

    // Remove invalid characters and limit length
    const sanitized = sessionId.replace(/[^a-zA-Z0-9_-]/g, '').substring(0, 64);

    return sanitized.length > 0 ? sanitized : null;
  }

  static validateAICLIArgs(args) {
    if (!Array.isArray(args)) {
      throw new Error('Arguments must be an array');
    }

    // Validate each argument
    for (const arg of args) {
      if (typeof arg !== 'string') {
        throw new Error('All arguments must be strings');
      }

      // Security: prevent dangerous arguments
      const dangerousPattern = /[|&;<>`$(){}[\]]/;
      if (dangerousPattern.test(arg)) {
        throw new Error('Arguments cannot contain dangerous shell metacharacters');
      }
    }

    return args;
  }
}
