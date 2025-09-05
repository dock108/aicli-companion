/**
 * Project Creator Service
 * Handles project creation, folder structure, and template application
 */

import { promises as fs } from 'fs';
import path from 'path';
import { createLogger } from '../utils/logger.js';
import { templateEngine } from './template-engine.js';
import { ServerConfig } from '../config/server-config.js';

const logger = createLogger('ProjectCreator');

export class ProjectCreator {
  constructor() {
    this.config = new ServerConfig();
    this.projectsDir = this.config.configPath;
  }

  /**
   * Create a new project with templates
   * @param {object} projectConfig - Project configuration
   * @returns {Promise<object>} - Creation result
   */
  async createProject(projectConfig) {
    const {
      projectName,
      projectType = 'web-app',
      techStack = 'Node.js',
      teamSize = 'small',
      description = '',
      author = 'Developer',
    } = projectConfig;

    // Validate project name
    if (!this.isValidProjectName(projectName)) {
      throw new Error(
        'Invalid project name. Use alphanumeric characters, hyphens, and underscores only.'
      );
    }

    const projectPath = path.join(this.projectsDir, projectName);

    // Check if project already exists
    if (await this.projectExists(projectPath)) {
      throw new Error(`Project '${projectName}' already exists`);
    }

    try {
      logger.info('Creating new project', { projectName, projectType });

      // Create project directory
      await fs.mkdir(projectPath, { recursive: true });

      // Create folder structure
      await this.createFolderStructure(projectPath, projectType);

      // Generate and write templates
      const templates = await templateEngine.generateProjectTemplates({
        project_name: projectName,
        project_description: description,
        project_type: projectType,
        tech_stack: techStack,
        team_size: teamSize,
        author,
        version: '0.1.0',
      });

      // Version the templates
      const versionedTemplates = templateEngine.versionTemplates('0.1.0', templates);

      // Write template files
      await this.writeTemplates(projectPath, versionedTemplates);

      // Initialize git repository if requested
      if (projectConfig.initGit) {
        await this.initializeGit(projectPath);
      }

      // Create initial project metadata
      const metadata = await this.createProjectMetadata(projectPath, projectConfig);

      logger.info('Project created successfully', { projectName, projectPath });

      return {
        success: true,
        projectName,
        projectPath,
        templates: Object.keys(templates),
        metadata,
        message: `Project '${projectName}' created successfully`,
      };
    } catch (error) {
      logger.error('Failed to create project', { projectName, error: error.message });

      // Cleanup on failure
      try {
        await fs.rmdir(projectPath, { recursive: true });
      } catch (cleanupError) {
        logger.error('Failed to cleanup after error', { cleanupError: cleanupError.message });
      }

      throw error;
    }
  }

  /**
   * Validate project name
   * @param {string} name - Project name to validate
   * @returns {boolean} - Whether name is valid
   */
  isValidProjectName(name) {
    if (!name || typeof name !== 'string') return false;
    if (name.length < 1 || name.length > 100) return false;

    // Allow alphanumeric, hyphens, underscores
    const validPattern = /^[a-zA-Z0-9_-]+$/;
    return validPattern.test(name);
  }

  /**
   * Check if project already exists
   * @param {string} projectPath - Path to check
   * @returns {Promise<boolean>} - Whether project exists
   */
  async projectExists(projectPath) {
    try {
      await fs.access(projectPath);
      return true;
    } catch (error) {
      return false;
    }
  }

  /**
   * Create project folder structure
   * @param {string} projectPath - Project root path
   * @param {string} projectType - Type of project
   * @returns {Promise<void>}
   */
  async createFolderStructure(projectPath, projectType) {
    const baseFolders = ['src', 'tests', 'docs', 'issues', '.github/workflows'];

    // Type-specific folders
    const typeFolders = {
      'web-app': ['src/components', 'src/pages', 'src/styles', 'public'],
      'mobile-app': ['src/screens', 'src/components', 'src/navigation', 'assets'],
      'api-service': ['src/routes', 'src/controllers', 'src/models', 'src/middleware'],
      'cli-tool': ['src/commands', 'src/utils', 'bin'],
    };

    const folders = [...baseFolders, ...(typeFolders[projectType] || [])];

    for (const folder of folders) {
      const folderPath = path.join(projectPath, folder);
      await fs.mkdir(folderPath, { recursive: true });
    }

    logger.info('Created folder structure', { projectPath, folders: folders.length });
  }

  /**
   * Write template files to project
   * @param {string} projectPath - Project root path
   * @param {object} templates - Template content by filename
   * @returns {Promise<void>}
   */
  async writeTemplates(projectPath, templates) {
    for (const [filename, content] of Object.entries(templates)) {
      const filePath = path.join(projectPath, filename);

      // Ensure directory exists
      const dir = path.dirname(filePath);
      await fs.mkdir(dir, { recursive: true });

      // Write file
      await fs.writeFile(filePath, content, 'utf-8');

      logger.debug('Wrote template file', { filename, size: content.length });
    }
  }

