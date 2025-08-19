import { resolve } from 'path';
import { access, constants } from 'fs/promises';
import { FORBIDDEN_PATHS } from '../constants/index.js';

/**
 * Unified validation service for AICLI
 * Combines validation logic from utils/validation.js and the original aicli-validation-service.js
 */
export class AICLIValidationService {
  /**
   * Sanitize and validate prompt input
   * @param {any} prompt - Prompt to validate
   * @returns {string} Sanitized prompt
   * @throws {Error} If prompt is invalid
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
   * Validate and normalize format parameter
   * @param {any} format - Format to validate
   * @returns {string} Validated format
   * @throws {Error} If format is invalid
   */
  static validateFormat(format) {
    const allowedFormats = ['json', 'text', 'markdown', 'stream-json'];

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
   * Validate that JSON is complete and not truncated
   */
  static isValidCompleteJSON(jsonString) {
    if (!jsonString || jsonString.length === 0) {
      console.log(`JSON validation: Empty or null input`);
      return false;
    }

    try {
      // First, try basic JSON parsing
      const parsed = JSON.parse(jsonString);

      // Additional checks for completeness
      const _trimmed = jsonString.trim();

      // For primitive JSON values, they are valid if they parse successfully
      // No additional validation needed for strings, numbers, booleans, null

      // Successful parsing and validation
      console.log(`JSON validation: Valid complete JSON (${parsed ? 'object' : 'value'})`);
      return true;
    } catch (error) {
      console.log(`JSON validation: Parse error - ${error.message}`);
      return false;
    }
  }

  /**
   * Parse stream-json format output into structured responses
   */
  static parseStreamJsonOutput(output) {
    const responses = [];
    const lines = output.split('\n');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (!line) continue;

      try {
        // Try parsing each line as JSON
        const parsed = JSON.parse(line);
        responses.push(parsed);
      } catch (parseError) {
        // Not JSON, check if it's a system message or content
        if (line.startsWith('System:') || line.startsWith('Error:')) {
          responses.push({
            type: 'system',
            message: line,
          });
        } else if (line.length > 0) {
          // Add as raw content if not empty
          responses.push({
            type: 'text',
            content: line,
          });
        }
      }
    }

    return responses;
  }

  /**
   * Extract final result from stream-json responses
   */
  static extractFinalResult(responses) {
    // Look for the last response with a result field
    for (let i = responses.length - 1; i >= 0; i--) {
      if (responses[i].result !== undefined) {
        return responses[i].result;
      }
    }

    // If no result field, concatenate content from content responses
    const contentResponses = responses.filter((r) => r.type === 'content' || r.content);
    if (contentResponses.length > 0) {
      return contentResponses.map((r) => r.content || r.result || '').join('');
    }

    // Fallback to the last response
    return responses[responses.length - 1];
  }

  /**
   * Extract session ID from stream-json responses
   */
  static extractSessionId(responses) {
    // Look for session_id in any response
    for (const response of responses) {
      if (response.session_id) {
        return response.session_id;
      }
    }
    return null;
  }

  /**
   * Parse JSON response into structured format
   */
  static parseJSONResponse(jsonString) {
    try {
      const parsed = JSON.parse(jsonString);

      // Handle direct JSON response
      if (parsed.result !== undefined) {
        return {
          success: true,
          result: parsed.result,
          session_id: parsed.session_id || null,
          metadata: {
            type: parsed.type || 'json',
            hasError: parsed.error !== undefined,
            timestamp: Date.now(),
          },
        };
      }

      // Handle structured Claude response
      if (parsed.content || parsed.text || parsed.message) {
        return {
          success: true,
          result: parsed.content || parsed.text || parsed.message,
          session_id: parsed.session_id || null,
          metadata: {
            type: parsed.type || 'structured',
            hasThinking: !!parsed.thinking,
            hasToolUse: !!(parsed.tool_calls || parsed.tools_used),
            timestamp: Date.now(),
          },
        };
      }

      // Handle error response
      if (parsed.error) {
        return {
          success: false,
          error: parsed.error,
          session_id: parsed.session_id || null,
          metadata: {
            type: 'error',
            timestamp: Date.now(),
          },
        };
      }

      // Fallback for unrecognized structure
      return {
        success: true,
        result: parsed,
        session_id: null,
        metadata: {
          type: 'unknown',
          timestamp: Date.now(),
        },
      };
    } catch (error) {
      return {
        success: false,
        error: `Failed to parse JSON: ${error.message}`,
        session_id: null,
        metadata: {
          type: 'parse_error',
          timestamp: Date.now(),
        },
      };
    }
  }

