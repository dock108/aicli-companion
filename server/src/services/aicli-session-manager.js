import { EventEmitter } from 'events';
import { InputValidator } from './aicli-utils.js';
import { AICLIMessageHandler } from './aicli-message-handler.js';
// Session persistence removed - server is stateless
import { getTelemetryService } from './telemetry.js';
import { messageQueueManager } from './message-queue.js';

/**
 * Manages AICLI CLI session lifecycle, timeout handling, and cleanup
 */
export class AICLISessionManager extends EventEmitter {
  constructor(options = {}) {
    super();

    // Session storage
    this.activeSessions = new Map();
    this.sessionMessageBuffers = new Map();
    this.interactiveSessions = new Map(); // Track running Claude processes (not used in --print mode)
    this.claudeSessions = new Map(); // Track Claude session IDs and their last activity
    this.projectSessions = new Map(); // Track project path → latest session ID mapping

    // Configuration
    this.sessionTimeout = options.sessionTimeout || 24 * 60 * 60 * 1000; // 24 hours
    this.sessionWarningTime = options.sessionWarningTime || 20 * 60 * 60 * 1000; // 20 hours
    this.minTimeoutCheckInterval = options.minTimeoutCheckInterval || 60000; // 1 minute default

    // Resource limits
    this.maxConcurrentSessions = options.maxConcurrentSessions || 10;
    this.maxMemoryPerSession = options.maxMemoryPerSession || 500 * 1024 * 1024; // 500MB
    this.maxTotalMemory = options.maxTotalMemory || 2 * 1024 * 1024 * 1024; // 2GB
    this.maxCpuUsage = options.maxCpuUsage || 80; // 80%

    // Start monitoring sessions
    this.startSessionMonitoring();
  }

  /**
   * Start monitoring sessions for timeouts and resource usage
   */
  startSessionMonitoring() {
    // Check sessions every minute
    this.monitoringInterval = setInterval(() => {
      this.checkSessionTimeouts();
      this.checkResourceUsage();
      // Clean up old expired sessions every hour
      if (Date.now() % (60 * 60 * 1000) < 60000) {
        this.cleanupExpiredClaudeSessions();
      }
    }, 60000); // Every minute
  }

  /**
   * Check for sessions approaching timeout
   */
  async checkSessionTimeouts() {
    const now = Date.now();

    // Check Claude sessions
    for (const [sessionId, sessionData] of this.claudeSessions) {
      const timeSinceActivity = now - sessionData.lastActivity;
      const timeUntilTimeout = this.sessionTimeout - timeSinceActivity;

      // Send warning when approaching timeout (within the warning window)
      if (
        timeSinceActivity >= this.sessionWarningTime &&
        timeUntilTimeout > 0 &&
        !sessionData.warningsSent?.includes('timeout_warning')
      ) {
        const hoursInactive = Math.floor(timeSinceActivity / (60 * 60 * 1000));
        const minutesInactive = Math.floor((timeSinceActivity % (60 * 60 * 1000)) / (60 * 1000));
        console.log(`⏰ Claude session ${sessionId} approaching 24hr timeout`);
        console.log(`   Time since activity: ${hoursInactive}h ${minutesInactive}m`);
        console.log(`   Last activity: ${new Date(sessionData.lastActivity).toISOString()}`);
        console.log(`   Time until timeout: ${Math.floor(timeUntilTimeout / (60 * 1000))} minutes`);

        // Mark warning as sent
        if (!sessionData.warningsSent) sessionData.warningsSent = [];
        sessionData.warningsSent.push('timeout_warning');

        // Emit event for push notification
        this.emit('sessionWarning', {
          sessionId,
          type: 'timeout',
          message: 'Session will expire in 4 hours due to inactivity',
          timeRemaining: timeUntilTimeout,
        });
      }

      // Mark as expired after 24 hours of inactivity
      if (timeUntilTimeout <= 0 && !sessionData.expired) {
        console.log(
          `⏰ Claude session ${sessionId} expired (24 hours of inactivity), marking for cleanup`
        );
        sessionData.expired = true;

        // Emit event
        this.emit('sessionExpired', {
          sessionId,
          reason: 'inactivity_timeout',
          lastActivity: new Date(sessionData.lastActivity).toISOString(),
        });
      }
    }

    // Also check interactive sessions if we have any (future feature)
    for (const [sessionId, session] of this.interactiveSessions) {
      const sessionAge = now - session.createdAt;
      const timeUntilTimeout = this.sessionTimeout - sessionAge;

      // Send warning when approaching timeout
      if (
        sessionAge >= this.sessionWarningTime &&
        timeUntilTimeout > 0 &&
        !session.warningsSent?.includes('timeout_warning')
      ) {
        console.log(`⏰ Interactive session ${sessionId} approaching 24hr timeout (4 hours left)`);

        // Mark warning as sent
        if (!session.warningsSent) session.warningsSent = [];
        session.warningsSent.push('timeout_warning');

        // Emit event for push notification
        this.emit('sessionWarning', {
          sessionId,
          type: 'timeout',
          message: 'Session will expire in 4 hours',
          timeRemaining: timeUntilTimeout,
        });
      }

      // Auto-cleanup after 24 hours
      if (timeUntilTimeout <= 0) {
        console.log(`⏰ Interactive session ${sessionId} expired (24 hours), cleaning up`);
        await this.killSession(sessionId);
      }
    }
  }