  /**
   * Initialize git repository
   * @param {string} projectPath - Project root path
   * @returns {Promise<void>}
   */
  async initializeGit(projectPath) {
    try {
      const { exec } = await import('child_process');
      const { promisify } = await import('util');
      const execAsync = promisify(exec);

      // Initialize git
      await execAsync('git init', { cwd: projectPath });

      // Create initial commit
      await execAsync('git add .', { cwd: projectPath });
      await execAsync('git commit -m "Initial project setup"', { cwd: projectPath });

      logger.info('Initialized git repository', { projectPath });
    } catch (error) {
      logger.warn('Failed to initialize git repository', { error: error.message });
      // Non-fatal error, continue
    }
  }

  /**
   * Create project metadata file
   * @param {string} projectPath - Project root path
   * @param {object} config - Project configuration
   * @returns {Promise<object>} - Metadata object
   */
  async createProjectMetadata(projectPath, config) {
    const metadata = {
      name: config.projectName,
      type: config.projectType,
      techStack: config.techStack,
      teamSize: config.teamSize,
      author: config.author,
      createdAt: new Date().toISOString(),
      version: '0.1.0',
      status: 'planning',
      templates: {
        version: '0.1.0',
        lastModified: new Date().toISOString(),
      },
    };

    const metadataPath = path.join(projectPath, '.aicli-companion', 'project.json');

    // Create .aicli-companion directory
    await fs.mkdir(path.dirname(metadataPath), { recursive: true });

    // Write metadata
    await fs.writeFile(metadataPath, JSON.stringify(metadata, null, 2));

    return metadata;
  }

  /**
   * List all projects
   * @returns {Promise<array>} - List of projects
   */
  async listProjects() {
    try {
      const items = await fs.readdir(this.projectsDir, { withFileTypes: true });

      const projects = [];
      for (const item of items) {
        if (item.isDirectory() && !item.name.startsWith('.')) {
          const projectPath = path.join(this.projectsDir, item.name);

          // Try to load metadata
          let metadata = null;
          try {
            const metadataPath = path.join(projectPath, '.aicli-companion', 'project.json');
            const metadataContent = await fs.readFile(metadataPath, 'utf-8');
            metadata = JSON.parse(metadataContent);
          } catch (err) {
            // No metadata, create basic info
            metadata = {
              name: item.name,
              type: 'unknown',
              createdAt: null,
            };
          }

          projects.push({
            ...metadata,
            path: projectPath,
          });
        }
      }

      return projects.sort((a, b) => a.name.localeCompare(b.name));
    } catch (error) {
      logger.error('Failed to list projects', { error: error.message });
      throw error;
    }
  }

  /**
   * Delete a project
   * @param {string} projectName - Name of project to delete
   * @param {boolean} archive - Whether to archive instead of delete
   * @returns {Promise<object>} - Deletion result
   */
  async deleteProject(projectName, archive = false) {
    const projectPath = path.join(this.projectsDir, projectName);

    // Check if project exists
    if (!(await this.projectExists(projectPath))) {
      throw new Error(`Project '${projectName}' not found`);
    }

    try {
      if (archive) {
        // Archive project
        const archivePath = path.join(this.projectsDir, '.archived', projectName);
        await fs.mkdir(path.dirname(archivePath), { recursive: true });
        await fs.rename(projectPath, archivePath);

        logger.info('Project archived', { projectName, archivePath });

        return {
          success: true,
          message: `Project '${projectName}' archived`,
          archivePath,
        };
      } else {
        // Delete project
        await fs.rm(projectPath, { recursive: true, force: true });

        logger.info('Project deleted', { projectName });

        return {
          success: true,
          message: `Project '${projectName}' deleted`,
        };
      }
    } catch (error) {
      logger.error('Failed to delete/archive project', { projectName, error: error.message });
      throw error;
    }
  }

  /**
   * Update project metadata
   * @param {string} projectName - Project name
   * @param {object} updates - Metadata updates
   * @returns {Promise<object>} - Updated metadata
   */
  async updateProjectMetadata(projectName, updates) {
    const projectPath = path.join(this.projectsDir, projectName);
    const metadataPath = path.join(projectPath, '.aicli-companion', 'project.json');

    try {
      // Load existing metadata
      const content = await fs.readFile(metadataPath, 'utf-8');
      const metadata = JSON.parse(content);

      // Apply updates
      const updated = {
        ...metadata,
        ...updates,
        lastModified: new Date().toISOString(),
      };

      // Write back
      await fs.writeFile(metadataPath, JSON.stringify(updated, null, 2));

      logger.info('Updated project metadata', { projectName, updates });

      return updated;
    } catch (error) {
      logger.error('Failed to update project metadata', { projectName, error: error.message });
      throw error;
    }
  }
}

// Export singleton instance
export const projectCreator = new ProjectCreator();
