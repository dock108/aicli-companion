/**
 * Workspace Security Service
 * Handles security and validation for workspace mode operations
 */

import path from 'path';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('WorkspaceSecurity');

export class WorkspaceSecurity {
  constructor() {
    // Define allowed operations in workspace mode
    this.allowedOperations = new Set([
      'list_projects',
      'search_across_projects',
      'move_file',
      'copy_file',
      'create_project',
      'archive_project',
      'analyze_workspace',
      'generate_report',
    ]);

    // Define forbidden paths/patterns
    this.forbiddenPaths = [
      /node_modules/,
      /\.git(?:\/|$)/,
      /\.env/,
      /\.ssh/,
      /\.aws/,
      /\.config/,
      /private/,
      /secret/,
    ];

    // Define allowed file extensions for cross-project operations
    this.allowedExtensions = new Set([
      '.js',
      '.ts',
      '.jsx',
      '.tsx',
      '.json',
      '.md',
      '.txt',
      '.yml',
      '.yaml',
      '.html',
      '.css',
      '.scss',
      '.py',
      '.java',
      '.swift',
      '.go',
      '.rs',
      '.cpp',
      '.c',
      '.h',
    ]);
  }

  /**
   * Check if a path is within the workspace bounds
   * @param {string} requestedPath - The path to check
   * @param {string} workspaceRoot - The workspace root directory
   * @returns {boolean} - Whether the path is valid
   */
  isPathWithinWorkspace(requestedPath, workspaceRoot) {
    try {
      const normalizedPath = path.resolve(requestedPath);
      const normalizedRoot = path.resolve(workspaceRoot);

      // Check if path is within workspace
      if (!normalizedPath.startsWith(normalizedRoot)) {
        logger.warn('Path traversal attempt detected', {
          requestedPath,
          workspaceRoot,
        });
        return false;
      }

      // Check against forbidden patterns
      const relativePath = path.relative(normalizedRoot, normalizedPath);
      for (const pattern of this.forbiddenPaths) {
        if (pattern.test(relativePath)) {
          logger.warn('Forbidden path pattern detected', {
            path: relativePath,
            pattern: pattern.toString(),
          });
          return false;
        }
      }

      return true;
    } catch (error) {
      logger.error('Error validating path', { error: error.message });
      return false;
    }
  }

  /**
   * Check if an operation is allowed in workspace mode
   * @param {string} operation - The operation to check
   * @returns {boolean} - Whether the operation is allowed
   */
  isOperationAllowed(operation) {
    return this.allowedOperations.has(operation);
  }

  /**
   * Check if a file extension is allowed for cross-project operations
   * @param {string} filePath - The file path to check
   * @returns {boolean} - Whether the file type is allowed
   */
  isFileTypeAllowed(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    return this.allowedExtensions.has(ext);
  }

  /**
   * Validate a workspace command before execution
   * @param {object} command - The command to validate
   * @param {string} workspaceRoot - The workspace root directory
   * @returns {object} - Validation result with allowed flag and message
   */
  validateWorkspaceCommand(command, workspaceRoot) {
    const { operation, sourcePath, targetPath, files } = command;

    // Check if operation is allowed
    if (!this.isOperationAllowed(operation)) {
      return {
        allowed: false,
        message: `Operation '${operation}' is not allowed in workspace mode`,
      };
    }

    // Validate source path if provided
    if (sourcePath && !this.isPathWithinWorkspace(sourcePath, workspaceRoot)) {
      return {
        allowed: false,
        message: 'Source path is outside workspace bounds or forbidden',
      };
    }

    // Validate target path if provided
    if (targetPath && !this.isPathWithinWorkspace(targetPath, workspaceRoot)) {
      return {
        allowed: false,
        message: 'Target path is outside workspace bounds or forbidden',
      };
    }

    // Validate file list if provided
    if (files && Array.isArray(files)) {
      for (const file of files) {
        if (!this.isPathWithinWorkspace(file, workspaceRoot)) {
          return {
            allowed: false,
            message: `File path '${file}' is outside workspace bounds`,
          };
        }
        if (!this.isFileTypeAllowed(file)) {
          return {
            allowed: false,
            message: `File type not allowed for workspace operations: ${file}`,
          };
        }
      }
    }

    logger.info('Workspace command validated successfully', {
      operation,
      sourcePath,
      targetPath,
      fileCount: files?.length || 0,
    });

    return {
      allowed: true,
      message: 'Command validated successfully',
    };
  }

  /**
   * Get workspace restrictions for client information
   * @returns {object} - Workspace restrictions configuration
   */
  getWorkspaceRestrictions() {
    return {
      allowedOperations: Array.from(this.allowedOperations),
      allowedExtensions: Array.from(this.allowedExtensions),
      forbiddenPatterns: this.forbiddenPaths.map((p) => p.source),
      securityNote:
        'Workspace mode allows limited cross-project operations within the configured directory',
    };
  }

  /**
   * Create a safe workspace context for AICLI
   * @param {string} workspaceRoot - The workspace root directory
   * @returns {object} - Safe workspace context
   */
  createWorkspaceContext(workspaceRoot) {
    return {
      type: 'workspace',
      root: workspaceRoot,
      restrictions: this.getWorkspaceRestrictions(),
      sessionId: `workspace-${Date.now()}`,
      createdAt: new Date().toISOString(),
      permissions: {
        read: true,
        write: false, // Limited write in workspace mode
        execute: false,
        crossProject: true,
      },
    };
  }
}

// Singleton instance
export const workspaceSecurity = new WorkspaceSecurity();
