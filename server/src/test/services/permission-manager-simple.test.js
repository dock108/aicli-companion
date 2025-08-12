import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { PermissionManager } from '../../services/permission-manager.js';

describe('PermissionManager - Core Functionality', () => {
  let manager;

  beforeEach(() => {
    manager = new PermissionManager({
      requestTimeout: 100, // Short timeout for tests
      defaultAction: 'deny',
      requireApproval: true,
    });

    // Mock notification method
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

  describe('Auto Approval/Denial', () => {
    it('should auto-approve known safe operations', async () => {
      manager.addAutoApprovePattern('read file');
      const result = await manager.requestPermission('read file /tmp/safe.txt');

      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.auto, true);
    });

    it('should auto-deny dangerous operations', async () => {
      manager.addAutoDenyPattern('format disk');
      const result = await manager.requestPermission('format disk C:');

      assert.strictEqual(result.approved, false);
      assert.strictEqual(result.auto, true);
      assert.ok(result.reason);
    });

    it('should auto-approve based on history', async () => {
      const operation = 'routine backup';

      // Simulate 5 approvals
      for (let i = 0; i < 5; i++) {
        manager.logApproval({
          id: `backup-${i}`,
          operation,
          status: 'approved',
          timestamp: new Date().toISOString(),
        });
      }

      const result = await manager.requestPermission(operation);
      assert.strictEqual(result.approved, true);
      assert.strictEqual(result.auto, true);
    });

    it('should auto-deny based on denial history', async () => {
      const operation = 'suspicious command';

      // Simulate 3 denials
      for (let i = 0; i < 3; i++) {
        manager.logApproval({
          id: `deny-${i}`,
          operation,
          status: 'denied',
          timestamp: new Date().toISOString(),
        });
      }

      const result = await manager.requestPermission(operation);
      assert.strictEqual(result.approved, false);
      assert.strictEqual(result.auto, true);
    });
  });

  describe('Pattern Matching', () => {
    it('should match string patterns', () => {
      assert.strictEqual(manager.matchesPattern('test operation', 'test'), true);
      assert.strictEqual(manager.matchesPattern('test operation', 'missing'), false);
    });

    it('should match regex patterns', () => {
      const regex = /^delete\s+file/;
      assert.strictEqual(manager.matchesPattern('delete file test.txt', regex), true);
      assert.strictEqual(manager.matchesPattern('create file test.txt', regex), false);
    });

    it('should handle invalid patterns', () => {
      assert.strictEqual(manager.matchesPattern('test', null), false);
      assert.strictEqual(manager.matchesPattern('test', undefined), false);
    });
  });

  describe('Manual Approval/Denial', () => {
    it('should approve pending requests', () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);
      const result = manager.approveRequest('test-request', 'admin');

      assert.strictEqual(result, true);
      assert.strictEqual(manager.pendingRequests.has('test-request'), false);
    });

    it('should deny pending requests', () => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);
      const result = manager.denyRequest('test-request', 'Too risky', 'admin');

      assert.strictEqual(result, true);
      assert.strictEqual(manager.pendingRequests.has('test-request'), false);
    });

    it('should reject operations on non-existent requests', () => {
      assert.strictEqual(manager.approveRequest('non-existent'), false);
      assert.strictEqual(manager.denyRequest('non-existent'), false);
    });

    it('should reject operations on already resolved requests', () => {
      const request = {
        id: 'resolved-request',
        operation: 'test operation',
        status: 'approved',
      };

      manager.pendingRequests.set('resolved-request', request);

      assert.strictEqual(manager.approveRequest('resolved-request'), false);
      assert.strictEqual(manager.denyRequest('resolved-request'), false);
    });
  });

  describe('Request Management', () => {
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
        status: 'approved',
      };

      manager.pendingRequests.set('req1', request1);
      manager.pendingRequests.set('req2', request2);

      const pending = manager.getPendingRequests();
      assert.strictEqual(pending.length, 1);
      assert.strictEqual(pending[0].id, 'req1');
    });

    it('should handle timeouts for resolved requests', () => {
      const request = {
        id: 'resolved-request',
        operation: 'test operation',
        status: 'approved',
      };

      manager.pendingRequests.set('resolved-request', request);
      manager.handleTimeout('resolved-request');

      // Should still exist since it was already resolved
      assert.strictEqual(manager.pendingRequests.has('resolved-request'), true);
    });

    it('should ignore timeout for non-existent requests', () => {
      // Should not throw
      manager.handleTimeout('non-existent');
      assert.ok(true);
    });
  });

  describe('Approval History', () => {
    beforeEach(() => {
      manager.logApproval({
        id: 'req1',
        operation: 'operation1',
        status: 'approved',
        timestamp: '2023-01-01T00:00:00Z',
      });

      manager.logApproval({
        id: 'req2',
        operation: 'operation2',
        status: 'denied',
        timestamp: '2023-01-01T01:00:00Z',
        reason: 'Too risky',
      });
    });

    it('should get all approval history', () => {
      const history = manager.getApprovalHistory();
      assert.strictEqual(history.length, 2);
    });

    it('should filter history by operation', () => {
      const filtered = manager.getApprovalHistory({ operation: 'operation1' });
      assert.strictEqual(filtered.length, 1);
      assert.strictEqual(filtered[0].operation, 'operation1');
    });

    it('should filter history by status', () => {
      const approved = manager.getApprovalHistory({ status: 'approved' });
      const denied = manager.getApprovalHistory({ status: 'denied' });

      assert.strictEqual(approved.length, 1);
      assert.strictEqual(denied.length, 1);
    });

    it('should limit history results', () => {
      const limited = manager.getApprovalHistory({ limit: 1 });
      assert.strictEqual(limited.length, 1);
    });

    it('should clear approval history', () => {
      const clearedCount = manager.clearHistory();
      assert.strictEqual(clearedCount, 2);
      assert.strictEqual(manager.approvalHistory.length, 0);
    });

    it('should auto-trim large history', () => {
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

  describe('Pattern Management', () => {
    it('should add auto-approve patterns', () => {
      manager.addAutoApprovePattern('safe operation');
      assert.ok(manager.autoApprovePatterns.has('safe operation'));
    });

    it('should add auto-deny patterns', () => {
      manager.addAutoDenyPattern('dangerous operation');
      assert.ok(manager.autoDenyPatterns.has('dangerous operation'));
    });

    it('should check auto-approval conditions', () => {
      manager.addAutoApprovePattern('backup');
      assert.strictEqual(manager.shouldAutoApprove('backup file'), true);
      assert.strictEqual(manager.shouldAutoApprove('delete file'), false);
    });

    it('should check auto-denial conditions', () => {
      manager.addAutoDenyPattern('format');
      assert.strictEqual(manager.shouldAutoDeny('format disk'), true);
      assert.strictEqual(manager.shouldAutoDeny('backup disk'), false);
    });
  });

  describe('Utilities', () => {
    it('should generate unique request IDs', () => {
      const id1 = manager.generateRequestId();
      const id2 = manager.generateRequestId();

      assert.ok(id1.startsWith('perm_'));
      assert.ok(id2.startsWith('perm_'));
      assert.notStrictEqual(id1, id2);
    });

    it('should generate IDs with correct format', () => {
      const id = manager.generateRequestId();
      const parts = id.split('_');

      assert.strictEqual(parts.length, 3);
      assert.strictEqual(parts[0], 'perm');
      assert.ok(!isNaN(parseInt(parts[1])));
      assert.ok(parts[2].length > 0);
    });
  });

  describe('Event Emission', () => {
    it('should emit approval events', (t, done) => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);

      manager.once('permissionApproved', (approvedRequest) => {
        assert.strictEqual(approvedRequest.id, 'test-request');
        done();
      });

      manager.approveRequest('test-request');
    });

    it('should emit denial events', (t, done) => {
      const request = {
        id: 'test-request',
        operation: 'test operation',
        status: 'pending',
        timeout: null,
      };

      manager.pendingRequests.set('test-request', request);

      manager.once('permissionDenied', (deniedRequest) => {
        assert.strictEqual(deniedRequest.id, 'test-request');
        done();
      });

      manager.denyRequest('test-request');
    });
  });
});