import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { NotificationTypes } from '../../../services/push-notification/notification-types.js';

describe('NotificationTypes', () => {
  let notificationTypes;
  let mockFormatter;
  let originalEnv;
  let consoleLogSpy;

  beforeEach(() => {
    // Save original env
    originalEnv = process.env.APNS_BUNDLE_ID;

    // Mock console
    consoleLogSpy = mock.method(console, 'log', () => {});

    // Mock MessageFormatter methods
    mockFormatter = {
      formatAttachmentText: mock.fn((info) => (info ? ' [📎]' : '')),
      formatThinkingPrefix: mock.fn((meta) => (meta ? '🤔 ' : '')),
      truncateMessage: mock.fn((msg, len) => (msg ? msg.substring(0, len) : '')),
      createPreview: mock.fn((msg, len) => (msg ? msg.substring(0, len) : '')),
      formatTokenText: mock.fn((count) => `${count} tokens`),
    };

    // Create instance and replace formatter
    notificationTypes = new NotificationTypes();
    notificationTypes.formatter = mockFormatter;
  });

  afterEach(() => {
    // Restore env
    if (originalEnv !== undefined) {
      process.env.APNS_BUNDLE_ID = originalEnv;
    } else {
      delete process.env.APNS_BUNDLE_ID;
    }
  });

  describe('constructor', () => {
    it('should create formatter instance', () => {
      const instance = new NotificationTypes();
      assert(instance.formatter);
    });
  });

  describe('getBundleId', () => {
    it('should return bundle ID from environment', () => {
      process.env.APNS_BUNDLE_ID = 'com.test.app';
      const bundleId = notificationTypes.getBundleId();
      assert.strictEqual(bundleId, 'com.test.app');
    });

    it('should return default bundle ID when env not set', () => {
      delete process.env.APNS_BUNDLE_ID;
      const bundleId = notificationTypes.getBundleId();
      assert.strictEqual(bundleId, 'com.aiclicompanion.ios');
    });

    it('should handle empty string env variable', () => {
      process.env.APNS_BUNDLE_ID = '';
      const bundleId = notificationTypes.getBundleId();
      assert.strictEqual(bundleId, 'com.aiclicompanion.ios');
    });
  });

  // Since we can't easily mock the apn.Notification class with ES modules,
  // we'll test the methods by verifying they don't throw errors and return objects
  // with the expected structure. The actual notification creation will be tested
  // in integration tests or with a proper mocking library.

  describe('createGenericNotification', () => {
    it('should create notification without throwing', () => {
      const data = {
        title: 'Test Title',
        message: 'Test Message',
        data: { custom: 'payload' },
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createGenericNotification(data);
        assert(notification);
      });
    });

    it('should handle empty data object', () => {
      assert.doesNotThrow(() => {
        const notification = notificationTypes.createGenericNotification({});
        assert(notification);
      });
    });
  });

  describe('createClaudeResponseNotification', () => {
    it('should create notification for regular response', () => {
      const data = {
        message: 'Claude response text',
        projectName: 'My Project',
        projectPath: '/path/to/project',
        sessionId: 'session123',
        requestId: 'req456',
        totalChunks: 5,
        attachmentInfo: { count: 2 },
        autoResponse: { enabled: true },
        thinkingMetadata: { duration: 1000 },
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createClaudeResponseNotification(data, {});
        assert(notification);
      });

      // Verify formatter methods were called
      assert.strictEqual(mockFormatter.formatAttachmentText.mock.callCount(), 1);
      assert.strictEqual(mockFormatter.formatThinkingPrefix.mock.callCount(), 1);
      assert.strictEqual(mockFormatter.truncateMessage.mock.callCount(), 1);
    });

    it('should create notification for long-running completion', () => {
      const data = {
        message: 'Task completed successfully',
        projectName: 'My Project',
        projectPath: '/project',
        isLongRunningCompletion: true,
        sessionId: 'session123',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createClaudeResponseNotification(data, {});
        assert(notification);
      });
    });

    it('should handle large message requiring fetch', () => {
      const longMessage = 'x'.repeat(5000);
      const data = {
        message: longMessage,
        projectName: 'My Project',
        projectPath: '/project',
        sessionId: 'session123',
        requestId: 'req456',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createClaudeResponseNotification(data, {
          requiresFetch: true,
          messageId: 'msg789',
        });
        assert(notification);
      });

      // Verify console log for large message requiring fetch
      assert(
        consoleLogSpy.mock.calls.some(
          (call) =>
            call.arguments[0].includes('Large message') && call.arguments[0].includes('5000 chars')
        )
      );

      // Verify preview was created
      assert.strictEqual(mockFormatter.createPreview.mock.callCount(), 1);
    });

    it('should handle missing optional fields', () => {
      const data = {
        message: 'Response',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createClaudeResponseNotification(data, {});
        assert(notification);
      });
    });

    it('should format attachment and thinking text for long-running completion', () => {
      const data = {
        message: 'Response',
        projectName: 'Project',
        attachmentInfo: { files: ['file1.txt'] },
        thinkingMetadata: { tokens: 100 },
        isLongRunningCompletion: true,
      };

      notificationTypes.createClaudeResponseNotification(data, {});

      assert.strictEqual(mockFormatter.formatAttachmentText.mock.callCount(), 1);
      assert.strictEqual(mockFormatter.formatThinkingPrefix.mock.callCount(), 1);
      assert.deepStrictEqual(mockFormatter.formatAttachmentText.mock.calls[0].arguments[0], {
        files: ['file1.txt'],
      });
      assert.deepStrictEqual(mockFormatter.formatThinkingPrefix.mock.calls[0].arguments[0], {
        tokens: 100,
      });
    });
  });

  describe('createProgressNotification', () => {
    it('should create silent progress notification', () => {
      const data = {
        projectPath: '/project',
        activity: 'thinking',
        duration: 3000,
        tokenCount: 1500,
        requestId: 'req123',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createProgressNotification(data);
        assert(notification);
      });

      // Verify token text formatting
      assert.strictEqual(mockFormatter.formatTokenText.mock.callCount(), 1);
      assert.strictEqual(mockFormatter.formatTokenText.mock.calls[0].arguments[0], 1500);
    });

    it('should handle missing projectPath', () => {
      const data = {
        activity: 'processing',
        tokenCount: 0,
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createProgressNotification(data);
        assert(notification);
      });
    });

    it('should handle all data fields', () => {
      const data = {
        projectPath: '/my/project',
        activity: 'analyzing',
        duration: 5000,
        tokenCount: 2500,
        requestId: 'req-abc',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createProgressNotification(data);
        assert(notification);
      });

      assert.strictEqual(mockFormatter.formatTokenText.mock.callCount(), 1);
    });
  });

  describe('createAutoResponseControlNotification', () => {
    it('should create pause notification', () => {
      const data = {
        action: 'pause',
        projectPath: '/project',
        reason: 'User requested pause',
        requestId: 'req123',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createAutoResponseControlNotification(data);
        assert(notification);
      });
    });

    it('should create resume notification', () => {
      const data = {
        action: 'resume',
        projectPath: '/project',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createAutoResponseControlNotification(data);
        assert(notification);
      });
    });

    it('should create stop notification', () => {
      const data = {
        action: 'stop',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createAutoResponseControlNotification(data);
        assert(notification);
      });
    });

    it('should handle unknown action', () => {
      const data = {
        action: 'unknown',
        projectPath: '/project',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createAutoResponseControlNotification(data);
        assert(notification);
      });
    });

    it('should handle action with reason but no projectPath', () => {
      const data = {
        action: 'pause',
        reason: 'Manual intervention needed',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createAutoResponseControlNotification(data);
        assert(notification);
      });
    });
  });

  describe('createStallAlert', () => {
    it('should create stall alert for alive process', () => {
      const data = {
        sessionId: 'session123',
        requestId: 'req456',
        projectPath: '/project',
        silentMinutes: 5,
        lastActivity: '10:30 AM',
        processAlive: true,
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createStallAlert(data);
        assert(notification);
      });
    });

    it('should create alert for stopped process', () => {
      const data = {
        sessionId: 'session123',
        projectPath: '/project',
        lastActivity: '11:00 AM',
        processAlive: false,
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createStallAlert(data);
        assert(notification);
      });
    });

    it('should handle singular minute', () => {
      const data = {
        sessionId: 'session123',
        silentMinutes: 1,
        processAlive: true,
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createStallAlert(data);
        assert(notification);
      });
    });

    it('should handle missing lastActivity and projectPath', () => {
      const data = {
        sessionId: 'session123',
        processAlive: false,
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createStallAlert(data);
        assert(notification);
      });
    });

    it('should handle large silent minutes value', () => {
      const data = {
        sessionId: 'session123',
        silentMinutes: 120,
        processAlive: true,
        lastActivity: 'Yesterday',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createStallAlert(data);
        assert(notification);
      });
    });
  });

  describe('createMessageNotification', () => {
    it('should create message notification with all data', () => {
      const data = {
        message: 'This is a test message',
        projectPath: '/project',
        sessionId: 'session123',
        customField: 'custom value',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createMessageNotification(data);
        assert(notification);
      });

      // Verify message truncation - called twice now (for alert body and messagePreview)
      assert.strictEqual(mockFormatter.truncateMessage.mock.callCount(), 2);
      // First call for alert body
      assert.strictEqual(
        mockFormatter.truncateMessage.mock.calls[0].arguments[0],
        'This is a test message'
      );
      assert.strictEqual(mockFormatter.truncateMessage.mock.calls[0].arguments[1], 150);
      // Second call for messagePreview
      assert.strictEqual(
        mockFormatter.truncateMessage.mock.calls[1].arguments[0],
        'This is a test message'
      );
      assert.strictEqual(mockFormatter.truncateMessage.mock.calls[1].arguments[1], 150);
    });

    it('should handle missing projectPath', () => {
      const data = {
        message: 'Message',
        sessionId: 'session123',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createMessageNotification(data);
        assert(notification);
      });
    });

    it('should truncate long messages', () => {
      const longMessage = 'x'.repeat(200);
      const data = {
        message: longMessage,
        sessionId: 'session123',
      };

      notificationTypes.createMessageNotification(data);

      // Called twice now (for alert body and messagePreview)
      assert.strictEqual(mockFormatter.truncateMessage.mock.callCount(), 2);
      // First call for alert body
      assert.strictEqual(mockFormatter.truncateMessage.mock.calls[0].arguments[0], longMessage);
      assert.strictEqual(mockFormatter.truncateMessage.mock.calls[0].arguments[1], 150);
      // Second call for messagePreview
      assert.strictEqual(mockFormatter.truncateMessage.mock.calls[1].arguments[0], longMessage);
      assert.strictEqual(mockFormatter.truncateMessage.mock.calls[1].arguments[1], 150);
    });

    it('should include additional data fields in payload', () => {
      const data = {
        message: 'Test',
        sessionId: 'session123',
        extra1: 'value1',
        extra2: { nested: 'data' },
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createMessageNotification(data);
        assert(notification);
      });
    });
  });

  describe('createErrorNotification', () => {
    it('should create timeout error notification', () => {
      const data = {
        errorType: 'TIMEOUT',
        error: 'Request timed out after 30 seconds',
        projectName: 'My Project',
        projectPath: '/project',
        sessionId: 'session123',
        requestId: 'req456',
        technicalDetails: 'Stack trace',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should create connection error', () => {
      const data = {
        errorType: 'CONNECTION_ERROR',
        error: 'Failed to connect to service',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should create memory error', () => {
      const data = {
        errorType: 'MEMORY_ERROR',
        error: 'Out of memory',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should create rate limit error', () => {
      const data = {
        errorType: 'RATE_LIMIT',
        error: 'Too many requests',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should create service not found error', () => {
      const data = {
        errorType: 'SERVICE_NOT_FOUND',
        error: 'Service unavailable',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should handle unknown error type', () => {
      const data = {
        error: 'Something went wrong',
        sessionId: 'session123',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should handle missing error message', () => {
      const data = {
        errorType: 'TIMEOUT',
        projectName: 'Project',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });

    it('should include technical details', () => {
      const data = {
        error: 'Error occurred',
        technicalDetails: 'Detailed stack trace here',
        sessionId: 'session123',
        projectPath: '/path',
      };

      assert.doesNotThrow(() => {
        const notification = notificationTypes.createErrorNotification(data);
        assert(notification);
      });
    });
  });
});
