/**
 * Notification Type Builders
 * Creates different types of push notifications with appropriate formatting
 */

import apn from '@parse/node-apn';
import { MessageFormatter } from './message-formatter.js';

export class NotificationTypes {
  constructor() {
    this.formatter = new MessageFormatter();
  }

  /**
   * Get bundle ID from environment
   */
  getBundleId() {
    return process.env.APNS_BUNDLE_ID || 'com.aiclicompanion.ios';
  }

  /**
   * Create a generic push notification
   */
  createGenericNotification(data) {
    const notification = new apn.Notification();

    notification.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    notification.badge = 1;
    notification.sound = 'default';
    notification.alert = {
      title: data.title || 'AICLI Companion',
      body: data.message || 'New notification',
    };
    notification.topic = this.getBundleId();
    notification.payload = data.data || {};
    notification.pushType = 'alert';

    return notification;
  }

  /**
   * Create a Claude response notification
   */
  createClaudeResponseNotification(data, options = {}) {
    const notification = new apn.Notification();
    const { requiresFetch, messageId } = options;

    // Configure the notification
    notification.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    notification.sound = 'default';
    notification.contentAvailable = true;
    notification.priority = 10;

    // Format attachment and thinking text
    const attachmentText = this.formatter.formatAttachmentText(data.attachmentInfo);
    const titlePrefix = this.formatter.formatThinkingPrefix(data.thinkingMetadata);

    if (data.isLongRunningCompletion) {
      notification.alert = {
        title: `${titlePrefix}🎯 Task Completed${attachmentText}`,
        subtitle: data.projectName,
        body: this.formatter.truncateMessage(data.message, 150),
      };
      notification.sound = 'success.aiff';
    } else {
      notification.alert = {
        title: `${titlePrefix}Claude Response Ready${attachmentText}`,
        subtitle: data.projectName,
        body: this.formatter.truncateMessage(data.message, 150),
      };
    }

    notification.topic = this.getBundleId();
    notification.pushType = 'alert';
    notification.category = 'CLAUDE_RESPONSE';
    notification.threadId = data.projectPath || 'default';

    // Build payload based on message size
    if (requiresFetch) {
      notification.payload = {
        messageId,
        projectName: data.projectName,
        projectPath: data.projectPath,
        preview: this.formatter.createPreview(data.message, 100),
        messageLength: data.message.length,
        requiresFetch: true,
        timestamp: new Date().toISOString(),
        requestId: data.requestId,
        deliveryMethod: 'apns_signal',
        sessionId: data.sessionId, // Include sessionId for large messages
        claudeSessionId: data.sessionId, // Also as claudeSessionId for compatibility
      };
      console.log(
        `📱 Large message (${data.message.length} chars) - sending signal with messageId: ${messageId}`
      );
    } else {
      notification.payload = {
        projectName: data.projectName,
        projectPath: data.projectPath,
        message: data.message,
        totalChunks: data.totalChunks,
        timestamp: new Date().toISOString(),
        isLongRunningCompletion: data.isLongRunningCompletion || false,
        requestId: data.requestId,
        deliveryMethod: 'apns_primary',
        attachmentInfo: data.attachmentInfo || null,
        autoResponse: data.autoResponse || null,
        thinkingMetadata: data.thinkingMetadata || null,
        sessionId: data.sessionId, // Include sessionId for small messages
        claudeSessionId: data.sessionId, // Also as claudeSessionId for compatibility
      };
    }

    // Add action buttons for long-running completions
    if (data.isLongRunningCompletion) {
      notification.mutableContent = 1;
      notification.category = 'TASK_COMPLETE';
    }

    return notification;
  }

