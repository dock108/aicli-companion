import { promises as fs } from 'fs';
import path from 'path';
import os from 'os';

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
  }

  /**
   * Initialize the persistence service - create directories and load existing sessions
   */
  async initialize() {
    if (this.isInitialized) return;

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
      const sessions = JSON.parse(data);
      
      // Convert array to Map for efficient lookups
      this.sessionsCache.clear();
      for (const session of sessions) {
        this.sessionsCache.set(session.sessionId, {
          ...session,
          // Parse timestamps back to numbers
          createdAt: new Date(session.createdAt).getTime(),
          lastActivity: new Date(session.lastActivity).getTime(),
          backgroundedAt: session.backgroundedAt ? new Date(session.backgroundedAt).getTime() : null,
        });
      }
      
      console.log(`📖 Loaded ${sessions.length} persisted sessions from disk`);
    } catch (error) {
      if (error.code === 'ENOENT') {
        // File doesn't exist yet - this is normal for first run
        console.log('📖 No existing sessions file found - starting fresh');
        this.sessionsCache.clear();
      } else {
        console.error('❌ Error loading sessions from disk:', error);
        // Try to load from backup
        await this.loadFromBackup();
        throw error;
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
          backgroundedAt: session.backgroundedAt ? new Date(session.backgroundedAt).getTime() : null,
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
      const sessions = Array.from(this.sessionsCache.values()).map(session => ({
        ...session,
        // Convert timestamps to ISO strings for JSON serialization
        createdAt: new Date(session.createdAt).toISOString(),
        lastActivity: new Date(session.lastActivity).toISOString(),
        backgroundedAt: session.backgroundedAt ? new Date(session.backgroundedAt).toISOString() : null,
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
      
      // Atomic write: write to temp file first, then rename
      const tempFile = `${this.sessionsFile}.tmp`;
      await fs.writeFile(tempFile, data, 'utf8');
      await fs.rename(tempFile, this.sessionsFile);
      
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
      isBackgrounded: sessionData.isBackgrounded || false,
      backgroundedAt: sessionData.backgroundedAt || null,
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
    
    console.log(`🔄 Updated persisted session ${sessionId}:`, Object.keys(updates));
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
      console.log(`🗑️ Removed session ${sessionId} from persistence`);
    }
    return existed;
  }

  /**
   * Clean up old sessions (older than specified age)
   */
  async cleanup(maxAgeMs = 7 * 24 * 60 * 60 * 1000) { // Default: 7 days
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
  getStaleSessionIds(maxIdleMs = 4 * 60 * 60 * 1000) { // Default: 4 hours
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
      withConversation: sessions.filter(s => s.conversationStarted).length,
      backgrounded: sessions.filter(s => s.isBackgrounded).length,
      recentlyActive: sessions.filter(s => (now - s.lastActivity) < 60 * 60 * 1000).length, // Active in last hour
      oldest: sessions.length > 0 ? Math.min(...sessions.map(s => s.createdAt)) : null,
      newest: sessions.length > 0 ? Math.max(...sessions.map(s => s.createdAt)) : null,
    };

    return stats;
  }
}

// Export singleton instance
export const sessionPersistence = new SessionPersistenceService();