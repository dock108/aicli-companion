/**
 * Command Security Service
 *
 * Provides comprehensive security controls for command execution including:
 * - Command pattern filtering (blocklist/allowlist)
 * - Directory access controls
 * - Destructive command detection
 * - File size limits
 * - Audit logging
 */

import path from 'path';
import { EventEmitter } from 'events';
import { createLogger } from '../utils/logger.js';
import _ from 'lodash';

const logger = createLogger('CommandSecurity');

/**
 * Security violation error
 */
export class SecurityViolationError extends Error {
  constructor(message, code = 'SECURITY_VIOLATION', details = {}) {
    super(message);
    this.name = 'SecurityViolationError';
    this.code = code;
    this.details = details;
  }
}

/**
 * Command security configuration
 */
export class SecurityConfig {
  constructor(options = {}) {
    // Parse environment variables
    this.safeDirectories = this.parseDirectories(
      process.env.AICLI_SAFE_DIRECTORIES || options.safeDirectories || ''
    );

    this.blockedCommands = this.parsePatterns(
      process.env.AICLI_BLOCKED_COMMANDS || options.blockedCommands || ''
    );

    this.destructiveCommands = this.parsePatterns(
      process.env.AICLI_DESTRUCTIVE_COMMANDS ||
        options.destructiveCommands ||
        'rm -rf,format,diskutil erase,dd if=,mkfs,fdisk'
    );

    this.requireConfirmation =
      process.env.AICLI_DESTRUCTIVE_COMMANDS_REQUIRE_CONFIRMATION === 'true' ||
      options.requireConfirmation ||
      false;

    this.maxFileSize = parseInt(
      process.env.AICLI_MAX_FILE_SIZE || options.maxFileSize || '10485760' // 10MB default
    );

    this.readOnlyMode = process.env.AICLI_READONLY_MODE === 'true' || options.readOnlyMode || false;

    this.enableAudit = process.env.AICLI_ENABLE_AUDIT === 'true' || options.enableAudit !== false; // Default true

    // Security presets
    this.preset = process.env.AICLI_SECURITY_PRESET || options.preset || 'standard';
    this.applyPreset(this.preset);
  }

  parseDirectories(dirString) {
    if (!dirString) return [];

    // Handle both string and array inputs
    if (Array.isArray(dirString)) {
      return dirString
        .filter((dir) => dir && dir.length > 0)
        .map((dir) => path.resolve(dir.replace('~', process.env.HOME || '')));
    }

    return dirString
      .split(',')
      .map((dir) => dir.trim())
      .filter((dir) => dir.length > 0)
      .map((dir) => path.resolve(dir.replace('~', process.env.HOME || '')));
  }

  parsePatterns(patternString) {
    if (!patternString) return [];

    // Handle both string and array inputs
    if (Array.isArray(patternString)) {
      return patternString.filter((pattern) => pattern && pattern.length > 0);
    }

    return patternString
      .split(',')
      .map((pattern) => pattern.trim())
      .filter((pattern) => pattern.length > 0);
  }

  applyPreset(preset) {
    const presets = {
      unrestricted: {
        // Current behavior - minimal restrictions
        blockedCommands: [],
        requireConfirmation: false,
        readOnlyMode: false,
      },
      standard: {
        // Balanced security - block obviously dangerous commands
        blockedCommands: [
          'rm -rf /',
          'rm -rf /*',
          'format',
          'diskutil eraseDisk',
          'dd if=/dev/zero of=/dev/',
          'mkfs',
          ':(){ :|:& };:', // Fork bomb
        ],
        requireConfirmation: true,
        readOnlyMode: false,
      },
      restricted: {
        // High security - read-only with minimal tools
        blockedCommands: ['*'], // Block all commands
        requireConfirmation: true,
        readOnlyMode: true,
      },
    };

    if (preset !== 'custom' && presets[preset]) {
      const settings = presets[preset];
      if (settings.blockedCommands) {
        this.blockedCommands = [...this.blockedCommands, ...settings.blockedCommands];
      }
      if (settings.requireConfirmation !== undefined) {
        this.requireConfirmation = settings.requireConfirmation;
      }
      if (settings.readOnlyMode !== undefined) {
        this.readOnlyMode = settings.readOnlyMode;
      }
    }
  }
}

