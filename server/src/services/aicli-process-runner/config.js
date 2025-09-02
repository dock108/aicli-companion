/**
 * AICLI Configuration
 * Handles AICLI command detection and configuration
 */

import { spawn } from 'child_process';
import { createLogger } from '../../utils/logger.js';

const logger = createLogger('AICLIConfig');

export class AICLIConfig {
  constructor(options = {}) {
    this._aicliCommand = null;
    this.spawnFunction = options.spawnFunction || spawn;

    // Permission configuration
    this.permissionMode = 'default';
    this.allowedTools = ['Read', 'Write', 'Edit'];
    this.disallowedTools = [];
    this.skipPermissions = false;
  }

  // Lazy getter for AICLI command
  get aicliCommand() {
    if (!this._aicliCommand) {
      // Skip command detection in test environment to avoid spawning processes
      this._aicliCommand = process.env.NODE_ENV === 'test' ? 'claude' : this.findAICLICommand();
    }
    return this._aicliCommand;
  }

  /**
   * Try to find the AICLI CLI command using 'which'
   * Supports different installation methods:
   * - Global/uv tools: 'claude'
   * - Poetry: 'poetry run claude'
   * - Direct execution: './claude'
   */
  findAICLICommand() {
    if (process.env.NODE_ENV === 'test') {
      return 'claude';
    }

    try {
      const result = this.spawnFunction('which', ['claude'], {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      });

      // Wait for the process to complete
      let stdout = '';
      result.stdout.on('data', (data) => {
        stdout += data;
      });

      // Check if found
      return new Promise((resolve) => {
        result.on('close', (code) => {
          if (code === 0 && stdout.trim()) {
            logger.info('Found AICLI CLI command via which', { command: 'claude' });
            resolve('claude');
          } else {
            // Fallback to other methods if needed
            logger.warn('AICLI CLI not found via which, using fallback', { command: 'claude' });
            resolve('claude'); // Assume it's in PATH anyway
          }
        });
      });
    } catch (error) {
      logger.error('Error finding AICLI CLI command', { error: error.message });
      return 'claude'; // Default fallback
    }
  }

  /**
   * Test if the AICLI CLI is working
   */
  async testAICLICommand(testType = 'version') {
    return new Promise((resolve) => {
      const args = testType === 'version' ? ['--version'] : ['--help'];

      try {
        const testProcess = this.spawnFunction(this.aicliCommand, args, {
          timeout: 5000,
        });

        testProcess.on('close', (code) => {
          resolve(code === 0);
        });

        testProcess.on('error', () => {
          resolve(false);
        });
      } catch (error) {
        logger.error('AICLI CLI test failed', { error: error.message });
        resolve(false);
      }
    });
  }

  /**
   * Add permission-related arguments to the command
   */
  addPermissionArgs(args) {
    if (this.skipPermissions) {
      args.push('--dangerously-skip-permissions');
    } else {
      // Only add permission configuration if not skipping permissions

      // Add permission mode if configured
      if (this.permissionMode && this.permissionMode !== 'default') {
        args.push('--permission-mode');
        args.push(this.permissionMode);
      }

      // Add allowed tools if configured
      if (this.allowedTools && this.allowedTools.length > 0) {
        args.push('--allowedTools');
        args.push(this.allowedTools.join(','));
      }

      // Add disallowed tools if configured
      if (this.disallowedTools && this.disallowedTools.length > 0) {
        args.push('--disallowedTools');
        args.push(this.disallowedTools.join(','));
      }
    }

    return args;
  }
}

export default AICLIConfig;
