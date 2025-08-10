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

    it('should throw error when no expected token provided', () => {
      assert.throws(() => authMiddleware(), /Expected token must be a non-empty string/);
      assert.throws(() => authMiddleware(''), /Expected token must be a non-empty string/);
      assert.throws(() => authMiddleware(null), /Expected token must be a non-empty string/);
      assert.throws(() => authMiddleware(123), /Expected token must be a non-empty string/);
    });

    it('should reject tokens with invalid characters', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.query.token = 'invalid-token-with-@-symbols!';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
    });

    it('should reject non-string tokens', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.query.token = 12345;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
    });

    it('should handle control characters in token', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.query.token = 'token\x00with\x1Fcontrol\x7Fchars';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
    });

    it('should handle very long tokens', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      const longToken = 'a'.repeat(2000); // Over 1024 character limit
      mockReq.query.token = longToken;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
    });

    it('should accept tokens with allowed special characters', () => {
      const specialToken = 'test-token_123=value+some/path';
      const middleware = authMiddleware(specialToken);
      mockReq.query.token = specialToken;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls.length, 0);
    });

    it('should prefer Authorization header over query parameter', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.headers.authorization = `Bearer ${TEST_TOKEN}`;
      mockReq.query.token = 'different-token';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls.length, 0);
    });

    it('should handle empty Authorization header', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.headers.authorization = '';

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
    });

    it('should handle undefined Authorization header', () => {
      const middleware = authMiddleware(TEST_TOKEN);
      mockReq.headers.authorization = undefined;

      middleware(mockReq, mockRes, mockNext);

      assert.strictEqual(mockNext.mock.calls.length, 0);
      assert.strictEqual(mockRes.status.mock.calls.length, 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
    });
  });
});
