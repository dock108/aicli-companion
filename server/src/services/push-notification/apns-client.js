/**
 * APNs HTTP/2 Client Wrapper
 * Handles Apple Push Notification service connections and provider management
 */

import apn from '@parse/node-apn';
import fs from 'fs';

export class APNsClient {
  constructor() {
    this.provider = null;
    this.bundleId = null;
    this.isConfigured = false;
  }

  /**
   * Initialize the APNs provider with HTTP/2 API (.p8 key)
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
   * Send a notification via APNs
   */
  async send(notification, deviceToken) {
    if (!this.provider) {
      throw new Error('APNs provider not initialized');
    }

    const result = await this.provider.send(notification, deviceToken);

    if (result.sent.length > 0) {
      return { success: true, result };
    }

    // Handle specific error cases
    if (result.failed.length > 0) {
      const failure = result.failed[0];
      const reason = failure.response?.reason;

      if (reason === 'BadDeviceToken') {
        return { success: false, error: 'BadDeviceToken' };
      }

      if (reason === 'ExpiredProviderToken') {
        return { success: false, error: 'ExpiredProviderToken' };
      }

      return { success: false, error: reason || 'Unknown error' };
    }

    return { success: false, error: 'No sent or failed results' };
  }

  /**
   * Get the configured bundle ID
   */
  getBundleId() {
    return this.bundleId || process.env.APNS_BUNDLE_ID || 'com.aiclicompanion.ios';
  }

  /**
   * Shutdown the provider
   */
  shutdown() {
    if (this.provider) {
      this.provider.shutdown();
    }
  }
}
