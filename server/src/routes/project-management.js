/**
 * Project Management Routes
 * Handles project creation, listing, and management with templates
 */

import express from 'express';
import { projectCreator } from '../services/project-creator.js';
import { templateEngine } from '../services/template-engine.js';
import { createLogger } from '../utils/logger.js';
import { authMiddleware } from '../middleware/auth.js';
import { validateProjectPath, isValidFilename } from '../utils/path-validator.js';

const router = express.Router();
const logger = createLogger('ProjectManagementRoutes');

/**
 * Create a new project with templates
 */
router.post('/project-management/create', authMiddleware, async (req, res) => {
  try {
    const projectConfig = req.body;

    // Validate required fields
    if (!projectConfig.projectName) {
      return res.status(400).json({
        error: 'Project name is required',
      });
    }

    // Create the project
    const result = await projectCreator.createProject(projectConfig);

    logger.info('Project created via API', {
      projectName: projectConfig.projectName,
      deviceToken: req.deviceToken,
    });

    res.json(result);
  } catch (error) {
    logger.error('Failed to create project', { error: error.message });

    if (error.message.includes('already exists')) {
      return res.status(409).json({ error: error.message });
    }
    if (error.message.includes('Invalid project name')) {
      return res.status(400).json({ error: error.message });
    }

    res.status(500).json({ error: 'Failed to create project' });
  }
});

/**
 * List all projects with metadata
 */
router.get('/project-management/list', authMiddleware, async (req, res) => {
  try {
    const projects = await projectCreator.listProjects();

    logger.info('Projects listed', {
      count: projects.length,
      deviceToken: req.deviceToken,
    });

    res.json({
      projects,
      count: projects.length,
    });
  } catch (error) {
    logger.error('Failed to list projects', { error: error.message });
    res.status(500).json({ error: 'Failed to list projects' });
  }
});

/**
 * Get project details
 */
router.get('/project-management/project/:projectName', authMiddleware, async (req, res) => {
  try {
    const { projectName } = req.params;
    const projects = await projectCreator.listProjects();

    const project = projects.find((p) => p.name === projectName);

    if (!project) {
      return res.status(404).json({ error: 'Project not found' });
    }

    res.json(project);
  } catch (error) {
    logger.error('Failed to get project details', { error: error.message });
    res.status(500).json({ error: 'Failed to get project details' });
  }
});

/**
 * Update project metadata
 */
router.patch('/project-management/project/:projectName', authMiddleware, async (req, res) => {
  try {
    const { projectName } = req.params;
    const updates = req.body;

    const metadata = await projectCreator.updateProjectMetadata(projectName, updates);

    logger.info('Project metadata updated', {
      projectName,
      updates,
      deviceToken: req.deviceToken,
    });

    res.json({
      success: true,
      metadata,
    });
  } catch (error) {
    logger.error('Failed to update project metadata', { error: error.message });

    if (error.message.includes('not found')) {
      return res.status(404).json({ error: 'Project not found' });
    }

    res.status(500).json({ error: 'Failed to update project' });
  }
});

/**
 * Delete or archive a project
 */
router.delete('/project-management/project/:projectName', authMiddleware, async (req, res) => {
  try {
    const { projectName } = req.params;
    const { archive = false } = req.query;

    const result = await projectCreator.deleteProject(projectName, archive === 'true');

    logger.info('Project deleted/archived', {
      projectName,
      archived: archive === 'true',
      deviceToken: req.deviceToken,
    });

    res.json(result);
  } catch (error) {
    logger.error('Failed to delete/archive project', { error: error.message });

    if (error.message.includes('not found')) {
      return res.status(404).json({ error: 'Project not found' });
    }

    res.status(500).json({ error: 'Failed to delete project' });
  }
});

/**
 * List available templates
 */
router.get('/project-management/templates', authMiddleware, async (req, res) => {
  try {
    const templates = await templateEngine.listAvailableTemplates();

    logger.info('Templates listed', {
      deviceToken: req.deviceToken,
    });

    res.json(templates);
  } catch (error) {
    logger.error('Failed to list templates', { error: error.message });
    res.status(500).json({ error: 'Failed to list templates' });
  }
});

/**
 * Create custom template from existing project
 */
router.post('/project-management/templates/custom', authMiddleware, async (req, res) => {
  try {
    const { projectPath: rawPath, templateName } = req.body;

    if (!rawPath || !templateName) {
      return res.status(400).json({
        error: 'Project path and template name are required',
      });
    }

    // Validate project path
    const projectPath = validateProjectPath(rawPath);
    if (!projectPath) {
      return res.status(400).json({
        error: 'Invalid project path',
      });
    }

    // Validate template name (no path components allowed)
    if (!isValidFilename(templateName)) {
      return res.status(400).json({
        error: 'Invalid template name',
      });
    }

    await templateEngine.createCustomTemplate(projectPath, templateName);

    logger.info('Custom template created', {
      templateName,
      projectPath,
      deviceToken: req.deviceToken,
    });

    res.json({
      success: true,
      message: `Custom template '${templateName}' created successfully`,
    });
  } catch (error) {
    logger.error('Failed to create custom template', { error: error.message });
    res.status(500).json({ error: 'Failed to create custom template' });
  }
});

/**
 * Preview generated templates for a project configuration
 */
router.post('/project-management/templates/preview', authMiddleware, async (req, res) => {
  try {
    const config = req.body;

    // Generate templates without creating project
    const templates = await templateEngine.generateProjectTemplates(config);

    logger.info('Template preview generated', {
      projectType: config.project_type,
      deviceToken: req.deviceToken,
    });

    res.json({
      templates,
      count: Object.keys(templates).length,
    });
  } catch (error) {
    logger.error('Failed to preview templates', { error: error.message });
    res.status(500).json({ error: 'Failed to preview templates' });
  }
});

export default router;
