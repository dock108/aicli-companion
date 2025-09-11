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
   * Sanitize and validate a path to ensure it's within the projects directory
   * @param {string} inputPath - Path to validate
   * @param {string} basePath - Base path to validate against
   * @returns {string} - Validated path
   * @throws {Error} - If path is invalid
   */
  sanitizePath(inputPath, basePath = this.projectsDir) {
    // Remove any null bytes and normalize
    const cleaned = String(inputPath).replace(/\0/g, '');

    // Resolve to absolute path
    const resolved = path.resolve(basePath, cleaned);
    const baseResolved = path.resolve(basePath);

    // Ensure the resolved path is within the base directory
    // Allow if path equals base or starts with base + separator
    if (!resolved.startsWith(baseResolved)) {
      throw new Error('Path traversal attempt detected');
    }

    return resolved;
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

    // Double-sanitize project name for extra safety
    const safeProjectName = projectName.replace(/[^a-zA-Z0-9_-]/g, '');
    if (safeProjectName !== projectName) {
      throw new Error('Project name contains invalid characters after sanitization');
    }

    const projectPath = this.sanitizePath(safeProjectName);

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
        // Re-validate path before cleanup
        const cleanupPath = this.sanitizePath(path.basename(projectPath));
        await fs.rmdir(cleanupPath, { recursive: true });
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
      // If already absolute and within bounds, use as-is
      // Otherwise, sanitize it
      let validPath;
      if (path.isAbsolute(projectPath)) {
        // If it's already absolute, just verify it's within bounds
        const baseResolved = path.resolve(this.projectsDir);
        if (projectPath.startsWith(baseResolved)) {
          validPath = projectPath;
        } else {
          // If absolute but outside bounds, reject
          return false;
        }
      } else {
        // Relative path, sanitize it
        validPath = this.sanitizePath(projectPath);
      }

      await fs.access(validPath);
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
    // Ensure projectPath is resolved and safe
    const safeProjectPath = path.resolve(projectPath);

    for (const [filename, content] of Object.entries(templates)) {
      // Sanitize filename to prevent traversal
      // Remove any parent directory references
      const normalizedPath = path.normalize(filename).replace(/^(\.\.(\/|\\|$))+/, '');
      const filePath = path.resolve(safeProjectPath, normalizedPath);

      // Ensure the file is within the project directory
      if (!filePath.startsWith(safeProjectPath)) {
        logger.warn('Skipping file outside project directory', { filename });
        continue;
      }

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

    // Validate project path and create safe metadata path
    const validProjectPath = this.sanitizePath(path.basename(projectPath));
    const metadataDir = this.sanitizePath('.aicli-companion', validProjectPath);

    // Create .aicli-companion directory
    await fs.mkdir(metadataDir, { recursive: true });

    const metadataPath = this.sanitizePath('project.json', metadataDir);

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
          // Sanitize the project name before creating path
          const projectPath = this.sanitizePath(item.name);

          // Try to load metadata
          let metadata = null;
          try {
            // Use sanitized paths for metadata
            const metadataDir = this.sanitizePath('.aicli-companion', projectPath);
            const metadataPath = this.sanitizePath('project.json', metadataDir);
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
    // Sanitize project name to prevent path traversal
    const safeProjectName = path.basename(projectName).replace(/[^a-zA-Z0-9_-]/g, '');
    const projectPath = this.sanitizePath(safeProjectName);

    // Check if project exists
    if (!(await this.projectExists(projectPath))) {
      throw new Error(`Project '${projectName}' not found`);
    }

    try {
      if (archive) {
        // Archive project
        // Create safe archive path
        const archiveDir = this.sanitizePath('.archived');
        await fs.mkdir(archiveDir, { recursive: true });
        const archivePath = this.sanitizePath(`${safeProjectName}_${Date.now()}`, archiveDir);
        await fs.rename(projectPath, archivePath);

        logger.info('Project archived', { projectName, archivePath });

        return {
          success: true,
          message: `Project '${projectName}' archived`,
          archivePath,
        };
      } else {
        // Delete project
        // Validate path once more before deletion
        const deletePath = this.sanitizePath(safeProjectName);
        await fs.rm(deletePath, { recursive: true, force: true });

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
    // Sanitize project name and create safe paths
    const safeProjectName = path.basename(projectName).replace(/[^a-zA-Z0-9_-]/g, '');
    const projectPath = this.sanitizePath(safeProjectName);
    const metadataDir = this.sanitizePath('.aicli-companion', projectPath);
    const metadataPath = this.sanitizePath('project.json', metadataDir);

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
