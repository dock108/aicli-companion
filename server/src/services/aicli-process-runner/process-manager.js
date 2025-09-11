/**
 * Process Manager
 * Manages AICLI process lifecycle and monitoring
 */

import { spawn } from 'child_process';
import { EventEmitter } from 'events';
import { createLogger } from '../../utils/logger.js';
import { processMonitor } from '../../utils/process-monitor.js';

const logger = createLogger('ProcessManager');

export class ProcessManager extends EventEmitter {
  constructor(config, spawnFunction = spawn) {
    super();
    this.config = config;
    this.spawnFunction = spawnFunction;
    this.activeProcesses = new Map(); // sessionId -> process
  }

  /**
   * Spawn a new AICLI process
   */
  spawnProcess(args, options) {
    try {
      const process = this.spawnFunction(this.config.aicliCommand, args, options);

      if (!process.pid) {
        throw new Error('Process failed to start (no PID)');
      }

      logger.info('Process spawned', {
        pid: process.pid,
        cwd: options.cwd,
        args: args.slice(0, 3), // Log first few args
      });

      this.emit('processStarted', { pid: process.pid });

      return process;
    } catch (error) {
      logger.error('Failed to spawn process', {
        error: error.message,
        code: error.code,
      });
      this.emit('processError', { error: error.message });
      throw error;
    }
  }

  /**
   * Register a process for tracking
   */
  registerProcess(sessionId, process) {
    this.activeProcesses.set(sessionId, process);

    // Monitor process exit
    process.on('exit', (code, signal) => {
      this.activeProcesses.delete(sessionId);
      logger.info('Process exited', { sessionId, code, signal });
      this.emit('processExited', { sessionId, code, signal });
    });

    process.on('error', (error) => {
      logger.error('Process error', { sessionId, error: error.message });
      this.emit('processError', { sessionId, error: error.message });
    });
  }

  /**
   * Kill a process by session ID
   */
  async killProcess(sessionId, reason = 'User requested cancellation') {
    const process = this.activeProcesses.get(sessionId);

    if (!process) {
      logger.warn('No active process found for session', { sessionId });
      return false;
    }

    logger.info('Killing process', { sessionId, pid: process.pid, reason });

    try {
      // Try graceful termination first
      process.kill('SIGTERM');

      // Give it 2 seconds to terminate gracefully
      await new Promise((resolve) => {
        const timeout = setTimeout(() => resolve(false), 2000);

        process.once('exit', () => {
          clearTimeout(timeout);
          resolve(true);
        });
      });

      // If still running, force kill
      if (this.activeProcesses.has(sessionId)) {
        logger.warn('Process did not terminate gracefully, forcing kill', { sessionId });
        process.kill('SIGKILL');
      }

      this.activeProcesses.delete(sessionId);
      return true;
    } catch (error) {
      logger.error('Failed to kill process', { sessionId, error: error.message });
      return false;
    }
  }

  /**
   * Get count of active processes
   */
  getActiveProcessCount() {
    return this.activeProcesses.size;
  }

  /**
   * Check if a session has an active process
   */
  hasActiveProcess(sessionId) {
    return this.activeProcesses.has(sessionId);
  }

  /**
   * Start monitoring a process
   */
  async startProcessMonitoring(pid) {
    try {
      await processMonitor.monitorProcess(pid);
      logger.info('Process monitoring started', { pid });
    } catch (error) {
      logger.warn('Failed to start process monitoring', {
        pid,
        error: error.message,
      });
    }
  }

  /**
   * Clean up all processes
   */
  async cleanup() {
    const promises = [];

    for (const [sessionId, process] of this.activeProcesses) {
      logger.info('Cleaning up process', { sessionId, pid: process.pid });
      promises.push(this.killProcess(sessionId, 'Cleanup'));
    }

    await Promise.all(promises);
    this.activeProcesses.clear();
  }
}

export default ProcessManager;
