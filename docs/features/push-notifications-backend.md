# Push Notifications Setup Guide

This guide explains how to set up Apple Push Notification Service (APNS) for Claude Companion.

## Prerequisites

1. Apple Developer Account
2. iOS app running on a real device (push notifications don't work on simulator)
3. Valid APNS certificates

## Setup Steps

### 1. Generate APNS Certificates

1. Log in to [Apple Developer Portal](https://developer.apple.com)
2. Navigate to Certificates, Identifiers & Profiles
3. Create a new Push Notification SSL Certificate for your app
4. Download the certificate and export it as .pem files

### 2. Configure Server Environment

Create a `.env` file in the server directory with:

```bash
# Copy from .env.example
cp .env.example .env
```

Edit `.env` and add your APNS configuration:

```env
# Apple Push Notification Service (APNS)
APNS_CERT_PATH=./certs/apns-cert.pem
APNS_KEY_PATH=./certs/apns-key.pem
APNS_PASSPHRASE=your-passphrase-here
APNS_BUNDLE_ID=com.yourcompany.claudecompanion
```

### 3. Install APNS Certificates

Create a certs directory and add your certificates:

```bash
mkdir -p certs
cp /path/to/your/apns-cert.pem certs/
cp /path/to/your/apns-key.pem certs/
```

### 4. Test Push Notifications

1. Run the iOS app on a real device
2. Look for the device token in the Xcode console (starts with "📱 Device token:")
3. Test notifications:

```bash
node test-push-notification.js YOUR_DEVICE_TOKEN_HERE
```

## How It Works

1. **Device Registration**: When the iOS app launches, it registers for remote notifications and sends the device token to the server
2. **Token Storage**: Server stores device tokens mapped to client IDs in memory
3. **Notification Trigger**: When Claude finishes responding, the server sends a push notification
4. **Delivery**: APNS delivers the notification to the device

## Troubleshooting

### Common Issues

1. **"No registered device token"**
   - Ensure the iOS app successfully registered and sent the token
   - Check server logs for device registration messages

2. **Certificate errors**
   - Verify certificate paths are correct
   - Ensure certificates are in .pem format
   - Check certificate isn't expired

3. **Notifications not received**
   - Confirm testing on real device (not simulator)
   - Check notification permissions in iOS Settings
   - Verify bundle ID matches between server and app

### Debug Mode

Enable debug logging in the server:

```javascript
// In push-notification.js
this.provider = new apn.Provider({
    cert: process.env.APNS_CERT_PATH,
    key: process.env.APNS_KEY_PATH,
    passphrase: process.env.APNS_PASSPHRASE,
    production: process.env.NODE_ENV === 'production',
    // Add debug logging
    connectionRetryLimit: 10,
    debug: true
});
```

## Production Considerations

1. **Token Management**: Implement persistent storage for device tokens (Redis, database)
2. **Token Validation**: Handle invalid/expired tokens gracefully
3. **Rate Limiting**: Implement notification throttling to avoid overwhelming users
4. **Analytics**: Track notification delivery and engagement
5. **Silent Notifications**: Consider using background notifications for updates

## Security

- Keep APNS certificates secure and never commit them to version control
- Use environment variables for all sensitive configuration
- Implement authentication for device registration endpoints
- Validate and sanitize notification content