  /**
   * Create a progress/thinking notification
   */
  createProgressNotification(data) {
    const notification = new apn.Notification();

    // Configure as silent notification for progress updates
    notification.expiry = Math.floor(Date.now() / 1000) + 300; // 5 minutes
    notification.contentAvailable = true;
    notification.priority = 5; // Lower priority for progress

    notification.topic = this.getBundleId();
    notification.pushType = 'background';
    notification.category = 'THINKING_PROGRESS';
    notification.threadId = data.projectPath || 'default';

    const tokenText = this.formatter.formatTokenText(data.tokenCount);

    notification.payload = {
      projectPath: data.projectPath,
      activity: data.activity,
      duration: data.duration,
      tokenCount: data.tokenCount,
      tokenText,
      requestId: data.requestId,
      sessionId: data.sessionId || null,
      correlationId: data.correlationId || data.requestId,
      timestamp: new Date().toISOString(),
      type: 'thinkingProgress',
      isThinking: true,
    };

    return notification;
  }

  /**
   * Create an auto-response control notification
   */
  createAutoResponseControlNotification(data) {
    const notification = new apn.Notification();

    notification.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    notification.sound = 'default';
    notification.contentAvailable = true;
    notification.priority = 10;

    // Set alert based on action
    const actionText = {
      pause: '⏸️ Auto-Response Paused',
      resume: '▶️ Auto-Response Resumed',
      stop: '⏹️ Auto-Response Stopped',
    };

    notification.alert = {
      title: actionText[data.action] || 'Auto-Response Update',
      body: data.reason ? `Reason: ${data.reason}` : `Project: ${data.projectPath || 'Default'}`,
    };

    notification.topic = this.getBundleId();
    notification.pushType = 'alert';
    notification.category = 'AUTO_RESPONSE_CONTROL';
    notification.threadId = data.projectPath || 'default';

    notification.payload = {
      projectPath: data.projectPath,
      action: data.action,
      reason: data.reason,
      requestId: data.requestId,
      sessionId: data.sessionId || null,
      correlationId: data.correlationId || data.requestId,
      timestamp: new Date().toISOString(),
      type: 'autoResponseControl',
    };

    return notification;
  }

  /**
   * Create a stall alert notification
   */
  createStallAlert(data) {
    const notification = new apn.Notification();

    notification.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
    notification.sound = 'default';
    notification.contentAvailable = true;
    notification.priority = 10; // High priority for stall alerts

    // Different messages based on process state
    const title = data.processAlive ? '⚠️ Claude May Have Stalled' : '❌ Claude Process Stopped';

    const bodyMessage = data.processAlive
      ? `No output for ${data.silentMinutes} minute${data.silentMinutes > 1 ? 's' : ''}. Last activity: ${data.lastActivity || 'Unknown'}`
      : `Claude process unexpectedly stopped. Last activity: ${data.lastActivity || 'Unknown'}`;

    notification.alert = {
      title,
      subtitle: data.projectPath || 'AICLI Companion',
      body: bodyMessage,
    };

    notification.topic = this.getBundleId();
    notification.pushType = 'alert';
    notification.category = 'CLAUDE_STALL';
    notification.mutableContent = 1; // Allow notification actions
    notification.threadId = data.projectPath || 'stall';

    notification.payload = {
      type: 'stallAlert',
      sessionId: data.sessionId,
      requestId: data.requestId,
      correlationId: data.correlationId || data.requestId,
      projectPath: data.projectPath,
      silentMinutes: data.silentMinutes,
      lastActivity: data.lastActivity,
      processAlive: data.processAlive,
      timestamp: new Date().toISOString(),
      deliveryMethod: 'apns_stall_alert',
    };

    return notification;
  }

