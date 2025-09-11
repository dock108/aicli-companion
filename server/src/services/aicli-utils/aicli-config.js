/**
 * Configuration and Command Utilities
 * Handles timeout calculation and AICLI command discovery
 */

import { existsSync } from 'fs';
import { execSync } from 'child_process';

export class AICLIConfig {
  static calculateTimeoutForCommand(command) {
    if (!command || typeof command !== 'string') {
      return 60000; // 1 minute default
    }

    const length = command.length;
    const lowerCommand = command.toLowerCase();

    // Keywords that indicate complex operations
    const complexKeywords = [
      'review',
      'analyze',
      'audit',
      'assess',
      'evaluate',
      'examine',
      'refactor',
      'optimize',
      'improve',
      'redesign',
      'restructure',
      'debug',
      'troubleshoot',
      'investigate',
      'diagnose',
      'document',
      'explain',
      'summarize',
      'overview',
      'test',
      'benchmark',
      'profile',
      'performance',
    ];

    const veryComplexKeywords = [
      'expert',
      'comprehensive',
      'thorough',
      'complete',
      'full',
      'entire project',
      'whole codebase',
      'all files',
    ];

    // Check for very complex operations
    const hasVeryComplexKeywords = veryComplexKeywords.some((keyword) =>
      lowerCommand.includes(keyword)
    );

    // Check for complex operations
    const hasComplexKeywords = complexKeywords.some((keyword) => lowerCommand.includes(keyword));

    // Calculate base timeout
    let timeoutMs;

    if (hasVeryComplexKeywords) {
      timeoutMs = 600000; // 10 minutes for very complex operations
    } else if (hasComplexKeywords) {
      timeoutMs = 300000; // 5 minutes for complex operations
    } else if (length > 200) {
      timeoutMs = 300000; // 5 minutes for long commands
    } else if (length > 50) {
      timeoutMs = 180000; // 3 minutes for medium commands
    } else {
      timeoutMs = 120000; // 2 minutes for simple commands
    }

    console.log(
      `🕐 Calculated timeout for command: ${timeoutMs}ms (${Math.round(timeoutMs / 1000)}s)`
    );
    console.log(`   Command length: ${length} chars`);
    console.log(`   Has complex keywords: ${hasComplexKeywords}`);
    console.log(`   Has very complex keywords: ${hasVeryComplexKeywords}`);

    return timeoutMs;
  }

  static findAICLICommand() {
    // First check if CLAUDE_CLI_PATH env variable is set
    if (process.env.CLAUDE_CLI_PATH) {
      console.log(`Using AICLI CLI path from CLAUDE_CLI_PATH: ${process.env.CLAUDE_CLI_PATH}`);
      return process.env.CLAUDE_CLI_PATH;
    }

    // CRITICAL: Never run execSync in test environment
    if (process.env.NODE_ENV === 'test') {
      return 'claude';
    }

    // Try to use 'which' command to find claude
    try {
      const path = execSync('which claude', { encoding: 'utf8' }).trim();
      if (path) {
        console.log(`Found AICLI CLI at: ${path}`);
        return path;
      }
    } catch (error) {
      // 'which' failed, try common locations
    }

    // Common installation paths for claude
    const commonPaths = [
      '/usr/local/bin/claude',
      '/opt/homebrew/bin/claude',
      `${process.env.HOME}/.local/bin/claude`,
    ];

    for (const path of commonPaths) {
      if (existsSync(path)) {
        console.log(`Found AICLI CLI at: ${path}`);
        return path;
      }
    }

    console.log('AICLI CLI not found in common locations, using "claude" as fallback');
    // Default fallback - let the system find it
    return 'claude';
  }
}
