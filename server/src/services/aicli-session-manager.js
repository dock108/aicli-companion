import { EventEmitter } from 'events';
import { InputValidator } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';

/**
 * Manages AICLI CLI session lifecycle, timeout handling, and cleanup
 */
export class AICLISessionManager extends EventEmitter {
  constructor(options = {}) {
    super();

    // Session storage
    this.activeSessions = new Map();
    this.sessionMessageBuffers = new Map();

    // Configuration
    this.maxSessions = options.maxSessions || 10;
    this.sessionTimeout = options.sessionTimeout || 30 * 60 * 1000; // 30 minutes
  }

  /**
   * Create a new interactive session with metadata tracking
   */
  async createInteractiveSession(sessionId, initialPrompt, workingDirectory) {
    // Validate and sanitize inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(initialPrompt);
    const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);

    console.log(`🚀 Creating AICLI CLI session (metadata-only)`);
    console.log(`   Session ID: ${sanitizedSessionId}`);
    console.log(`   Working directory: ${validatedWorkingDir}`);
    console.log(`   Initial prompt: "${sanitizedPrompt}"`);

    // Check session limits
    if (this.activeSessions.size >= this.maxSessions) {
      throw new Error(`Maximum number of sessions (${this.maxSessions}) reached`);
    }

    // Create session metadata (no long-running process)
    const session = {
      sessionId: sanitizedSessionId,
      workingDirectory: validatedWorkingDir,
      isActive: true,
      isProcessing: false,
      createdAt: Date.now(),
      lastActivity: Date.now(),
      initialPrompt: sanitizedPrompt,
      conversationStarted: false,
      timeoutId: null,
    };

    this.activeSessions.set(sanitizedSessionId, session);

    // Initialize message buffer for this session
    this.sessionMessageBuffers.set(sanitizedSessionId, AICLIMessageHandler.createSessionBuffer());

    // Set up session timeout (only timeout if inactive AND no pending messages)
    const timeoutId = setTimeout(() => {
      if (this.activeSessions.has(sanitizedSessionId)) {
        const sessionData = this.activeSessions.get(sanitizedSessionId);
        const buffer = this.sessionMessageBuffers.get(sanitizedSessionId);

        // Only timeout if session is truly inactive (no pending messages)
        if (!sessionData.isProcessing && (!buffer || buffer.messages.length === 0)) {
          console.log(`Session ${sanitizedSessionId} timed out, cleaning up`);
          this.closeSession(sanitizedSessionId);
        } else {
          console.log(
            `Session ${sanitizedSessionId} timeout deferred - still active or has pending messages`
          );
          // Reschedule timeout check
          setTimeout(() => this.checkSessionTimeout(sanitizedSessionId), this.sessionTimeout);
        }
      }
    }, this.sessionTimeout);

    // Store timeout ID for potential cancellation
    session.timeoutId = timeoutId;

    console.log(`✅ AICLI CLI session metadata created successfully`);

