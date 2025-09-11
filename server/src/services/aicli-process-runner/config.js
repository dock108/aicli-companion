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
    this._aicliCommandPromise = null;
    this.spawnFunction = options.spawnFunction || spawn;

    // Permission configuration - using prompt-based security
    this.permissionMode = 'default';
    this.allowedTools = []; // Not used when skipPermissions = true
    this.disallowedTools = [];
    this.skipPermissions = true; // Enable --dangerously-skip-permissions for prompt-based security

    // Initialize the command immediately
    this.initializeCommand();
  }

  async initializeCommand() {
    if (process.env.NODE_ENV === 'test') {
      this._aicliCommand = 'claude';
    } else if (!this._aicliCommandPromise) {
      this._aicliCommandPromise = this.findAICLICommand();
      this._aicliCommand = await this._aicliCommandPromise;
    }
  }

  // Lazy getter for AICLI command - returns the resolved value or 'claude' as fallback
  get aicliCommand() {
    // If already resolved, return it
    if (this._aicliCommand) {
      return this._aicliCommand;
    }

    // In test environment, just return 'claude'
    if (process.env.NODE_ENV === 'test') {
      this._aicliCommand = 'claude';
      return this._aicliCommand;
    }

    // Otherwise, return 'claude' as a fallback and let initializeCommand handle async resolution
    // This prevents [object Promise] from being used as a command
    return 'claude';
  }

  // Async getter for when we need to ensure the command is resolved
  async getAicliCommand() {
    if (this._aicliCommand) {
      return this._aicliCommand;
    }

    if (this._aicliCommandPromise) {
      return this._aicliCommandPromise;
    }

    // Reinitialize if needed
    await this.initializeCommand();
    return this._aicliCommand || 'claude';
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
