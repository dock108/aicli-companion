import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import { NotificationTypes } from '../../../services/push-notification/notification-types.js';

// Mock the APNs Notification class
class MockNotification {
  constructor() {
    this.expiry = null;
    this.badge = null;
    this.sound = null;
    this.alert = null;
    this.topic = null;
    this.payload = null;
    this.pushType = null;
    this.contentAvailable = null;
    this.priority = null;
    this.category = null;
    this.threadId = null;
    this.mutableContent = null;
  }
}

// Mock MessageFormatter
class MockMessageFormatter {
  formatAttachmentText(info) {
    return info ? ' 📎' : '';
  }

  formatThinkingPrefix(metadata) {
    return metadata ? '💭 ' : '';
  }

  formatTokenText(count) {
    return count ? `${count} tokens` : '';
  }

  truncateMessage(message, length) {
    if (!message) return '';
    return message.length > length ? `${message.substring(0, length)}...` : message;
  }

  createPreview(message, length) {
    if (!message) return '';
    return message.substring(0, length);
  }
}

describe('NotificationTypes', () => {
  let notificationTypes;
  let originalEnv;

  beforeEach(() => {
    originalEnv = { ...process.env };

    // Create instance with mocked dependencies
    notificationTypes = new NotificationTypes();
    notificationTypes.formatter = new MockMessageFormatter();

    // Mock the Notification constructor
    notificationTypes.createNotification = () => new MockNotification();
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  describe('getBundleId', () => {
    it('should return bundle ID from environment', () => {
      process.env.APNS_BUNDLE_ID = 'com.test.app';
      assert.strictEqual(notificationTypes.getBundleId(), 'com.test.app');
    });

    it('should return default bundle ID when env not set', () => {
      delete process.env.APNS_BUNDLE_ID;
      assert.strictEqual(notificationTypes.getBundleId(), 'com.aiclicompanion.ios');
    });
  });

  describe('createGenericNotification', () => {
    it('should create generic notification with provided data', () => {
      const data = {
        title: 'Test Title',
        message: 'Test Message',
        data: { custom: 'value' },
      };

      const notification = notificationTypes.createGenericNotification(data);

      assert(notification.expiry > Math.floor(Date.now() / 1000));
      assert.strictEqual(notification.badge, 1);
      assert.strictEqual(notification.sound, 'default');
      assert.deepStrictEqual(notification.alert, {
        title: 'Test Title',
        body: 'Test Message',
      });
      assert.strictEqual(notification.pushType, 'alert');
      assert.deepStrictEqual(notification.payload, { custom: 'value' });
    });

    it('should create generic notification with defaults', () => {
      const notification = notificationTypes.createGenericNotification({});

      assert.deepStrictEqual(notification.alert, {
        title: 'AICLI Companion',
        body: 'New notification',
      });
      assert.deepStrictEqual(notification.payload, {});
    });

    it('should set correct topic', () => {
      process.env.APNS_BUNDLE_ID = 'com.custom.bundle';
      const notification = notificationTypes.createGenericNotification({});
      assert.strictEqual(notification.topic, 'com.custom.bundle');
    });
  });

  describe('createClaudeResponseNotification', () => {
    it('should create notification for small message', () => {
      const data = {
        message: 'Short response',
        projectName: 'Test Project',
        projectPath: '/test/path',
        sessionId: 'session123',
        requestId: 'req123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data);

      assert.strictEqual(notification.sound, 'default');
      assert.strictEqual(notification.contentAvailable, true);
      assert.strictEqual(notification.priority, 10);
      assert.strictEqual(notification.category, 'CLAUDE_RESPONSE');
      assert.strictEqual(notification.threadId, '/test/path');
      assert.strictEqual(notification.payload.deliveryMethod, 'apns_primary');
      assert.strictEqual(notification.payload.sessionId, 'session123');
      assert.strictEqual(notification.payload.claudeSessionId, 'session123');
      assert.strictEqual(notification.payload.message, 'Short response');
    });

    it('should create notification for large message with fetch', () => {
      const data = {
        message: 'A very long message that needs fetching',
        projectName: 'Test Project',
        projectPath: '/test/path',
        sessionId: 'session123',
        requestId: 'req123',
      };

      const options = {
        requiresFetch: true,
        messageId: 'msg123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data, options);

      assert.strictEqual(notification.payload.requiresFetch, true);
      assert.strictEqual(notification.payload.messageId, 'msg123');
      assert.strictEqual(notification.payload.deliveryMethod, 'apns_signal');
      assert(notification.payload.preview);
      assert.strictEqual(notification.payload.messageLength, data.message.length);
      assert(!notification.payload.message); // Should not include full message
    });

    it('should create notification for long running completion', () => {
      const data = {
        message: 'Task completed',
        projectName: 'Test Project',
        isLongRunningCompletion: true,
        sessionId: 'session123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data);

      assert(notification.alert.title.includes('Task Completed'));
      assert.strictEqual(notification.sound, 'success.aiff');
      assert.strictEqual(notification.mutableContent, 1);
      assert.strictEqual(notification.category, 'TASK_COMPLETE');
    });

    it('should handle attachment and thinking metadata', () => {
      const data = {
        message: 'Response',
        projectName: 'Test',
        attachmentInfo: { hasAttachments: true },
        thinkingMetadata: { isThinking: true },
        sessionId: 'session123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data);

      assert(notification.alert.title.includes('📎'));
      assert(notification.alert.title.includes('💭'));
      assert.strictEqual(notification.payload.attachmentInfo, data.attachmentInfo);
      assert.strictEqual(notification.payload.thinkingMetadata, data.thinkingMetadata);
    });

    it('should include autoResponse when provided', () => {
      const data = {
        message: 'Response',
        projectName: 'Test',
        autoResponse: { enabled: true },
        sessionId: 'session123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data);
      assert.strictEqual(notification.payload.autoResponse, data.autoResponse);
    });

    it('should handle totalChunks', () => {
      const data = {
        message: 'Response',
        projectName: 'Test',
        totalChunks: 5,
        sessionId: 'session123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data);
      assert.strictEqual(notification.payload.totalChunks, 5);
    });

    it('should use default threadId when projectPath is missing', () => {
      const data = {
        message: 'Response',
        projectName: 'Test',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createClaudeResponseNotification(data);
      assert.strictEqual(notification.threadId, 'default');
    });
  });

  describe('createProgressNotification', () => {
    it('should create silent progress notification', () => {
      const data = {
        projectPath: '/test/path',
        activity: 'thinking',
        duration: 5000,
        tokenCount: 1500,
        requestId: 'req123',
      };

      const notification = notificationTypes.createProgressNotification(data);

      assert.strictEqual(notification.contentAvailable, true);
      assert.strictEqual(notification.priority, 5);
      assert.strictEqual(notification.sound, null); // Silent
      assert.strictEqual(notification.pushType, 'background');
      assert.strictEqual(notification.category, 'THINKING_PROGRESS');
      assert.strictEqual(notification.payload.type, 'thinkingProgress');
      assert.strictEqual(notification.payload.isThinking, true);
      assert.strictEqual(notification.payload.tokenText, '1500 tokens');
    });

    it('should handle missing token count', () => {
      const data = {
        projectPath: '/test/path',
        activity: 'processing',
      };

      const notification = notificationTypes.createProgressNotification(data);
      assert.strictEqual(notification.payload.tokenText, '');
    });

    it('should set shorter expiry for progress notifications', () => {
      const notification = notificationTypes.createProgressNotification({});
      const expectedExpiry = Math.floor(Date.now() / 1000) + 300;
      assert(Math.abs(notification.expiry - expectedExpiry) < 2);
    });
  });

  describe('createAutoResponseControlNotification', () => {
    it('should create pause notification', () => {
      const data = {
        action: 'pause',
        projectPath: '/test/path',
        reason: 'User requested',
        requestId: 'req123',
      };

      const notification = notificationTypes.createAutoResponseControlNotification(data);

      assert(notification.alert.title.includes('Paused'));
      assert(notification.alert.body.includes('User requested'));
      assert.strictEqual(notification.category, 'AUTO_RESPONSE_CONTROL');
      assert.strictEqual(notification.payload.action, 'pause');
      assert.strictEqual(notification.payload.type, 'autoResponseControl');
    });

    it('should create resume notification', () => {
      const data = {
        action: 'resume',
        projectPath: '/test/path',
      };

      const notification = notificationTypes.createAutoResponseControlNotification(data);

      assert(notification.alert.title.includes('Resumed'));
      assert(notification.alert.body.includes('Project:'));
    });

    it('should create stop notification', () => {
      const data = {
        action: 'stop',
        projectPath: '/test/path',
      };

      const notification = notificationTypes.createAutoResponseControlNotification(data);

      assert(notification.alert.title.includes('Stopped'));
    });

    it('should handle unknown action', () => {
      const data = {
        action: 'unknown',
        projectPath: '/test/path',
      };

      const notification = notificationTypes.createAutoResponseControlNotification(data);
      assert(notification.alert.title.includes('Auto-Response Update'));
    });

    it('should handle missing projectPath', () => {
      const data = {
        action: 'pause',
        reason: 'Test reason',
      };

      const notification = notificationTypes.createAutoResponseControlNotification(data);
      assert.strictEqual(notification.threadId, 'default');
    });
  });

  describe('createStallAlert', () => {
    it('should create stall alert for alive process', () => {
      const data = {
        processAlive: true,
        silentMinutes: 3,
        lastActivity: 'Reading file',
        sessionId: 'session123',
        projectPath: '/test/path',
        requestId: 'req123',
      };

      const notification = notificationTypes.createStallAlert(data);

      assert(notification.alert.title.includes('May Have Stalled'));
      assert(notification.alert.body.includes('3 minutes'));
      assert(notification.alert.body.includes('Reading file'));
      assert.strictEqual(notification.category, 'CLAUDE_STALL');
      assert.strictEqual(notification.mutableContent, 1);
      assert.strictEqual(notification.payload.processAlive, true);
      assert.strictEqual(notification.payload.deliveryMethod, 'apns_stall_alert');
    });

    it('should create stall alert for dead process', () => {
      const data = {
        processAlive: false,
        lastActivity: 'Writing output',
        sessionId: 'session123',
        projectPath: '/test/path',
      };

      const notification = notificationTypes.createStallAlert(data);

      assert(notification.alert.title.includes('Process Stopped'));
      assert(notification.alert.body.includes('unexpectedly stopped'));
      assert(notification.alert.body.includes('Writing output'));
    });

    it('should handle singular minute', () => {
      const data = {
        processAlive: true,
        silentMinutes: 1,
        sessionId: 'session123',
      };

      const notification = notificationTypes.createStallAlert(data);
      assert(notification.alert.body.includes('1 minute'));
      assert(!notification.alert.body.includes('minutes'));
    });

    it('should handle missing lastActivity', () => {
      const data = {
        processAlive: true,
        silentMinutes: 5,
        sessionId: 'session123',
      };

      const notification = notificationTypes.createStallAlert(data);
      assert(notification.alert.body.includes('Unknown'));
    });

    it('should set threadId to stall when no projectPath', () => {
      const data = {
        processAlive: false,
        sessionId: 'session123',
      };

      const notification = notificationTypes.createStallAlert(data);
      assert.strictEqual(notification.threadId, 'stall');
    });
  });

  describe('createMessageNotification', () => {
    it('should create message notification', () => {
      const data = {
        message: 'This is a test message that is quite long and should be truncated',
        projectPath: '/test/path',
        sessionId: 'session123',
        customField: 'customValue',
      };

      const notification = notificationTypes.createMessageNotification(data);

      assert.strictEqual(notification.alert.title, 'Claude Response');
      assert.strictEqual(notification.alert.subtitle, '/test/path');
      assert(notification.alert.body.includes('...'));
      assert.strictEqual(notification.category, 'CLAUDE_MESSAGE');
      assert.strictEqual(notification.payload.type, 'message');
      assert.strictEqual(notification.payload.deliveryMethod, 'apns_message');
      assert.strictEqual(notification.payload.sessionId, 'session123');
      assert.strictEqual(notification.payload.claudeSessionId, 'session123');
      assert.strictEqual(notification.payload.customField, 'customValue');
    });

    it('should handle default values', () => {
      const data = {
        message: 'Short msg',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createMessageNotification(data);

      assert.strictEqual(notification.alert.subtitle, 'AICLI Companion');
      assert.strictEqual(notification.threadId, 'default');
    });

    it('should preserve all data fields in payload', () => {
      const data = {
        message: 'Test',
        sessionId: 'session123',
        field1: 'value1',
        field2: { nested: 'value' },
        field3: [1, 2, 3],
      };

      const notification = notificationTypes.createMessageNotification(data);

      assert.strictEqual(notification.payload.field1, 'value1');
      assert.deepStrictEqual(notification.payload.field2, { nested: 'value' });
      assert.deepStrictEqual(notification.payload.field3, [1, 2, 3]);
    });
  });

  describe('createErrorNotification', () => {
    it('should create timeout error notification', () => {
      const data = {
        errorType: 'TIMEOUT',
        error: 'Request timed out after 30 seconds',
        projectName: 'Test Project',
        projectPath: '/test/path',
        sessionId: 'session123',
        requestId: 'req123',
      };

      const notification = notificationTypes.createErrorNotification(data);

      assert(notification.alert.title.includes('Request Timeout'));
      assert.strictEqual(notification.alert.subtitle, 'Test Project');
      assert.strictEqual(notification.alert.body, 'Request timed out after 30 seconds');
      assert.strictEqual(notification.category, 'ERROR_NOTIFICATION');
      assert.strictEqual(notification.payload.error, true);
      assert.strictEqual(notification.payload.errorType, 'TIMEOUT');
      assert.strictEqual(notification.payload.deliveryMethod, 'apns_error');
    });

    it('should create connection error notification', () => {
      const data = {
        errorType: 'CONNECTION_ERROR',
        error: 'Failed to connect',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createErrorNotification(data);
      assert(notification.alert.title.includes('Connection Error'));
    });

    it('should create memory error notification', () => {
      const data = {
        errorType: 'MEMORY_ERROR',
        error: 'Out of memory',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createErrorNotification(data);
      assert(notification.alert.title.includes('Memory Error'));
    });

    it('should create rate limit notification', () => {
      const data = {
        errorType: 'RATE_LIMIT',
        error: 'Too many requests',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createErrorNotification(data);
      assert(notification.alert.title.includes('Rate Limited'));
    });

    it('should create service not found notification', () => {
      const data = {
        errorType: 'SERVICE_NOT_FOUND',
        error: 'Service unavailable',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createErrorNotification(data);
      assert(notification.alert.title.includes('Service Not Found'));
    });

    it('should handle unknown error type', () => {
      const data = {
        error: 'Something went wrong',
        sessionId: 'session123',
        technicalDetails: { stack: 'Error stack trace' },
      };

      const notification = notificationTypes.createErrorNotification(data);

      assert(notification.alert.title.includes('Processing Error'));
      assert.strictEqual(notification.payload.errorType, 'UNKNOWN');
      assert.deepStrictEqual(notification.payload.technicalDetails, data.technicalDetails);
    });

    it('should handle missing error message', () => {
      const data = {
        sessionId: 'session123',
      };

      const notification = notificationTypes.createErrorNotification(data);
      assert.strictEqual(notification.alert.body, 'An error occurred processing your message');
    });

    it('should set error threadId when no projectPath', () => {
      const data = {
        error: 'Test error',
        sessionId: 'session123',
      };

      const notification = notificationTypes.createErrorNotification(data);
      assert.strictEqual(notification.threadId, 'error');
    });

    it('should set high priority for errors', () => {
      const notification = notificationTypes.createErrorNotification({
        sessionId: 'session123',
      });

      assert.strictEqual(notification.priority, 10);
      assert.strictEqual(notification.contentAvailable, true);
    });
  });
});
