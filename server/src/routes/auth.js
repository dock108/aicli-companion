import express from 'express';
import QRCode from 'qrcode';
import { createLogger } from '../utils/logger.js';
import os from 'os';

const router = express.Router();
const logger = createLogger('AuthRoutes');

/**
 * Get network interfaces to find local IP addresses
 */
function getLocalIPAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];

  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      // Skip internal (127.0.0.1) and non-IPv4 addresses
      if (iface.family === 'IPv4' && !iface.internal) {
        addresses.push({
          name,
          address: iface.address,
        });
      }
    }
  }

  return addresses;
}

/**
 * GET /api/auth/setup
 * Generate QR code for mobile app connection
 */
router.get('/setup', async (req, res) => {
  try {
    const authRequired = req.app.locals.authRequired !== false;
    const authToken = req.app.locals.authToken;
    const port = req.app.locals.port || 3001;
    const enableTLS = req.app.locals.enableTLS || false;

    // Get local IP addresses
    const addresses = getLocalIPAddresses();
    const primaryAddress = addresses[0]?.address || 'localhost';

    // Build connection URL
    const protocol = enableTLS ? 'https' : 'http';
    let connectionUrl = `${protocol}://${primaryAddress}:${port}`;

    if (authRequired && authToken) {
      connectionUrl += `?token=${authToken}`;
    }

    // Generate QR code
    const qrCodeDataUrl = await QRCode.toDataURL(connectionUrl, {
      errorCorrectionLevel: 'M',
      type: 'image/png',
      quality: 0.92,
      margin: 1,
      color: {
        dark: '#000000',
        light: '#FFFFFF',
      },
      width: 256,
    });

    // Generate SVG as alternative
    const qrCodeSvg = await QRCode.toString(connectionUrl, {
      errorCorrectionLevel: 'M',
      type: 'svg',
      margin: 1,
      color: {
        dark: '#000000',
        light: '#FFFFFF',
      },
      width: 256,
    });

    res.json({
      success: true,
      connectionInfo: {
        url: connectionUrl,
        host: primaryAddress,
        port,
        protocol,
        authRequired,
        hasToken: !!authToken,
      },
      qrCode: {
        dataUrl: qrCodeDataUrl,
        svg: qrCodeSvg,
      },
      availableAddresses: addresses.map((a) => ({
        interface: a.name,
        address: a.address,
        url: `${protocol}://${a.address}:${port}${authRequired && authToken ? `?token=${authToken}` : ''}`,
      })),
    });
  } catch (error) {
    logger.error('Failed to generate QR code', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate QR code',
      message: error.message,
    });
  }
});

/**
 * GET /api/auth/status
 * Check authentication status
 */
router.get('/status', (req, res) => {
  const authRequired = req.app.locals.authRequired !== false;
  const hasToken = !!req.app.locals.authToken;

  res.json({
    authRequired,
    hasToken,
    authenticated:
      !authRequired || req.headers.authorization === `Bearer ${req.app.locals.authToken}`,
  });
});

export default router;