  /**
   * Create a message notification
   */
  createMessageNotification(data) {
    const notification = new apn.Notification();

    notification.expiry = Math.floor(Date.now() / 1000) + 3600;
    notification.sound = 'default';
    notification.contentAvailable = true;
    notification.priority = 10;

    notification.alert = {
      title: 'Claude Response',
      subtitle: data.projectPath || 'AICLI Companion',
      body: data.message
        ? this.formatter.truncateMessage(data.message, 150)
        : 'New message received',
    };

    notification.topic = this.getBundleId();
    notification.pushType = 'alert';
    notification.category = 'CLAUDE_MESSAGE';
    notification.threadId = data.projectPath || 'default';

    const { message: _message, ...metadataOnly } = data;

    // Build initial payload
    let payload = {
      ...metadataOnly,
      type: 'message',
      deliveryMethod: 'apns_message',
      sessionId: data.sessionId, // Ensure sessionId is explicitly included
      claudeSessionId: data.sessionId, // Also include as claudeSessionId for compatibility
      correlationId: data.correlationId || data.requestId, // Add correlation ID for tracking
      messagePreview: data.message
        ? this.formatter.truncateMessage(data.message, 150)
        : 'New message', // Small preview only
      requiresFetch: data.requiresFetch || false, // Tell the app to fetch the full message if needed
      messageId: data.messageId || null, // Include message ID for fetching
    };

    // Check payload size and truncate if needed (APNS max is 4KB)
    const MAX_PAYLOAD_SIZE = 3800; // Leave some buffer for APNS overhead
    let payloadString = JSON.stringify(payload);

    if (payloadString.length > MAX_PAYLOAD_SIZE) {
      // Remove non-essential fields progressively
      const fieldsToRemove = ['messagePreview', 'metadata', 'context'];

      for (const field of fieldsToRemove) {
        if (payload[field]) {
          delete payload[field];
          payloadString = JSON.stringify(payload);
          if (payloadString.length <= MAX_PAYLOAD_SIZE) break;
        }
      }

      // If still too large, keep only essential fields
      if (payloadString.length > MAX_PAYLOAD_SIZE) {
        payload = {
          type: 'message',
          sessionId: data.sessionId,
          requestId: data.requestId,
          requiresFetch: true, // Force fetch since we stripped data
          messageId: data.messageId || null,
        };
      }
    }

    notification.payload = payload;

    return notification;
  }

  /**
   * Create an error notification
   */
  createErrorNotification(data) {
    const notification = new apn.Notification();

    notification.expiry = Math.floor(Date.now() / 1000) + 3600;
    notification.sound = 'default';
    notification.contentAvailable = true; // Ensure app wakes up to handle error
    notification.priority = 10; // High priority for errors

    // Different alert styles based on error type
    const errorTitle =
      {
        TIMEOUT: '⏱️ Request Timeout',
        CONNECTION_ERROR: '🔌 Connection Error',
        MEMORY_ERROR: '💾 Memory Error',
        RATE_LIMIT: '🚦 Rate Limited',
        SERVICE_NOT_FOUND: '❓ Service Not Found',
      }[data.errorType] || '❌ Processing Error';

    notification.alert = {
      title: errorTitle,
      subtitle: data.projectName || 'AICLI Companion',
      body: data.error || 'An error occurred processing your message',
    };

    notification.topic = this.getBundleId();
    notification.category = 'ERROR_NOTIFICATION';
    notification.threadId = data.projectPath || 'error';

    // Build initial payload
    const payload = {
      projectName: data.projectName,
      projectPath: data.projectPath,
      sessionId: data.sessionId,
      correlationId: data.correlationId || data.requestId,
      error: true,
      errorType: data.errorType || 'UNKNOWN',
      errorMessage: data.error,
      technicalDetails: data.technicalDetails,
      requestId: data.requestId,
      timestamp: new Date().toISOString(),
      deliveryMethod: 'apns_error',
    };

    // Check payload size and truncate if needed
    const MAX_PAYLOAD_SIZE = 3800;
    let payloadString = JSON.stringify(payload);

    if (payloadString.length > MAX_PAYLOAD_SIZE) {
      // Truncate technical details first, then error message
      if (payload.technicalDetails && payload.technicalDetails.length > 100) {
        payload.technicalDetails = `${payload.technicalDetails.substring(0, 100)}...`;
        payloadString = JSON.stringify(payload);
      }

      if (payloadString.length > MAX_PAYLOAD_SIZE && payload.errorMessage) {
        const maxErrorLength = Math.max(
          50,
          MAX_PAYLOAD_SIZE - payloadString.length + payload.errorMessage.length - 100
        );
        payload.errorMessage = `${payload.errorMessage.substring(0, maxErrorLength)}...`;
        payloadString = JSON.stringify(payload);
      }

      // If still too large, remove technical details entirely
      if (payloadString.length > MAX_PAYLOAD_SIZE) {
        delete payload.technicalDetails;
      }
    }

    notification.payload = payload;

    return notification;
  }
}
