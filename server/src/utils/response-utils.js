/**
 * Standardized HTTP Response Utilities
 * Provides consistent success and error response formatting across all routes
 */

import { createErrorResponse, getHttpStatusForError } from './errors.js';

/**
 * Send a standardized success response
 * @param {Object} res - Express response object
 * @param {Object} data - Response data
 * @param {string} message - Optional success message
 * @param {number} statusCode - HTTP status code (default: 200)
 */
export function sendSuccessResponse(res, data = {}, message = null, statusCode = 200) {
  const response = {
    success: true,
    timestamp: new Date().toISOString(),
    ...data,
  };

  if (message) {
    response.message = message;
  }

  res.status(statusCode).json(response);
}

/**
 * Send a standardized error response using existing error utilities
 * @param {Object} res - Express response object
 * @param {string} errorCode - Error code from ERROR_CODES
 * @param {string} message - Error message
 * @param {Object} details - Additional error details
 */
export function sendErrorResponse(res, errorCode, message, details = {}) {
  const statusCode = getHttpStatusForError(errorCode);
  const errorResponse = {
    success: false,
    timestamp: new Date().toISOString(),
    ...createErrorResponse(errorCode, message, details),
  };

  res.status(statusCode).json(errorResponse);
}

/**
 * Send a validation error response
 * @param {Object} res - Express response object
 * @param {Array} validationErrors - Array of validation error objects
 */
export function sendValidationErrorResponse(res, validationErrors) {
  const response = {
    success: false,
    timestamp: new Date().toISOString(),
    error: 'VALIDATION_ERROR',
    message: 'Request validation failed',
    details: {
      validationErrors,
    },
  };

  res.status(400).json(response);
}

/**
 * Send a not found error response
 * @param {Object} res - Express response object
 * @param {string} resource - Resource that was not found
 */
export function sendNotFoundResponse(res, resource = 'Resource') {
  const response = {
    success: false,
    timestamp: new Date().toISOString(),
    error: 'NOT_FOUND',
    message: `${resource} not found`,
  };

  res.status(404).json(response);
}

/**
 * Send an unauthorized error response
 * @param {Object} res - Express response object
 * @param {string} message - Custom message (optional)
 */
export function sendUnauthorizedResponse(res, message = 'Authentication required') {
  const response = {
    success: false,
    timestamp: new Date().toISOString(),
    error: 'UNAUTHORIZED',
    message,
  };

  res.status(401).json(response);
}

/**
 * Send a forbidden error response
 * @param {Object} res - Express response object
 * @param {string} message - Custom message (optional)
 */
export function sendForbiddenResponse(res, message = 'Access denied') {
  const response = {
    success: false,
    timestamp: new Date().toISOString(),
    error: 'FORBIDDEN',
    message,
  };

  res.status(403).json(response);
}

/**
 * Send a created response (HTTP 201)
 * @param {Object} res - Express response object
 * @param {Object} data - Created resource data
 * @param {string} message - Optional success message
 */
export function sendCreatedResponse(res, data = {}, message = 'Resource created successfully') {
  sendSuccessResponse(res, data, message, 201);
}

/**
 * Send an accepted response (HTTP 202) for async operations
 * @param {Object} res - Express response object
 * @param {Object} data - Response data
 * @param {string} message - Optional message
 */
export function sendAcceptedResponse(res, data = {}, message = 'Request accepted for processing') {
  sendSuccessResponse(res, data, message, 202);
}

/**
 * Send a no content response (HTTP 204)
 * @param {Object} res - Express response object
 */
export function sendNoContentResponse(res) {
  res.status(204).end();
}

/**
 * Wrap async route handlers to provide consistent error handling
 * @param {Function} handler - Async route handler function
 * @returns {Function} Wrapped handler with error handling
 */
export function asyncHandler(handler) {
  return async (req, res, next) => {
    try {
      await handler(req, res, next);
    } catch (error) {
      // Log the error
      console.error('Route handler error:', error);

      // Send standardized error response
      if (error.code && error.statusCode) {
        // App error with predefined code
        sendErrorResponse(res, error.code, error.message, error.details || {});
      } else {
        // Generic server error
        sendErrorResponse(res, 'INTERNAL_SERVER_ERROR', 'An unexpected error occurred', {
          error: process.env.NODE_ENV === 'development' ? error.message : undefined,
        });
      }
    }
  };
}

/**
 * Create a paginated response
 * @param {Object} res - Express response object
 * @param {Array} items - Array of items
 * @param {number} page - Current page number
 * @param {number} limit - Items per page
 * @param {number} total - Total number of items
 * @param {Object} additionalData - Additional response data
 */
export function sendPaginatedResponse(res, items, page, limit, total, additionalData = {}) {
  const totalPages = Math.ceil(total / limit);
  const hasNextPage = page < totalPages;
  const hasPrevPage = page > 1;

  const response = {
    success: true,
    timestamp: new Date().toISOString(),
    data: items,
    pagination: {
      page,
      limit,
      total,
      totalPages,
      hasNextPage,
      hasPrevPage,
      nextPage: hasNextPage ? page + 1 : null,
      prevPage: hasPrevPage ? page - 1 : null,
    },
    ...additionalData,
  };

  res.json(response);
}
