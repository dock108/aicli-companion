import { promises as fs } from 'fs';
import path from 'path';
import os from 'os';
import { atomicWriteFile } from '../utils/atomic-write.js';

/**
 * Validate sessionId to prevent path traversal and injection
 * Only allow UUIDs or alphanumeric/dash/underscore
 */
function isValidSessionId(sessionId) {
  // Accept UUIDs (v1-v5) or simple alphanumeric/dash (no underscore)
  const uuidRegex =
    /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/;
  const simpleIdRegex = /^[a-zA-Z0-9-]{1,64}$/;
  return (
    typeof sessionId === 'string' && (uuidRegex.test(sessionId) || simpleIdRegex.test(sessionId))
  );
}

/**
 * Handles persistent storage of AICLI CLI session metadata
 * Ensures sessions survive server restarts and maintain consistency with AICLI CLI
 */
export class SessionPersistenceService {
  constructor(options = {}) {
    // Default to storing sessions in user's home directory
    this.storageDir = options.storageDir || path.join(os.homedir(), '.claude-companion');
    this.sessionsFile = path.join(this.storageDir, 'sessions.json');
    this.backupFile = path.join(this.storageDir, 'sessions.backup.json');

    // In-memory cache for performance
    this.sessionsCache = new Map();
    this.isInitialized = false;
    this.initializePromise = null; // Guard against concurrent initialization
  }

  /**
   * Initialize the persistence service - create directories and load existing sessions
   */
  async initialize() {
    // If already initialized, return immediately
    if (this.isInitialized) return;

    // If initialization is in progress, return the existing promise
    if (this.initializePromise) {
      return this.initializePromise;
    }

    // Start initialization and store the promise
    this.initializePromise = this._doInitialize();

    try {
      await this.initializePromise;
    } finally {
      // Clear the promise after completion (success or failure)
      this.initializePromise = null;
    }
  }

  async _doInitialize() {
    try {
      // Ensure storage directory exists
      await fs.mkdir(this.storageDir, { recursive: true });

      // Load existing sessions into cache
      await this.loadSessions();

      this.isInitialized = true;
      console.log(`📚 Session persistence initialized: ${this.sessionsCache.size} sessions loaded`);
    } catch (error) {
      console.error('❌ Failed to initialize session persistence:', error);
      throw error;
    }
  }

  /**
   * Load sessions from disk into memory cache
   */
  async loadSessions() {
    try {
      const data = await fs.readFile(this.sessionsFile, 'utf8');

      // Validate JSON before parsing
      let sessions;
      try {
        sessions = JSON.parse(data);
      } catch (parseError) {
        console.error('❌ Failed to parse sessions.json - file is corrupted:', parseError.message);
        // Attempt recovery from backup
        await this.loadFromBackup();
        return;
      }

      // Validate the structure
      if (!Array.isArray(sessions)) {
        console.error('❌ Invalid sessions format - expected array');
        await this.loadFromBackup();
        return;
      }

      // Convert array to Map for efficient lookups
      this.sessionsCache.clear();
      for (const session of sessions) {
        // Basic validation of session structure
        if (!session.sessionId || typeof session.sessionId !== 'string') {
          console.warn('⚠️ Skipping invalid session entry - missing sessionId');
          continue;
        }

        this.sessionsCache.set(session.sessionId, {
          ...session,
          // Parse timestamps back to numbers
          createdAt: new Date(session.createdAt).getTime(),
          lastActivity: new Date(session.lastActivity).getTime(),
        });
      }

      console.log(`📖 Loaded ${this.sessionsCache.size} valid sessions from disk`);
    } catch (error) {
      if (error.code === 'ENOENT') {
        // File doesn't exist yet - this is normal for first run
        console.log('📖 No existing sessions file found - starting fresh');
        this.sessionsCache.clear();
      } else {
        console.error('❌ Error loading sessions from disk:', error);
        // Try to load from backup
        try {
          await this.loadFromBackup();
          // If backup loaded successfully, don't throw the original error
          console.log('✅ Successfully recovered from backup file');
        } catch (backupError) {
          // Both main and backup files failed - throw original error
          throw error;
        }
      }
    }
  }

