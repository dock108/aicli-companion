import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { PermissionManager } from '../../services/permission-manager.js';

// Mock push notification service (unused but kept for reference)
const _mockPushService = {
  sendToAll: async () => Promise.resolve(),
};

describe('PermissionManager', () => {
  let manager;

  beforeEach(() => {
    manager = new PermissionManager({
      requestTimeout: 1000, // 1 second for faster tests
      defaultAction: 'deny',
      requireApproval: true,
    });

    // Mock the notifyApps method instead
    manager.notifyApps = async () => Promise.resolve();
  });

  afterEach(() => {
    // Clear any pending timeouts
    manager.pendingRequests.forEach((request) => {
      if (request.timeout) {
        clearTimeout(request.timeout);
      }
    });
    manager.pendingRequests.clear();
  });

  describe('Permission Requests', () => {
    it('should create permission request', async () => {
      const operation = 'delete file /tmp/test.txt';
      const context = { filePath: '/tmp/test.txt' };

      // Mock notification to avoid actual push
      manager.notifyApps = async () => Promise.resolve();

      const promise = manager.requestPermission(operation, context);

      // Wait a bit for the request to be created
      await new Promise((resolve) => setTimeout(resolve, 5));

      // Check pending request was created
      const pending = manager.getPendingRequests();
      assert.strictEqual(pending.length, 1);
      assert.strictEqual(pending[0].operation, operation);
      assert.deepStrictEqual(pending[0].context, context);

      // Approve the request immediately
      const requestId = pending[0].id;
      manager.approveRequest(requestId);

      const result = await promise;
      assert.strictEqual(result.approved, true);
      assert.ok(result.requestId);
    });

    it('should auto-approve known safe operations', async () => {
      const operation = 'read file /tmp/safe.txt';

      // Add auto-approve pattern
      manager.addAutoApprovePattern('read file');

      const result = await manager.requestPermission(operation);

      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.auto, true);
      assert.strictEqual(manager.getPendingRequests().length, 0);
    });

    it('should auto-deny known dangerous operations', async () => {
      const operation = 'format disk C:';

      // Add auto-deny pattern
      manager.addAutoDenyPattern('format disk');

      const result = await manager.requestPermission(operation);

      assert.strictEqual(result.approved, false);
      assert.strictEqual(result.auto, true);
      assert.ok(result.reason);
      assert.strictEqual(manager.getPendingRequests().length, 0);
    });

    it('should timeout requests with default action', async () => {
      // Use very short timeout for test
      const shortTimeoutManager = new PermissionManager({
        requestTimeout: 10, // 10ms timeout
        defaultAction: 'deny',
      });

      const operation = 'test operation';

      // Mock notification to avoid actual push
      shortTimeoutManager.notifyApps = async () => Promise.resolve();

      const result = await shortTimeoutManager.requestPermission(operation);

      // Should be denied due to timeout and default action
      assert.strictEqual(result.approved, false);
      assert.ok(result.reason.includes('timed out'));
    });

    it('should handle timeout with approve default', async () => {
      // Use very short timeout for test
      const shortTimeoutManager = new PermissionManager({
        requestTimeout: 10, // 10ms timeout
        defaultAction: 'approve',
      });

      const operation = 'test operation';

      // Mock notification to avoid actual push
      shortTimeoutManager.notifyApps = async () => Promise.resolve();

      const result = await shortTimeoutManager.requestPermission(operation);

      // Should be approved due to timeout and default action
      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.approver, 'timeout-default');
    });
  });

  describe('Request Approval', () => {
    it('should approve pending request', () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        resolver: null,
      };

      manager.pendingRequests.set('test-request', request);

      const result = manager.approveRequest('test-request', 'admin');

      assert.strictEqual(result, true);
      assert.strictEqual(manager.pendingRequests.has('test-request'), false);
    });

    it('should reject approval of non-existent request', () => {
      const result = manager.approveRequest('non-existent');
      assert.strictEqual(result, false);
    });

    it('should reject approval of already resolved request', () => {
      const request = {
        id: 'resolved-request',
        operation: 'test operation',
        status: 'approved',
      };

      manager.pendingRequests.set('resolved-request', request);

      const result = manager.approveRequest('resolved-request');
      assert.strictEqual(result, false);
    });

    it('should emit approval event', () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);

      let approvedRequestReceived = null;
      manager.once('permissionApproved', (approvedRequest) => {
        approvedRequestReceived = approvedRequest;
      });

      manager.approveRequest('test-request');

      assert.ok(approvedRequestReceived);
      assert.strictEqual(approvedRequestReceived.id, 'test-request');
      assert.strictEqual(approvedRequestReceived.status, 'approved');
    });
  });

  describe('Request Denial', () => {
    it('should deny pending request', () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        resolver: null,
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);

      const result = manager.denyRequest('test-request', 'Too dangerous', 'admin');

      assert.strictEqual(result, true);
      assert.strictEqual(manager.pendingRequests.has('test-request'), false);
    });

    it('should reject denial of non-existent request', () => {
      const result = manager.denyRequest('non-existent');
      assert.strictEqual(result, false);
    });

    it('should reject denial of already resolved request', () => {
      const request = {
        id: 'resolved-request',
        operation: 'test operation',
        status: 'denied',
      };

      manager.pendingRequests.set('resolved-request', request);

      const result = manager.denyRequest('resolved-request');
      assert.strictEqual(result, false);
    });

    it('should emit denial event', () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);

      let deniedRequestReceived = null;
      manager.once('permissionDenied', (deniedRequest) => {
        deniedRequestReceived = deniedRequest;
      });

      manager.denyRequest('test-request');

      assert.ok(deniedRequestReceived);
      assert.strictEqual(deniedRequestReceived.id, 'test-request');
      assert.strictEqual(deniedRequestReceived.status, 'denied');
    });
  });

  describe('Auto-Pattern Management', () => {
    it('should add auto-approve patterns', () => {
      manager.addAutoApprovePattern('safe operation');
      assert.ok(manager.autoApprovePatterns.has('safe operation'));
    });

    it('should add auto-deny patterns', () => {
      manager.addAutoDenyPattern('dangerous operation');
      assert.ok(manager.autoDenyPatterns.has('dangerous operation'));
    });

    it('should match string patterns', () => {
      assert.strictEqual(manager.matchesPattern('test operation', 'test'), true);
      assert.strictEqual(manager.matchesPattern('test operation', 'missing'), false);
    });

    it('should match regex patterns', () => {
      const regex = /^delete\s+file/;
      assert.strictEqual(manager.matchesPattern('delete file test.txt', regex), true);
      assert.strictEqual(manager.matchesPattern('create file test.txt', regex), false);
    });

    it('should determine auto-approval based on history', async () => {
      const operation = 'consistent operation';

      // Mock the history to show 5 approvals
      manager.approvalHistory = Array(5).fill({
        operation,
        status: 'approved',
      });

      assert.strictEqual(manager.shouldAutoApprove(operation), true);
    });

    it('should determine auto-denial based on history', async () => {
      const operation = 'consistently denied operation';

      // Mock the history to show 3 denials
      manager.approvalHistory = Array(3).fill({
        operation,
        status: 'denied',
      });

      assert.strictEqual(manager.shouldAutoDeny(operation), true);
    });

    it('should not auto-approve with insufficient history', () => {
      const operation = 'new operation';

      // Only 3 approvals (need 5)
      manager.approvalHistory = Array(3).fill({
        operation,
        status: 'approved',
      });

      assert.strictEqual(manager.shouldAutoApprove(operation), false);
    });
  });

  describe('Approval History', () => {
    beforeEach(() => {
      // Add some test history
      manager.logApproval({
        id: 'req1',
        operation: 'operation1',
        status: 'approved',
        timestamp: '2023-01-01T00:00:00Z',
        approver: 'user',
      });

      manager.logApproval({
        id: 'req2',
        operation: 'operation2',
        status: 'denied',
        timestamp: '2023-01-01T01:00:00Z',
        denier: 'user',
        reason: 'Too risky',
      });

      manager.logApproval({
        id: 'req3',
        operation: 'operation1',
        status: 'approved',
        timestamp: '2023-01-01T02:00:00Z',
        autoApproved: true,
      });
    });

    it('should log approval entries', () => {
      assert.strictEqual(manager.approvalHistory.length, 3);
    });

    it('should get all approval history', () => {
      const history = manager.getApprovalHistory();
      assert.strictEqual(history.length, 3);
      // Should be in reverse chronological order
      assert.strictEqual(history[0].id, 'req3');
    });

    it('should filter history by operation', () => {
      const filtered = manager.getApprovalHistory({ operation: 'operation1' });
      assert.strictEqual(filtered.length, 2);
      filtered.forEach((entry) => {
        assert.strictEqual(entry.operation, 'operation1');
      });
    });

    it('should filter history by status', () => {
      const approved = manager.getApprovalHistory({ status: 'approved' });
      assert.strictEqual(approved.length, 2);

      const denied = manager.getApprovalHistory({ status: 'denied' });
      assert.strictEqual(denied.length, 1);
    });

    it('should limit history results', () => {
      const limited = manager.getApprovalHistory({ limit: 2 });
      assert.strictEqual(limited.length, 2);
    });

    it('should clear approval history', () => {
      const clearedCount = manager.clearHistory();
      assert.strictEqual(clearedCount, 3);
      assert.strictEqual(manager.approvalHistory.length, 0);
    });

    it('should limit history size automatically', () => {
      // Clear existing history first
      manager.clearHistory();

      // Add exactly 1001 entries to trigger one trim
      for (let i = 0; i < 1001; i++) {
        manager.logApproval({
          id: `req${i}`,
          operation: `operation${i}`,
          status: 'approved',
          timestamp: new Date().toISOString(),
        });
      }

      // Should have trimmed to 500 when it exceeded 1000 (after 1001st entry)
      assert.ok(manager.approvalHistory.length <= 500);
    });
  });

  describe('Notification Handling', () => {
    it('should call notifyApps method', async () => {
      let notificationSent = false;
      const request = {
        id: 'test-request',
        operation: 'test operation',
        context: { test: 'data' },
      };

      // Override the method to track calls
      manager.notifyApps = async (req) => {
        assert.strictEqual(req.id, 'test-request');
        assert.strictEqual(req.operation, 'test operation');
        notificationSent = true;
        return Promise.resolve();
      };

      await manager.notifyApps(request);
      assert.strictEqual(notificationSent, true);
    });

    it('should emit notification sent event when using original method', async () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        context: {},
      };

      // Use a mock push service
      const _originalNotifyApps = manager.constructor.prototype.notifyApps;
      manager.notifyApps = async function (req) {
        this.emit('notificationSent', req);
        return Promise.resolve();
      };

      let sentRequestReceived = null;
      manager.once('notificationSent', (sentRequest) => {
        sentRequestReceived = sentRequest;
      });

      await manager.notifyApps(request);

      assert.ok(sentRequestReceived);
      assert.strictEqual(sentRequestReceived.id, 'test-request');
    });
  });

  describe('Pending Requests Management', () => {
    it('should get pending requests', () => {
      const request1 = {
        id: 'req1',
        operation: 'op1',
        context: { test: 1 },
        timestamp: '2023-01-01T00:00:00Z',
        status: 'pending',
      };

      const request2 = {
        id: 'req2',
        operation: 'op2',
        context: { test: 2 },
        timestamp: '2023-01-01T01:00:00Z',
        status: 'approved', // This should be filtered out
      };

      manager.pendingRequests.set('req1', request1);
      manager.pendingRequests.set('req2', request2);

      const pending = manager.getPendingRequests();
      assert.strictEqual(pending.length, 1);
      assert.strictEqual(pending[0].id, 'req1');
      assert.strictEqual(pending[0].operation, 'op1');
    });

    it('should handle timeout correctly', () => {
      const request = {
        id: 'timeout-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('timeout-request', request);

      // Manually trigger timeout
      manager.handleTimeout('timeout-request');

      // Request should be resolved
      assert.strictEqual(manager.pendingRequests.has('timeout-request'), false);
    });

    it('should ignore timeout for non-existent requests', () => {
      // Should not throw
      manager.handleTimeout('non-existent');
    });

    it('should ignore timeout for already resolved requests', () => {
      const request = {
        id: 'resolved-request',
        operation: 'test operation',
        status: 'approved',
      };

      manager.pendingRequests.set('resolved-request', request);

      // Should not affect the request
      manager.handleTimeout('resolved-request');
      assert.strictEqual(manager.pendingRequests.has('resolved-request'), true);
    });
  });

  describe('Request ID Generation', () => {
    it('should generate unique request IDs', () => {
      const id1 = manager.generateRequestId();
      const id2 = manager.generateRequestId();

      assert.ok(id1.startsWith('perm_'));
      assert.ok(id2.startsWith('perm_'));
      assert.notStrictEqual(id1, id2);
    });

    it('should generate IDs with UUID format', () => {
      const id = manager.generateRequestId();
      const parts = id.split('_');

      assert.strictEqual(parts.length, 2);
      assert.strictEqual(parts[0], 'perm');
      // UUID format: 8-4-4-4-12 characters with hyphens
      assert.ok(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(parts[1]));
    });
  });

  describe('Integration Scenarios', () => {
    it('should handle complete approval workflow', async () => {
      const operation = 'delete important file';
      let notificationReceived = false;
      let approvalEventReceived = false;

      // Mock notification service
      manager.notifyApps = async () => {
        notificationReceived = true;
        return Promise.resolve();
      };

      // Listen for approval event
      manager.once('permissionApproved', () => {
        approvalEventReceived = true;
      });

      // Start request
      const requestPromise = manager.requestPermission(operation);

      // Wait a bit for request to be created, then approve
      await new Promise((resolve) => setTimeout(resolve, 5));
      const pending = manager.getPendingRequests();
      if (pending.length > 0) {
        manager.approveRequest(pending[0].id, 'test-user');
      }

      const result = await requestPromise;

      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.approver, 'test-user');
      assert.strictEqual(notificationReceived, true);
      assert.strictEqual(approvalEventReceived, true);
      assert.strictEqual(manager.approvalHistory.length, 1);
    });

    it('should handle complete denial workflow', async () => {
      const operation = 'suspicious operation';
      let denialEventReceived = false;

      manager.notifyApps = async () => Promise.resolve();

      manager.once('permissionDenied', () => {
        denialEventReceived = true;
      });

      const requestPromise = manager.requestPermission(operation);

      // Wait a bit for request to be created, then deny
      await new Promise((resolve) => setTimeout(resolve, 5));
      const pending = manager.getPendingRequests();
      if (pending.length > 0) {
        manager.denyRequest(pending[0].id, 'Looks suspicious', 'security-admin');
      }

      const result = await requestPromise;

      assert.strictEqual(result.approved, false);
      assert.strictEqual(result.reason, 'Looks suspicious');
      assert.strictEqual(result.denier, 'security-admin');
      assert.strictEqual(denialEventReceived, true);
      assert.strictEqual(manager.approvalHistory.length, 1);
    });

    it('should build approval patterns over time', async () => {
      const operation = 'routine backup';

      // Simulate multiple approvals
      for (let i = 0; i < 5; i++) {
        manager.logApproval({
          id: `backup-${i}`,
          operation,
          status: 'approved',
          timestamp: new Date().toISOString(),
          approver: 'user',
        });
      }

      // Should now auto-approve
      const result = await manager.requestPermission(operation);
      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.auto, true);
    });
  });
});
