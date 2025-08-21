import express from 'express';
import QRCode from 'qrcode';
import { createLogger } from '../utils/logger.js';
import { tunnelService } from '../services/tunnel.js';
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

    let connectionUrl;
    let primaryAddress;
    let protocol;

    // Get local addresses for fallback and alternative connections
    const addresses = getLocalIPAddresses();

    // Check if tunnel is active - PRIORITIZE TUNNEL URL
    const tunnelUrl = tunnelService.getPublicUrl();
    if (tunnelUrl) {
      // Use tunnel URL when available
      connectionUrl = tunnelUrl;
      protocol = tunnelUrl.startsWith('https') ? 'https' : 'http';

      // Extract host from tunnel URL for display
      try {
        const url = new URL(tunnelUrl);
        primaryAddress = url.host;
      } catch (e) {
        primaryAddress = tunnelUrl.replace(/^https?:\/\//, '').split('/')[0];
      }

      logger.info('Using tunnel URL for QR code', { tunnelUrl, authRequired });
    } else {
      // Fall back to local IP addresses only if no tunnel
      primaryAddress = addresses[0]?.address || 'localhost';
      protocol = enableTLS ? 'https' : 'http';
      connectionUrl = `${protocol}://${primaryAddress}:${port}`;

      logger.info('Using local IP for QR code', { primaryAddress, port });
    }

    // Add auth token as query parameter if required
    if (authRequired && authToken) {
      // Properly handle existing query parameters in tunnel URLs
      const separator = connectionUrl.includes('?') ? '&' : '?';
      connectionUrl += `${separator}token=${authToken}`;
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
      availableAddresses: tunnelUrl
        ? [
            {
              interface: 'tunnel',
              address: primaryAddress,
              url: connectionUrl,
            },
          ]
        : addresses.map((a) => ({
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
