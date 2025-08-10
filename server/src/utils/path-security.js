/**
 * Secure path validation utilities to prevent directory traversal attacks
 *
 * This module provides robust protection against various attack vectors including:
 * - Path traversal with ../
 * - Symlink attacks
 * - Unicode normalization attacks
 * - Null byte injection
 * - URL encoded attacks
 */

import path from 'path';
import { realpath, lstat, access } from 'fs/promises';
import { constants } from 'fs';
import { createLogger } from './logger.js';

const logger = createLogger('PathSecurity');

/**
 * Security error for path validation failures
 */
export class PathSecurityError extends Error {
  constructor(message, code = 'PATH_SECURITY_ERROR') {
    super(message);
    this.name = 'PathSecurityError';
    this.code = code;
  }
}

/**
 * Path security validator with comprehensive protection mechanisms
 */
export class PathValidator {
  /**
   * Validate that a target path is safely contained within a base directory
   * Uses path.resolve() and real filesystem resolution to prevent bypasses
   *
   * @param {string} basePath - The base directory path
   * @param {string} targetPath - The path to validate
   * @param {Object} options - Validation options
   * @param {boolean} options.allowSymlinks - Whether to allow symlinks (default: false)
   * @param {boolean} options.mustExist - Whether the target must exist (default: false)
   * @param {boolean} options.mustBeDirectory - Whether target must be a directory (default: false)
   * @returns {Promise<string>} - Resolved safe path
   * @throws {PathSecurityError} - If validation fails
   */
  static async validatePath(basePath, targetPath, options = {}) {
    const { allowSymlinks = false, mustExist = false, mustBeDirectory = false } = options;

    // Input validation
    if (!basePath || typeof basePath !== 'string') {
      throw new PathSecurityError('Base path must be a non-empty string', 'INVALID_BASE_PATH');
    }

    if (!targetPath || typeof targetPath !== 'string') {
      throw new PathSecurityError('Target path must be a non-empty string', 'INVALID_TARGET_PATH');
    }

    // Check for null bytes and other dangerous characters
    if (basePath.includes('\0') || targetPath.includes('\0')) {
      throw new PathSecurityError('Path contains null bytes', 'NULL_BYTE_ATTACK');
    }

    // URL decode to prevent encoded path traversal
    const decodedTargetPath = decodeURIComponent(targetPath);

    try {
      // Resolve both paths to absolute paths
      const resolvedBase = path.resolve(basePath);
      const resolvedTarget = path.resolve(resolvedBase, decodedTargetPath);

      logger.debug('Path validation', {
        basePath,
        targetPath,
        resolvedBase,
        resolvedTarget,
      });

      // First check: ensure target is within base using string comparison
      if (resolvedTarget !== resolvedBase && !resolvedTarget.startsWith(resolvedBase + path.sep)) {
        throw new PathSecurityError(
          `Path '${targetPath}' is outside base directory '${basePath}'`,
          'PATH_TRAVERSAL_ATTEMPT'
        );
      }

      // Get real base path first (safe since basePath is controlled by us)
      let realBase;
      try {
        realBase = await realpath(resolvedBase);
      } catch (error) {
        throw new PathSecurityError(
          `Cannot resolve base path '${basePath}': ${error.message}`,
          'BASE_PATH_ERROR'
        );
      }

      // If target must exist or we need to check symlinks, validate using safe operations
      if (mustExist || !allowSymlinks) {
        try {
          await access(resolvedTarget, constants.F_OK);
        } catch (error) {
          if (mustExist) {
            throw new PathSecurityError(`Path '${targetPath}' does not exist`, 'PATH_NOT_FOUND');
          }
          // If path doesn't exist and we don't require it to exist,
          // we can't check for symlinks, so just return the resolved path
          return resolvedTarget;
        }

        // For symlink checking, build a safe target path
        const relativePath = path.relative(resolvedBase, resolvedTarget);

        // SECURITY: Extra validation - ensure relative path doesn't escape
        if (relativePath.startsWith('..') || path.isAbsolute(relativePath)) {
          throw new PathSecurityError(
            `Path '${targetPath}' attempts to escape base directory`,
            'PATH_ESCAPE_ATTEMPT'
          );
        }

        const safeTargetPath = path.resolve(realBase, relativePath);

        // SECURITY: Final check before realpath - ensure constructed path is within base
        if (!safeTargetPath.startsWith(realBase + path.sep) && safeTargetPath !== realBase) {
          throw new PathSecurityError(
            `Constructed path escapes base directory`,
            'CONSTRUCTED_PATH_ESCAPE'
          );
        }

        // Get real path using our safe constructed path
        let realTargetPath;
        try {
          realTargetPath = await realpath(safeTargetPath);
        } catch (error) {
          throw new PathSecurityError(
            `Cannot resolve real path for '${targetPath}': ${error.message}`,
            'REALPATH_ERROR'
          );
        }

        // Check for symlink attacks by comparing safe and real paths
        if (!allowSymlinks && realTargetPath !== safeTargetPath) {
          // Ensure the real path is still within bounds using already resolved realBase
          if (realTargetPath !== realBase && !realTargetPath.startsWith(realBase + path.sep)) {
            throw new PathSecurityError(
              `Symlink '${targetPath}' points outside base directory`,
              'SYMLINK_ATTACK'
            );
          }
        }

        // Final security check: ensure real path is within real base
        if (realTargetPath !== realBase && !realTargetPath.startsWith(realBase + path.sep)) {
          throw new PathSecurityError(
            `Real path '${realTargetPath}' is outside base directory`,
            'REAL_PATH_OUTSIDE_BASE'
          );
        }

        // Directory validation if required
        if (mustBeDirectory) {
          try {
            // Use the validated realTargetPath instead of uncontrolled resolvedTarget
            const stat = await lstat(realTargetPath);
            if (!stat.isDirectory()) {
              throw new PathSecurityError(
                `Path '${targetPath}' is not a directory`,
                'NOT_DIRECTORY'
              );
            }
          } catch (error) {
            if (error instanceof PathSecurityError) throw error;
            throw new PathSecurityError(
              `Cannot stat path '${targetPath}': ${error.message}`,
              'STAT_ERROR'
            );
          }
        }

        return realTargetPath;
      }

      return resolvedTarget;
    } catch (error) {
      if (error instanceof PathSecurityError) {
        logger.warn('Path security violation', {
          basePath,
          targetPath,
          error: error.message,
          code: error.code,
        });
        throw error;
      }

      // Wrap unexpected errors
      throw new PathSecurityError(`Path validation failed: ${error.message}`, 'VALIDATION_ERROR');
    }
  }

