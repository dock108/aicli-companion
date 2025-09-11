/**
 * Session Router
 * Handles session routing and mapping
 */

import { createLogger } from '../../utils/logger.js';

const logger = createLogger('SessionRouter');

export class SessionRouter {
  constructor(storage) {
    this.storage = storage;
  }

  /**
   * Find session by working directory
   */
  async findByWorkingDirectory(workingDirectory) {
    // Check project sessions mapping
    const sessionId = this.storage.getProjectSession(workingDirectory);

    if (sessionId) {
      const session = this.storage.getSession(sessionId);
      if (session) {
        logger.debug('Found session for working directory', {
          workingDirectory,
          sessionId,
        });
        return session;
      }
    }

    // Fallback: search through active sessions
    for (const session of this.storage.getActiveSessions()) {
      if (session.workingDirectory === workingDirectory) {
        logger.debug('Found session by directory search', {
          workingDirectory,
          sessionId: session.sessionId,
        });
        return session;
      }
    }

    return null;
  }

  /**
   * Track session for routing purposes
   */
  trackForRouting(sessionId, projectPath, ourSessionId = null) {
    // Store project path mapping
    if (projectPath) {
      this.storage.setProjectSession(projectPath, ourSessionId || sessionId);
      logger.debug('Tracked session for project', {
        projectPath,
        sessionId: ourSessionId || sessionId,
      });
    }

    // If this is a Claude session, track it
    if (sessionId && sessionId !== ourSessionId) {
      this.storage.addClaudeSession(sessionId, {
        ourSessionId,
        projectPath,
        createdAt: Date.now(),
        lastActivity: Date.now(),
      });
      logger.debug('Tracked Claude session', {
        claudeSessionId: sessionId,
        ourSessionId,
      });
    }

    // Create a temporary session for response routing if needed
    if (!this.storage.hasActiveSession(sessionId)) {
      const session = {
        sessionId,
        workingDirectory: projectPath,
        createdAt: Date.now(),
        lastActivity: Date.now(),
        conversationStarted: true,
        timeoutId: null,
        isTemporary: true,
      };

      this.storage.addActiveSession(sessionId, session);
      logger.info('Temporarily tracking session for response routing', { sessionId });
    }
  }

  /**
   * Map Claude session to our session
   */
  mapClaudeSession(ourSessionId, claudeSessionId) {
    if (!claudeSessionId || !ourSessionId) {
      logger.warn('Invalid session mapping attempt', {
        ourSessionId,
        claudeSessionId,
      });
      return false;
    }

    // Update or create Claude session record
    const existingSession = this.storage.getClaudeSession(claudeSessionId);

    if (existingSession) {
      existingSession.ourSessionId = ourSessionId;
      existingSession.lastActivity = Date.now();
      logger.debug('Updated Claude session mapping', {
        claudeSessionId,
        ourSessionId,
      });
    } else {
      this.storage.addClaudeSession(claudeSessionId, {
        ourSessionId,
        createdAt: Date.now(),
        lastActivity: Date.now(),
      });
      logger.debug('Created Claude session mapping', {
        claudeSessionId,
        ourSessionId,
      });
    }

    // Update our session to reference the Claude session
    const ourSession = this.storage.getSession(ourSessionId);
    if (ourSession) {
      ourSession.claudeSessionId = claudeSessionId;
      ourSession.lastActivity = Date.now();
    }

    return true;
  }

  /**
   * Find Claude session for our session
   */
  findClaudeSessionForOurSession(ourSessionId) {
    // First check if our session has a direct reference
    const ourSession = this.storage.getSession(ourSessionId);
    if (ourSession?.claudeSessionId) {
      return ourSession.claudeSessionId;
    }

    // Search through Claude sessions
    for (const [claudeId, sessionData] of this.storage.getAllClaudeSessions()) {
      if (sessionData.ourSessionId === ourSessionId) {
        return claudeId;
      }
    }

    return null;
  }

  /**
   * Find our session for a Claude session
   */
  findOurSessionForClaudeSession(claudeSessionId) {
    const claudeSession = this.storage.getClaudeSession(claudeSessionId);
    if (claudeSession?.ourSessionId) {
      return claudeSession.ourSessionId;
    }

    // Search through active sessions
    for (const session of this.storage.getActiveSessions()) {
      if (session.claudeSessionId === claudeSessionId) {
        return session.sessionId;
      }
    }

    return null;
  }

  /**
   * Get routing statistics
   */
  getRoutingStats() {
    return {
      projectMappings: this.storage.getAllProjectSessions().size,
      claudeSessions: this.storage.getAllClaudeSessions().size,
      activeSessions: this.storage.getActiveSessions().length,
    };
  }
}

export default SessionRouter;
