/**
 * Security API Routes
 * 
 * Provides endpoints for:
 * - Viewing current security configuration
 * - Updating security settings
 * - Viewing audit logs
 * - Testing command validation
 */

import express from 'express';
import { commandSecurity } from '../services/command-security.js';
import { createLogger } from '../utils/logger.js';

const router = express.Router();
const logger = createLogger('SecurityAPI');

/**
 * GET /api/security/settings
 * Get current security configuration
 */
router.get('/settings', (req, res) => {
  try {
    const config = commandSecurity.getConfig();
    
    res.json({
      success: true,
      config
    });
  } catch (error) {
    logger.error('Failed to get security settings', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve security settings'
    });
  }
});

/**
 * PUT /api/security/settings
 * Update security configuration
 * Requires authentication if AUTH_REQUIRED is true
 */
router.put('/settings', (req, res) => {
  try {
    const {
      preset,
      safeDirectories,
      blockedCommands,
      destructiveCommands,
      requireConfirmation,
      maxFileSize,
      readOnlyMode,
      enableAudit
    } = req.body;
    
    // Build update object with only provided fields
    const updates = {};
    if (preset !== undefined) updates.preset = preset;
    if (safeDirectories !== undefined) updates.safeDirectories = safeDirectories;
    if (blockedCommands !== undefined) updates.blockedCommands = blockedCommands;
    if (destructiveCommands !== undefined) updates.destructiveCommands = destructiveCommands;
    if (requireConfirmation !== undefined) updates.requireConfirmation = requireConfirmation;
    if (maxFileSize !== undefined) updates.maxFileSize = maxFileSize;
    if (readOnlyMode !== undefined) updates.readOnlyMode = readOnlyMode;
    if (enableAudit !== undefined) updates.enableAudit = enableAudit;
    
    // Update configuration
    commandSecurity.updateConfig(updates);
    
    logger.info('Security configuration updated', { updates });
    
    res.json({
      success: true,
      message: 'Security configuration updated',
      config: commandSecurity.getConfig()
    });
  } catch (error) {
    logger.error('Failed to update security settings', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to update security settings'
    });
  }
});

/**
 * GET /api/security/audit
 * Get security audit log
 * Query params:
 * - limit: Number of entries to return (default: 100)
 * - sessionId: Filter by session ID
 * - allowed: Filter by allowed/denied (true/false)
 */
router.get('/audit', (req, res) => {
  try {
    const { limit = 100, sessionId, allowed } = req.query;
    
    const options = {
      limit: parseInt(limit),
      sessionId,
      allowed: allowed === 'true' ? true : allowed === 'false' ? false : undefined
    };
    
    const auditLog = commandSecurity.getAuditLog(options);
    
    res.json({
      success: true,
      count: auditLog.length,
      entries: auditLog
    });
  } catch (error) {
    logger.error('Failed to get audit log', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve audit log'
    });
  }
});

/**
 * DELETE /api/security/audit
 * Clear the audit log
 * Requires authentication
 */
router.delete('/audit', (req, res) => {
  try {
    const count = commandSecurity.clearAuditLog();
    
    logger.info('Audit log cleared', { entriesRemoved: count });
    
    res.json({
      success: true,
      message: 'Audit log cleared',
      entriesRemoved: count
    });
  } catch (error) {
    logger.error('Failed to clear audit log', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to clear audit log'
    });
  }
});

/**
 * POST /api/security/test
 * Test if a command would be allowed
 * Body:
 * - command: The command to test
 * - workingDirectory: The working directory (optional)
 */
router.post('/test', async (req, res) => {
  try {
    const { command, workingDirectory = process.cwd() } = req.body;
    
    if (!command) {
      return res.status(400).json({
        success: false,
        error: 'Command is required'
      });
    }
    
    const result = await commandSecurity.testCommand(command, workingDirectory);
    
    res.json({
      success: true,
      command,
      workingDirectory,
      ...result
    });
  } catch (error) {
    logger.error('Failed to test command', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to test command'
    });
  }
});

/**
 * GET /api/security/permissions
 * Get pending permission requests
 */
router.get('/permissions', (req, res) => {
  try {
    const pending = commandSecurity.getPendingPermissions();
    
    res.json({
      success: true,
      count: pending.length,
      permissions: pending
    });
  } catch (error) {
    logger.error('Failed to get pending permissions', { error: error.message });
    res.status(500).json({
      success: false,
      error: 'Failed to retrieve pending permissions'
    });
  }
});

/**
 * POST /api/security/permissions/:id/approve
 * Approve a permission request
 */
router.post('/permissions/:id/approve', (req, res) => {
  try {
    const { id } = req.params;
    
    const request = commandSecurity.approvePermission(id);
    
    logger.info('Permission approved', { requestId: id });
    
    res.json({
      success: true,
      message: 'Permission approved',
      request
    });
  } catch (error) {
    logger.error('Failed to approve permission', { error: error.message });
    res.status(404).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * POST /api/security/permissions/:id/deny
 * Deny a permission request
 */
router.post('/permissions/:id/deny', (req, res) => {
  try {
    const { id } = req.params;
    const { reason } = req.body;
    
    const request = commandSecurity.denyPermission(id, reason);
    
    logger.info('Permission denied', { requestId: id, reason });
    
    res.json({
      success: true,
      message: 'Permission denied',
      request
    });
  } catch (error) {
    logger.error('Failed to deny permission', { error: error.message });
    res.status(404).json({
      success: false,
      error: error.message
    });
  }
});

/**
 * GET /api/security/presets
 * Get available security presets
 */
router.get('/presets', (req, res) => {
  res.json({
    success: true,
    presets: [
      {
        name: 'unrestricted',
        description: 'No restrictions - full access (current behavior)',
        settings: {
          blockedCommands: [],
          requireConfirmation: false,
          readOnlyMode: false
        }
      },
      {
        name: 'standard',
        description: 'Balanced security - blocks dangerous commands',
        settings: {
          blockedCommands: ['rm -rf /', 'format', 'diskutil eraseDisk'],
          requireConfirmation: true,
          readOnlyMode: false
        }
      },
      {
        name: 'restricted',
        description: 'High security - read-only with minimal tools',
        settings: {
          blockedCommands: ['*'],
          requireConfirmation: true,
          readOnlyMode: true
        }
      },
      {
        name: 'custom',
        description: 'User-defined security settings',
        settings: {}
      }
    ]
  });
});

export default router;