import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import { errorHandler } from '../../middleware/error.js';

describe('Error Middleware', () => {
  let mockReq, mockRes, mockNext;

  beforeEach(() => {
    mockReq = {
      headers: {},
      method: 'GET',
      path: '/test',
      query: {},
      body: {},
    };
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

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'Invalid JSON');
      assert.strictEqual(response.message, 'The request body contains invalid JSON');
      assert.ok(response.requestId); // Request ID should be present
    });

    it('should handle ENOTFOUND errors', () => {
      const error = new Error('Service not found');
      error.code = 'ENOTFOUND';

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 503);

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'Service unavailable');
      assert.strictEqual(response.message, 'Claude Code CLI not found or not accessible');
      assert.ok(response.requestId);
      assert.ok(response.suggestion);
    });

    it('should handle ECONNREFUSED errors', () => {
      const error = new Error('Connection refused');
      error.code = 'ECONNREFUSED';

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 503);

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'Connection refused');
      assert.strictEqual(response.message, 'Unable to connect to Claude Code service');
      assert.ok(response.requestId);
      assert.ok(response.suggestion);
    });

    it('should handle generic errors in development mode', () => {
      process.env.NODE_ENV = 'development';
      const error = new Error('Something went wrong');

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 500);

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'Internal server error');
      assert.strictEqual(response.message, 'Something went wrong');
      assert.ok(response.requestId);
    });

    it('should hide error details in production mode', () => {
      process.env.NODE_ENV = 'production';
      const error = new Error('Sensitive error details');

      errorHandler(error, mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 500);

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'Internal server error');
      assert.strictEqual(response.message, 'An unexpected error occurred. Please try again later.');
      assert.ok(response.requestId);
    });

    it('should include request ID in all error responses', () => {
      const error = new Error('Test error');
      errorHandler(error, mockReq, mockRes, mockNext);

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.ok(response.requestId, 'Response should include requestId');
      assert.strictEqual(typeof response.requestId, 'string');
    });
  });
});