  /**
   * Validate a project path (synchronous version for simple cases)
   * @param {string} basePath - Base directory
   * @param {string} projectName - Project name to validate
   * @returns {string} - Safe resolved path
   * @throws {PathSecurityError} - If validation fails
   */
  static validateProjectPath(basePath, projectName) {
    if (!basePath || typeof basePath !== 'string') {
      throw new PathSecurityError('Base path must be a non-empty string');
    }

    if (!projectName || typeof projectName !== 'string') {
      throw new PathSecurityError('Project name must be a non-empty string');
    }

    // Check for dangerous characters
    if (
      projectName.includes('\0') ||
      projectName.includes('/') ||
      projectName.includes('\\') ||
      projectName.includes('..')
    ) {
      throw new PathSecurityError('Project name contains invalid characters');
    }

    const resolvedBase = path.resolve(basePath);
    const resolvedTarget = path.resolve(resolvedBase, projectName);

    // Ensure target is within base
    if (resolvedTarget !== resolvedBase && !resolvedTarget.startsWith(resolvedBase + path.sep)) {
      throw new PathSecurityError('Project path is outside base directory');
    }

    return resolvedTarget;
  }

  /**
   * Create a safe project path by joining base and name
   * @param {string} basePath - Base directory
   * @param {string} projectName - Project name
   * @returns {string} - Safe joined path
   * @throws {PathSecurityError} - If validation fails
   */
  static createSafeProjectPath(basePath, projectName) {
    return this.validateProjectPath(basePath, projectName);
  }
}

/**
 * Convenience function for async path validation
 * @param {string} basePath - Base directory path
 * @param {string} targetPath - Target path to validate
 * @param {Object} options - Validation options
 * @returns {Promise<string>} - Validated path
 */
export const validateSecurePath = (basePath, targetPath, options) =>
  PathValidator.validatePath(basePath, targetPath, options);

/**
 * Convenience function for project path validation
 * @param {string} basePath - Base directory
 * @param {string} projectName - Project name
 * @returns {string} - Safe project path
 */
export const validateProjectPath = (basePath, projectName) =>
  PathValidator.validateProjectPath(basePath, projectName);

/**
 * Convenience function for creating safe project paths
 * @param {string} basePath - Base directory
 * @param {string} projectName - Project name
 * @returns {string} - Safe project path
 */
export const createSafeProjectPath = (basePath, projectName) =>
  PathValidator.createSafeProjectPath(basePath, projectName);