  /**
   * Check resource usage and emit warnings
   */
  async checkResourceUsage() {
    const processMonitor = (await import('../utils/process-monitor.js')).processMonitor;

    let totalMemory = 0;
    const sessionMetrics = [];

    for (const [sessionId, session] of this.interactiveSessions) {
      if (session.pid) {
        const metrics = await processMonitor.monitorProcess(session.pid);
        if (metrics) {
          totalMemory += metrics.rss;
          sessionMetrics.push({
            sessionId,
            memory: metrics.rss,
            cpu: metrics.cpu,
          });

          // Check per-session memory limit
          if (metrics.rss > this.maxMemoryPerSession) {
            this.emit('resourceWarning', {
              sessionId,
              type: 'memory',
              message: `Session using ${(metrics.rss / 1024 / 1024).toFixed(0)}MB (limit: ${(this.maxMemoryPerSession / 1024 / 1024).toFixed(0)}MB)`,
              usage: metrics.rss,
              limit: this.maxMemoryPerSession,
            });
          }
        }
      }
    }

    // Check total memory limit
    if (totalMemory > this.maxTotalMemory) {
      this.emit('resourceWarning', {
        type: 'total_memory',
        message: `Total memory usage ${(totalMemory / 1024 / 1024).toFixed(0)}MB exceeds limit`,
        usage: totalMemory,
        limit: this.maxTotalMemory,
        sessions: sessionMetrics,
      });
    }

    // Check concurrent session limit
    if (this.interactiveSessions.size >= this.maxConcurrentSessions) {
      this.emit('resourceWarning', {
        type: 'session_limit',
        message: `Reached maximum concurrent sessions (${this.maxConcurrentSessions})`,
        count: this.interactiveSessions.size,
        limit: this.maxConcurrentSessions,
      });
    }
  }