/**
 * Command Security Service
 */
export class CommandSecurityService extends EventEmitter {
  constructor(config = {}) {
    super();
    this.config = new SecurityConfig(config);
    this.auditLog = [];
    this.pendingPermissions = new Map();

    logger.info('Command security initialized', {
      preset: this.config.preset,
      readOnlyMode: this.config.readOnlyMode,
      safeDirectories: this.config.safeDirectories.length,
      blockedCommands: this.config.blockedCommands.length,
    });
  }

  /**
   * Validate a command before execution
   * @param {string} command - The command to validate
   * @param {string} workingDirectory - The working directory
   * @param {Object} _options - Additional options
   * @returns {Promise<{allowed: boolean, reason?: string, requiresConfirmation?: boolean}>}
   */
  async validateCommand(command, workingDirectory, _options = {}) {
    const validation = {
      command,
      workingDirectory,
      timestamp: new Date().toISOString(),
      allowed: true,
      reason: null,
      requiresConfirmation: false,
    };

    try {
      // Check read-only mode
      if (this.config.readOnlyMode && this.isWriteCommand(command)) {
        validation.allowed = false;
        validation.reason = 'Read-only mode is enabled';
        validation.code = 'READONLY_MODE';
      }

      // Check blocked commands
      if (validation.allowed && this.isBlockedCommand(command)) {
        validation.allowed = false;
        validation.reason = 'Command matches blocked pattern';
        validation.code = 'BLOCKED_COMMAND';
      }

      // Check destructive commands
      if (validation.allowed && this.isDestructiveCommand(command)) {
        if (this.config.requireConfirmation) {
          validation.requiresConfirmation = true;
          validation.reason = 'Destructive command requires confirmation';
        }
      }

      // Validate working directory
      if (validation.allowed && workingDirectory) {
        const dirValidation = await this.validateDirectory(workingDirectory);
        if (!dirValidation.allowed) {
          validation.allowed = false;
          validation.reason = dirValidation.reason;
          validation.code = 'DIRECTORY_VIOLATION';
        }
      }

      // Extract and validate file paths from command
      if (validation.allowed) {
        const paths = this.extractPaths(command);
        for (const filePath of paths) {
          const pathValidation = await this.validatePath(filePath, workingDirectory);
          if (!pathValidation.allowed) {
            validation.allowed = false;
            validation.reason = pathValidation.reason;
            validation.code = 'PATH_VIOLATION';
            break;
          }
        }
      }

      // Audit log
      if (this.config.enableAudit) {
        this.logAudit(validation);
      }

      // Emit security event
      this.emit('commandValidated', validation);

      return validation;
    } catch (error) {
      logger.error('Command validation error', { error: error.message, command });
      validation.allowed = false;
      validation.reason = `Validation error: ${error.message}`;
      validation.code = 'VALIDATION_ERROR';

      if (this.config.enableAudit) {
        this.logAudit(validation);
      }

      return validation;
    }
  }

  /**
   * Check if command is a write operation
   */
  isWriteCommand(command) {
    const writePatterns = [
      /^(echo|printf|cat).+>/, // Output redirection
      /^(rm|rmdir|unlink)/, // Deletion
      /^(mv|cp|rsync)/, // Move/copy
      /^(mkdir|touch)/, // Creation
      /^(chmod|chown)/, // Permission changes
      /^(sed|awk).+-i/, // In-place editing
      /^git\s+(add|commit|push|merge|rebase)/, // Git writes
      /^npm\s+(install|uninstall|update)/, // Package changes
      /^(apt|yum|brew)\s+(install|remove)/, // System packages
    ];

    return writePatterns.some((pattern) => pattern.test(command));
  }

  /**
   * Check if command matches blocked patterns
   */
  isBlockedCommand(command) {
    if (this.config.blockedCommands.includes('*')) {
      return true; // Block all commands
    }

    return this.config.blockedCommands.some((blocked) => {
      // Exact match or pattern match
      if (blocked === command) return true;
      if (command.includes(blocked)) return true;

      // Try as regex
      try {
        const safeBlocked = _.escapeRegExp(blocked);
        const regex = new RegExp(safeBlocked);
        return regex.test(command);
      } catch {
        return false;
      }
    });
  }

