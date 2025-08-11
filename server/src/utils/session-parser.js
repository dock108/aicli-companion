/**
 * Session ID parsing utilities
 * Handles different session ID formats safely without hardcoded assumptions
 */

// Session ID format constants for better maintainability
export const SESSION_ID_FORMATS = {
  // Standard UUID format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  UUID: 'uuid',
  // Composite format: project_name_uuid or project_name_sessionId
  COMPOSITE: 'composite',
  // Simple format: just a session identifier
  SIMPLE: 'simple',
};

// Regex patterns for different session ID formats
const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/**
 * Session ID parser with format detection and validation
 */
export class SessionIdParser {
  /**
   * Parse session ID and extract components
   * @param {string} sessionId - Session ID to parse
   * @returns {Object} Parsed session information
   */
  static parseSessionId(sessionId) {
    if (!sessionId || typeof sessionId !== 'string') {
      return {
        isValid: false,
        format: null,
        sessionId: null,
        projectName: null,
        error: 'Invalid or missing session ID',
      };
    }

    const trimmedId = sessionId.trim();

    // Check for empty string after trimming
    if (!trimmedId) {
      return {
        isValid: false,
        format: null,
        sessionId: null,
        projectName: null,
        error: 'Invalid or missing session ID',
      };
    }

    // Try UUID format first (pure UUID without underscores)
    if (UUID_REGEX.test(trimmedId)) {
      return {
        isValid: true,
        format: SESSION_ID_FORMATS.UUID,
        sessionId: trimmedId,
        projectName: null,
        rawSessionId: trimmedId,
      };
    }

    // Check if it contains underscores (potential composite format)
    // But single underscore alone should be treated as simple
    if (trimmedId.includes('_') && trimmedId !== '_') {
      const sessionParts = trimmedId.split('_');

      // If we have at least 2 parts, treat as composite format
      // Project name is everything except the last part, session ID is the last part
      if (sessionParts.length >= 2) {
        const extractedSessionId = sessionParts[sessionParts.length - 1];
        const projectName = sessionParts.slice(0, -1).join('_');

        return {
          isValid: true,
          format: SESSION_ID_FORMATS.COMPOSITE,
          sessionId: extractedSessionId,
          projectName,
          rawSessionId: trimmedId,
        };
      }
    }

    // Fallback to simple format (no underscores or single underscore at start/end)
    return {
      isValid: true,
      format: SESSION_ID_FORMATS.SIMPLE,
      sessionId: trimmedId,
      projectName: null,
      rawSessionId: trimmedId,
    };
  }

  /**
   * Extract project name from session ID (backwards compatibility)
   * @param {string} sessionId - Session ID to parse
   * @returns {string} Project name or fallback
   */
  static extractProjectName(sessionId, fallback = 'Project') {
    const parsed = this.parseSessionId(sessionId);
    return parsed.projectName || fallback;
  }

  /**
   * Extract the actual session identifier (without project prefix)
   * @param {string} sessionId - Session ID to parse
   * @returns {string} Clean session ID
   */
  static extractSessionId(sessionId) {
    const parsed = this.parseSessionId(sessionId);
    return parsed.sessionId || sessionId;
  }

  /**
   * Validate session ID format
   * @param {string} sessionId - Session ID to validate
   * @returns {boolean} True if valid
   */
  static isValidSessionId(sessionId) {
    return this.parseSessionId(sessionId).isValid;
  }

  /**
   * Get the format type of a session ID
   * @param {string} sessionId - Session ID to analyze
   * @returns {string|null} Format type or null if invalid
   */
  static getFormat(sessionId) {
    return this.parseSessionId(sessionId).format;
  }

  /**
   * Create a composite session ID from project name and session ID
   * @param {string} projectName - Project name
   * @param {string} sessionId - Session ID
   * @returns {string} Composite session ID
   */
  static createCompositeId(projectName, sessionId) {
    if (!projectName || !sessionId) {
      throw new Error('Both projectName and sessionId are required');
    }

    // Sanitize project name (replace spaces and special chars with underscores)
    const sanitizedProject = projectName
      .replace(/[^a-zA-Z0-9-]/g, '_')
      .replace(/_+/g, '_')
      .replace(/^_|_$/g, '');

    return `${sanitizedProject}_${sessionId}`;
  }
}

// Convenience functions for common usage patterns
export const parseSessionId = (sessionId) => SessionIdParser.parseSessionId(sessionId);
export const extractProjectName = (sessionId, fallback = 'Project') =>
  SessionIdParser.extractProjectName(sessionId, fallback);
export const extractSessionId = (sessionId) => SessionIdParser.extractSessionId(sessionId);
export const isValidSessionId = (sessionId) => SessionIdParser.isValidSessionId(sessionId);
export const createCompositeSessionId = (projectName, sessionId) =>
  SessionIdParser.createCompositeId(projectName, sessionId);
