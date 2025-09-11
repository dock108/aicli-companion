/**
 * Session Lifecycle
 * Manages session creation, updates, and cleanup
 */

import { createLogger } from '../../utils/logger.js';
import { InputValidator } from '../aicli-utils.js';
import { AICLIMessageHandler } from '../aicli-message-handler.js';
import { getTelemetryService } from '../telemetry.js';
import { messageQueueManager } from '../message-queue.js';

const logger = createLogger('SessionLifecycle');

export class SessionLifecycle {
  constructor(storage, config, eventEmitter) {
    this.storage = storage;
    this.config = config;
    this.eventEmitter = eventEmitter;
  }

  /**
   * Create a new interactive session
   */
  async createSession(sessionId, initialPrompt, workingDirectory, options = {}) {
    // Check if this is a workspace session
    const isWorkspaceSession = options.workspace === true || workingDirectory === '__workspace__';

    // Validate and sanitize inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(initialPrompt);

    // For workspace mode, use parent directory of all projects
    // We'll keep __workspace__ as a marker but the actual directory is resolved later
    const validatedWorkingDir = isWorkspaceSession
      ? '__workspace__'
      : await InputValidator.validateWorkingDirectory(workingDirectory);

    // Check if session already exists for this directory
    // Skip check for workspace mode since it's special
    const existingSession = isWorkspaceSession
      ? null
      : await this.findSessionByWorkingDirectory(validatedWorkingDir);
    if (existingSession) {
      logger.info('Reusing existing session for directory', {
        sessionId: existingSession.sessionId,
        workingDirectory: validatedWorkingDir,
      });

      await this.updateActivity(existingSession.sessionId);

      // Mark conversation as started for reused sessions
      if (!existingSession.conversationStarted) {
        await this.markConversationStarted(existingSession.sessionId);
      }

      // Record telemetry
      getTelemetryService().recordSessionCreated(true); // reused = true

      return {
        sessionId: existingSession.sessionId,
        success: true,
        message: 'Reusing existing session for this project',
        reused: true,
      };
    }

    logger.info('Creating new session', {
      sessionId: sanitizedSessionId,
      workingDirectory: validatedWorkingDir,
    });

    // Create session data
    const session = {
      sessionId: sanitizedSessionId,
      workingDirectory: validatedWorkingDir,
      initialPrompt: sanitizedPrompt,
      createdAt: Date.now(),
      lastActivity: Date.now(),
      conversationStarted: false,
      timeoutId: null,
      skipPermissions: options.skipPermissions,
      isWorkspace: isWorkspaceSession,
      workspaceContext: isWorkspaceSession
        ? {
            rootDirectory: '__workspace__', // Marker that gets resolved to actual path
            mode: 'workspace',
            permissions: ['read', 'crossProject'],
          }
        : undefined,
    };

    // Store session
    this.storage.addActiveSession(sanitizedSessionId, session);

    // Initialize message buffer
    this.storage.addMessageBuffer(sanitizedSessionId, AICLIMessageHandler.createSessionBuffer());

    // Set up session timeout (skip in test environment)
    if (process.env.NODE_ENV !== 'test') {
      const timeoutId = setTimeout(() => {
        this.checkTimeout(sanitizedSessionId);
      }, this.config.sessionTimeout);

      session.timeoutId = timeoutId;
    }

    // Track for routing
    this.storage.setProjectSession(validatedWorkingDir, sanitizedSessionId);

    // Record telemetry
    getTelemetryService().recordSessionCreated(false); // reused = false

    logger.info('Session created successfully', { sessionId: sanitizedSessionId });

    return {
      sessionId: sanitizedSessionId,
      success: true,
      message: 'Session created successfully',
      reused: false,
    };
  }

