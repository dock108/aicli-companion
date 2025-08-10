import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { ServerConfig } from '../config/server-config.js';
import { validateSecurePath, PathSecurityError } from '../utils/path-security.js';
import rateLimit from 'express-rate-limit';
export function setupProjectRoutes(app, _aicliService) {
  const router = express.Router();
  const config = new ServerConfig();

  // Get the configured project directory from config
  const getProjectsDir = () => {
    return config.configPath;
  };

  // List all projects (folders) in the configured directory
  // Define rate limiter for projects listing route
  const projectsListLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: {
      error: 'Too many requests',
      message: 'Please try again later.',
    },
  });

  router.get('/projects', projectsListLimiter, async (req, res) => {
    try {
      const projectsDir = getProjectsDir();
      console.log('Listing projects from directory:', path.basename(projectsDir));

      // Read directory contents
      const items = await fs.readdir(projectsDir, { withFileTypes: true });

      // Filter for directories only and exclude hidden folders
      const projects = items
        .filter((item) => item.isDirectory() && !item.name.startsWith('.'))
        .map((item) => ({
          name: item.name,
          path: path.join(projectsDir, item.name),
          type: 'folder',
        }));

      res.json({
        basePath: projectsDir,
        projects: projects.sort((a, b) => a.name.localeCompare(b.name)),
      });
    } catch (error) {
      console.error('Error listing projects:', error);
      res.status(500).json({
        error: 'Failed to list projects',
        message: error.message,
      });
    }
  });

  // Define rate limiter for project info route
  const projectInfoLimiter = rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 100, // Limit each IP to 100 requests per windowMs
    message: {
      error: 'Too many requests',
      message: 'Please try again later.',
    },
  });

  // Get specific project info
  router.get('/projects/:name', projectInfoLimiter, async (req, res) => {
    try {
      const { name } = req.params;
      
      // SECURITY: Validate project name format to prevent path traversal
      // Only allow alphanumeric characters, dashes, underscores, and dots
      const projectNameRegex = /^[a-zA-Z0-9._-]+$/;
      if (!name || !projectNameRegex.test(name)) {
        return res.status(400).json({
          error: 'Invalid project name',
          message: 'Project name contains invalid characters',
        });
      }
      
      // Additional checks for suspicious patterns
      if (name.includes('..') || name.startsWith('.') || name === '.' || name === '..') {
        return res.status(400).json({
          error: 'Invalid project name',
          message: 'Project name contains forbidden patterns',
        });
      }
      
      const projectsDir = getProjectsDir();

      // Secure path validation to prevent directory traversal attacks
      let validatedPath;
      try {
        validatedPath = await validateSecurePath(projectsDir, name, {
          allowSymlinks: false,
          mustExist: true,
          mustBeDirectory: true,
        });
      } catch (error) {
        if (error instanceof PathSecurityError) {
          console.warn(`Path security violation in project access: ${error.message}`, {
            projectsDir,
            requestedName: name,
            code: error.code,
          });
          return res.status(403).json({
            error: 'Access denied',
            message: 'Invalid project path',
          });
        }
        throw error;
      }

      const projectPath = validatedPath;
      // Note: Path validation already confirmed it exists and is a directory

      // Get project info
      const info = {
        name,
        path: projectPath,
        type: 'folder',
      };

      // Try to get additional info if available
      try {
        // Check for package.json
        const packageJsonPath = path.join(projectPath, 'package.json');
        const packageJson = await fs.readFile(packageJsonPath, 'utf-8');
        const packageData = JSON.parse(packageJson);
        info.description = packageData.description;
        info.projectType = 'node';
      } catch (error) {
        // Not a Node project or no package.json
      }

      res.json(info);
    } catch (error) {
      console.error('Error getting project info:', error);
      res.status(500).json({
        error: 'Failed to get project info',
        message: error.message,
      });
    }
  });

  // Mount routes
  app.use('/api', router);
}
