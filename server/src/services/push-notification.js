import apn from '@parse/node-apn';
import fs from 'fs';
import { getTelemetryService } from './telemetry.js';

class PushNotificationService {
  constructor() {
    this.provider = null;
    this.deviceTokens = new Map(); // Map clientId -> { token, platform }
    this.isConfigured = false;
    this.badTokens = new Set(); // Track bad tokens
    this.tokenRetryCount = new Map(); // Track retry attempts per token
  }

  /**
   * Initialize the push notification service with APNs HTTP/2 API (.p8 key)
   * @param {Object} config - Configuration object
   * @param {string} config.keyPath - Path to the .p8 key file
   * @param {string} config.keyId - APNs Key ID
   * @param {string} config.teamId - Apple Developer Team ID
   * @param {string} config.bundleId - iOS app bundle identifier
   * @param {boolean} config.production - Whether to use production environment
   */
  initialize(config = {}) {
    try {
      // Get configuration from environment or config object
      const keyPath = config.keyPath || process.env.APNS_KEY_PATH;
      const keyId = config.keyId || process.env.APNS_KEY_ID;
      const teamId = config.teamId || process.env.APNS_TEAM_ID;
      const bundleId = config.bundleId || process.env.APNS_BUNDLE_ID;
      const production =
        config.production !== undefined
          ? config.production
          : process.env.APNS_PRODUCTION === 'true' || process.env.NODE_ENV === 'production';

      if (!keyPath || !keyId || !teamId) {
        console.log('⚠️  Push notifications not configured - missing keyPath, keyId, or teamId');
        console.log(
          '   Required env vars: APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID'
        );
        return;
      }

      // Check if .p8 key file exists
      if (!fs.existsSync(keyPath)) {
        console.log(`⚠️  APNs key file not found: ${keyPath}`);
        return;
      }

      // Create APNs provider with HTTP/2 API (.p8 key)
      const options = {
        token: {
          key: keyPath, // Path to .p8 file
          keyId, // Key ID from Apple Developer Portal
          teamId, // Team ID from Apple Developer Portal
        },
        production,
      };

      this.provider = new apn.Provider(options);
      this.bundleId = bundleId;
      this.isConfigured = true;

      console.log(`✅ Push notification service initialized with APNs HTTP/2`);
      console.log(`   Environment: ${production ? 'production' : 'development'}`);
      console.log(`   Key ID: ${keyId}`);
      console.log(`   Team ID: ${teamId}`);
      console.log(`   Bundle ID: ${bundleId}`);
    } catch (error) {
      console.error('❌ Failed to initialize push notification service:', error);
    }
  }

  /**
   * Register a device token for a client
   * @param {string} clientId - The client ID (can be device ID or WebSocket client ID)
   * @param {Object|string} tokenOrDevice - Device info object or token string for backward compatibility
   * @param {string} platform - The platform (ios, android) - for backward compatibility
   */
  registerDevice(clientId, tokenOrDevice, platform = 'ios') {
    let token, devicePlatform;

    // Handle both new API (object) and old API (string) for compatibility
    if (typeof tokenOrDevice === 'object') {
      token = tokenOrDevice.token;
      devicePlatform = tokenOrDevice.platform || 'ios';
    } else {
      token = tokenOrDevice;
      devicePlatform = platform;
    }

    if (!token || !clientId) {
      console.warn('⚠️  Cannot register device - missing token or clientId');
      return;
    }

    this.deviceTokens.set(clientId, { token, platform: devicePlatform });
    console.log(`📱 Registered device token for client ${clientId} (${devicePlatform})`);
    console.log(`   Token: ${token.substring(0, 16)}...`);
  }

  /**
   * Unregister a device when client disconnects
   * @param {string} clientId - The WebSocket client ID
   */
  unregisterDevice(clientId) {
    if (this.deviceTokens.has(clientId)) {
      this.deviceTokens.delete(clientId);
      console.log(`📱 Unregistered device token for client ${clientId}`);
    }
  }

