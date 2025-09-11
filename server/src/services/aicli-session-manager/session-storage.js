/**
 * Session Storage
 * Manages in-memory storage of sessions and related data
 */

import { createLogger } from '../../utils/logger.js';

const logger = createLogger('SessionStorage');

export class SessionStorage {
  constructor() {
    // Session storage maps
    this.activeSessions = new Map();
    this.sessionMessageBuffers = new Map();
    this.interactiveSessions = new Map(); // Track running Claude processes
    this.claudeSessions = new Map(); // Track Claude session IDs and their last activity
    this.projectSessions = new Map(); // Track project path → latest session ID mapping
  }

  // Active sessions
  addActiveSession(sessionId, sessionData) {
    this.activeSessions.set(sessionId, sessionData);
    logger.debug('Added active session', { sessionId });
  }

  getSession(sessionId) {
    return this.activeSessions.get(sessionId) || null;
  }

  hasActiveSession(sessionId) {
    return this.activeSessions.has(sessionId);
  }

  getActiveSessions() {
    return Array.from(this.activeSessions.values());
  }

  getAllActiveSessions() {
    return this.activeSessions;
  }

  removeActiveSession(sessionId) {
    const removed = this.activeSessions.delete(sessionId);
    if (removed) {
      logger.debug('Removed active session', { sessionId });
    }
    return removed;
  }

  // Message buffers
  addMessageBuffer(sessionId, buffer) {
    this.sessionMessageBuffers.set(sessionId, buffer);
  }

  getMessageBuffer(sessionId) {
    return this.sessionMessageBuffers.get(sessionId);
  }

  hasMessageBuffer(sessionId) {
    return this.sessionMessageBuffers.has(sessionId);
  }

  removeMessageBuffer(sessionId) {
    return this.sessionMessageBuffers.delete(sessionId);
  }

  // Interactive sessions
  addInteractiveSession(sessionId, processInfo) {
    this.interactiveSessions.set(sessionId, processInfo);
    logger.info('Added interactive session', {
      sessionId,
      pid: processInfo.pid,
    });
  }

  getInteractiveSession(sessionId) {
    return this.interactiveSessions.get(sessionId);
  }

  hasInteractiveSession(sessionId) {
    return this.interactiveSessions.has(sessionId);
  }

  removeInteractiveSession(sessionId) {
    const removed = this.interactiveSessions.delete(sessionId);
    if (removed) {
      logger.info('Removed interactive session', { sessionId });
    }
    return removed;
  }

  // Claude sessions
  addClaudeSession(sessionId, sessionData) {
    this.claudeSessions.set(sessionId, {
      ...sessionData,
      lastActivity: Date.now(),
      createdAt: sessionData.createdAt || Date.now(),
    });
    logger.debug('Added Claude session', { sessionId });
  }

  getClaudeSession(sessionId) {
    return this.claudeSessions.get(sessionId);
  }

  hasClaudeSession(sessionId) {
    return this.claudeSessions.has(sessionId);
  }

  updateClaudeSessionActivity(sessionId) {
    const session = this.claudeSessions.get(sessionId);
    if (session) {
      session.lastActivity = Date.now();
      logger.debug('Updated Claude session activity', { sessionId });
      return true;
    }
    return false;
  }

  getAllClaudeSessions() {
    return this.claudeSessions;
  }

  removeClaudeSession(sessionId) {
    const removed = this.claudeSessions.delete(sessionId);
    if (removed) {
      logger.debug('Removed Claude session', { sessionId });
    }
    return removed;
  }

  // Project sessions
  setProjectSession(projectPath, sessionId) {
    this.projectSessions.set(projectPath, sessionId);
    logger.debug('Set project session', { projectPath, sessionId });
  }

  getProjectSession(projectPath) {
    return this.projectSessions.get(projectPath);
  }

  removeProjectSession(projectPath) {
    return this.projectSessions.delete(projectPath);
  }

  getAllProjectSessions() {
    return this.projectSessions;
  }

  // Utility methods
  getStats() {
    return {
      activeSessions: this.activeSessions.size,
      messageBuffers: this.sessionMessageBuffers.size,
      interactiveSessions: this.interactiveSessions.size,
      claudeSessions: this.claudeSessions.size,
      projectSessions: this.projectSessions.size,
    };
  }

  clear() {
    this.activeSessions.clear();
    this.sessionMessageBuffers.clear();
    this.interactiveSessions.clear();
    this.claudeSessions.clear();
    this.projectSessions.clear();
    logger.info('Cleared all session storage');
  }
}

export default SessionStorage;
