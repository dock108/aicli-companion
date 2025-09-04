/**
 * Planning Mode Service
 * Manages restrictions and configurations for planning/documentation-only mode
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('PlanningMode');

export class PlanningModeService {
  constructor() {
    // Default allowed extensions for planning mode
    this.defaultAllowedExtensions = [
      '.md', // Markdown
      '.txt', // Plain text
      '.doc', // Documentation
      '.docx', // Word docs
      '.plan', // Plan files
      '.todo', // Todo lists
      '.rst', // reStructuredText
      '.adoc', // AsciiDoc
      '.org', // Org mode
      '.wiki', // Wiki format
      '.notes', // Notes files
      '.yml', // YAML config (for docs)
      '.yaml', // YAML config (for docs)
      '.json', // JSON (for configuration docs)
    ];

    // Files that can be written regardless of extension
    this.allowedFileNames = [
      'README',
      'TODO',
      'PLAN',
      'ISSUES',
      'NOTES',
      'CHANGELOG',
      'CONTRIBUTING',
      'AUTHORS',
      'LICENSE',
    ];

    // Load custom extensions from environment
    this.loadCustomExtensions();
  }

  /**
   * Load custom extensions from environment variables
   */
  loadCustomExtensions() {
    const customExtensions = process.env.PLANNING_MODE_EXTENSIONS;
    if (customExtensions) {
      const extensions = customExtensions.split(',').map((ext) => ext.trim());
      this.customAllowedExtensions = extensions;
      logger.info('Custom planning mode extensions loaded', { extensions });
    }
  }

  /**
   * Get all allowed extensions for planning mode
   */
  getAllowedExtensions() {
    return this.customAllowedExtensions || this.defaultAllowedExtensions;
  }

  /**
   * Check if a file path is allowed for writing in planning mode
   */
  isFileAllowedForWriting(filePath) {
    if (!filePath) return false;

    // Extract filename and extension
    const pathParts = filePath.split('/');
    const fileName = pathParts[pathParts.length - 1];
    const fileNameWithoutExt = fileName.split('.')[0];
    const extension = fileName.includes('.') ? `.${fileName.split('.').pop()}` : '';

    // Check if it's an allowed file name (regardless of extension)
    if (this.allowedFileNames.some((name) => fileNameWithoutExt.toUpperCase() === name)) {
      logger.debug('File allowed by name', { filePath, fileName });
      return true;
    }

    // Check if extension is allowed
    const allowedExtensions = this.getAllowedExtensions();
    const isAllowed = allowedExtensions.includes(extension.toLowerCase());

    logger.debug('File write permission check', {
      filePath,
      extension,
      isAllowed,
      allowedExtensions,
    });

    return isAllowed;
  }

  /**
   * Wrap user prompt with planning mode restrictions
   */
  wrapPromptForPlanning(userPrompt) {
    const wrappedPrompt = {
      mode: 'planning',
      instructions: {
        primary: 'You are in PLANNING MODE. You can only create or modify documentation files.',
        restrictions: [
          'You may READ any file to understand the codebase',
          'You may ONLY WRITE to documentation files',
          `Documentation files include: ${this.getAllowedExtensions().join(', ')}`,
          'Also allowed: README, TODO, PLAN, ISSUES, NOTES, CHANGELOG files',
          'You must REFUSE to modify code files with a polite explanation',
        ],
        onViolation:
          'If asked to modify code, respond: "I\'m in Planning Mode and can only modify documentation files. Would you like me to create a plan for these changes instead?"',
      },
      userPrompt,
      timestamp: new Date().toISOString(),
    };

    logger.info('Wrapped prompt for planning mode', {
      originalLength: userPrompt.length,
      wrappedLength: JSON.stringify(wrappedPrompt).length,
    });

    return JSON.stringify(wrappedPrompt);
  }

  /**
   * Build tool restrictions for planning mode
   */
  buildToolRestrictions() {
    const allowedTools = [
      'Read', // Can read any file
      'Grep', // Can search any file
      'Bash:ls', // Can list directories
      'Bash:find', // Can find files
      'Bash:cat', // Can view files
      'Bash:head', // Can preview files
      'Bash:tail', // Can view file ends
      'Bash:pwd', // Can check current directory
      'Bash:tree', // Can view directory structure
    ];

    // For Write and Edit tools, we need dynamic validation
    // These will be checked per-file in validateFileOperation

    return {
      allowedTools,
      requiresValidation: ['Write', 'Edit', 'MultiEdit', 'Create'],
      disallowedTools: ['Delete', 'Bash:rm', 'Bash:mv'], // No deletion in planning mode
    };
  }

  /**
   * Validate a file operation in planning mode
   */
  validateFileOperation(operation, filePath, mode = 'normal') {
    if (mode !== 'planning') {
      return { allowed: true };
    }

    // Read operations are always allowed
    if (operation === 'Read' || operation === 'Grep') {
      return { allowed: true };
    }

    // Write/Edit operations need file validation
    if (['Write', 'Edit', 'MultiEdit', 'Create'].includes(operation)) {
      const isAllowed = this.isFileAllowedForWriting(filePath);

      if (!isAllowed) {
        return {
          allowed: false,
          reason: `Planning Mode: Cannot modify code file '${filePath}'. Only documentation files are allowed.`,
          suggestion: 'Would you like me to create a plan document for these changes instead?',
        };
      }

      return { allowed: true };
    }

    // Delete operations are not allowed in planning mode
    if (operation === 'Delete') {
      return {
        allowed: false,
        reason:
          'Planning Mode: File deletion is not allowed. You can only create or modify documentation.',
        suggestion: 'Consider creating a TODO document listing files to be deleted instead.',
      };
    }

    // Default allow for other operations
    return { allowed: true };
  }

  /**
   * Generate planning mode status message
   */
  getStatusMessage(mode) {
    if (mode !== 'planning') {
      return null;
    }

    return {
      mode: 'planning',
      emoji: '📝',
      title: 'Planning Mode Active',
      description: 'Only documentation files can be modified',
      allowedExtensions: this.getAllowedExtensions(),
      allowedFileNames: this.allowedFileNames,
      restrictions: [
        'Can read any file',
        'Can only write to documentation files',
        'Cannot delete files',
        'Cannot run arbitrary commands',
      ],
    };
  }

  /**
   * Check if planning mode should be enforced server-side
   */
  shouldEnforceServerSide() {
    return process.env.PLANNING_MODE_STRICT === 'true';
  }

  /**
   * Generate error response for planning mode violations
   */
  generateViolationResponse(operation, filePath) {
    return {
      error: 'Planning Mode Violation',
      message: `Cannot ${operation} '${filePath}' in Planning Mode`,
      details: 'Planning Mode restricts modifications to documentation files only.',
      allowedExtensions: this.getAllowedExtensions(),
      suggestion: 'To modify code files, please switch to Normal or Code mode.',
      mode: 'planning',
    };
  }
}

// Export singleton instance
export const planningMode = new PlanningModeService();

export default planningMode;
