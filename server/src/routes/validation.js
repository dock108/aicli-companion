/**
 * Validation API Routes
 * Handles planning validation and requirement analysis
 */

import express from 'express';
import { createLogger } from '../utils/logger.js';
import { planningValidator } from '../services/planning-validator.js';
import { requirementsAnalyzer } from '../services/requirements-analyzer.js';

const router = express.Router();
const logger = createLogger('ValidationAPI');

/**
 * Setup validation routes
 * @param {express.Application} app - Express application
 */
export function setupValidationRoutes(app) {
  /**
   * POST /api/validation/session
   * Initialize a new validation session
   */
  router.post('/validation/session', async (req, res) => {
    try {
      const { sessionId, projectType } = req.body;
      
      if (!sessionId) {
        return res.status(400).json({
          error: 'Missing session ID',
          message: 'Session ID is required to initialize validation'
        });
      }
      
      planningValidator.initializeSession(sessionId, projectType);
      
      res.json({
        success: true,
        sessionId,
        projectType: projectType || 'web-app',
        message: 'Validation session initialized'
      });
    } catch (error) {
      logger.error('Failed to initialize validation session', { error: error.message });
      res.status(500).json({
        error: 'Failed to initialize validation session',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/analyze
   * Analyze a message for requirements
   */
  router.post('/validation/analyze', async (req, res) => {
    try {
      const { message } = req.body;
      
      if (!message || !message.content) {
        return res.status(400).json({
          error: 'Missing message content',
          message: 'Message content is required for analysis'
        });
      }
      
      const result = await planningValidator.analyzeMessage(message);
      
      res.json({
        success: true,
        requirements: result.requirements,
        confidence: result.confidence
      });
    } catch (error) {
      logger.error('Failed to analyze message', { error: error.message });
      res.status(500).json({
        error: 'Failed to analyze message',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/validate
   * Validate entire conversation for completeness
   */
  router.post('/validation/validate', async (req, res) => {
    try {
      const { messages, projectType } = req.body;
      
      if (!messages || !Array.isArray(messages)) {
        return res.status(400).json({
          error: 'Invalid messages',
          message: 'Messages array is required for validation'
        });
      }
      
      // Set project type if provided
      if (projectType) {
        planningValidator.projectType = projectType;
      }
      
      const validation = await planningValidator.validateConversation(messages);
      
      res.json({
        success: true,
        validation
      });
    } catch (error) {
      logger.error('Failed to validate conversation', { error: error.message });
      res.status(500).json({
        error: 'Failed to validate conversation',
        message: error.message
      });
    }
  });

  /**
   * GET /api/validation/report
   * Get validation report for current session
   */
  router.get('/validation/report', async (req, res) => {
    try {
      const report = await planningValidator.exportReport();
      
      res.json({
        success: true,
        report
      });
    } catch (error) {
      logger.error('Failed to generate report', { error: error.message });
      res.status(500).json({
        error: 'Failed to generate report',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/checklist
   * Update checklist item status
   */
  router.post('/validation/checklist', async (req, res) => {
    try {
      const { itemId, completed, notes } = req.body;
      
      if (itemId === undefined) {
        return res.status(400).json({
          error: 'Missing item ID',
          message: 'Item ID is required to update checklist'
        });
      }
      
      // This would update the checklist in the validator
      // For now, just acknowledge the update
      logger.info('Checklist item updated', { itemId, completed });
      
      res.json({
        success: true,
        itemId,
        completed,
        notes
      });
    } catch (error) {
      logger.error('Failed to update checklist', { error: error.message });
      res.status(500).json({
        error: 'Failed to update checklist',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/requirements/extract
   * Extract requirements from text
   */
  router.post('/validation/requirements/extract', async (req, res) => {
    try {
      const { text } = req.body;
      
      if (!text) {
        return res.status(400).json({
          error: 'Missing text',
          message: 'Text is required for requirement extraction'
        });
      }
      
      const requirements = requirementsAnalyzer.extractRequirements(text);
      
      res.json({
        success: true,
        requirements: requirements.requirements,
        confidence: requirements.confidence
      });
    } catch (error) {
      logger.error('Failed to extract requirements', { error: error.message });
      res.status(500).json({
        error: 'Failed to extract requirements',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/requirements/database
   * Detect database schema from messages
   */
  router.post('/validation/requirements/database', async (req, res) => {
    try {
      const { messages } = req.body;
      
      if (!messages || !Array.isArray(messages)) {
        return res.status(400).json({
          error: 'Invalid messages',
          message: 'Messages array is required for database detection'
        });
      }
      
      const schema = requirementsAnalyzer.detectDatabaseSchema(messages);
      
      res.json({
        success: true,
        schema
      });
    } catch (error) {
      logger.error('Failed to detect database schema', { error: error.message });
      res.status(500).json({
        error: 'Failed to detect database schema',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/requirements/api
   * Detect API contracts from messages
   */
  router.post('/validation/requirements/api', async (req, res) => {
    try {
      const { messages } = req.body;
      
      if (!messages || !Array.isArray(messages)) {
        return res.status(400).json({
          error: 'Invalid messages',
          message: 'Messages array is required for API detection'
        });
      }
      
      const contracts = requirementsAnalyzer.detectAPIContracts(messages);
      
      res.json({
        success: true,
        contracts
      });
    } catch (error) {
      logger.error('Failed to detect API contracts', { error: error.message });
      res.status(500).json({
        error: 'Failed to detect API contracts',
        message: error.message
      });
    }
  });

  /**
   * POST /api/validation/requirements/ui
   * Detect UI requirements from messages
   */
  router.post('/validation/requirements/ui', async (req, res) => {
    try {
      const { messages } = req.body;
      
      if (!messages || !Array.isArray(messages)) {
        return res.status(400).json({
          error: 'Invalid messages',
          message: 'Messages array is required for UI detection'
        });
      }
      
      const ui = requirementsAnalyzer.detectUIRequirements(messages);
      
      res.json({
        success: true,
        ui
      });
    } catch (error) {
      logger.error('Failed to detect UI requirements', { error: error.message });
      res.status(500).json({
        error: 'Failed to detect UI requirements',
        message: error.message
      });
    }
  });

  /**
   * GET /api/validation/suggestions
   * Get suggestions for improving completeness
   */
  router.get('/validation/suggestions', async (req, res) => {
    try {
      const suggestions = planningValidator.getSuggestions();
      
      res.json({
        success: true,
        suggestions
      });
    } catch (error) {
      logger.error('Failed to get suggestions', { error: error.message });
      res.status(500).json({
        error: 'Failed to get suggestions',
        message: error.message
      });
    }
  });

  /**
   * DELETE /api/validation/session
   * Clear validation session
   */
  router.delete('/validation/session', async (req, res) => {
    try {
      planningValidator.clearSession();
      
      res.json({
        success: true,
        message: 'Validation session cleared'
      });
    } catch (error) {
      logger.error('Failed to clear session', { error: error.message });
      res.status(500).json({
        error: 'Failed to clear session',
        message: error.message
      });
    }
  });

  // Mount routes
  app.use('/api', router);
}

// Export router for testing
export default router;