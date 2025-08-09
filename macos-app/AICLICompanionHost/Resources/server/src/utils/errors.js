import { ERROR_CODES, HTTP_STATUS_CODES } from '../constants/index.js';

/**
 * Standardized error response utilities
 */

/**
 * Create a standardized error response for HTTP endpoints
 * @param {string} code - Error code from ERROR_CODES
 * @param {string} message - Error message
 * @param {Object} details - Additional error details
 * @returns {Object} Standardized error response
 */
export function createErrorResponse(code, message, details = {}) {
  return {
    error: code,
    message,
    details,
    timestamp: new Date().toISOString(),
  };
}

/**
 * Create a standardized error response for WebSocket messages
 * @param {string} clientId - Client ID
 * @param {string|null} requestId - Request ID
 * @param {string} code - Error code from ERROR_CODES
 * @param {string} message - Error message
 * @param {Object} details - Additional error details
 * @returns {Object} Standardized WebSocket error message
 */
export function createWebSocketError(clientId, requestId, code, message, details = {}) {
  return {
    type: 'error',
    requestId,
    timestamp: new Date().toISOString(),
    data: {
      code,
      message,
      details,
    },
  };
}

/**
 * Get HTTP status code for error code
 * @param {string} errorCode - Error code from ERROR_CODES
 * @returns {number} HTTP status code
 */
export function getHttpStatusForError(errorCode) {
  switch (errorCode) {
    case ERROR_CODES.AUTH_REQUIRED:
    case ERROR_CODES.INVALID_TOKEN:
      return HTTP_STATUS_CODES.UNAUTHORIZED;

    case ERROR_CODES.INVALID_REQUEST:
    case ERROR_CODES.INVALID_JSON:
    case ERROR_CODES.INVALID_INPUT:
    case ERROR_CODES.DIRECTORY_NOT_FOUND:
    case ERROR_CODES.NOT_A_DIRECTORY:
    case ERROR_CODES.FORBIDDEN_PATH:
    case ERROR_CODES.INVALID_PATH:
      return HTTP_STATUS_CODES.BAD_REQUEST;

    case ERROR_CODES.SERVICE_UNAVAILABLE:
    case ERROR_CODES.CONNECTION_REFUSED:
      return HTTP_STATUS_CODES.SERVICE_UNAVAILABLE;

    default:
      return HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR;
  }
}

/**
 * Express middleware to send standardized error responses
 * @param {Object} res - Express response object
 * @param {string} code - Error code
 * @param {string} message - Error message
 * @param {Object} details - Additional details
 */
export function sendErrorResponse(res, code, message, details = {}) {
  const statusCode = getHttpStatusForError(code);
  const errorResponse = createErrorResponse(code, message, details);
  res.status(statusCode).json(errorResponse);
}

/**
 * Create error from known patterns
 */
export class AppError extends Error {
  constructor(code, message, details = {}) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.details = details;
    this.statusCode = getHttpStatusForError(code);
  }
}
