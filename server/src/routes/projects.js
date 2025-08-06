import express from 'express';
import { promises as fs } from 'fs';
import path from 'path';
import { ServerConfig } from '../config/server-config.js';
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
      const projectsDir = getProjectsDir();
      const projectPath = path.join(projectsDir, name);

      // Security check - prevent directory traversal
      const normalizedPath = path.normalize(projectPath);
      const normalizedBase = path.normalize(projectsDir);

      if (!normalizedPath.startsWith(normalizedBase)) {
        return res.status(403).json({
          error: 'Access denied',
          message: 'Invalid project path',
        });
      }

      // Check if project exists
      try {
        const stat = await fs.stat(projectPath);
        if (!stat.isDirectory()) {
          throw new Error('Not a directory');
        }
      } catch (error) {
        return res.status(404).json({
          error: 'Project not found',
          message: `Project '${name}' does not exist`,
        });
      }

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
