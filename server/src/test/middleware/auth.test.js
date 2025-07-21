import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import { authMiddleware } from '../../middleware/auth.js';

describe('Authentication Middleware', () => {
  let mockReq, mockRes, mockNext;
  const TEST_TOKEN = 'test-token-123';

  beforeEach(() => {
    mockReq = {
      query: {},
      headers: {},
      path: '/api/test',
    };
    mockRes = {
      status: mock.fn(() => mockRes),
      json: mock.fn(() => mockRes),
    };
    mockNext = mock.fn();
  });

  describe('authMiddleware', () => {
    it('should pass authentication with valid token in query', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.query.token = TEST_TOKEN;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls.length, 0);
    });

    it('should pass authentication with valid token in Authorization header', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.headers.authorization = `Bearer ${TEST_TOKEN}`;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls.length, 0);
    });

    it('should skip authentication for health check', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.path = '/health';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls.length, 0);
    });

    it('should reject request without token', () => {
      const middleware = authMiddleware(TEST_TOKEN);

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Authentication required',
        message: 'Please provide a valid auth token',
      });
    });

    it('should reject request with invalid token', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.query.token = 'invalid-token';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
      assert.deepStrictEqual(mockRes.json.mock.calls[0].arguments[0], {
        error: 'Invalid token',
        message: 'The provided auth token is not valid',
      });
    });

    it('should handle malformed Authorization header', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.headers.authorization = 'InvalidFormat';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
    });

    it('should extract Bearer token correctly', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.headers.authorization = `Bearer ${TEST_TOKEN}`;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 1);
    });
  });
});
