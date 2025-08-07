import express from 'express';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('DevicesAPI');
// TODO: Check what validation middleware exists
// import { validateRequest } from '../middleware/validation.js';
import { pushNotificationService } from '../services/push-notification.js';

const router = express.Router();

/**
 * POST /api/devices/register - Register device for push notifications
 */
router.post('/register', async (req, res) => {
  const { deviceToken, platform = 'ios', bundleId } = req.body;
  
  if (!deviceToken) {
    return res.status(400).json({
      success: false,
      error: 'Device token is required'
    });
  }

  const deviceId = req.headers['x-device-id'] || `device_${Date.now()}`;
  
  logger.info('Registering device for push notifications', {
    deviceId,
    platform,
    bundleId,
    tokenLength: deviceToken.length
  });

  try {
    // Register device token with push notification service
    await pushNotificationService.registerDevice(deviceId, {
      token: deviceToken,
      platform,
      bundleId,
      registeredAt: new Date()
    });

    logger.info('Device registered successfully', { deviceId });

    res.json({
      success: true,
      deviceId,
      message: 'Device registered for push notifications',
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Device registration failed', { 
      deviceId,
      error: error.message 
    });

    res.status(500).json({
      success: false,
      error: 'Failed to register device'
    });
  }
});

/**
 * DELETE /api/devices/:deviceId - Unregister device
 */
router.delete('/:deviceId', async (req, res) => {
  const { deviceId } = req.params;
  
  logger.info('Unregistering device', { deviceId });

  try {
    await pushNotificationService.unregisterDevice(deviceId);

    res.json({
      success: true,
      message: 'Device unregistered',
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    logger.error('Device unregistration failed', { 
      deviceId,
      error: error.message 
    });

    res.status(500).json({
      success: false,
      error: 'Failed to unregister device'
    });
  }
});

/**
 * POST /api/devices/test-push - Test push notification
 */
router.post('/test-push', async (req, res) => {
  const { deviceToken, message = 'Test notification from Claude Companion' } = req.body;
  
  if (!deviceToken) {
    return res.status(400).json({
      success: false,
      error: 'Device token is required'
    });
  }

  logger.info('Sending test push notification');

  try {
    const result = await pushNotificationService.sendPushNotification(deviceToken, {
      message,
      title: 'Test Notification',
      data: { test: true }
    });

    res.json({
      success: result.success,
      message: result.success ? 'Test notification sent' : 'Test notification failed',
      error: result.error || null
    });

  } catch (error) {
    logger.error('Test push notification failed', { error: error.message });

    res.status(500).json({
      success: false,
      error: 'Failed to send test notification'
    });
  }
});

export default router;