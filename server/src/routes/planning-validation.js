/**
 * Planning Validation Routes
 * Handles plan.md validation and project readiness assessment
 */

import express from 'express';
import fs from 'fs/promises';
import path from 'path';
import { requirementsAnalyzer } from '../services/requirements-analyzer.js';
import { readinessScorer } from '../services/readiness-scorer.js';
import { createLogger } from '../utils/logger.js';
import { authMiddleware } from '../middleware/auth.js';
import { validateProjectPath } from '../utils/path-validator.js';

const router = express.Router();
const logger = createLogger('PlanningValidationRoutes');

/**
 * POST /api/planning-validation/validate
 * Validate planning document content and get readiness assessment
 */
router.post('/validate', authMiddleware, async (req, res) => {
  try {
    const { content, projectType, projectPath } = req.body;

    if (!content) {
      return res.status(400).json({
        error: 'Content is required for validation',
      });
    }

    logger.info('Validating planning document', {
      contentLength: content.length,
      projectType,
      projectPath,
    });

    // Analyze requirements from the content
    const requirementsAnalysis = requirementsAnalyzer.analyzeConversation(content);

    // Calculate readiness score
    const readinessResult = readinessScorer.calculateReadiness(content, { projectType });

    // Format response for iOS app
    const response = {
      success: true,
      validation: {
        overallScore: readinessResult.overallScore,
        readinessLevel: readinessResult.readinessLevel,
        confidence: readinessResult.confidence || requirementsAnalysis.confidence,
        domains: Object.values(requirementsAnalysis.domains).map((domain) => ({
          name: domain.name,
          icon: domain.icon,
          score: domain.score,
          keywordMatches: domain.keywordMatches,
          foundRequirements: domain.foundRequirements,
          missingRequirements: domain.missingRequirements,
        })),
        blockers: readinessResult.blockers || [],
        suggestions: requirementsAnalysis.suggestions || [],
        actionItems: readinessResult.actionItems || [],
        feedback: readinessResult.feedback || [],
      },
      metadata: {
        analyzedAt: new Date().toISOString(),
        contentLength: content.length,
        projectType: projectType || 'general',
      },
    };

    logger.info('Planning validation completed', {
      overallScore: readinessResult.overallScore,
      readinessLevel: readinessResult.readinessLevel.level,
    });

    res.json(response);
  } catch (error) {
    logger.error('Failed to validate planning document', { error: error.message });
    res.status(500).json({ error: 'Failed to validate planning document' });
  }
});

/**
 * POST /api/planning-validation/analyze
 * Analyze project directory structure and existing files
 */
router.post('/analyze', authMiddleware, async (req, res) => {
  try {
    const { projectPath: rawPath } = req.body;

    if (!rawPath) {
      return res.status(400).json({
        error: 'Project path is required for analysis',
      });
    }

    // Validate and sanitize the path
    const projectPath = validateProjectPath(rawPath);
    if (!projectPath) {
      return res.status(400).json({
        error: 'Invalid project path',
      });
    }

    logger.info('Analyzing project directory', { projectPath });

    // Check if directory exists
    try {
      await fs.access(projectPath);
    } catch {
      return res.status(404).json({
        error: 'Project directory not found',
      });
    }

    // Read plan.md if it exists
    let planContent = '';
    const planPath = path.join(projectPath, 'plan.md');
    try {
      planContent = await fs.readFile(planPath, 'utf-8');
      logger.info('Found existing plan.md', {
        projectPath,
        planSize: planContent.length,
      });
    } catch {
      logger.info('No plan.md found in project', { projectPath });
    }

    // Get directory structure
    const files = await fs.readdir(projectPath, { withFileTypes: true });
    const structure = {
      directories: files.filter((f) => f.isDirectory()).map((f) => f.name),
      files: files.filter((f) => f.isFile()).map((f) => f.name),
      hasPlan: !!planContent,
      hasReadme: files.some((f) => f.name.toLowerCase() === 'readme.md'),
      hasClaude: files.some((f) => f.name.toUpperCase() === 'CLAUDE.MD'),
      hasIssues: files.some((f) => f.name === 'issues' && f.isDirectory()),
    };

    // If plan exists, analyze it
    let validation = null;
    if (planContent) {
      const requirementsAnalysis = requirementsAnalyzer.analyzeConversation(planContent);
      const readinessResult = readinessScorer.calculateReadiness(planContent);
      validation = {
        overallScore: readinessResult.overallScore,
        readinessLevel: readinessResult.readinessLevel,
        domains: Object.values(requirementsAnalysis.domains),
      };
    }

    const response = {
      success: true,
      analysis: {
        projectPath,
        structure,
        validation,
        recommendations: generateRecommendations(structure, validation),
      },
    };

    logger.info('Directory analysis completed', { projectPath });
    res.json(response);
  } catch (error) {
    logger.error('Failed to analyze directory', { error: error.message });
    res.status(500).json({ error: 'Failed to analyze project directory' });
  }
});

/**
 * POST /api/planning-validation/save
 * Save and validate plan.md file
 */
router.post('/save', authMiddleware, async (req, res) => {
  try {
    const { projectPath: rawPath, content } = req.body;

    if (!rawPath || !content) {
      return res.status(400).json({
        error: 'Project path and content are required',
      });
    }

    // Validate and sanitize the path
    const projectPath = validateProjectPath(rawPath);
    if (!projectPath) {
      return res.status(400).json({
        error: 'Invalid project path',
      });
    }

    logger.info('Saving plan.md', {
      projectPath,
      contentLength: content.length,
    });

    // Ensure project directory exists
    try {
      await fs.access(projectPath);
    } catch {
      await fs.mkdir(projectPath, { recursive: true });
      logger.info('Created project directory', { projectPath });
    }

    // Save plan.md
    const planPath = path.join(projectPath, 'plan.md');
    await fs.writeFile(planPath, content, 'utf-8');

    // Validate the saved content
    const readinessResult = readinessScorer.calculateReadiness(content);

    const response = {
      success: true,
      result: {
        filePath: planPath,
        saved: true,
        validation: {
          overallScore: readinessResult.overallScore,
          readinessLevel: readinessResult.readinessLevel,
          isReady: readinessResult.overallScore >= 70,
        },
      },
    };

    logger.info('Plan saved and validated', {
      projectPath,
      overallScore: readinessResult.overallScore,
    });

    res.json(response);
  } catch (error) {
    logger.error('Failed to save plan', { error: error.message });
    res.status(500).json({ error: 'Failed to save plan.md' });
  }
});

/**
 * Generate recommendations based on project structure and validation
 */
function generateRecommendations(structure, validation) {
  const recommendations = [];

  if (!structure.hasPlan) {
    recommendations.push({
      priority: 'high',
      message: 'Create a plan.md file to document project requirements',
      action: 'Create comprehensive planning document',
    });
  }

  if (!structure.hasClaude) {
    recommendations.push({
      priority: 'medium',
      message: 'Add CLAUDE.md for development guidelines',
      action: 'Generate project-specific guidelines',
    });
  }

  if (!structure.hasReadme) {
    recommendations.push({
      priority: 'medium',
      message: 'Create README.md for project documentation',
      action: 'Add project overview and setup instructions',
    });
  }

  if (validation && validation.overallScore < 70) {
    recommendations.push({
      priority: 'high',
      message: `Planning document needs improvement (score: ${validation.overallScore}%)`,
      action: 'Add more detail to requirements and specifications',
    });
  }

  return recommendations;
}

export default router;
