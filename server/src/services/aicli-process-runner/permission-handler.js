/**
 * Permission Handler
 * Manages permission settings and tool validation
 */

import { EventEmitter } from 'events';
import { createLogger } from '../../utils/logger.js';
import { permissionManager } from '../permission-manager.js';
import { commandSecurity } from '../command-security.js';

const logger = createLogger('PermissionHandler');

export class PermissionHandler extends EventEmitter {
  constructor(config) {
    super();
    this.config = config;
  }

  /**
   * Configure permission settings
   */
  setPermissionMode(mode) {
    const validModes = ['default', 'acceptEdits', 'bypassPermissions', 'plan'];
    if (validModes.includes(mode)) {
      this.config.permissionMode = mode;
      logger.info('Permission mode set', { mode });
    } else {
      logger.warn('Invalid permission mode', { mode, validModes });
    }
  }

  /**
   * Set allowed tools
   */
  setAllowedTools(tools) {
    this.config.allowedTools = tools;
    logger.info('Allowed tools updated', { tools });
  }

  /**
   * Set disallowed tools
   */
  setDisallowedTools(tools) {
    this.config.disallowedTools = tools;
    logger.info('Disallowed tools updated', { tools });
  }

  /**
   * Set skip permissions flag
   */
  setSkipPermissions(skip) {
    this.config.skipPermissions = skip;
    logger.info('Skip permissions updated', { skip });
  }

  /**
   * Validate tool use with permission manager
   */
  async validateToolUse(toolName, toolInput, sessionId) {
    // Planning mode is now handled via prompt prefix, not permission validation
    // Claude will self-regulate based on the planning mode instructions

    // Check with permission manager
    const permissionResult = await permissionManager.checkToolPermission(
      toolName,
      toolInput,
      sessionId
    );

    if (!permissionResult.allowed) {
      logger.warn('Tool use denied by permission manager', {
        tool: toolName,
        reason: permissionResult.reason,
        sessionId,
      });

      this.emit('permissionDenied', {
        tool: toolName,
        reason: permissionResult.reason,
        sessionId,
      });

      return false;
    }

    // Additional security checks for file operations
    if (['Write', 'Edit', 'Delete'].includes(toolName) && toolInput.file_path) {
      const securityCheck = await commandSecurity.validateFilePath(toolInput.file_path);
      if (!securityCheck.allowed) {
        logger.warn('File operation denied by security check', {
          tool: toolName,
          path: toolInput.file_path,
          reason: securityCheck.reason,
        });

        this.emit('permissionDenied', {
          tool: toolName,
          path: toolInput.file_path,
          reason: securityCheck.reason,
          sessionId,
        });

        return false;
      }
    }

    logger.info('Tool use approved', {
      tool: toolName,
      sessionId,
    });

    this.emit('permissionGranted', {
      tool: toolName,
      sessionId,
    });

    return true;
  }

  /**
   * Check if a tool is allowed based on configuration
   */
  isToolAllowed(toolName) {
    // Check disallowed list first
    if (this.config.disallowedTools && this.config.disallowedTools.includes(toolName)) {
      return false;
    }

    // Check allowed list if specified
    if (this.config.allowedTools && this.config.allowedTools.length > 0) {
      return this.config.allowedTools.includes(toolName);
    }

    // Default to allowed
    return true;
  }

  /**
   * Build permission arguments for CLI command
   */
  buildPermissionArgs(skipPermissions) {
    const args = [];

    // Check if permissions should be skipped
    const shouldSkip =
      skipPermissions !== undefined ? skipPermissions : this.config.skipPermissions;

    if (shouldSkip) {
      args.push('--dangerously-skip-permissions');
      return args;
    }

    // Add permission mode if not default
    // Note: Planning mode is handled via prompt prefix, not permission restrictions
    if (this.config.permissionMode && this.config.permissionMode !== 'default') {
      args.push('--permission-mode', this.config.permissionMode);
    }

    // Add allowed tools if specified
    if (this.config.allowedTools && this.config.allowedTools.length > 0) {
      args.push('--allow-tools', this.config.allowedTools.join(','));
    }

    // Add disallowed tools if specified
    if (this.config.disallowedTools && this.config.disallowedTools.length > 0) {
      args.push('--disallow-tools', this.config.disallowedTools.join(','));
    }

    return args;
  }

  /**
   * Handle permission request from Claude
   */
  async handlePermissionRequest(request, sessionId) {
    const { tool, input } = request;

    logger.info('Permission request received', {
      tool,
      sessionId,
      hasInput: !!input,
    });

    this.emit('permissionRequired', {
      tool,
      input,
      sessionId,
    });

    // Check if we should auto-approve based on mode
    if (this.config.skipPermissions || this.config.permissionMode === 'bypassPermissions') {
      logger.info('Auto-approving permission request', {
        tool,
        sessionId,
        mode: this.config.permissionMode,
      });
      return { approved: true, auto: true };
    }

    // Otherwise validate normally
    const approved = await this.validateToolUse(tool, input, sessionId);
    return { approved, auto: false };
  }
}

export default PermissionHandler;