  /**
   * Check if command is potentially destructive
   */
  isDestructiveCommand(command) {
    const destructivePatterns = [
      /rm\s+-rf/, // Recursive force delete
      /rm\s+.*\*/, // Wildcard deletion
      />\s*\/dev\/(sda|disk)/, // Writing to disk devices
      /mkfs/, // Format filesystem
      /dd\s+if=.+of=\/dev\//, // Direct disk write
      /format\s+/i, // Format commands
      /diskutil\s+erase/, // macOS disk erase
      /:(){ :|:& };:/, // Fork bomb
    ];

    // Check configured patterns
    const isConfiguredDestructive = this.config.destructiveCommands.some((pattern) => {
      if (command.includes(pattern)) return true;
      try {
        const regex = new RegExp(pattern);
        return regex.test(command);
      } catch {
        return false;
      }
    });

    // Check built-in patterns
    const isBuiltinDestructive = destructivePatterns.some((pattern) => pattern.test(command));

    return isConfiguredDestructive || isBuiltinDestructive;
  }

  /**
   * Extract file paths from command
   */
  extractPaths(command) {
    const paths = [];

    // Common patterns for file paths in commands
    const patterns = [
      /(?:^|\s)([~/][^\s]*)/g, // Absolute paths
      /(?:^|\s)\.\.\/([^\s]*)/g, // Parent directory paths
      />\s*([^\s]+)/g, // Output redirection
      /<\s*([^\s]+)/g, // Input redirection
      /--file[=\s]+([^\s]+)/g, // --file arguments
      /-f\s+([^\s]+)/g, // -f arguments
    ];

    patterns.forEach((pattern) => {
      let match;
      while ((match = pattern.exec(command)) !== null) {
        if (match[1]) {
          paths.push(match[1]);
        }
      }
    });

    return paths;
  }

  /**
   * Validate a directory is within safe directories
   */
  async validateDirectory(directory) {
    // If no safe directories configured, allow all (backward compatibility)
    if (this.config.safeDirectories.length === 0) {
      return { allowed: true };
    }

    try {
      const resolvedDir = path.resolve(directory);

      // Check if directory is within any safe directory
      const isWithinSafe = this.config.safeDirectories.some((safeDir) => {
        return resolvedDir === safeDir || resolvedDir.startsWith(safeDir + path.sep);
      });

      if (!isWithinSafe) {
        return {
          allowed: false,
          reason: `Directory '${directory}' is outside configured safe directories`,
        };
      }

      return { allowed: true };
    } catch (error) {
      return {
        allowed: false,
        reason: `Directory validation failed: ${error.message}`,
      };
    }
  }

  /**
   * Validate a file path
   */
  async validatePath(filePath, workingDirectory) {
    // If no safe directories configured, allow all
    if (this.config.safeDirectories.length === 0) {
      return { allowed: true };
    }

    try {
      // Resolve path relative to working directory
      const resolvedPath = path.resolve(workingDirectory || process.cwd(), filePath);

      // Check if path is within any safe directory
      const isWithinSafe = this.config.safeDirectories.some((safeDir) => {
        return resolvedPath.startsWith(safeDir + path.sep) || resolvedPath === safeDir;
      });

      if (!isWithinSafe) {
        return {
          allowed: false,
          reason: `Path '${filePath}' is outside configured safe directories`,
        };
      }

      return { allowed: true };
    } catch (error) {
      return {
        allowed: false,
        reason: `Path validation failed: ${error.message}`,
      };
    }
  }

  /**
   * Log audit entry
   */
  logAudit(entry) {
    const auditEntry = {
      ...entry,
      id: Date.now().toString(),
      sessionId: entry.sessionId || null,
    };

    this.auditLog.push(auditEntry);

    // Limit audit log size
    if (this.auditLog.length > 10000) {
      this.auditLog.shift();
    }

    // Emit audit event
    this.emit('auditLogged', auditEntry);

    // Log security violations
    if (!entry.allowed) {
      logger.warn('Security violation', {
        command: entry.command,
        reason: entry.reason,
        code: entry.code,
      });
    }
  }