    return {
      sessionId: sanitizedSessionId,
      success: true,
      message: 'Session ready for commands',
    };
  }

  /**
   * Close a session and clean up all resources
   */
  async closeSession(sessionId) {
    const session = this.activeSessions.get(sessionId);

    if (!session) {
      console.log(`⚠️  Attempted to close non-existent session: ${sessionId}`);
      return { success: false, message: 'Session not found' };
    }

    console.log(`🔚 Closing AICLI CLI session: ${sessionId}`);
    console.log(`   Session type: metadata-only (no long-running process)`);

    try {
      // Clear any pending timeout
      if (session.timeoutId) {
        clearTimeout(session.timeoutId);
        session.timeoutId = null;
        console.log(`   Cleared timeout for session ${sessionId}`);
      }

      // Mark session as inactive
      session.isActive = false;

      // Remove from active sessions and clean up message buffer
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);

      // Emit session cleaned event for other components to handle cleanup
      this.emit('sessionCleaned', {
        sessionId,
        reason: 'user_requested',
        timestamp: new Date().toISOString(),
      });

      console.log(`✅ Session ${sessionId} closed successfully`);
      console.log(`   Remaining active sessions: ${this.activeSessions.size}`);

      return { success: true, message: 'Session closed' };
    } catch (error) {
      console.error('Error closing session:', error);
      return { success: false, message: error.message };
    }
  }

  /**
   * Check if a session exists and is active
   */
  hasSession(sessionId) {
    return this.activeSessions.has(sessionId);
  }

  /**
   * Get session metadata
   */
  getSession(sessionId) {
    return this.activeSessions.get(sessionId);
  }

  /**
   * Get all active sessions
   */
  getActiveSessions() {
    const sessions = Array.from(this.activeSessions.keys());
    console.log(`📊 Active AICLI CLI sessions: ${sessions.length}`);
    sessions.forEach((sessionId, index) => {
      const session = this.activeSessions.get(sessionId);
      const age = Math.round((Date.now() - session.createdAt) / 1000);
      console.log(
        `   ${index + 1}. ${sessionId} (age: ${age}s, conversation: ${session.conversationStarted ? 'started' : 'pending'})`
      );
    });
    return sessions;
  }

  /**
   * Update session activity timestamp
   */
  updateSessionActivity(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.lastActivity = Date.now();
    }
  }

  /**
   * Set session processing state
   */
  setSessionProcessing(sessionId, isProcessing) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isProcessing = isProcessing;
      this.updateSessionActivity(sessionId);
    }
  }

  /**
   * Mark conversation as started for a session
   */
  markConversationStarted(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.conversationStarted = true;
    }
  }

  /**
   * Check if session should timeout
   */
  checkSessionTimeout(sessionId) {
    if (!this.activeSessions.has(sessionId)) {
      return; // Session already cleaned up
    }

    const session = this.activeSessions.get(sessionId);
    const buffer = this.sessionMessageBuffers.get(sessionId);
    const now = Date.now();
    const inactiveTime = now - session.lastActivity;

    // Only timeout if truly inactive for longer than timeout period
    if (
      !session.isProcessing &&
      (!buffer || buffer.messages.length === 0) &&
      inactiveTime > this.sessionTimeout
    ) {
      console.log(
        `Session ${sessionId} timed out after ${Math.round(inactiveTime / 1000)}s of inactivity`
      );

      // Clean up the session immediately (closeSession already emits sessionCleaned event)
      this.closeSession(sessionId);
    } else {
      // Reschedule another timeout check
      const remainingTime = Math.max(this.sessionTimeout - inactiveTime, 60000); // At least 1 minute
      setTimeout(() => this.checkSessionTimeout(sessionId), remainingTime);
    }
  }

  /**
   * Get session message buffer
   */
  getSessionBuffer(sessionId) {
    return this.sessionMessageBuffers.get(sessionId);
  }

  /**
   * Clear session message buffer
   */
  clearSessionBuffer(sessionId) {
    const buffer = this.sessionMessageBuffers.get(sessionId);
    if (buffer) {
      AICLIMessageHandler.clearSessionBuffer(buffer);
      console.log(`🧹 Cleared message buffer for session ${sessionId}`);
    }
  }

  /**
   * Cleanup dead session (called when process dies)
   */
  cleanupDeadSession(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      // Clear timeout if it exists
      if (session.timeoutId) {
        clearTimeout(session.timeoutId);
        session.timeoutId = null;
      }

      session.isActive = false;
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);

      this.emit('sessionCleaned', {
        sessionId,
        reason: 'process_died',
        timestamp: new Date().toISOString(),
      });
    }
  }

  /**
   * Shutdown all sessions
   */
  shutdown() {
    console.log('🔄 Shutting down AICLI Session Manager...');

    // Close all active sessions
    for (const [sessionId, _] of this.activeSessions) {
      try {
        this.closeSession(sessionId);
      } catch (error) {
        console.warn(`Failed to close session ${sessionId}:`, error.message);
      }
    }

    // Clear all buffers and data structures
    this.sessionMessageBuffers.clear();
    this.activeSessions.clear();

    console.log('✅ AICLI Session Manager shut down complete');
  }
}
