/**
 * Permission Manager Service
 *
 * Handles permission requests for dangerous operations
 * Integrates with iOS/macOS apps for user approval
 */

import { EventEmitter } from 'events';
import { createLogger } from '../utils/logger.js';
import { pushNotificationService } from './push-notification.js';

const logger = createLogger('PermissionManager');

export class PermissionManager extends EventEmitter {
  constructor(options = {}) {
    super();

    this.pendingRequests = new Map();
    this.requestTimeout = options.requestTimeout || 30000; // 30 seconds default
    this.defaultAction = options.defaultAction || 'deny'; // deny by default
    this.requireApproval = options.requireApproval !== false;

    // Track approval history for learning patterns
    this.approvalHistory = [];
    this.autoApprovePatterns = new Set();
    this.autoDenyPatterns = new Set();
  }

  /**
   * Request permission for a dangerous operation
   */
  async requestPermission(operation, context = {}) {
    const requestId = this.generateRequestId();

    const request = {
      id: requestId,
      operation,
      context,
      timestamp: new Date().toISOString(),
      status: 'pending',
      timeout: null,
    };

    // Check auto-approve/deny patterns
    if (this.shouldAutoApprove(operation)) {
      logger.info('Auto-approving operation', { operation });
      request.status = 'approved';
      request.autoApproved = true;
      this.logApproval(request);
      return { approved: true, requestId, auto: true };
    }

    if (this.shouldAutoDeny(operation)) {
      logger.info('Auto-denying operation', { operation });
      request.status = 'denied';
      request.autoDenied = true;
      request.reason = 'Matches auto-deny pattern';
      this.logApproval(request);
      return { approved: false, requestId, reason: request.reason, auto: true };
    }

    // Store request
    this.pendingRequests.set(requestId, request);

    // Send notification to apps
    await this.notifyApps(request);

    // Set timeout
    request.timeout = setTimeout(() => {
      this.handleTimeout(requestId);
    }, this.requestTimeout);

    // Wait for response
    return new Promise((resolve) => {
      request.resolver = resolve;
    });
  }

  /**
   * Approve a permission request
   */
  approveRequest(requestId, approver = 'user') {
    const request = this.pendingRequests.get(requestId);

    if (!request) {
      logger.warn('Permission request not found', { requestId });
      return false;
    }

    if (request.status !== 'pending') {
      logger.warn('Permission request already resolved', { requestId, status: request.status });
      return false;
    }

    // Clear timeout
    if (request.timeout) {
      clearTimeout(request.timeout);
    }

    // Update request
    request.status = 'approved';
    request.approver = approver;
    request.resolvedAt = new Date().toISOString();

    // Log approval
    this.logApproval(request);

    // Resolve promise
    if (request.resolver) {
      request.resolver({
        approved: true,
        requestId,
        approver,
      });
    }

    // Clean up
    this.pendingRequests.delete(requestId);

    // Emit event
    this.emit('permissionApproved', request);

    logger.info('Permission approved', { requestId, operation: request.operation });

    return true;
  }

  /**
   * Deny a permission request
   */
  denyRequest(requestId, reason = 'User denied', denier = 'user') {
    const request = this.pendingRequests.get(requestId);

    if (!request) {
      logger.warn('Permission request not found', { requestId });
      return false;
    }

    if (request.status !== 'pending') {
      logger.warn('Permission request already resolved', { requestId, status: request.status });
      return false;
    }

    // Clear timeout
    if (request.timeout) {
      clearTimeout(request.timeout);
    }

    // Update request
    request.status = 'denied';
    request.reason = reason;
    request.denier = denier;
    request.resolvedAt = new Date().toISOString();

    // Log denial
    this.logApproval(request);

    // Resolve promise
    if (request.resolver) {
      request.resolver({
        approved: false,
        requestId,
        reason,
        denier,
      });
    }

    // Clean up
    this.pendingRequests.delete(requestId);

    // Emit event
    this.emit('permissionDenied', request);

    logger.info('Permission denied', { requestId, operation: request.operation, reason });

    return true;
  }

  /**
   * Handle request timeout
   */
  handleTimeout(requestId) {
    const request = this.pendingRequests.get(requestId);

    if (!request || request.status !== 'pending') {
      return;
    }

    logger.warn('Permission request timed out', {
      requestId,
      operation: request.operation,
    });

    // Apply default action
    if (this.defaultAction === 'approve') {
      this.approveRequest(requestId, 'timeout-default');
    } else {
      this.denyRequest(requestId, 'Request timed out', 'timeout');
    }
  }

