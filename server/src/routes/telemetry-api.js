import express from 'express';
import { getTelemetryService } from '../services/telemetry.js';
import { authenticate } from '../middleware/auth.js';

const router = express.Router();

/**
 * GET /api/telemetry
 * Get current telemetry metrics
 */
router.get('/api/telemetry', authenticate, (req, res) => {
  try {
    const metrics = getTelemetryService().getMetrics();
    res.json(metrics);
  } catch (error) {
    console.error('Error fetching telemetry:', error);
    res.status(500).json({
      error: 'Failed to fetch telemetry',
      message: error.message,
    });
  }
});

/**
 * GET /api/telemetry/connection/:clientId
 * Get connection-specific metrics
 */
router.get('/api/telemetry/connection/:clientId', authenticate, (req, res) => {
  try {
    const { clientId } = req.params;
    const metrics = getTelemetryService().getConnectionMetrics(clientId);

    if (!metrics) {
      return res.status(404).json({
        error: 'Connection not found',
        clientId,
      });
    }

    res.json(metrics);
  } catch (error) {
    console.error('Error fetching connection telemetry:', error);
    res.status(500).json({
      error: 'Failed to fetch connection telemetry',
      message: error.message,
    });
  }
});

/**
 * POST /api/telemetry/reset
 * Reset telemetry metrics (admin only)
 *
 * TODO: [QUESTION] Should this be restricted to admin users only?
 * Currently protected by authentication, but may need additional authorization
 */
router.post('/api/telemetry/reset', authenticate, (req, res) => {
  try {
    getTelemetryService().reset();
    res.json({
      success: true,
      message: 'Telemetry metrics reset',
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Error resetting telemetry:', error);
    res.status(500).json({
      error: 'Failed to reset telemetry',
      message: error.message,
    });
  }
});

export default router;