  /**
   * Validate path access
   * @param {string} inputPath - Path to validate
   * @returns {Promise<string>} Resolved and validated path
   * @throws {Error} If path is invalid or inaccessible
   */
  static async validatePath(inputPath) {
    if (!inputPath || typeof inputPath !== 'string') {
      throw new Error('Path must be a non-empty string');
    }

    // Resolve to absolute path
    const resolvedPath = resolve(inputPath);

    // Check against forbidden paths
    for (const forbidden of FORBIDDEN_PATHS) {
      if (resolvedPath.startsWith(forbidden)) {
        throw new Error(`Access to ${forbidden} is not allowed`);
      }
    }

    // Check if path exists and is accessible
    try {
      await access(resolvedPath, constants.R_OK);
    } catch {
      throw new Error(`Path ${resolvedPath} is not accessible`);
    }

    return resolvedPath;
  }

  /**
   * Validate session ID format
   * @param {string} sessionId - Session ID to validate
   * @returns {boolean} True if valid
   */
  static isValidSessionId(sessionId) {
    if (!sessionId || typeof sessionId !== 'string') {
      return false;
    }

    // Basic UUID v4 format validation
    const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    return uuidRegex.test(sessionId);
  }

  /**
   * Validate request ID format
   * @param {string} requestId - Request ID to validate
   * @returns {boolean} True if valid
   */
  static isValidRequestId(requestId) {
    if (!requestId || typeof requestId !== 'string') {
      return false;
    }

    // Request IDs should be alphanumeric with hyphens
    const requestIdRegex = /^[a-zA-Z0-9-]{8,64}$/;
    return requestIdRegex.test(requestId);
  }

  /**
   * Sanitize message content for safe display
   * @param {string} content - Content to sanitize
   * @returns {string} Sanitized content
   */
  static sanitizeContent(content) {
    if (!content || typeof content !== 'string') {
      return '';
    }

    // Remove potentially dangerous characters while preserving formatting
    return (
      content
        .replace(/\0/g, '') // Remove null bytes
        // eslint-disable-next-line no-control-regex
        .replace(/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/g, '') // Remove control characters except \t, \n, \r
        .substring(0, 100000)
    ); // Limit length to 100KB
  }

  /**
   * Validate message attachments
   * @param {Array} attachments - Attachments to validate
   * @returns {Array} Validated attachments
   * @throws {Error} If attachments are invalid
   */
  static validateAttachments(attachments) {
    if (!attachments) {
      return [];
    }

    if (!Array.isArray(attachments)) {
      throw new Error('Attachments must be an array');
    }

    const maxAttachments = 10;
    const maxAttachmentSize = 10 * 1024 * 1024; // 10MB

    if (attachments.length > maxAttachments) {
      throw new Error(`Maximum ${maxAttachments} attachments allowed`);
    }

    return attachments.map((attachment, index) => {
      if (!attachment || typeof attachment !== 'object') {
        throw new Error(`Attachment ${index} must be an object`);
      }

      if (!attachment.type || !['image', 'file', 'code'].includes(attachment.type)) {
        throw new Error(`Attachment ${index} has invalid type`);
      }

      if (attachment.size && attachment.size > maxAttachmentSize) {
        throw new Error(`Attachment ${index} exceeds maximum size of ${maxAttachmentSize} bytes`);
      }

      return {
        type: attachment.type,
        name: attachment.name || `attachment_${index}`,
        size: attachment.size || 0,
        content: attachment.content || '',
      };
    });
  }
}

// Export for backward compatibility
export const ValidationUtils = AICLIValidationService;