  /**
   * Notify apps about permission request
   */
  async notifyApps(request) {
    const notification = {
      title: 'Permission Required',
      body: `Claude needs permission to: ${request.operation}`,
      data: {
        type: 'permission_request',
        requestId: request.id,
        operation: request.operation,
        context: request.context,
      },
    };

    try {
      // Send push notification
      await pushNotificationService.sendToAll(notification);

      // Also emit WebSocket event if available
      this.emit('notificationSent', request);
    } catch (error) {
      logger.error('Failed to send permission notification', {
        error: error.message,
        requestId: request.id,
      });
    }
  }

  /**
   * Check if operation should be auto-approved
   */
  shouldAutoApprove(operation) {
    // Check if operation matches any auto-approve pattern
    for (const pattern of this.autoApprovePatterns) {
      if (this.matchesPattern(operation, pattern)) {
        return true;
      }
    }

    // Check approval history for consistent approvals
    const recentApprovals = this.approvalHistory
      .filter((h) => h.operation === operation && h.status === 'approved')
      .slice(-5); // Last 5 approvals

    // If approved 5 times in a row, consider auto-approving
    return recentApprovals.length >= 5;
  }

  /**
   * Check if operation should be auto-denied
   */
  shouldAutoDeny(operation) {
    // Check if operation matches any auto-deny pattern
    for (const pattern of this.autoDenyPatterns) {
      if (this.matchesPattern(operation, pattern)) {
        return true;
      }
    }

    // Check denial history
    const recentDenials = this.approvalHistory
      .filter((h) => h.operation === operation && h.status === 'denied')
      .slice(-3); // Last 3 denials

    // If denied 3 times in a row, consider auto-denying
    return recentDenials.length >= 3;
  }

  /**
   * Check if operation matches pattern
   */
  matchesPattern(operation, pattern) {
    if (typeof pattern === 'string') {
      return operation.includes(pattern);
    }

    if (pattern instanceof RegExp) {
      return pattern.test(operation);
    }

    return false;
  }

  /**
   * Log approval/denial for history
   */
  logApproval(request) {
    const entry = {
      id: request.id,
      operation: request.operation,
      status: request.status,
      timestamp: request.timestamp,
      resolvedAt: request.resolvedAt || new Date().toISOString(),
      approver: request.approver,
      denier: request.denier,
      reason: request.reason,
      auto: request.autoApproved || request.autoDenied,
    };

    this.approvalHistory.push(entry);

    // Limit history size
    if (this.approvalHistory.length > 1000) {
      this.approvalHistory = this.approvalHistory.slice(-500);
    }
  }

  /**
   * Add auto-approve pattern
   */
  addAutoApprovePattern(pattern) {
    this.autoApprovePatterns.add(pattern);
    logger.info('Added auto-approve pattern', { pattern: pattern.toString() });
  }

  /**
   * Add auto-deny pattern
   */
  addAutoDenyPattern(pattern) {
    this.autoDenyPatterns.add(pattern);
    logger.info('Added auto-deny pattern', { pattern: pattern.toString() });
  }

  /**
   * Get pending requests
   */
  getPendingRequests() {
    return Array.from(this.pendingRequests.values())
      .filter((r) => r.status === 'pending')
      .map((r) => ({
        id: r.id,
        operation: r.operation,
        context: r.context,
        timestamp: r.timestamp,
      }));
  }

  /**
   * Get approval history
   */
  getApprovalHistory(options = {}) {
    const { limit = 100, operation, status } = options;

    let filtered = [...this.approvalHistory];

    if (operation) {
      filtered = filtered.filter((h) => h.operation === operation);
    }

    if (status) {
      filtered = filtered.filter((h) => h.status === status);
    }

    return filtered.slice(-limit).reverse();
  }

  /**
   * Clear approval history
   */
  clearHistory() {
    const count = this.approvalHistory.length;
    this.approvalHistory = [];
    logger.info('Approval history cleared', { entriesRemoved: count });
    return count;
  }

  /**
   * Generate unique request ID
   */
  generateRequestId() {
    return `perm_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }
}

// Export singleton instance
export const permissionManager = new PermissionManager();