  /**
   * Get audit log
   */
  getAuditLog(options = {}) {
    const { limit = 100, sessionId, allowed } = options;

    let filtered = [...this.auditLog];

    if (sessionId !== undefined) {
      filtered = filtered.filter((entry) => entry.sessionId === sessionId);
    }

    if (allowed !== undefined) {
      filtered = filtered.filter((entry) => entry.allowed === allowed);
    }

    // Return most recent entries
    return filtered.slice(-limit).reverse();
  }

  /**
   * Clear audit log
   */
  clearAuditLog() {
    const count = this.auditLog.length;
    this.auditLog = [];
    logger.info('Audit log cleared', { entriesRemoved: count });
    return count;
  }

  /**
   * Request permission for a command
   */
  async requestPermission(command, workingDirectory, options = {}) {
    const requestId = Date.now().toString();

    const request = {
      id: requestId,
      command,
      workingDirectory,
      timestamp: new Date().toISOString(),
      status: 'pending',
      ...options,
    };

    this.pendingPermissions.set(requestId, request);

    // Emit permission request event
    this.emit('permissionRequested', request);

    // Set timeout for auto-deny
    setTimeout(() => {
      if (this.pendingPermissions.has(requestId)) {
        this.denyPermission(requestId, 'Timeout - no response received');
      }
    }, options.timeout || 30000); // 30 second default timeout

    return requestId;
  }

  /**
   * Approve a permission request
   */
  approvePermission(requestId) {
    const request = this.pendingPermissions.get(requestId);
    if (!request) {
      throw new Error(`Permission request ${requestId} not found`);
    }

    request.status = 'approved';
    request.resolvedAt = new Date().toISOString();

    this.pendingPermissions.delete(requestId);

    // Log to audit
    if (this.config.enableAudit) {
      this.logAudit({
        ...request,
        allowed: true,
        reason: 'User approved',
      });
    }

    this.emit('permissionResolved', request);

    return request;
  }

  /**
   * Deny a permission request
   */
  denyPermission(requestId, reason = 'User denied') {
    const request = this.pendingPermissions.get(requestId);
    if (!request) {
      throw new Error(`Permission request ${requestId} not found`);
    }

    request.status = 'denied';
    request.reason = reason;
    request.resolvedAt = new Date().toISOString();

    this.pendingPermissions.delete(requestId);

    // Log to audit
    if (this.config.enableAudit) {
      this.logAudit({
        ...request,
        allowed: false,
        reason,
      });
    }

    this.emit('permissionResolved', request);

    return request;
  }

  /**
   * Get pending permission requests
   */
  getPendingPermissions() {
    return Array.from(this.pendingPermissions.values());
  }

  /**
   * Update security configuration
   */
  updateConfig(newConfig) {
    this.config = new SecurityConfig({ ...this.config, ...newConfig });

    logger.info('Security configuration updated', {
      preset: this.config.preset,
      readOnlyMode: this.config.readOnlyMode,
    });

    this.emit('configUpdated', this.config);
  }

  /**
   * Get current configuration
   */
  getConfig() {
    return {
      preset: this.config.preset,
      safeDirectories: this.config.safeDirectories,
      blockedCommands: this.config.blockedCommands,
      destructiveCommands: this.config.destructiveCommands,
      requireConfirmation: this.config.requireConfirmation,
      maxFileSize: this.config.maxFileSize,
      readOnlyMode: this.config.readOnlyMode,
      enableAudit: this.config.enableAudit,
    };
  }

  /**
   * Test if a command would be allowed
   */
  async testCommand(command, workingDirectory) {
    const validation = await this.validateCommand(command, workingDirectory, {
      test: true, // Don't log to audit in test mode
    });

    return {
      allowed: validation.allowed,
      reason: validation.reason,
      requiresConfirmation: validation.requiresConfirmation,
    };
  }
}

// Export singleton instance
export const commandSecurity = new CommandSecurityService();
