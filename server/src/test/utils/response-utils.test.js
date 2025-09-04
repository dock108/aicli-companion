import { describe, it, beforeEach, mock } from 'node:test';
import assert from 'node:assert';
import {
  sendSuccessResponse,
  sendErrorResponse,
  sendValidationErrorResponse,
  sendNotFoundResponse,
  sendUnauthorizedResponse,
  sendForbiddenResponse,
  sendCreatedResponse,
  sendAcceptedResponse,
  sendNoContentResponse,
  sendPaginatedResponse,
  asyncHandler,
} from '../../utils/response-utils.js';

describe('Response Utils', () => {
  let mockRes;

  beforeEach(() => {
    mockRes = {
      status: mock.fn(() => mockRes),
      json: mock.fn(() => mockRes),
      end: mock.fn(() => mockRes),
    };
  });

  describe('sendSuccessResponse', () => {
    it('should send success response with default status 200', () => {
      const data = { id: 1, name: 'test' };
      sendSuccessResponse(mockRes, data);

      assert.strictEqual(mockRes.status.mock.callCount(), 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 200);
      assert.strictEqual(mockRes.json.mock.callCount(), 1);
      
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, true);
      assert.strictEqual(response.id, 1);
      assert.strictEqual(response.name, 'test');
      assert(response.timestamp);
    });

    it('should send success response with custom status and message', () => {
      const data = { id: 1 };
      const message = 'Operation completed';
      sendSuccessResponse(mockRes, data, message, 201);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 201);
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.message, message);
    });
  });

  describe('sendErrorResponse', () => {
    it('should send error response with correct format', () => {
      sendErrorResponse(mockRes, 'INVALID_REQUEST', 'Invalid data');

      assert.strictEqual(mockRes.status.mock.callCount(), 1);
      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 400);
      
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'INVALID_REQUEST');
      assert.strictEqual(response.message, 'Invalid data');
      assert(response.timestamp);
    });
  });

  describe('sendNotFoundResponse', () => {
    it('should send 404 response', () => {
      sendNotFoundResponse(mockRes, 'User');

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 404);
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.message, 'User not found');
    });
  });

  describe('sendUnauthorizedResponse', () => {
    it('should send 401 response', () => {
      sendUnauthorizedResponse(mockRes);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 401);
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.strictEqual(response.error, 'UNAUTHORIZED');
    });
  });

  describe('sendForbiddenResponse', () => {
    it('should send 403 response', () => {
      sendForbiddenResponse(mockRes);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 403);
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.error, 'FORBIDDEN');
    });
  });

  describe('sendCreatedResponse', () => {
    it('should send 201 response', () => {
      const data = { id: 1 };
      sendCreatedResponse(mockRes, data);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 201);
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, true);
      assert.strictEqual(response.id, 1);
    });
  });

  describe('sendAcceptedResponse', () => {
    it('should send 202 response', () => {
      sendAcceptedResponse(mockRes);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 202);
    });
  });

  describe('sendNoContentResponse', () => {
    it('should send 204 response', () => {
      sendNoContentResponse(mockRes);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 204);
      assert.strictEqual(mockRes.end.mock.callCount(), 1);
    });
  });

  describe('sendPaginatedResponse', () => {
    it('should send paginated response', () => {
      const items = [1, 2, 3];
      sendPaginatedResponse(mockRes, items, 1, 10, 25);

      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, true);
      assert.deepStrictEqual(response.data, items);
      assert.strictEqual(response.pagination.page, 1);
      assert.strictEqual(response.pagination.totalPages, 3);
      assert.strictEqual(response.pagination.hasNextPage, true);
    });
  });

  describe('sendValidationErrorResponse', () => {
    it('should send validation error response', () => {
      const errors = [{ field: 'name', message: 'Required' }];
      sendValidationErrorResponse(mockRes, errors);

      assert.strictEqual(mockRes.status.mock.calls[0].arguments[0], 400);
      const response = mockRes.json.mock.calls[0].arguments[0];
      assert.strictEqual(response.success, false);
      assert.deepStrictEqual(response.details.validationErrors, errors);
    });
  });

  describe('asyncHandler', () => {
    it('should handle successful async operations', async () => {
      const handler = asyncHandler(async (req, res) => {
        res.json({ success: true });
      });

      const mockReq = {};
      const mockNext = mock.fn();

      await handler(mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.json.mock.callCount(), 1);
      assert.strictEqual(mockNext.mock.callCount(), 0);
    });

    it('should handle errors and send error response', async () => {
      const handler = asyncHandler(async () => {
        throw new Error('Test error');
      });

      const mockReq = {};
      const mockNext = mock.fn();

      await handler(mockReq, mockRes, mockNext);

      assert.strictEqual(mockRes.status.mock.callCount(), 1);
      assert.strictEqual(mockRes.json.mock.callCount(), 1);
    });
  });
});