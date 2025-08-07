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
      const production = config.production || process.env.NODE_ENV === 'production';

      if (!keyPath || !keyId || !teamId) {
        console.log('⚠️  Push notifications not configured - missing keyPath, keyId, or teamId');
        console.log('   Required env vars: APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID');
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
          key: keyPath,  // Path to .p8 file
          keyId: keyId,   // Key ID from Apple Developer Portal
          teamId: teamId  // Team ID from Apple Developer Portal
        },
        production: production
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
   * @param {string} clientId - The WebSocket client ID
   * @param {string} token - The device push token
   * @param {string} platform - The platform (ios, android)
   */
  registerDevice(clientId, token, platform = 'ios') {
    if (!token || !clientId) {
      console.warn('⚠️  Cannot register device - missing token or clientId');
      return;
    }

    this.deviceTokens.set(clientId, { token, platform });
    console.log(`📱 Registered device token for client ${clientId} (${platform})`);
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
      notification.badge = 1;
      notification.sound = 'default';

      // Customize notification based on context
      if (data.isLongRunningCompletion) {
        notification.alert = {
          title: '🎯 Task Completed',
          subtitle: data.projectName,
          body: this.truncateMessage(data.message, 150),
        };
        notification.sound = 'success.aiff'; // Different sound for completions
      } else {
        notification.alert = {
          title: 'Claude Response Ready',
          subtitle: data.projectName,
          body: this.truncateMessage(data.message, 150),
        };
      }
      notification.topic = this.bundleId || process.env.APNS_BUNDLE_ID || 'com.claude.companion';
      notification.payload = {
        sessionId: data.sessionId,
        projectName: data.projectName,
        totalChunks: data.totalChunks,
        timestamp: new Date().toISOString(),
        isLongRunningCompletion: data.isLongRunningCompletion || false,
        deepLink: `claude-companion://session/${data.sessionId}`,
      };
      notification.pushType = 'alert';
      notification.category = 'CLAUDE_RESPONSE';

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
        error: true,
      };

      const result = await this.sendNotification(device.token, notification);

      if (!result.success) {
        console.error(`❌ Error notification failed for client ${clientId}:`, result.error);
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
   * Truncate a message for notification display
   * @param {string} message - The message to truncate
   * @param {number} maxLength - Maximum length
   * @returns {string} - Truncated message
   */
  truncateMessage(message, maxLength = 150) {
    if (!message || message.length <= maxLength) {
      return message || '';
    }
    return `${message.substring(0, maxLength)}...`;
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
