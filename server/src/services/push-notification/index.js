/**
 * Main Push Notification Service
 * Coordinates APNs client, message formatting, and device management
 */

import { EventEmitter } from 'events';
import { randomUUID } from 'crypto';
import { APNsClient } from './apns-client.js';
import { MessageFormatter } from './message-formatter.js';
import { NotificationTypes } from './notification-types.js';
import { getTelemetryService } from '../telemetry.js';
import { storeMessage } from '../../routes/messages.js';

export class PushNotificationService extends EventEmitter {
  constructor() {
    super();
    this.apnsClient = new APNsClient();
    this.messageFormatter = new MessageFormatter();
    this.notificationTypes = new NotificationTypes();
    this.deviceTokens = new Map(); // Map clientId -> { token, platform }
    this.isConfigured = false;
    this.badTokens = new Set(); // Track bad tokens
    this.tokenRetryCount = new Map(); // Track retry attempts per token
  }

  /**
   * Initialize the push notification service
   */
  initialize(config = {}) {
    this.apnsClient.initialize(config);
    this.isConfigured = this.apnsClient.isConfigured;
  }

  /**
   * Register a device token for a client
   */
  registerDevice(clientId, tokenOrDevice, platform = 'ios') {
    let token, devicePlatform;

    // Handle both new API (object) and old API (string) for compatibility
    if (tokenOrDevice && typeof tokenOrDevice === 'object') {
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
   */
  unregisterDevice(clientId) {
    if (this.deviceTokens.has(clientId)) {
      this.deviceTokens.delete(clientId);
      console.log(`📱 Unregistered device token for client ${clientId}`);
    }
  }

  /**
   * Send a notification with retry logic
   */
  async sendNotification(deviceToken, notification, options = {}) {
    const maxRetries = options.retries || 3;
    const retryDelay = options.retryDelay || 1000;

    // Check if token is known bad
    if (this.badTokens.has(deviceToken)) {
      console.log(`⚠️ Skipping known bad token: ${deviceToken.substring(0, 10)}...`);
      return { success: false, error: 'BadDeviceToken' };
    }

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        const result = await this.apnsClient.send(notification, deviceToken);

        if (result.success) {
          // Reset retry count on success
          this.tokenRetryCount.delete(deviceToken);
          return result;
        }

        // Handle specific error cases
        if (result.error === 'BadDeviceToken') {
          await this.handleBadToken(deviceToken);
          return { success: false, error: 'BadDeviceToken' };
        }

        if (result.error === 'ExpiredProviderToken') {
          console.error('⚠️ Provider token expired - requires service restart');
          return { success: false, error: 'ExpiredProviderToken' };
        }

        // For other errors, continue retrying
        console.warn(`Push notification attempt ${attempt} failed:`, result.error);

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
  }

  /**
   * Send a generic push notification to a device token
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
      const notification = this.notificationTypes.createGenericNotification(data);
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
      // Check if message requires fetching (large message)
      const requiresFetch = this.messageFormatter.requiresFetch(data.message);

      let messageId = data.messageId;
      if (requiresFetch && !messageId) {
        messageId = randomUUID();
        // Store the full message
        storeMessage(messageId, data.message, {
          projectPath: data.projectPath,
          projectName: data.projectName,
          requestId: data.requestId,
        });
      }

      const notification = this.notificationTypes.createClaudeResponseNotification(data, {
        requiresFetch,
        messageId,
      });

      const result = await this.sendNotification(device.token, notification);

      if (result.success) {
        console.log(`✅ Push notification sent to client ${clientId}`);
        getTelemetryService().recordMessageSent(clientId, 'push_notification', true);
      } else {
        console.error('❌ Push notification failed for client %s:', clientId, result.error);
        getTelemetryService().recordMessageSent(clientId, 'push_notification', false);
      }
    } catch (error) {
      console.error('❌ Error sending push notification:', error);
    }
  }

  /**
   * Send a push notification for thinking/progress updates
   */
  async sendProgressNotification(clientId, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping');
      return;
    }

    const device = this.deviceTokens.get(clientId) || { token: clientId };

    try {
      const notification = this.notificationTypes.createProgressNotification(data);
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
   */
  async sendAutoResponseControlNotification(clientId, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping');
      return;
    }

    const device = this.deviceTokens.get(clientId) || { token: clientId };

    try {
      const notification = this.notificationTypes.createAutoResponseControlNotification(data);
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
   * Send a push notification for Claude stall detection
   */
  async sendStallAlert(deviceToken, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping stall alert');
      return { success: false, error: 'Not configured' };
    }

    if (!deviceToken) {
      return { success: false, error: 'No device token provided' };
    }

    try {
      const notification = this.notificationTypes.createStallAlert(data);
      const result = await this.sendNotification(deviceToken, notification, {
        retries: 2,
        retryDelay: 500,
      });

      if (result.success) {
        console.log(
          `✅ Stall alert sent for session ${data.sessionId} (${data.silentMinutes} minutes silent)`
        );
      } else {
        console.error('❌ Stall alert failed for session %s:', data.sessionId, result.error);
      }

      return result;
    } catch (error) {
      console.error('❌ Error sending stall alert:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Send a message notification with structured data
   */
  async sendMessageNotification(deviceToken, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping message notification');
      return { success: false, error: 'Not configured' };
    }

    if (!deviceToken) {
      return { success: false, error: 'No device token provided' };
    }

    try {
      const notification = this.notificationTypes.createMessageNotification(data);
      const result = await this.sendNotification(deviceToken, notification);

      if (result.success) {
        console.log(`✅ Message notification sent for session ${data.sessionId}`);
      } else {
        console.error(`❌ Message notification failed:`, result.error);
      }

      return result;
    } catch (error) {
      console.error('❌ Error sending message notification:', error);
      return { success: false, error: error.message };
    }
  }

  /**
   * Send a push notification for an error
   */
  async sendErrorNotification(clientId, data) {
    if (!this.isConfigured) {
      console.log('⚠️  Push notifications not configured - skipping error notification');
      return;
    }

    const device = this.deviceTokens.get(clientId) || { token: clientId };
    if (!device.token) {
      console.log(`⚠️  No device token found for client ${clientId}`);
      return;
    }

    try {
      const notification = this.notificationTypes.createErrorNotification(data);
      const result = await this.sendNotification(device.token, notification);

      if (result.success) {
        console.log(`✅ Error notification sent to client ${clientId} (${data.errorType})`);
      } else {
        console.error('❌ Error notification failed for client %s:', clientId, result.error);
      }
    } catch (error) {
      console.error('Error sending error notification:', error);
    }
  }

  /**
   * Send notification to multiple clients
   */
  async sendToMultipleClients(clientIds, data) {
    if (!this.isConfigured || !clientIds || clientIds.length === 0) {
      return { sent: 0, failed: 0 };
    }

    const results = { sent: 0, failed: 0 };
    const concurrencyLimit = 10;
    const chunks = [];

    for (let i = 0; i < clientIds.length; i += concurrencyLimit) {
      chunks.push(clientIds.slice(i, i + concurrencyLimit));
    }

    for (const chunk of chunks) {
      const promises = chunk.map(async (clientId) => {
        try {
          const device = this.deviceTokens.get(clientId);
          if (!device || !device.token) {
            console.log(`⚠️  No device token found for client ${clientId}`);
            results.failed++;
            return;
          }

          // Check if message requires fetching (large message)
          const requiresFetch = this.messageFormatter.requiresFetch(data.message);
          let messageId = data.messageId;
          if (requiresFetch && !messageId) {
            messageId = randomUUID();
            // Store the full message
            storeMessage(messageId, data.message, {
              projectPath: data.projectPath,
              projectName: data.projectName,
              requestId: data.requestId,
            });
          }

          const notification = this.notificationTypes.createClaudeResponseNotification(data, {
            requiresFetch,
            messageId,
          });

          const result = await this.sendNotification(device.token, notification);
          
          if (result.success) {
            results.sent++;
            console.log(`✅ Push notification sent to client ${clientId}`);
          } else {
            results.failed++;
            console.error('❌ Push notification failed for client %s:', clientId, result.error);
          }
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
   * Shutdown the service
   */
  shutdown() {
    if (this.apnsClient) {
      this.apnsClient.shutdown();
      console.log('📱 Push notification service shut down');
    }
  }
}

// Export singleton instance
export const pushNotificationService = new PushNotificationService();

// Export class for testing
export { PushNotificationService as default };
