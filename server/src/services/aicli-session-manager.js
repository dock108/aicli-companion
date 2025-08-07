import { EventEmitter } from 'events';
import { InputValidator } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';
import { sessionPersistence } from './session-persistence.js';
import { getTelemetryService } from './telemetry.js';
import { getMessageQueueService } from './message-queue.js';

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
    this.backgroundedSessionTimeout = options.backgroundedSessionTimeout || 2 * 60 * 60 * 1000; // 2 hours for backgrounded sessions
    this.minTimeoutCheckInterval = options.minTimeoutCheckInterval || 60000; // 1 minute default

    // Persistence will be initialized by the server after startup
    // This prevents race conditions from multiple initialization attempts
  }

  /**
   * Track a session temporarily for response routing only
   * This is used when iOS sends a session ID that we don't know about
   */
  async trackSessionForRouting(sessionId, workingDirectory) {
    if (!sessionId) return;

    // Create minimal session entry for routing only
    const session = {
      sessionId,
      workingDirectory,
      isActive: true,
      isProcessing: false,
      createdAt: new Date(),
      lastActivity: new Date(),
      conversationStarted: true, // Assume it's an existing conversation
      timeoutId: null,
      isTemporary: true, // Mark as temporary routing session
    };

    this.activeSessions.set(sessionId, session);

    // Create empty message buffer
    this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());

    console.log(`🔄 Temporarily tracking session ${sessionId} for response routing`);
  }

  /**
   * Initialize session persistence (disabled - sessions should be client-managed)
   */
  async initializePersistence() {
    // DISABLED: Session persistence should be managed by clients
    // Server should start fresh without loading old sessions
    // try {
    //   await sessionPersistence.initialize();
    //
    //   // Also initialize message queue service
    //   const messageQueueService = getMessageQueueService();
    //   await messageQueueService.initialize();
    //
    //   await this.restorePersistedSessions();
    // } catch (error) {
    //   console.error('❌ Failed to initialize session persistence:', error);
    // }
    
    // Still initialize the message queue service (without loading persisted data)
    const messageQueueService = getMessageQueueService();
    await messageQueueService.initialize();
  }

  /**
   * Restore sessions from persistent storage (disabled)
   */
  async restorePersistedSessions() {
    // DISABLED: Session restoration on server startup
    // Sessions should be managed by clients, not persisted by server
    return;
    
    // Original code kept for reference:
    // if (process.env.NODE_ENV === 'test') {
    //   return; // Skip persistence in test environment
    // }
    // const persistedSessions = sessionPersistence.getAllSessions();
    // console.log(`🔄 Restoring ${persistedSessions.length} persisted sessions`);
    //
    // // Load all message buffers first
    // const messageBuffers = await sessionPersistence.loadAllMessageBuffers();

    for (const persistedSession of persistedSessions) {
      const { sessionId } = persistedSession;

      // Create in-memory session based on persisted data
      const session = {
        sessionId,
        workingDirectory: persistedSession.workingDirectory,
        isActive: true,
        isProcessing: false,
        createdAt: persistedSession.createdAt,
        lastActivity: persistedSession.lastActivity,
        initialPrompt: persistedSession.initialPrompt,
        conversationStarted: persistedSession.conversationStarted,
        timeoutId: null,
        skipPermissions: persistedSession.skipPermissions,
        isRestoredSession: true, // Mark this session as restored from persistence
      };

      this.activeSessions.set(sessionId, session);

      // Restore message buffer from disk or create new one
      const restoredBuffer = messageBuffers.get(sessionId);
      if (restoredBuffer) {
        console.log(
          `   📚 Restored message buffer for session ${sessionId} (${restoredBuffer.assistantMessages.length} messages)`
        );
        this.sessionMessageBuffers.set(sessionId, restoredBuffer);
      } else {
        // Initialize empty message buffer for restored session
        this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());
      }

      // Set up timeout for restored session
      const timeoutId = setTimeout(() => {
        this.checkSessionTimeout(sessionId);
      }, this.sessionTimeout);
      session.timeoutId = timeoutId;

      console.log(
        `   ✅ Restored session ${sessionId} (conversation: ${session.conversationStarted})`
      );
    }

    if (persistedSessions.length > 0) {
      console.log(`🎉 Successfully restored ${persistedSessions.length} sessions from persistence`);
    }
  }

  /**
   * Create a new interactive session with metadata tracking
   */
  async createInteractiveSession(sessionId, initialPrompt, workingDirectory, options = {}) {
    // Validate and sanitize inputs
    const sanitizedSessionId = InputValidator.sanitizeSessionId(sessionId);
    const sanitizedPrompt = InputValidator.sanitizePrompt(initialPrompt);
    const validatedWorkingDir = await InputValidator.validateWorkingDirectory(workingDirectory);

    // Check if session already exists for this directory
    const existingSession = await this.findSessionByWorkingDirectory(validatedWorkingDir);
    if (existingSession) {
      console.log(
        `♻️ Reusing existing session ${existingSession.sessionId} for ${validatedWorkingDir}`
      );

      // TODO: [QUESTION] Should we update the initial prompt when reusing session?
      // Current behavior: preserve existing session context

      await this.updateSessionActivity(existingSession.sessionId);

      // IMPORTANT: Mark conversation as started for reused sessions
      // This prevents --session-id conflicts since Claude CLI already knows about this session
      if (!existingSession.conversationStarted) {
        console.log(`   📝 Marking reused session as conversation started to prevent conflicts`);
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

    console.log(`🚀 Creating AICLI CLI session (metadata-only)`);
    console.log(`   Session ID: ${sanitizedSessionId}`);
    console.log(`   Working directory: ${validatedWorkingDir}`);
    console.log(`   Initial prompt: "${sanitizedPrompt}"`);

    // Check session limits
    if (this.activeSessions.size >= this.maxSessions) {
      throw new Error(`Maximum number of sessions (${this.maxSessions}) reached`);
    }

    // Create session metadata (no long-running process)
    const { skipPermissions = false } = options;
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
      skipPermissions, // Store permission setting for this session
    };

    this.activeSessions.set(sanitizedSessionId, session);

    // DISABLED: Session persistence
    // if (process.env.NODE_ENV !== 'test') {
    //   try {
    //     await sessionPersistence.setSession(sanitizedSessionId, {
    //       workingDirectory: validatedWorkingDir,
    //       conversationStarted: false,
    //       initialPrompt: sanitizedPrompt,
    //       skipPermissions,
    //     });
    //     console.log(`💾 Session ${sanitizedSessionId} persisted to disk`);
    //   } catch (error) {
    //     console.error('❌ Failed to persist session %s:', sanitizedSessionId, error);
    //   }
    // }

    // Initialize message buffer for this session
    this.sessionMessageBuffers.set(sanitizedSessionId, AICLIMessageHandler.createSessionBuffer());

    // Set up session timeout (only timeout if inactive AND no pending messages)
    const timeoutId = setTimeout(() => {
      this.checkSessionTimeout(sanitizedSessionId);
    }, this.sessionTimeout);

    // Store timeout ID for potential cancellation
    session.timeoutId = timeoutId;

    console.log(`✅ AICLI CLI session metadata created successfully`);

    // Record telemetry
    getTelemetryService().recordSessionCreated(false); // reused = false

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

      // DISABLED: Session persistence removal
      // if (process.env.NODE_ENV !== 'test') {
      //   try {
      //     await sessionPersistence.removeSession(sessionId);
      //     console.log(`💾 Session ${sessionId} removed from persistent storage`);
      //   } catch (error) {
      //     console.error('❌ Failed to remove session %s from persistence:', sessionId, error);
      //   }
      // }

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
   * Check if a session exists and is active (including persisted sessions)
   */
  hasSession(sessionId) {
    // First check active sessions in memory
    if (this.activeSessions.has(sessionId)) {
      return true;
    }

    // If not in memory, check if it exists in persistence
    // This allows us to restore backgrounded sessions
    if (process.env.NODE_ENV !== 'test') {
      return sessionPersistence.hasSession(sessionId);
    }

    return false;
  }

  /**
   * Get session metadata (restore from persistence if needed)
   */
  async getSession(sessionId) {
    // First check active sessions in memory
    let session = this.activeSessions.get(sessionId);
    if (session) {
      return session;
    }

    // If not in memory but exists in persistence, restore it
    if (process.env.NODE_ENV !== 'test' && sessionPersistence.hasSession(sessionId)) {
      console.log(`🔄 Restoring session ${sessionId} from persistence`);
      await this._restoreSingleSession(sessionId);
      session = this.activeSessions.get(sessionId);
    }

    return session || null;
  }

  /**
   * Restore a single session from persistence
   */
  async _restoreSingleSession(sessionId) {
    try {
      const persistedSession = sessionPersistence.getSession(sessionId);
      if (!persistedSession) {
        return false;
      }

      // Create in-memory session based on persisted data
      const session = {
        sessionId,
        workingDirectory: persistedSession.workingDirectory,
        isActive: true,
        isProcessing: false,
        createdAt: persistedSession.createdAt,
        lastActivity: persistedSession.lastActivity,
        initialPrompt: persistedSession.initialPrompt,
        conversationStarted: persistedSession.conversationStarted,
        timeoutId: null,
        skipPermissions: persistedSession.skipPermissions,
        isRestoredSession: true,
      };

      this.activeSessions.set(sessionId, session);

      // Restore message buffer from disk or create new one
      const restoredBuffer = await sessionPersistence.loadMessageBuffer(sessionId);
      if (restoredBuffer) {
        console.log(
          `   📚 Restored message buffer for session ${sessionId} (${restoredBuffer.assistantMessages.length} messages)`
        );
        this.sessionMessageBuffers.set(sessionId, restoredBuffer);
      } else {
        // Initialize empty message buffer for restored session
        this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());
      }

      // Set up timeout for restored session
      const timeoutId = setTimeout(() => {
        this.checkSessionTimeout(sessionId);
      }, this.sessionTimeout);
      session.timeoutId = timeoutId;

      console.log(`✅ Restored session ${sessionId} from persistence`);
      return true;
    } catch (error) {
      console.error(`❌ Failed to restore session ${sessionId}:`, error);
      return false;
    }
  }

  /**
   * Find session by working directory
   * @param {string} workingDirectory - The working directory path
   * @returns {Object|null} Session object if found
   */
  async findSessionByWorkingDirectory(workingDirectory) {
    // First check active sessions in memory
    for (const [, session] of this.activeSessions) {
      if (session.workingDirectory === workingDirectory) {
        return session;
      }
    }

    // Then check persistence
    if (process.env.NODE_ENV !== 'test') {
      const persistedResult = sessionPersistence.getSessionByWorkingDirectory(workingDirectory);
      if (persistedResult) {
        // Restore the session to active memory
        await this._restoreSingleSession(persistedResult.sessionId);
        return this.activeSessions.get(persistedResult.sessionId);
      }
    }

    return null;
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
   * Get all sessions with metadata
   */
  getAllSessions() {
    const sessions = [];
    for (const [sessionId, session] of this.activeSessions) {
      sessions.push({
        sessionId,
        ...session,
      });
    }
    return sessions;
  }

  /**
   * Update session activity timestamp
   */
  async updateSessionActivity(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.lastActivity = Date.now();

      // DISABLED: Session persistence update
      // if (process.env.NODE_ENV !== 'test') {
      //   try {
      //     await sessionPersistence.updateSession(sessionId, {
      //       lastActivity: session.lastActivity,
      //     });
      //   } catch (error) {
      //     console.warn(`⚠️ Failed to update session activity in persistence:`, error.message);
      //   }
      // }
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
  async markConversationStarted(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.conversationStarted = true;

      // DISABLED: Session persistence update
      // if (process.env.NODE_ENV !== 'test') {
      //   try {
      //     await sessionPersistence.updateSession(sessionId, {
      //       conversationStarted: true,
      //     });
      //     console.log(`💾 Session ${sessionId} conversation start persisted`);
      //   } catch (error) {
      //     console.warn(
      //       '⚠️ Failed to persist conversation start for session %s: %s',
      //       sessionId,
      //       error.message
      //     );
      //   }
      // }
    }
  }

  /**
   * Check if Claude CLI has an active session with this ID
   * This is used to determine whether to use --session-id or --resume
   */
  isClaudeSessionActive(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (!session) {
      return false;
    }

    // If conversation has started, Claude CLI knows about this session
    if (session.conversationStarted) {
      return true;
    }

    // If this is a restored session, Claude CLI may still have it active
    if (session.isRestoredSession) {
      return true;
    }

    return false;
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

    // Use standard timeout for all sessions
    const timeoutToUse = this.sessionTimeout;
    const timeoutName = 'session timeout';

    // Only timeout if truly inactive for longer than timeout period
    if (
      !session.isProcessing &&
      (!buffer || buffer.assistantMessages.length === 0) &&
      inactiveTime > timeoutToUse
    ) {
      console.log(
        `Session ${sessionId} timed out after ${Math.round(inactiveTime / 1000)}s of inactivity (${timeoutName})`
      );

      // Clean up the session immediately (closeSession already emits sessionCleaned event)
      this.closeSession(sessionId);
    } else {
      // Reschedule another timeout check
      const remainingTime = Math.max(timeoutToUse - inactiveTime, this.minTimeoutCheckInterval);
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
   * Set session message buffer (used when restoring from persistence)
   */
  setSessionBuffer(sessionId, buffer) {
    this.sessionMessageBuffers.set(sessionId, buffer);
    console.log(
      `📝 Set message buffer for session ${sessionId} with ${buffer.assistantMessages?.length || 0} assistant messages`
    );
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
  async cleanupDeadSession(sessionId) {
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

      // DISABLED: Session persistence removal
      // if (process.env.NODE_ENV !== 'test') {
      //   try {
      //     await sessionPersistence.removeSession(sessionId);
      //     console.log(`💾 Dead session ${sessionId} removed from persistent storage`);
      //   } catch (error) {
      //     console.warn(
      //       '⚠️ Failed to remove dead session %s from persistence:',
      //       sessionId,
      //       error.message
      //     );
      //   }
      // }

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
  async shutdown() {
    console.log('🔄 Shutting down AICLI Session Manager...');

    // Close all active sessions
    for (const [sessionId, _] of this.activeSessions) {
      try {
        await this.closeSession(sessionId);
      } catch (error) {
        console.warn(`Failed to close session ${sessionId}:`, error.message);
      }
    }

    // Clear all buffers and data structures
    this.sessionMessageBuffers.clear();
    this.activeSessions.clear();

    console.log('✅ AICLI Session Manager shut down complete');
  }

  /**
   * Get persistence stats for debugging
   */
  getPersistenceStats() {
    return sessionPersistence.getStats();
  }

  /**
   * Export sessions for debugging
   */
  async exportSessions() {
    return sessionPersistence.exportSessions();
  }

  /**
   * Cleanup old persisted sessions
   */
  async cleanupOldSessions(maxAgeMs) {
    return sessionPersistence.cleanup(maxAgeMs);
  }

  /**
   * Mark session as backgrounded (mobile app went to background)
   */
  async markSessionBackgrounded(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isBackgrounded = true;
      session.backgroundedAt = Date.now();
      console.log(`📱 Session ${sessionId} marked as backgrounded`);

      // Update timeout for backgrounded session
      if (session.timeoutId) {
        clearTimeout(session.timeoutId);
      }

      // Set longer timeout for backgrounded sessions
      session.timeoutId = setTimeout(() => {
        console.log(`⏰ Backgrounded session ${sessionId} timed out`);
        this.closeSession(sessionId);
      }, this.backgroundedSessionTimeout);
    } else {
      console.warn(`⚠️ Cannot mark non-existent session ${sessionId} as backgrounded`);
    }
  }

  /**
   * Mark session as foregrounded (mobile app returned to foreground)
   */
  async markSessionForegrounded(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.isBackgrounded = false;
      session.backgroundedAt = null;
      console.log(`📱 Session ${sessionId} marked as foregrounded`);

      // Reset to normal timeout
      if (session.timeoutId) {
        clearTimeout(session.timeoutId);
      }

      session.timeoutId = setTimeout(() => {
        console.log(`⏰ Session ${sessionId} timed out`);
        this.closeSession(sessionId);
      }, this.sessionTimeout);
    } else {
      console.warn(`⚠️ Cannot mark non-existent session ${sessionId} as foregrounded`);
    }
  }

  /**
   * Reconcile session state with AICLI CLI to ensure consistency
   * This checks for sessions that exist in persistence but may be stale
   * and removes sessions that AICLI CLI no longer recognizes
   */
  async reconcileSessionState() {
    try {
      console.log('🔄 Reconciling session state with AICLI CLI...');

      const persistedSessions = sessionPersistence.getAllSessions();
      const staleSessions = [];

      // Check each persisted session by attempting a test command
      for (const persistedSession of persistedSessions) {
        const { sessionId } = persistedSession;

        // Skip if session is already active in memory
        if (this.activeSessions.has(sessionId)) {
          continue;
        }

        // Try to test if AICLI CLI recognizes this session
        // We'll do this by attempting to resume the session with a no-op command
        try {
          console.log(`🔍 Testing session ${sessionId} recognition with AICLI CLI...`);

          // If the session is truly stale, this will fail
          // For now, we'll mark sessions older than 7 days as potentially stale
          const age = Date.now() - persistedSession.lastActivity;
          const sevenDays = 7 * 24 * 60 * 60 * 1000;

          if (age > sevenDays) {
            console.log(
              `⚠️ Session ${sessionId} is ${Math.round(age / (24 * 60 * 60 * 1000))} days old, marking as stale`
            );
            staleSessions.push(sessionId);
          }
        } catch (error) {
          console.log(`❌ Session ${sessionId} failed AICLI CLI recognition test:`, error.message);
          staleSessions.push(sessionId);
        }
      }

      // DISABLED: Session persistence removal
      let removedCount = 0;
      // for (const staleSessionId of staleSessions) {
      //   try {
      //     await sessionPersistence.removeSession(staleSessionId);
      //     removedCount++;
      //     console.log(`🗑️ Removed stale session ${staleSessionId} from persistence`);
      //   } catch (error) {
      //     console.warn(`⚠️ Failed to remove stale session ${staleSessionId}:`, error.message);
      //   }
      // }

      console.log(`✅ Session reconciliation complete: removed ${removedCount} stale sessions`);
      return {
        totalPersisted: persistedSessions.length,
        staleRemoved: removedCount,
        activeInMemory: this.activeSessions.size,
      };
    } catch (error) {
      console.error('❌ Failed to reconcile session state:', error);
      throw error;
    }
  }
}