  /**
   * Send a notification with retry logic
   * @param {string} deviceToken - The device token
   * @param {Object} notification - The notification object
   * @param {Object} options - Options for retry
   * @returns {Object} - Result of the send operation
   */
  async sendNotification(deviceToken, notification, options = {}) {
    const maxRetries = options.retries || 3;
    const retryDelay = options.retryDelay || 1000;

    // TODO: [OPTIMIZE] Implement exponential backoff?
    // Current implementation uses linear delay
    // May need: retryDelay * Math.pow(2, attempt - 1)

    // Check if token is known bad
    if (this.badTokens.has(deviceToken)) {
      console.log(`⚠️ Skipping known bad token: ${deviceToken.substring(0, 10)}...`);
      return { success: false, error: 'BadDeviceToken' };
    }

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        const result = await this.provider.send(notification, deviceToken);

        if (result.sent.length > 0) {
          // Reset retry count on success
          this.tokenRetryCount.delete(deviceToken);
          return { success: true, result };
        }

        // Handle specific error cases
        if (result.failed.length > 0) {
          const failure = result.failed[0];

          if (failure.response?.reason === 'BadDeviceToken') {
            // TODO: [QUESTION] Define token cleanup policy
            // Should we immediately remove bad tokens?
            // Or mark them and retry later?
            await this.handleBadToken(deviceToken);
            return { success: false, error: 'BadDeviceToken' };
          }

          if (failure.response?.reason === 'ExpiredProviderToken') {
            console.error('⚠️ Provider token expired - requires service restart');
            return { success: false, error: 'ExpiredProviderToken' };
          }

          // For other errors, continue retrying
          console.warn(`Push notification attempt ${attempt} failed:`, failure.response);
        }

        if (attempt < maxRetries) {
          await new Promise((resolve) => setTimeout(resolve, retryDelay));
        }
      } catch (error) {
        console.error(`Push notification attempt ${attempt} failed:`, error);
        if (attempt === maxRetries) {
          throw error;
        }
        await new Promise((resolve) => setTimeout(resolve, retryDelay));
      }
    }

    return { success: false, error: 'MaxRetriesExceeded' };
  }

  /**
   * Handle bad device token
   * @param {string} deviceToken - The bad device token
   */
  async handleBadToken(deviceToken) {
    this.badTokens.add(deviceToken);

    // Find and remove client with this token
    for (const [clientId, device] of this.deviceTokens) {
      if (device.token === deviceToken) {
        this.deviceTokens.delete(clientId);
        console.log(`🗑️ Removed bad token for client ${clientId}`);
        break;
      }
    }

    // TODO: [OPTIMIZE] Persist bad tokens to avoid re-registration?
    // Could store in Redis or file system
  }

  /**
   * Send a generic push notification to a device token
   * @param {string} deviceToken - The device token
   * @param {Object} data - Notification data
   * @param {string} data.title - Notification title
   * @param {string} data.message - Notification message
   * @param {Object} data.data - Additional payload data
   * @returns {Object} - Result of the send operation
   */
  async sendPushNotification(deviceToken, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping');
      return { success: false, error: 'Not configured' };
    }

    if (!deviceToken) {
      return { success: false, error: 'No device token provided' };
    }

    try {
      const notification = new apn.Notification();

      notification.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
      notification.badge = 1;
      notification.sound = 'default';
      notification.alert = {
        title: data.title || 'AICLI Companion',
        body: data.message || 'New notification',
      };
      notification.topic = this.bundleId || process.env.APNS_BUNDLE_ID || 'com.aiclicompanion.ios';
      notification.payload = data.data || {};
      notification.pushType = 'alert';

      const result = await this.sendNotification(deviceToken, notification);

      if (result.success) {
        console.log(
          `✅ Generic push notification sent to token ${deviceToken.substring(0, 10)}...`
        );
      } else {
        console.error(`❌ Generic push notification failed:`, result.error);
      }

      return result;
    } catch (error) {
      console.error('❌ Error sending generic push notification:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Send a push notification for a Claude response
   * @param {string} clientId - The WebSocket client ID
   * @param {Object} data - Notification data
   * @param {string} data.sessionId - The session ID
   * @param {string} data.projectName - The project name
   * @param {string} data.message - The message content
   * @param {number} data.totalChunks - Total number of chunks
   */
  async sendClaudeResponseNotification(clientId, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping');
      return;
    }

    const device = this.deviceTokens.get(clientId);
    if (!device) {
      console.log(`⚠️  No device token found for client ${clientId}`);
      return;
    }

    try {
      const notification = new apn.Notification();

      // Configure the notification
      notification.expiry = Math.floor(Date.now() / 1000) + 3600; // 1 hour
      // Don't set badge - let the client manage badge counts
      // notification.badge = 1;  // REMOVED - causing persistent badge issue
      notification.sound = 'default';

      // CRITICAL: Set content-available for background/silent delivery
      // This ensures the app wakes up to process the notification
      notification.contentAvailable = true;
      notification.priority = 10; // High priority for immediate delivery

      // Customize notification based on context
      const hasAttachments = data.attachmentInfo && data.attachmentInfo.length > 0;
      const attachmentText = hasAttachments
        ? ` (${data.attachmentInfo.length} attachment${data.attachmentInfo.length > 1 ? 's' : ''})`
        : '';

      // Include thinking indicator in title if active
      let titlePrefix = '';
      if (data.thinkingMetadata && data.thinkingMetadata.isThinking) {
        const activity = data.thinkingMetadata.activity || 'Thinking';
        const duration = data.thinkingMetadata.duration || 0;
        titlePrefix = `${activity}... (${duration}s) `;
      }

      if (data.isLongRunningCompletion) {
        notification.alert = {
          title: `${titlePrefix}🎯 Task Completed${attachmentText}`,
          subtitle: data.projectName,
          body: this.truncateMessage(data.message, 150),
        };
        notification.sound = 'success.aiff'; // Different sound for completions
      } else {
        notification.alert = {
          title: `${titlePrefix}Claude Response Ready${attachmentText}`,
          subtitle: data.projectName,
          body: this.truncateMessage(data.message, 150),
        };
      }
      notification.topic = this.bundleId || process.env.APNS_BUNDLE_ID || 'com.claude.companion';

      // Set push type for proper routing (alert with content-available)
      notification.pushType = 'alert';
      notification.category = 'CLAUDE_RESPONSE';

      notification.payload = {
        sessionId: data.sessionId,
        projectName: data.projectName,
        projectPath: data.projectPath, // Full path needed for message persistence
        message: data.message, // Full Claude response content
        originalMessage: data.originalMessage, // Original user message for context
        totalChunks: data.totalChunks,
        timestamp: new Date().toISOString(),
        isLongRunningCompletion: data.isLongRunningCompletion || false,
        requestId: data.requestId,
        deepLink: `claude-companion://session/${data.sessionId}`,
        // Always APNS delivery method
        deliveryMethod: 'apns_primary',
        // Include attachment metadata if present
        attachmentInfo: data.attachmentInfo || null,
        // Include auto-response metadata if present
        autoResponse: data.autoResponse || null,
        // Include thinking metadata if present
        thinkingMetadata: data.thinkingMetadata || null,
      };

      // Set thread ID for conversation grouping
      notification.threadId = data.sessionId;

      // Add action buttons for long-running completions
      if (data.isLongRunningCompletion) {
        notification.mutableContent = 1;
        notification.category = 'TASK_COMPLETE';
      }

      // Send the notification with retry logic
      const result = await this.sendNotification(device.token, notification);

      if (result.success) {
        console.log(`✅ Push notification sent to client ${clientId}`);
        // Record telemetry
        getTelemetryService().recordMessageSent(clientId, 'push_notification', true);
      } else {
        console.error('❌ Push notification failed for client %s:', clientId, result.error);
        // Record telemetry
        getTelemetryService().recordMessageSent(clientId, 'push_notification', false);
      }
    } catch (error) {
      console.error('❌ Error sending push notification:', error);
    }
  }

  /**
   * Send a push notification for thinking/progress updates
   * @param {string} clientId - The device token or client ID
   * @param {Object} data - Progress data
   * @param {string} data.sessionId - The session ID
   * @param {string} data.activity - Current activity (Thinking, Creating, etc)
   * @param {number} data.duration - Duration in seconds
   * @param {number} data.tokenCount - Token count
   * @param {string} data.requestId - Request ID for tracking
   */
  async sendProgressNotification(clientId, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping');
      return;
    }

    const device = this.deviceTokens.get(clientId) || { token: clientId };

    try {
      const notification = new apn.Notification();

      // Configure as silent notification for progress updates
      notification.expiry = Math.floor(Date.now() / 1000) + 300; // 5 minutes
      notification.contentAvailable = true;
      notification.priority = 5; // Lower priority for progress

      // Silent notification - no alert
      notification.sound = null;

      notification.topic = this.bundleId || process.env.APNS_BUNDLE_ID || 'com.claude.companion';
      notification.pushType = 'background';
      notification.category = 'THINKING_PROGRESS';

      // Format token display
      const tokenText =
        data.tokenCount > 1000
          ? `${(data.tokenCount / 1000).toFixed(1)}k tokens`
          : `${data.tokenCount} tokens`;

      notification.payload = {
        sessionId: data.sessionId,
        activity: data.activity,
        duration: data.duration,
        tokenCount: data.tokenCount,
        tokenText,
        requestId: data.requestId,
        timestamp: new Date().toISOString(),
        type: 'thinkingProgress',
        isThinking: true,
      };

      notification.threadId = data.sessionId;

      // Send the notification
      const result = await this.sendNotification(device.token, notification);

      if (result.success) {
        console.log(`✅ Progress notification sent: ${data.activity} (${data.duration}s)`);
      } else {
        console.error('❌ Progress notification failed:', result.error);
      }
    } catch (error) {
      console.error('❌ Error sending progress notification:', error);
    }
  }

  /**
   * Send a push notification for auto-response control actions
   * @param {string} clientId - The device token or client ID
   * @param {Object} data - Control action data
   * @param {string} data.sessionId - The session ID
   * @param {string} data.action - The action (pause, resume, stop)
   * @param {string} data.reason - Optional reason for stop action
   * @param {string} data.requestId - Request ID for tracking
   */
  async sendAutoResponseControlNotification(clientId, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping');
      return;
    }

    const device = this.deviceTokens.get(clientId) || { token: clientId };

    try {
      const notification = new apn.Notification();

      // Configure the notification
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
        body: data.reason ? `Reason: ${data.reason}` : `Session: ${data.sessionId}`,
      };

      notification.topic = this.bundleId || process.env.APNS_BUNDLE_ID || 'com.claude.companion';
      notification.pushType = 'alert';
      notification.category = 'AUTO_RESPONSE_CONTROL';

      notification.payload = {
        sessionId: data.sessionId,
        action: data.action,
        reason: data.reason,
        requestId: data.requestId,
        timestamp: new Date().toISOString(),
        type: 'autoResponseControl',
      };

      notification.threadId = data.sessionId;

      // Send the notification
      const result = await this.sendNotification(device.token, notification);

      if (result.success) {
        console.log(`✅ Auto-response control notification sent: ${data.action}`);
      } else {
        console.error('❌ Auto-response control notification failed:', result.error);
      }
    } catch (error) {
      console.error('❌ Error sending auto-response control notification:', error);
    }
  }

  /**
   * Send a push notification for an error
   * @param {string} clientId - The WebSocket client ID
   * @param {Object} data - Error data
   */
  async sendErrorNotification(clientId, data) {
    if (!this.isConfigured) {
      return;
    }

    const device = this.deviceTokens.get(clientId);
    if (!device) {
      return;
    }

    try {
      const notification = new apn.Notification();

      notification.expiry = Math.floor(Date.now() / 1000) + 3600;
      notification.sound = 'default';
      notification.alert = {
        title: 'Claude Error',
        subtitle: data.projectName,
        body: data.error,
      };
      notification.topic = this.bundleId || process.env.APNS_BUNDLE_ID || 'com.claude.companion';
      notification.payload = {
        sessionId: data.sessionId,
        projectName: data.projectName,
        projectPath: data.projectPath,
        error: true,
        errorMessage: data.error,
        requestId: data.requestId,
        timestamp: new Date().toISOString(),
        deliveryMethod: 'apns_primary',
      };

      const result = await this.sendNotification(device.token, notification);

      if (!result.success) {
        console.error('❌ Error notification failed for client %s:', clientId, result.error);
      }
    } catch (error) {
      console.error('Error sending error notification:', error);
    }
  }

  /**
   * Send notification to multiple clients (e.g., for long-running task completion)
   * @param {Array<string>} clientIds - Array of client IDs
   * @param {Object} data - Notification data
   * @returns {Object} - Summary of send results
   */
  async sendToMultipleClients(clientIds, data) {
    if (!this.isConfigured || !clientIds || clientIds.length === 0) {
      return { sent: 0, failed: 0 };
    }

    const results = { sent: 0, failed: 0 };

    // Send notifications in parallel with concurrency limit
    const concurrencyLimit = 10;
    const chunks = [];

    for (let i = 0; i < clientIds.length; i += concurrencyLimit) {
      chunks.push(clientIds.slice(i, i + concurrencyLimit));
    }

    for (const chunk of chunks) {
      const promises = chunk.map(async (clientId) => {
        try {
          await this.sendClaudeResponseNotification(clientId, data);
          results.sent++;
        } catch (error) {
          console.error(`Failed to send notification to ${clientId}:`, error);
          results.failed++;
        }
      });

      await Promise.all(promises);
    }

    console.log(
      `🔔 Sent push notifications to ${results.sent} devices for ${data.isLongRunningCompletion ? 'long-running task completion' : 'Claude response'}`
    );

    return results;
  }

  /**
   * Get notification statistics
   * @returns {Object} - Statistics about notifications
   */
  getStats() {
    return {
      configuredDevices: this.deviceTokens.size,
      badTokens: this.badTokens.size,
      isConfigured: this.isConfigured,
      retryingTokens: this.tokenRetryCount.size,
    };
  }

  /**
   * Strip markdown formatting from text for cleaner notification display
   * @param {string} text - The text to clean
   * @returns {string} - Clean text without markdown
   */
  stripMarkdown(text) {
    if (!text) return '';

    let cleanText = text;

    // Remove code blocks first (both backtick and indented)
    cleanText = cleanText.replace(/```[\s\S]*?```/g, '[code block]');
    cleanText = cleanText.replace(/`([^`]+)`/g, '$1');

    // Remove images
    cleanText = cleanText.replace(/!\[([^\]]*)\]\([^)]+\)/g, '[image: $1]');

    // Remove links but keep text
    cleanText = cleanText.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');

    // Remove headers
    cleanText = cleanText.replace(/^#{1,6}\s+(.+)$/gm, '$1');

    // Remove bold/italic markers
    cleanText = cleanText.replace(/(\*\*|__)(.*?)\1/g, '$2');
    cleanText = cleanText.replace(/(\*|_)(.*?)\1/g, '$2');

    // Remove blockquotes
    cleanText = cleanText.replace(/^>\s+(.+)$/gm, '$1');

    // Remove horizontal rules
    cleanText = cleanText.replace(/^[-*_]{3,}$/gm, '');

    // Remove list markers
    cleanText = cleanText.replace(/^[\s]*[-*+]\s+(.+)$/gm, '$1');
    cleanText = cleanText.replace(/^[\s]*\d+\.\s+(.+)$/gm, '$1');

    // Clean up extra whitespace
    cleanText = cleanText.replace(/\n{3,}/g, '\n\n');
    cleanText = cleanText.trim();

    return cleanText;
  }

  /**
   * Truncate a message for notification display
   * @param {string} message - The message to truncate
   * @param {number} maxLength - Maximum length
   * @returns {string} - Truncated message
   */
  truncateMessage(message, maxLength = 150) {
    if (!message) return '';

    // First strip markdown formatting
    const cleanMessage = this.stripMarkdown(message);

    if (cleanMessage.length <= maxLength) {
      return cleanMessage;
    }

    // Try to truncate at a word boundary
    const truncated = cleanMessage.substring(0, maxLength);
    const lastSpace = truncated.lastIndexOf(' ');

    if (lastSpace > maxLength * 0.8) {
      return `${truncated.substring(0, lastSpace)}...`;
    }

    return `${truncated}...`;
  }

  /**
   * Shutdown the service
   */
  shutdown() {
    if (this.provider) {
      this.provider.shutdown();
      console.log('📱 Push notification service shut down');
    }
  }
}

// Export singleton instance
export const pushNotificationService = new PushNotificationService();

// Export class for testing
export { PushNotificationService };