  /**
   * Load sessions from backup file if main file is corrupted
   */
  async loadFromBackup() {
    try {
      console.log('🔄 Attempting to load sessions from backup file...');
      const data = await fs.readFile(this.backupFile, 'utf8');
      const sessions = JSON.parse(data);

      this.sessionsCache.clear();
      for (const session of sessions) {
        this.sessionsCache.set(session.sessionId, {
          ...session,
          createdAt: new Date(session.createdAt).getTime(),
          lastActivity: new Date(session.lastActivity).getTime(),
        });
      }

      console.log(`✅ Restored ${sessions.length} sessions from backup`);
    } catch (backupError) {
      console.warn('⚠️ Could not load from backup file:', backupError.message);
      this.sessionsCache.clear();
    }
  }

  /**
   * Save all sessions to disk (atomic write with backup)
   */
  async saveSessions() {
    if (!this.isInitialized) {
      await this.initialize();
    }

    try {
      // Convert Map to serializable array
      const sessions = Array.from(this.sessionsCache.values()).map((session) => ({
        ...session,
        // Convert timestamps to ISO strings for JSON serialization
        createdAt: new Date(session.createdAt).toISOString(),
        lastActivity: new Date(session.lastActivity).toISOString(),
      }));

      const data = JSON.stringify(sessions, null, 2);

      // Create backup of current file before writing
      try {
        await fs.copyFile(this.sessionsFile, this.backupFile);
      } catch (error) {
        // Ignore if main file doesn't exist yet
        if (error.code !== 'ENOENT') {
          console.warn('⚠️ Could not create backup:', error.message);
        }
      }

      // Use our robust atomic write implementation
      await atomicWriteFile(this.sessionsFile, data);

      console.log(`💾 Saved ${sessions.length} sessions to disk`);
    } catch (error) {
      console.error('❌ Failed to save sessions to disk:', error);
      throw error;
    }
  }

  /**
   * Get a session by ID
   */
  getSession(sessionId) {
    return this.sessionsCache.get(sessionId) || null;
  }

  /**
   * Check if a session exists
   */
  hasSession(sessionId) {
    return this.sessionsCache.has(sessionId);
  }

  /**
   * Get all session IDs
   */
  getAllSessionIds() {
    return Array.from(this.sessionsCache.keys());
  }

  /**
   * Get all sessions
   */
  getAllSessions() {
    return Array.from(this.sessionsCache.values());
  }

  /**
   * Get session by working directory
   * @param {string} workingDirectory - The working directory path
   * @returns {Object|null} Session object with sessionId if found
   */
  getSessionByWorkingDirectory(workingDirectory) {
    for (const [sessionId, session] of this.sessionsCache) {
      if (session.workingDirectory === workingDirectory) {
        return { sessionId, session };
      }
    }
    return null;
  }

  /**
   * Store a new session or update existing one
   */
  async setSession(sessionId, sessionData) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    const session = {
      sessionId,
      workingDirectory: sessionData.workingDirectory,
      conversationStarted: sessionData.conversationStarted || false,
      createdAt: sessionData.createdAt || Date.now(),
      lastActivity: sessionData.lastActivity || Date.now(),
      initialPrompt: sessionData.initialPrompt || '',
      skipPermissions: sessionData.skipPermissions || false,
    };

    this.sessionsCache.set(sessionId, session);

    // Save to disk immediately for durability
    await this.saveSessions();

