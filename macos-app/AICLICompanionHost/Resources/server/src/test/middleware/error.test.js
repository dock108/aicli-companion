import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import { errorHandler } from '../../middleware/error.js';

describe('Error Middleware', () => {
  let mockReq, mockRes, mockNext;

  beforeEach(() => {
    mockReq = {};
    mockRes = {
      status: mock.fn(() => mockRes),
      json: mock.fn(() => mockRes),
    };
    mockNext = mock.fn();

    // Reset NODE_ENV for each test
    process.env.NODE_ENV = 'test';
  });

  describe('errorHandler', () => {
    it('should handle entity parse failed errors', () => {
      const error = new Error('Invalid JSON');
      error.type = 'entity.parse.failed';

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 400);
      assert.strictEqual(mockRes.json.mock.calls.length, 1);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Invalid JSON',
        message: 'The request body contains invalid JSON',
      });
    });

    it('should handle ENOTFOUND errors', () => {
      const error = new Error('Service not found');
      error.code = 'ENOTFOUND';

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 503);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Service unavailable',
        message: 'Claude Code CLI not found or not accessible',
      });
    });

    it('should handle ECONNREFUSED errors', () => {
      const error = new Error('Connection refused');
      error.code = 'ECONNREFUSED';

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 503);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Connection refused',
        message: 'Unable to connect to Claude Code service',
      });
    });

    it('should handle generic errors in development mode', () => {
      process.env.NODE_ENV = 'development';
      const error = new Error('Something went wrong');

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 500);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Internal server error',
        message: 'Something went wrong',
      });
    });

    it('should hide error details in production mode', () => {
      process.env.NODE_ENV = 'production';
      const error = new Error('Sensitive error details');

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 500);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Internal server error',
        message: 'An unexpected error occurred',
      });
    });

    it('should log errors to console', () => {
      const consoleErrorSpy = mock.fn();
      const originalConsoleError = console.error;
      console.error = consoleErrorSpy;

      const error = new Error('Test error');
      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(consoleErrorSpy.mock.calls.length, 1);
      assert.strictEqual(consoleErrorSpy.mock.calls[0].arguments[0], 'API Error:');
      assert.strictEqual(consoleErrorSpy.mock.calls[0].arguments[1], error);

      // Restore console.error
      console.error = originalConsoleError;
    });
  });
});