  /**
   * Track a session temporarily for response routing only
   * This is used when iOS sends a session ID that we don't know about
   * IMPORTANT: Updates project → session mapping as Claude returns NEW session IDs
   */
  async trackSessionForRouting(sessionId, workingDirectory) {
    if (!sessionId) return;

    // Update project → session mapping
    // Claude returns a new session ID with each response when using --resume
    if (workingDirectory) {
      const oldSessionId = this.projectSessions.get(workingDirectory);
      if (oldSessionId && oldSessionId !== sessionId) {
        console.log(`🔄 Project ${workingDirectory} session ID changed`);
        console.log(`   Old: ${oldSessionId}`);
        console.log(`   New: ${sessionId}`);

        // Clean up old session entry if it exists
        const oldSession = this.activeSessions.get(oldSessionId);
        if (oldSession && oldSession.isTemporary) {
          this.activeSessions.delete(oldSessionId);
          this.sessionMessageBuffers.delete(oldSessionId);
          console.log(`   Cleaned up old temporary session ${oldSessionId}`);
        }
      }

      // Update the mapping
      this.projectSessions.set(workingDirectory, sessionId);
      console.log(`📌 Project ${workingDirectory} → Session ${sessionId}`);
    }

    // Check if session already exists
    const existingSession = this.activeSessions.get(sessionId);
    if (existingSession) {
      // Update existing session's last activity and working directory if provided
      existingSession.lastActivity = new Date();
      if (workingDirectory) {
        existingSession.workingDirectory = workingDirectory;
      }
      console.log(`📌 Updated existing session ${sessionId} activity time`);

      // Ensure message buffer exists
      if (!this.sessionMessageBuffers.has(sessionId)) {
        this.sessionMessageBuffers.set(sessionId, AICLIMessageHandler.createSessionBuffer());
      }
      return;
    }

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
   * Track Claude session activity
   * Called when we send or receive messages from Claude
   */
  trackClaudeSessionActivity(sessionId) {
    if (!sessionId) return;

    // Check if this session is already expired
    const existingSession = this.claudeSessions.get(sessionId);
    if (existingSession?.expired) {
      console.log(`⚠️ Ignoring activity for expired session ${sessionId}`);
      return false; // Don't track activity for expired sessions
    }

    // Update or create session tracking
    if (!this.claudeSessions.has(sessionId)) {
      console.log(`📝 Starting to track Claude session ${sessionId}`);
      this.claudeSessions.set(sessionId, {
        lastActivity: Date.now(),
        warningsSent: [],
        expired: false,
      });
    } else {
      const sessionData = this.claudeSessions.get(sessionId);
      sessionData.lastActivity = Date.now();
      // Clear any previous warnings since the session is now active
      if (sessionData.warningsSent && sessionData.warningsSent.length > 0) {
        console.log(`🔄 Clearing timeout warnings for active session ${sessionId}`);
        sessionData.warningsSent = [];
      }
      console.log(`✅ Updated activity for Claude session ${sessionId}`);
    }

    return true; // Activity tracked successfully
  }

  /**
   * Check if a Claude session is expired
   * Returns true if the session should not be used anymore
   */
  isClaudeSessionExpired(sessionId) {
    if (!sessionId) return false;

    const sessionData = this.claudeSessions.get(sessionId);
    if (!sessionData) {
      // We don't know about this session, so it's not expired from our perspective
      return false;
    }

    // Check if explicitly marked as expired
    if (sessionData.expired) {
      return true;
    }

    // Check if it's been more than 24 hours since last activity
    const now = Date.now();
    const timeSinceActivity = now - sessionData.lastActivity;
    if (timeSinceActivity > this.sessionTimeout) {
      console.log(`⏰ Session ${sessionId} has exceeded 24-hour timeout, marking as expired`);
      sessionData.expired = true;
      return true;
    }

    return false;
  }

  /**
   * Clean up expired Claude sessions from tracking
   * This doesn't kill the sessions, just removes them from our tracking
   */
  cleanupExpiredClaudeSessions() {
    const now = Date.now();
    let cleanedCount = 0;

    for (const [sessionId, sessionData] of this.claudeSessions) {
      const timeSinceActivity = now - sessionData.lastActivity;

      // Remove sessions that have been expired for more than 24 hours
      // This gives a 48-hour total window (24h active + 24h expired)
      if (sessionData.expired && timeSinceActivity > this.sessionTimeout * 2) {
        console.log(`🗑️ Removing expired Claude session ${sessionId} from tracking (48h total)`);
        this.claudeSessions.delete(sessionId);
        cleanedCount++;
      }
    }

    if (cleanedCount > 0) {
      console.log(`🧹 Cleaned up ${cleanedCount} expired Claude sessions`);
    }

    return cleanedCount;
  }

  /**
   * Initialize session persistence (disabled - server is stateless)
   */
  async initializePersistence() {
    // Server is stateless - no persistence needed
  }

  // NOTE: Interactive session methods will be added in Phase 2

  /**
   * Kill an interactive session
   */
  async killSession(sessionId) {
    const session = this.interactiveSessions.get(sessionId);
    if (!session) {
      console.log(`⚠️ Session ${sessionId} not found`);
      return { success: false, message: 'Session not found' };
    }

    console.log(`🔪 Killing session ${sessionId}`);

    // Kill the Claude process
    if (session.process) {
      session.process.kill('SIGTERM');

      // Force kill after 5 seconds if still running
      setTimeout(() => {
        if (session.process && !session.process.killed) {
          session.process.kill('SIGKILL');
        }
      }, 5000);
    }

    // Remove from tracking
    this.interactiveSessions.delete(sessionId);
    this.activeSessions.delete(sessionId);
    this.sessionMessageBuffers.delete(sessionId);

    // Clean up message queue for this session
    messageQueueManager.removeQueue(sessionId);

    // Emit event
    this.emit('sessionClosed', {
      sessionId,
      reason: 'manual_kill',
    });

    return { success: true, message: 'Session killed successfully' };
  }

  /**
   * Get session status
   */
  getSessionStatus(sessionId) {
    const session = this.interactiveSessions.get(sessionId);
    if (!session) {
      return null;
    }

    const now = Date.now();
    const sessionAge = now - session.createdAt;
    const timeRemaining = this.sessionTimeout - sessionAge;

    return {
      sessionId,
      active: true,
      createdAt: new Date(session.createdAt).toISOString(),
      lastActivity: new Date(session.lastActivity).toISOString(),
      messageCount: session.messageCount,
      timeRemaining: Math.max(0, timeRemaining),
      hoursRemaining: Math.max(0, Math.floor(timeRemaining / (60 * 60 * 1000))),
      workingDirectory: session.workingDirectory,
      pid: session.pid,
    };
  }

  /**
   * Keep session alive (reset timeout)
   */
  keepSessionAlive(sessionId) {
    const session = this.interactiveSessions.get(sessionId);
    if (!session) {
      return false;
    }

    // Reset creation time to now
    session.createdAt = Date.now();
    session.warningsSent = []; // Clear warnings

    console.log(`♻️ Reset timeout for session ${sessionId}`);
    return true;
  }

  /**
   * Get all active sessions
   */
  getAllSessions() {
    const sessions = [];
    for (const [sessionId, _session] of this.activeSessions) {
      const status = this.getSessionStatus(sessionId);
      if (status) {
        sessions.push(status);
      }
    }
    return sessions;
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

    // Server is stateless - no session limits needed

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

      // Clean up message queue for this session
      messageQueueManager.removeQueue(sessionId);

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
   * Forcefully terminate a session (used when killing Claude process)
   * @param {string} sessionId - The session ID to terminate
   * @param {string} reason - Reason for termination
   * @returns {boolean} Whether the session was terminated
   */
  async terminateSession(sessionId, reason = 'User requested termination') {
    try {
      console.log(`⚠️ Forcefully terminating session: ${sessionId}`);
      console.log(`   Reason: ${reason}`);

      // Remove from all tracking maps
      const hadSession = this.activeSessions.has(sessionId);
      this.activeSessions.delete(sessionId);
      this.sessionMessageBuffers.delete(sessionId);
      this.interactiveSessions.delete(sessionId);
      this.claudeSessions.delete(sessionId);

      // Clean up message queue for this session
      messageQueueManager.removeQueue(sessionId);

      // Find and clear project session mapping
      for (const [projectPath, sid] of this.projectSessions.entries()) {
        if (sid === sessionId) {
          this.projectSessions.delete(projectPath);
          break;
        }
      }

      // Emit termination event
      this.emit('sessionTerminated', {
        sessionId,
        reason,
        timestamp: new Date().toISOString(),
      });

      console.log(`✅ Session ${sessionId} terminated`);
      console.log(`   Remaining active sessions: ${this.activeSessions.size}`);

      return hadSession;
    } catch (error) {
      console.error('Error terminating session:', error);
      return false;
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

    // Server is stateless - no persistent sessions
    return false;
  }

  /**
   * Get session metadata (restore from persistence if needed)
   */
  async getSession(sessionId) {
    // First check active sessions in memory
    const session = this.activeSessions.get(sessionId);
    if (session) {
      return session;
    }

    // Server is stateless - no persistent sessions to restore

    return session || null;
  }

  /**
   * Restore a single session from persistence - DISABLED
   * Server is stateless and doesn't persist sessions
   */
  async _restoreSingleSession(_sessionId) {
    // Server is stateless - no session restoration
    return false;
  }

  /**
   * Find session by working directory
   * @param {string} workingDirectory - The working directory path
   * @returns {Object|null} Session object if found
   */
  async findSessionByWorkingDirectory(workingDirectory) {
    // Use the projectSessions Map for project → session mapping
    // This tracks the latest session ID for each project (updated as Claude returns new IDs)
    const sessionId = this.projectSessions.get(workingDirectory);

    if (sessionId) {
      // Look up the actual session object
      const session = this.activeSessions.get(sessionId);
      if (session) {
        console.log(`✅ Found session ${sessionId} for project ${workingDirectory}`);
        return session;
      } else {
        console.log(
          `⚠️ Session ${sessionId} mapped to ${workingDirectory} but not in activeSessions`
        );
        // Clean up stale mapping
        this.projectSessions.delete(workingDirectory);
      }
    }

    // Fallback: check active sessions in memory (shouldn't happen with proper mapping)
    for (const [, session] of this.activeSessions) {
      if (session.workingDirectory === workingDirectory) {
        console.log(`📌 Found session via fallback search: ${session.sessionId}`);
        // Update the mapping for next time
        this.projectSessions.set(workingDirectory, session.sessionId);
        return session;
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
   * Update session activity timestamp
   */
  async updateSessionActivity(sessionId) {
    const session = this.activeSessions.get(sessionId);
    if (session) {
      session.lastActivity = Date.now();
    }

    // Also track Claude session activity if we have a session ID
    if (sessionId) {
      this.trackClaudeSessionActivity(sessionId);
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
    }
  }

  /**
   * Check if Claude CLI has an active session with this ID
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
   * Get a specific message by ID from a session
   */
  getMessageById(sessionId, messageId) {
    const buffer = this.getSessionBuffer(sessionId);
    if (!buffer || !buffer.messagesById) {
      return null;
    }
    return buffer.messagesById.get(messageId);
  }

  /**
   * Store a message with ID in session buffer
   */
  storeMessage(sessionId, messageId, content, metadata = {}) {
    const buffer = this.getSessionBuffer(sessionId);
    if (!buffer) {
      console.warn(`No buffer found for session ${sessionId}`);
      return null;
    }

    const message = {
      id: messageId,
      content,
      timestamp: new Date().toISOString(),
      sessionId,
      ...metadata,
    };

    // Initialize messagesById if needed
    if (!buffer.messagesById) {
      buffer.messagesById = new Map();
    }

    // Store the message
    buffer.messagesById.set(messageId, message);

    // Set expiry for message (24 hours)
    this.scheduleMessageExpiry(sessionId, messageId, 24 * 60 * 60 * 1000);

    return message;
  }

  /**
   * Schedule message expiry
   */
  scheduleMessageExpiry(sessionId, messageId, ttl) {
    // Initialize messageExpiryTimeouts if it doesn't exist
    if (!this.messageExpiryTimeouts) {
      this.messageExpiryTimeouts = new Map();
    }

    // Ensure a map exists for this session
    if (!this.messageExpiryTimeouts.has(sessionId)) {
      this.messageExpiryTimeouts.set(sessionId, new Map());
    }
    const sessionTimeouts = this.messageExpiryTimeouts.get(sessionId);

    // If a timeout already exists for this message, clear it first
    if (sessionTimeouts.has(messageId)) {
      clearTimeout(sessionTimeouts.get(messageId));
    }

    const timeoutId = setTimeout(() => {
      const buffer = this.getSessionBuffer(sessionId);
      if (buffer && buffer.messagesById) {
        buffer.messagesById.delete(messageId);
        console.log(`🗑️ Expired message ${messageId} from session ${sessionId}`);
      }
      // Remove the timeout from the map
      sessionTimeouts.delete(messageId);
      // If no more timeouts for this session, remove the session entry
      if (sessionTimeouts.size === 0) {
        this.messageExpiryTimeouts.delete(sessionId);
      }
    }, ttl);

    sessionTimeouts.set(messageId, timeoutId);
  }

  /**
   * Get all messages for a session with pagination
   */
  getSessionMessages(sessionId, limit = 50, offset = 0) {
    const buffer = this.getSessionBuffer(sessionId);
    if (!buffer || !buffer.messagesById) {
      return { messages: [], total: 0 };
    }

    // Convert Map to array and sort by timestamp
    const allMessages = Array.from(buffer.messagesById.values()).sort(
      (a, b) => new Date(a.timestamp) - new Date(b.timestamp)
    );

    // Apply pagination
    const messages = allMessages.slice(offset, offset + limit);

    return {
      messages: messages.map((msg) => ({
        id: msg.id,
        preview: msg.content ? msg.content.substring(0, 100) : '',
        timestamp: msg.timestamp,
        type: msg.type,
        length: msg.content ? msg.content.length : 0,
      })),
      total: allMessages.length,
      hasMore: offset + limit < allMessages.length,
    };
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

      // Clean up message queue for this session
      messageQueueManager.removeQueue(sessionId);

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

    // Clear monitoring interval
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this.monitoringInterval = null;
    }

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
    this.claudeSessions.clear();
    this.interactiveSessions.clear();
    this.projectSessions.clear();

    // Clean up all message queues
    messageQueueManager.destroy();

    console.log('✅ AICLI Session Manager shut down complete');
  }

  /**
   * Get persistence stats - DISABLED
   * Server is stateless
   */
  getPersistenceStats() {
    return { sessions: 0, buffers: 0, totalSize: 0 };
  }

  /**
   * Export sessions - DISABLED
   * Server is stateless
   */
  async exportSessions() {
    return [];
  }

  /**
   * Cleanup old sessions - DISABLED
   * Server is stateless
   */
  async cleanupOldSessions(_maxAgeMs) {
    return { cleaned: 0 };
  }

  /**
   * Reconcile session state - DISABLED
   * Server is stateless and doesn't persist sessions
   */
  async reconcileSessionState() {
    // Server is stateless - no session reconciliation needed
    console.log('✅ Session reconciliation skipped (stateless mode)');
    return {
      totalPersisted: 0,
      staleRemoved: 0,
      activeInMemory: this.activeSessions.size,
    };
  }
}
