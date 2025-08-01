import apn from '@parse/node-apn';
import fs from 'fs';

class PushNotificationService {
  constructor() {
    this.provider = null;
    this.deviceTokens = new Map(); // Map clientId -> { token, platform }
    this.isConfigured = false;
  }

  /**
   * Initialize the push notification service
   * @param {Object} config - Configuration object
   * @param {string} config.cert - Path to the certificate file
   * @param {string} config.key - Path to the key file
   * @param {string} config.passphrase - Passphrase for the key
   * @param {boolean} config.production - Whether to use production environment
   */
  initialize(config = {}) {
    try {
      // Check if we have the required configuration
      const certPath = config.cert || process.env.APNS_CERT_PATH;
      const keyPath = config.key || process.env.APNS_KEY_PATH;
      const passphrase = config.passphrase || process.env.APNS_PASSPHRASE;
      const production = config.production || process.env.NODE_ENV === 'production';

      if (!certPath || !keyPath) {
        console.log('⚠️  Push notifications not configured - missing certificate or key path');
        return;
      }

      // Check if files exist
      if (!fs.existsSync(certPath) || !fs.existsSync(keyPath)) {
        console.log('⚠️  Push notification certificate or key file not found');
        return;
      }

      // Create APN provider
      const options = {
        cert: certPath,
        key: keyPath,
        production,
      };

      if (passphrase) {
        options.passphrase = passphrase;
      }

      this.provider = new apn.Provider(options);
      this.isConfigured = true;

      console.log(
        `✅ Push notification service initialized (${production ? 'production' : 'development'} mode)`
      );
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
      notification.topic = process.env.APNS_BUNDLE_ID || 'com.claude.companion';
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

      // Send the notification
      const result = await this.provider.send(notification, device.token);

      if (result.sent.length > 0) {
        console.log(`✅ Push notification sent to client ${clientId}`);
      }

      if (result.failed.length > 0) {
        console.error('❌ Push notification failed:', result.failed[0]);
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
      notification.topic = process.env.APNS_BUNDLE_ID || 'com.claude.companion';
      notification.payload = {
        sessionId: data.sessionId,
        error: true,
      };

      await this.provider.send(notification, device.token);
    } catch (error) {
      console.error('Error sending error notification:', error);
    }
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