  /**
   * Update session activity
   */
  async updateActivity(sessionId, activity = {}) {
    const session = this.storage.getSession(sessionId);
    if (!session) {
      logger.warn('Session not found for activity update', { sessionId });
      return false;
    }

    session.lastActivity = Date.now();

    // Update Claude session if mapped
    const claudeSessionId = this.findClaudeSessionForOurSession(sessionId);
    if (claudeSessionId) {
      this.storage.updateClaudeSessionActivity(claudeSessionId);
    }

    // Reset timeout (skip in test environment)
    if (session.timeoutId && process.env.NODE_ENV !== 'test') {
      clearTimeout(session.timeoutId);
      session.timeoutId = setTimeout(() => {
        this.checkTimeout(sessionId);
      }, this.config.sessionTimeout);
    }

    logger.debug('Session activity updated', { sessionId, activity });
    return true;
  }

  /**
   * Mark conversation as started
   */
  async markConversationStarted(sessionId) {
    const session = this.storage.getSession(sessionId);
    if (session) {
      session.conversationStarted = true;
      logger.debug('Marked conversation as started', { sessionId });
      return true;
    }
    return false;
  }

  /**
   * Clean up a dead session
   */
  async cleanupSession(sessionId) {
    logger.info('Cleaning up session', { sessionId });

    // Remove from storage
    this.storage.removeActiveSession(sessionId);
    this.storage.removeMessageBuffer(sessionId);
    this.storage.removeInteractiveSession(sessionId);

    // Remove message queue
    messageQueueManager.removeQueue(sessionId);

    // Remove project mapping
    const allProjects = this.storage.getAllProjectSessions();
    for (const [projectPath, sid] of allProjects) {
      if (sid === sessionId) {
        this.storage.removeProjectSession(projectPath);
      }
    }

    logger.info('Session cleaned up', { sessionId });
  }

  /**
   * Kill a session
   */
  killSession(sessionId, reason = 'User requested termination') {
    logger.info('Killing session', { sessionId, reason });

    const interactiveSession = this.storage.getInteractiveSession(sessionId);
    if (interactiveSession && interactiveSession.process) {
      try {
        interactiveSession.process.kill();
        logger.info('Killed interactive process', {
          sessionId,
          pid: interactiveSession.process.pid,
        });
      } catch (error) {
        logger.error('Failed to kill process', {
          sessionId,
          error: error.message,
        });
      }
    }

    // Clean up session
    this.cleanupSession(sessionId);

    // Emit kill event
    this.eventEmitter.emit('sessionKilled', { sessionId, reason });
  }

  /**
   * Close an interactive session
   */
  closeSession(sessionId) {
    const interactiveSession = this.storage.getInteractiveSession(sessionId);
    if (!interactiveSession) {
      logger.warn('No interactive session found', { sessionId });
      return false;
    }

    try {
      if (interactiveSession.process && !interactiveSession.process.killed) {
        interactiveSession.process.stdin.end();
        interactiveSession.process.kill('SIGTERM');
      }

      this.storage.removeInteractiveSession(sessionId);
      logger.info('Closed interactive session', { sessionId });
      return true;
    } catch (error) {
      logger.error('Failed to close session', {
        sessionId,
        error: error.message,
      });
      return false;
    }
  }

  /**
   * Pause a session
   */
  pauseSession(sessionId) {
    messageQueueManager.pauseQueue(sessionId);
    logger.info('Session paused', { sessionId });
    return true;
  }

  /**
   * Resume a session
   */
  resumeSession(sessionId) {
    messageQueueManager.resumeQueue(sessionId);
    logger.info('Session resumed', { sessionId });
    return true;
  }

  /**
   * Clean up all sessions
   */
  async cleanupAllSessions() {
    const sessions = this.storage.getActiveSessions();

    for (const session of sessions) {
      await this.cleanupSession(session.sessionId);
    }

    logger.info('All sessions cleaned up', { count: sessions.length });
  }

  // Helper methods
  async findSessionByWorkingDirectory(workingDirectory) {
    for (const session of this.storage.getActiveSessions()) {
      if (session.workingDirectory === workingDirectory) {
        return session;
      }
    }
    return null;
  }

  findClaudeSessionForOurSession(ourSessionId) {
    for (const [claudeId, sessionData] of this.storage.getAllClaudeSessions()) {
      if (sessionData.ourSessionId === ourSessionId) {
        return claudeId;
      }
    }
    return null;
  }

  checkTimeout(sessionId) {
    this.eventEmitter.emit('checkTimeout', sessionId);
  }
}

export default SessionLifecycle;