    console.log(`💾 Persisted session ${sessionId} (conversation: ${session.conversationStarted})`);
    return session;
  }

  /**
   * Update specific fields of a session
   */
  async updateSession(sessionId, updates) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    const existingSession = this.sessionsCache.get(sessionId);
    if (!existingSession) {
      throw new Error(`Session ${sessionId} not found in persistence`);
    }

    const updatedSession = {
      ...existingSession,
      ...updates,
      lastActivity: Date.now(), // Always update last activity
    };

    this.sessionsCache.set(sessionId, updatedSession);
    await this.saveSessions();

    console.log('🔄 Updated persisted session %s:', sessionId, Object.keys(updates));
    return updatedSession;
  }

  /**
   * Remove a session from persistence
   */
  async removeSession(sessionId) {
    if (!this.isInitialized) {
      await this.initialize();
    }

    const existed = this.sessionsCache.delete(sessionId);
    if (existed) {
      await this.saveSessions();
      // Also remove associated message buffer and queue
      await this.removeMessageBuffer(sessionId);
      await this.removeMessageQueue(sessionId);
      console.log(`🗑️ Removed session ${sessionId} from persistence`);
    }
    return existed;
  }

  /**
   * Clean up old sessions (older than specified age)
   */
  async cleanup(maxAgeMs = 7 * 24 * 60 * 60 * 1000) {
    // Default: 7 days
    if (!this.isInitialized) {
      await this.initialize();
    }

    const now = Date.now();
    const sessionsToRemove = [];

    for (const [sessionId, session] of this.sessionsCache) {
      const age = now - session.lastActivity;
      if (age > maxAgeMs) {
        sessionsToRemove.push(sessionId);
      }
    }

    if (sessionsToRemove.length > 0) {
      for (const sessionId of sessionsToRemove) {
        this.sessionsCache.delete(sessionId);
      }

      await this.saveSessions();
      console.log(`🧹 Cleaned up ${sessionsToRemove.length} old sessions from persistence`);
    }

    return sessionsToRemove;
  }

  /**
   * Get sessions that might be stale (not updated recently)
   */
  getStaleSessionIds(maxIdleMs = 4 * 60 * 60 * 1000) {
    // Default: 4 hours
    const now = Date.now();
    const staleSessions = [];

    for (const [sessionId, session] of this.sessionsCache) {
      const idleTime = now - session.lastActivity;
      if (idleTime > maxIdleMs) {
        staleSessions.push(sessionId);
      }
    }

    return staleSessions;
  }

  /**
   * Export sessions for debugging/backup
   */
  async exportSessions() {
    if (!this.isInitialized) {
      await this.initialize();
    }

    return Array.from(this.sessionsCache.values());
  }

  /**
   * Get stats about persisted sessions
   */
  getStats() {
    const sessions = Array.from(this.sessionsCache.values());
    const now = Date.now();

    const stats = {
      total: sessions.length,
      withConversation: sessions.filter((s) => s.conversationStarted).length,
      backgrounded: sessions.filter((s) => s.isBackgrounded).length,
      recentlyActive: sessions.filter((s) => now - s.lastActivity < 60 * 60 * 1000).length, // Active in last hour
      oldest: sessions.length > 0 ? Math.min(...sessions.map((s) => s.createdAt)) : null,
      newest: sessions.length > 0 ? Math.max(...sessions.map((s) => s.createdAt)) : null,
    };

    return stats;
  }

  /**
   * Save message buffer for a session
   * @param {string} sessionId - The session ID
   * @param {Object} messageBuffer - The message buffer to persist
   */
  async saveMessageBuffer(sessionId, messageBuffer) {
    if (!this.isInitialized) {
      console.warn('⚠️ Session persistence not initialized - skipping message buffer save');
      return;
    }

    if (!isValidSessionId(sessionId)) {
      console.warn(`⚠️ Invalid sessionId provided to saveMessageBuffer: ${sessionId}`);
      return;
    }

    try {
      const bufferFile = path.join(this.storageDir, `buffer-${sessionId}.json`);
      const bufferData = {
        sessionId,
        assistantMessages: messageBuffer.assistantMessages || [],
        userPrompts: messageBuffer.userPrompts || [],
        lastUpdated: new Date().toISOString(),
      };

      // Use our robust atomic write implementation
      const jsonData = JSON.stringify(bufferData, null, 2);
      await atomicWriteFile(bufferFile, jsonData);

      console.log(
        `💾 Saved message buffer for session ${sessionId} (${bufferData.assistantMessages.length} assistant messages)`
      );
    } catch (error) {
      console.error(`❌ Failed to save message buffer for session ${sessionId}:`, error);
      // Don't throw - persistence failures shouldn't break message flow
    }
  }

  /**
   * Load message buffer for a session
   * @param {string} sessionId - The session ID
   * @returns {Object|null} The loaded message buffer or null if not found
   */
  async loadMessageBuffer(sessionId) {
    if (!isValidSessionId(sessionId)) {
      // Log only the first 6 safe characters to avoid log injection
      const safeSessionId =
        typeof sessionId === 'string' ? sessionId.replace(/[^a-zA-Z0-9-_]/g, '').slice(0, 6) : '';
      console.warn(
        `⚠️ Invalid sessionId for message buffer load: (${safeSessionId ? `id starts with: ${safeSessionId}` : 'unusable id'})`
      );
      return null;
    }
    if (!this.isInitialized) {
      console.warn('⚠️ Session persistence not initialized - skipping message buffer load');
      return null;
    }

    try {
      const bufferFile = path.join(this.storageDir, `buffer-${sessionId}.json`);
      const data = await fs.readFile(bufferFile, 'utf8');

      let bufferData;
      try {
        bufferData = JSON.parse(data);
      } catch (parseError) {
        console.error(
          `❌ Failed to parse message buffer for session ${sessionId} - file corrupted:`,
          parseError
        );
        // Try to backup corrupted file
        const backupFile = `${bufferFile}.corrupted.${Date.now()}`;
        try {
          await fs.rename(bufferFile, backupFile);
          console.log(`📦 Backed up corrupted buffer file to: ${backupFile}`);
        } catch (renameError) {
          console.error('Failed to backup corrupted file:', renameError);
        }
        return null;
      }

      console.log(
        `📖 Loaded message buffer for session ${sessionId} (${bufferData.assistantMessages?.length || 0} assistant messages)`
      );
      return {
        assistantMessages: bufferData.assistantMessages || [],
        userPrompts: bufferData.userPrompts || [],
      };
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.error(`❌ Failed to load message buffer for session ${sessionId}:`, error);
      }
      // Return null for not found or corrupted files
      return null;
    }
  }

  /**
   * Remove message buffer when session is removed
   * @param {string} sessionId - The session ID
   */
  async removeMessageBuffer(sessionId) {
    if (!isValidSessionId(sessionId)) {
      console.warn('⚠️ Invalid sessionId for message buffer removal');
      return;
    }
    try {
      const bufferFile = path.join(this.storageDir, `buffer-${sessionId}.json`);
      await fs.unlink(bufferFile);
      console.log(`🗑️ Removed message buffer for session ${sessionId}`);
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.error(`❌ Failed to remove message buffer for session ${sessionId}:`, error);
      }
    }
  }

  /**
   * Load all message buffers for restored sessions
   * Used during server startup to restore in-memory buffers
   * @returns {Map<string, Object>} Map of sessionId to message buffer
   */
  async loadAllMessageBuffers() {
    const buffers = new Map();

    try {
      const files = await fs.readdir(this.storageDir);
      const bufferFiles = files.filter((f) => f.startsWith('buffer-') && f.endsWith('.json'));

      for (const file of bufferFiles) {
        const sessionId = file.replace('buffer-', '').replace('.json', '');
        const buffer = await this.loadMessageBuffer(sessionId);
        if (buffer) {
          buffers.set(sessionId, buffer);
        }
      }

      console.log(`📚 Loaded ${buffers.size} message buffers from disk`);
    } catch (error) {
      console.error('❌ Failed to load message buffers:', error);
    }

    return buffers;
  }

  /**
   * Save message queue for a session
   * @param {string} sessionId - The session ID
   * @param {Array} messages - Array of queued messages
   */
  async saveMessageQueue(sessionId, messages) {
    if (!this.isInitialized) {
      console.warn('⚠️ Session persistence not initialized - skipping message queue save');
      return;
    }

    try {
      const queueFile = path.join(this.storageDir, `queue-${sessionId}.json`);
      const queueData = {
        sessionId,
        messages: messages || [],
        lastUpdated: new Date().toISOString(),
      };

      // Use our robust atomic write implementation
      const jsonData = JSON.stringify(queueData, null, 2);

      await atomicWriteFile(queueFile, jsonData);

      console.log(`💾 Saved message queue for session ${sessionId} (${messages.length} messages)`);
    } catch (error) {
      console.error(`❌ Failed to save message queue for session ${sessionId}:`, error);
      // Don't throw - persistence failures shouldn't break message flow
    }
  }

  /**
   * Load message queue for a session
   * @param {string} sessionId - The session ID
   * @returns {Array|null} Array of queued messages or null if not found
   */
  async loadMessageQueue(sessionId) {
    if (!isValidSessionId(sessionId)) {
      console.warn('⚠️ Invalid sessionId for message queue load');
      return null;
    }

    if (!this.isInitialized) {
      console.warn('⚠️ Session persistence not initialized - skipping message queue load');
      return null;
    }

    try {
      const queueFile = path.join(this.storageDir, `queue-${sessionId}.json`);
      const data = await fs.readFile(queueFile, 'utf8');

      let queueData;
      try {
        queueData = JSON.parse(data);
      } catch (parseError) {
        console.error(`❌ Failed to parse message queue for session ${sessionId}:`, parseError);
        return null;
      }

      // Convert Arrays back to Sets for deliveredTo and acknowledgedBy
      const messages = queueData.messages.map((msg) => ({
        ...msg,
        timestamp: new Date(msg.timestamp),
        expiresAt: new Date(msg.expiresAt),
        deliveredAt: msg.deliveredAt ? new Date(msg.deliveredAt) : null,
        acknowledgedAt: msg.acknowledgedAt ? new Date(msg.acknowledgedAt) : null,
        deliveredTo: new Set(msg.deliveredTo || []),
        acknowledgedBy: new Set(msg.acknowledgedBy || []),
      }));

      console.log(`📖 Loaded message queue for session ${sessionId} (${messages.length} messages)`);
      return messages;
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.error(`❌ Failed to load message queue for session ${sessionId}:`, error);
      }
      return null;
    }
  }

  /**
   * Load all message queues for restored sessions
   * @returns {Map<string, Array>} Map of sessionId to message array
   */
  async loadAllMessageQueues() {
    const queues = new Map();

    try {
      const files = await fs.readdir(this.storageDir);
      const queueFiles = files.filter((f) => f.startsWith('queue-') && f.endsWith('.json'));

      for (const file of queueFiles) {
        const sessionId = file.replace('queue-', '').replace('.json', '');
        const messages = await this.loadMessageQueue(sessionId);
        if (messages && messages.length > 0) {
          queues.set(sessionId, messages);
        }
      }

      console.log(`📚 Loaded ${queues.size} message queues from disk`);
    } catch (error) {
      console.error('❌ Failed to load message queues:', error);
    }

    return queues;
  }

  /**
   * Remove message queue when session is removed
   * @param {string} sessionId - The session ID
   */
  async removeMessageQueue(sessionId) {
    if (!isValidSessionId(sessionId)) {
      console.warn('⚠️ Invalid sessionId for message queue removal');
      return;
    }

    try {
      const queueFile = path.join(this.storageDir, `queue-${sessionId}.json`);
      const resolvedQueueFile = path.resolve(queueFile);
      const resolvedStorageDir = path.resolve(this.storageDir);
      if (!resolvedQueueFile.startsWith(resolvedStorageDir + path.sep)) {
        console.warn(`⚠️ Attempted path traversal in sessionId: ${sessionId}`);
        return;
      }
      await fs.unlink(resolvedQueueFile);
      console.log(`🗑️ Removed message queue for session ${sessionId}`);
    } catch (error) {
      if (error.code !== 'ENOENT') {
        console.error(`❌ Failed to remove message queue for session ${sessionId}:`, error);
      }
    }
  }
}

// Export singleton instance
export const sessionPersistence = new SessionPersistenceService();
