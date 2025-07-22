import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import {
  createErrorResponse,
  createWebSocketError,
  getHttpStatusForError,
  sendErrorResponse,
  AppError,
} from '../../utils/errors.js';
import { ERROR_CODES, HTTP_STATUS_CODES } from '../../constants/index.js';

describe('Error Utilities', () => {
  beforeEach(() => {
    // Mock console to reduce noise
    mock.method(console, 'log');
    mock.method(console, 'warn');
    mock.method(console, 'error');
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('createErrorResponse', () => {
    it('should create standardized error response with required fields', () => {
      const code = ERROR_CODES.INVALID_REQUEST;
      const message = 'Test error message';
      const details = { field: 'test' };

      const result = createErrorResponse(code, message, details);

      assert.strictEqual(result.error, code);
      assert.strictEqual(result.message, message);
      assert.deepStrictEqual(result.details, details);
      assert.ok(result.timestamp);
      assert.ok(new Date(result.timestamp).getTime() > 0);
    });

    it('should create error response with empty details by default', () => {
      const code = ERROR_CODES.AUTH_REQUIRED;
      const message = 'Authentication required';

      const result = createErrorResponse(code, message);

      assert.strictEqual(result.error, code);
      assert.strictEqual(result.message, message);
      assert.deepStrictEqual(result.details, {});
      assert.ok(result.timestamp);
    });

    it('should include valid ISO timestamp', () => {
      const result = createErrorResponse('TEST_CODE', 'Test message');

      // Verify timestamp is valid ISO string
      const timestamp = new Date(result.timestamp);
      assert.ok(!isNaN(timestamp.getTime()));
      assert.strictEqual(result.timestamp, timestamp.toISOString());
    });
  });

  describe('createWebSocketError', () => {
    it('should create standardized WebSocket error message', () => {
      const clientId = 'client-123';
      const requestId = 'request-456';
      const code = ERROR_CODES.INVALID_INPUT;
      const message = 'Invalid input provided';
      const details = { field: 'prompt' };

      const result = createWebSocketError(clientId, requestId, code, message, details);

      assert.strictEqual(result.type, 'error');
      assert.strictEqual(result.requestId, requestId);
      assert.ok(result.timestamp);
      assert.strictEqual(result.data.code, code);
      assert.strictEqual(result.data.message, message);
      assert.deepStrictEqual(result.data.details, details);
    });

    it('should handle null request ID', () => {
      const clientId = 'client-123';
      const requestId = null;
      const code = ERROR_CODES.SERVICE_UNAVAILABLE;
      const message = 'Service temporarily unavailable';

      const result = createWebSocketError(clientId, requestId, code, message);

      assert.strictEqual(result.type, 'error');
      assert.strictEqual(result.requestId, null);
      assert.strictEqual(result.data.code, code);
      assert.strictEqual(result.data.message, message);
      assert.deepStrictEqual(result.data.details, {});
    });

    it('should include valid ISO timestamp', () => {
      const result = createWebSocketError('client', 'request', 'CODE', 'Message');

      const timestamp = new Date(result.timestamp);
      assert.ok(!isNaN(timestamp.getTime()));
      assert.strictEqual(result.timestamp, timestamp.toISOString());
    });
  });

  describe('getHttpStatusForError', () => {
    it('should return UNAUTHORIZED for auth-related errors', () => {
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.AUTH_REQUIRED),
        HTTP_STATUS_CODES.UNAUTHORIZED
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.INVALID_TOKEN),
        HTTP_STATUS_CODES.UNAUTHORIZED
      );
    });

    it('should return BAD_REQUEST for input validation errors', () => {
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.INVALID_REQUEST),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.INVALID_JSON),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.INVALID_INPUT),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.DIRECTORY_NOT_FOUND),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.NOT_A_DIRECTORY),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.FORBIDDEN_PATH),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.INVALID_PATH),
        HTTP_STATUS_CODES.BAD_REQUEST
      );
    });

    it('should return SERVICE_UNAVAILABLE for service errors', () => {
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.SERVICE_UNAVAILABLE),
        HTTP_STATUS_CODES.SERVICE_UNAVAILABLE
      );
      assert.strictEqual(
        getHttpStatusForError(ERROR_CODES.CONNECTION_REFUSED),
        HTTP_STATUS_CODES.SERVICE_UNAVAILABLE
      );
    });

    it('should return INTERNAL_SERVER_ERROR for unknown errors', () => {
      assert.strictEqual(
        getHttpStatusForError('UNKNOWN_ERROR'),
        HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR
      );
      assert.strictEqual(
        getHttpStatusForError('CUSTOM_ERROR_CODE'),
        HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR
      );
      assert.strictEqual(getHttpStatusForError(null), HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR);
      assert.strictEqual(getHttpStatusForError(undefined), HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR);
    });
  });

  describe('sendErrorResponse', () => {
    let mockResponse;

    beforeEach(() => {
      mockResponse = {
        status: mock.fn(function () {
          return this;
        }),
        json: mock.fn(),
      };
    });

    it('should send error response with correct status and body', () => {
      const code = ERROR_CODES.INVALID_REQUEST;
      const message = 'Invalid request data';
      const details = { field: 'prompt' };

      sendErrorResponse(mockResponse, code, message, details);

      // Verify status was set correctly
      assert.strictEqual(mockResponse.status.mock.calls.length, 1);
      assert.strictEqual(
        mockResponse.status.mock.calls[0].arguments[0],
        HTTP_STATUS_CODES.BAD_REQUEST
      );

      // Verify JSON response was sent
      assert.strictEqual(mockResponse.json.mock.calls.length, 1);
      const responseBody = mockResponse.json.mock.calls[0].arguments[0];

      assert.strictEqual(responseBody.error, code);
      assert.strictEqual(responseBody.message, message);
      assert.deepStrictEqual(responseBody.details, details);
      assert.ok(responseBody.timestamp);
    });

    it('should handle errors without details', () => {
      const code = ERROR_CODES.AUTH_REQUIRED;
      const message = 'Authentication required';

      sendErrorResponse(mockResponse, code, message);

      assert.strictEqual(mockResponse.status.mock.calls.length, 1);
      assert.strictEqual(
        mockResponse.status.mock.calls[0].arguments[0],
        HTTP_STATUS_CODES.UNAUTHORIZED
      );

      const responseBody = mockResponse.json.mock.calls[0].arguments[0];
      assert.deepStrictEqual(responseBody.details, {});
    });

    it('should chain status and json calls correctly', () => {
      sendErrorResponse(mockResponse, ERROR_CODES.SERVICE_UNAVAILABLE, 'Service down');

      // Verify method chaining works
      assert.strictEqual(mockResponse.status.mock.calls.length, 1);
      assert.strictEqual(mockResponse.json.mock.calls.length, 1);
    });
  });

  describe('AppError', () => {
    it('should create error with code, message, and details', () => {
      const code = ERROR_CODES.INVALID_INPUT;
      const message = 'Invalid input provided';
      const details = { field: 'prompt', value: 'invalid' };

      const error = new AppError(code, message, details);

      assert.strictEqual(error.name, 'AppError');
      assert.strictEqual(error.code, code);
      assert.strictEqual(error.message, message);
      assert.deepStrictEqual(error.details, details);
      assert.strictEqual(error.statusCode, getHttpStatusForError(code));
      assert.ok(error instanceof Error);
    });

    it('should create error with empty details by default', () => {
      const code = ERROR_CODES.AUTH_REQUIRED;
      const message = 'Authentication required';

      const error = new AppError(code, message);

      assert.strictEqual(error.code, code);
      assert.strictEqual(error.message, message);
      assert.deepStrictEqual(error.details, {});
      assert.strictEqual(error.statusCode, HTTP_STATUS_CODES.UNAUTHORIZED);
    });

    it('should set correct status code based on error code', () => {
      const authError = new AppError(ERROR_CODES.INVALID_TOKEN, 'Invalid token');
      assert.strictEqual(authError.statusCode, HTTP_STATUS_CODES.UNAUTHORIZED);

      const validationError = new AppError(ERROR_CODES.INVALID_REQUEST, 'Bad request');
      assert.strictEqual(validationError.statusCode, HTTP_STATUS_CODES.BAD_REQUEST);

      const serviceError = new AppError(ERROR_CODES.SERVICE_UNAVAILABLE, 'Service down');
      assert.strictEqual(serviceError.statusCode, HTTP_STATUS_CODES.SERVICE_UNAVAILABLE);

      const unknownError = new AppError('UNKNOWN', 'Unknown error');
      assert.strictEqual(unknownError.statusCode, HTTP_STATUS_CODES.INTERNAL_SERVER_ERROR);
    });

    it('should be throwable and catchable', () => {
      const error = new AppError(ERROR_CODES.INVALID_INPUT, 'Test error');

      assert.throws(
        () => {
          throw error;
        },
        (err) => {
          return (
            err instanceof AppError &&
            err.code === ERROR_CODES.INVALID_INPUT &&
            err.message === 'Test error'
          );
        }
      );
    });

    it('should maintain Error prototype chain', () => {
      const error = new AppError('TEST', 'Test message');

      assert.ok(error instanceof Error);
      assert.ok(error instanceof AppError);
      assert.strictEqual(error.constructor, AppError);
    });
  });
});
