import { randomUUID } from 'crypto';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('ErrorHandler');

export function errorHandler(error, req, res, _next) {
  // Generate request ID if not present
  const requestId = req.headers['x-request-id'] || `ERR_${randomUUID()}`;

  // Log comprehensive error details
  logger.error('API Error occurred', {
    requestId,
    method: req.method,
    path: req.path,
    query: req.query,
    error: error.message,
    stack: error.stack,
    code: error.code,
    type: error.type,
    statusCode: error.statusCode || 500,
    headers: req.headers,
    body: process.env.NODE_ENV === 'development' ? req.body : undefined,
  });

  // Handle different types of errors with specific responses
  if (error.type === 'entity.parse.failed') {
    return res.status(400).json({
      success: false,
      error: 'Invalid JSON',
      message: 'The request body contains invalid JSON',
      requestId,
      details: process.env.NODE_ENV === 'development' ? error.message : undefined,
    });
  }

  if (error.type === 'entity.too.large') {
    return res.status(413).json({
      success: false,
      error: 'Payload too large',
      message: 'The request body exceeds the maximum allowed size',
      requestId,
      maxSize: process.env.MAX_REQUEST_SIZE || '50mb',
    });
  }

  if (error.code === 'ENOTFOUND') {
    return res.status(503).json({
      success: false,
      error: 'Service unavailable',
      message: 'Claude Code CLI not found or not accessible',
      requestId,
      suggestion: 'Please check if Claude Code CLI is installed and accessible',
    });
  }

  if (error.code === 'ECONNREFUSED') {
    return res.status(503).json({
      success: false,
      error: 'Connection refused',
      message: 'Unable to connect to Claude Code service',
      requestId,
      suggestion: 'Please check if the Claude Code service is running',
    });
  }

  if (error.code === 'ETIMEDOUT' || error.code === 'ESOCKETTIMEDOUT') {
    return res.status(504).json({
      success: false,
      error: 'Request timeout',
      message: 'The request took too long to process',
      requestId,
      suggestion: 'Please try again with a smaller request or check your connection',
    });
  }

  if (error.code === 'ENOMEM') {
    return res.status(507).json({
      success: false,
      error: 'Insufficient memory',
      message: 'The server ran out of memory processing your request',
      requestId,
      suggestion: 'Please try a smaller request or contact support',
    });
  }

  // Handle validation errors
  if (error.name === 'ValidationError' || error.message?.includes('validation')) {
    return res.status(400).json({
      success: false,
      error: 'Validation error',
      message: error.message || 'Request validation failed',
      requestId,
      details: error.details || error.errors,
    });
  }

  // Handle rate limiting
  if (error.statusCode === 429 || error.message?.includes('rate limit')) {
    return res.status(429).json({
      success: false,
      error: 'Rate limit exceeded',
      message: 'Too many requests. Please wait before trying again.',
      requestId,
      retryAfter: error.retryAfter || 60,
    });
  }

  // Default error response with more context
  const statusCode = error.statusCode || error.status || 500;
  const isServerError = statusCode >= 500;

  res.status(statusCode).json({
    success: false,
    error: isServerError ? 'Internal server error' : 'Request failed',
    message:
      process.env.NODE_ENV === 'development'
        ? error.message
        : isServerError
          ? 'An unexpected error occurred. Please try again later.'
          : error.message || 'Request could not be processed',
    requestId,
    timestamp: new Date().toISOString(),
    details:
      process.env.NODE_ENV === 'development'
        ? {
            stack: error.stack,
            code: error.code,
            type: error.type,
          }
        : undefined,
  });
}
