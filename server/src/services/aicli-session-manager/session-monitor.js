/**
 * Session Monitor
 * Monitors sessions for timeouts and resource usage
 */

import { createLogger } from '../../utils/logger.js';
import { messageQueueManager } from '../message-queue.js';

const logger = createLogger('SessionMonitor');

export class SessionMonitor {
  constructor(storage, config, eventEmitter) {
    this.storage = storage;
    this.config = config;
    this.eventEmitter = eventEmitter;
    this.monitoringInterval = null;
  }

  /**
   * Start monitoring sessions
   */
  start() {
    // Skip monitoring in test environment
    if (process.env.NODE_ENV === 'test') {
      logger.debug('Session monitoring skipped in test environment');
      return;
    }

    // Skip if already started
    if (this.monitoringInterval) {
      return;
    }

    // Check sessions every minute
    this.monitoringInterval = setInterval(() => {
      this.checkSessionTimeouts();
      // Clean up old expired sessions every hour
      if (Date.now() % (60 * 60 * 1000) < 60000) {
        this.cleanupExpiredClaudeSessions();
      }
    }, 60000); // Every minute

    logger.info('Session monitoring started');
  }

  /**
   * Stop monitoring
   */
  stop() {
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = null;
      logger.info('Session monitoring stopped');
    }
  }

  /**
   * Check for sessions approaching timeout
   */
  async checkSessionTimeouts() {
    const now = Date.now();

    // Check Claude sessions
    for (const [sessionId, sessionData] of this.storage.getAllClaudeSessions()) {
      const timeSinceActivity = now - sessionData.lastActivity;
      const timeUntilTimeout = this.config.sessionTimeout - timeSinceActivity;

      // Send warning when approaching timeout (within the warning window)
      if (
        timeSinceActivity >= this.config.sessionWarningTime &&
        timeUntilTimeout > 0 &&
        !sessionData.warningsSent?.includes('timeout_warning')
      ) {
        const hoursInactive = Math.floor(timeSinceActivity / (60 * 60 * 1000));
        const minutesInactive = Math.floor((timeSinceActivity % (60 * 60 * 1000)) / (60 * 1000));

        logger.warn('Session approaching timeout', {
          sessionId,
          hoursInactive,
          minutesInactive,
          lastActivity: new Date(sessionData.lastActivity).toISOString(),
          timeUntilTimeout: Math.floor(timeUntilTimeout / (60 * 1000)),
        });

        // Mark warning as sent
        if (!sessionData.warningsSent) sessionData.warningsSent = [];
        sessionData.warningsSent.push('timeout_warning');

        // Emit event for push notification
        this.eventEmitter.emit('sessionWarning', {
          sessionId,
          type: 'timeout',
          message: 'Session will expire in 4 hours due to inactivity',
          timeRemaining: timeUntilTimeout,
        });
      }

      // Mark as expired after 24 hours of inactivity
      if (timeUntilTimeout <= 0 && !sessionData.expired) {
        logger.warn('Session expired due to inactivity', {
          sessionId,
          lastActivity: new Date(sessionData.lastActivity).toISOString(),
        });

        sessionData.expired = true;

        // Emit event
        this.eventEmitter.emit('sessionExpired', {
          sessionId,
          reason: 'inactivity_timeout',
          lastActivity: new Date(sessionData.lastActivity).toISOString(),
        });
      }
    }

    // Check active sessions
    for (const [sessionId, session] of this.storage.getAllActiveSessions()) {
      // Check if we should run timeout check for this session
      const timeSinceLastCheck = now - (session.lastTimeoutCheck || 0);

      if (timeSinceLastCheck >= this.config.minTimeoutCheckInterval && session.timeoutId) {
        this.checkTimeout(sessionId);
        session.lastTimeoutCheck = now;
      }
    }
  }

  /**
   * Check timeout for a specific session
   */
  checkTimeout(sessionId) {
    const session = this.storage.getSession(sessionId);
    if (!session) return;

    const now = Date.now();
    const timeSinceActivity = now - (session.lastActivity || session.createdAt);
    const hasMessages = this.checkPendingMessages(sessionId);
    const isProcessing = session.isProcessing || false;

    // Only timeout if inactive AND no pending messages AND not actively processing
    if (timeSinceActivity > this.config.sessionTimeout && !hasMessages && !isProcessing) {
      logger.info('Session timeout triggered', {
        sessionId,
        timeSinceActivity,
        timeout: this.config.sessionTimeout,
      });

      // Clean up the session
      this.cleanupSessionResources(sessionId);

      // Emit timeout event
      this.eventEmitter.emit('sessionTimeout', {
        sessionId,
        reason: 'inactivity',
        lastActivity: session.lastActivity,
      });
    } else if (hasMessages) {
      logger.debug('Session has pending messages, skipping timeout', { sessionId });
    } else if (isProcessing) {
      logger.debug('Session is actively processing, skipping timeout', {
        sessionId,
        timeSinceActivity,
        isProcessing,
      });
    }
  }

  /**
   * Check if session has pending messages
   */
  checkPendingMessages(sessionId) {
    const queueStatus = messageQueueManager.getQueueStatus(sessionId);
    return queueStatus && queueStatus.queue.length > 0;
  }

  /**
   * Clean up expired Claude sessions
   */
  cleanupExpiredClaudeSessions() {
    const now = Date.now();
    const expiredSessions = [];

    for (const [sessionId, sessionData] of this.storage.getAllClaudeSessions()) {
      // Clean up sessions marked as expired more than 1 hour ago
      if (
        sessionData.expired &&
        now - sessionData.lastActivity > this.config.sessionTimeout + 3600000
      ) {
        expiredSessions.push(sessionId);
      }
    }

    for (const sessionId of expiredSessions) {
      logger.info('Cleaning up expired Claude session', { sessionId });
      this.storage.removeClaudeSession(sessionId);
    }

    if (expiredSessions.length > 0) {
      logger.info('Cleaned up expired sessions', { count: expiredSessions.length });
    }
  }

  /**
   * Clean up session resources
   */
  cleanupSessionResources(sessionId) {
    // Clear timeout if exists
    const session = this.storage.getSession(sessionId);
    if (session?.timeoutId) {
      clearTimeout(session.timeoutId);
    }

    // Remove session data
    this.storage.removeActiveSession(sessionId);
    this.storage.removeMessageBuffer(sessionId);

    // Remove message queue
    messageQueueManager.removeQueue(sessionId);

    logger.info('Cleaned up session resources', { sessionId });
  }
}

export default SessionMonitor;
