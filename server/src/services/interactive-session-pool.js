import { EventEmitter } from 'events';
import { spawn, execSync } from 'child_process';
import { createLogger } from '../utils/logger.js';
import { UnifiedMessageParser } from './message-parser.js';
import { commandSecurity } from './command-security.js';

const logger = createLogger('InteractiveSessionPool');

/**
 * Manages a pool of persistent interactive Claude CLI sessions
 * These sessions stay alive for 24 hours and can handle multiple messages
 */
export class InteractiveSessionPool extends EventEmitter {
  constructor(options = {}) {
    super();
    
    // Configuration
    this.maxSessions = parseInt(process.env.MAX_CONCURRENT_SESSIONS || options.maxSessions || 10);
    this.sessionTimeout = parseInt(process.env.SESSION_TIMEOUT_HOURS || 24) * 60 * 60 * 1000;
    this.warningTime = parseInt(process.env.SESSION_WARNING_HOURS || 20) * 60 * 60 * 1000;
    this.maxMemoryPerSession = parseInt(process.env.MAX_MEMORY_PER_SESSION_MB || 500) * 1024 * 1024;
    this.maxTotalMemory = parseInt(process.env.MAX_TOTAL_MEMORY_GB || 2) * 1024 * 1024 * 1024;
    this.cpuLimit = parseInt(process.env.CPU_USAGE_LIMIT_PERCENT || 80);
    
    // Session storage
    this.sessions = new Map(); // sessionId -> process info
    this.sessionMetadata = new Map(); // sessionId -> metadata
    
    // Health monitoring
    this.healthCheckInterval = 30000; // 30 seconds
    this.healthMonitor = null;
    
    // Command detection
    this._claudeCommand = null;
    
    logger.info('Interactive session pool initialized', {
      maxSessions: this.maxSessions,
      timeoutHours: this.sessionTimeout / (60 * 60 * 1000),
      warningHours: this.warningTime / (60 * 60 * 1000),
    });
  }
  
  // Lazy getter for Claude command
  get claudeCommand() {
    if (!this._claudeCommand) {
      this._claudeCommand = process.env.NODE_ENV === 'test' ? 'claude' : this.findClaudeCommand();
    }
    return this._claudeCommand;
  }
  
  findClaudeCommand() {
    // Try to find Claude CLI command
    try {
      execSync('which claude', { stdio: 'ignore' });
      return 'claude';
    } catch {
      logger.warn('claude command not found in PATH');
      return 'claude'; // Fallback, will error later if not available
    }
  }
  
  /**
   * Create a new interactive Claude session
   */
  async createSession(projectPath) {
    const sessionLogger = logger.child({ projectPath });
    
    // Check resource limits
    if (this.sessions.size >= this.maxSessions) {
      throw new Error(`Maximum concurrent sessions (${this.maxSessions}) reached`);
    }
    
    // Validate project path
    const dirValidation = await commandSecurity.validateDirectory(projectPath);
    if (!dirValidation.allowed) {
      throw new Error(`Invalid project path: ${dirValidation.reason}`);
    }
    
    // Build args - MUST include --print for Claude to output responses
    const args = ['--print', '--output-format', 'stream-json', '--verbose'];
    
    // Add permission flags if configured
    if (process.env.CLAUDE_SKIP_PERMISSIONS === 'true') {
      args.push('--dangerously-skip-permissions');
    }
    
    sessionLogger.info('Creating interactive Claude session', {
      workingDirectory: projectPath,
      args: args.slice(0, 4), // Log first few args
    });
    
    return new Promise((resolve, reject) => {
      let claudeProcess;
      let sessionId = null;
      let initComplete = false;
      const initTimeout = 30000; // 30 seconds
      
      try {
        // Spawn Claude with --print for interactive responses
        claudeProcess = spawn(this.claudeCommand, args, {
          cwd: projectPath,
          stdio: ['pipe', 'pipe', 'pipe'], // Keep pipes open for communication
          env: {
            ...process.env,
            // Ensure Claude uses the project directory
            PWD: projectPath,
          },
        });
      } catch (spawnError) {
        sessionLogger.error('Failed to spawn interactive Claude CLI', {
          error: spawnError.message,
          code: spawnError.code,
        });
        reject(new Error(`Failed to start Claude CLI: ${spawnError.message}`));
        return;
      }
      
      if (!claudeProcess.pid) {
        reject(new Error('Claude CLI process failed to start (no PID)'));
        return;
      }
      
      sessionLogger.info('Interactive process started', { pid: claudeProcess.pid });
      
      // Set up stream parser for this session
      const streamParser = new UnifiedMessageParser();
      let responseBuffer = [];
      
      // Handle stdout data - look for session ID in initial response
      const stdoutHandler = (data) => {
        const chunk = data.toString();
        const lines = chunk.split('\n');
        
        for (const line of lines) {
          if (!line.trim()) continue;
          
          try {
            const parsed = JSON.parse(line);
            
            // Look for session_id in response
            if (parsed.session_id && !sessionId) {
              sessionId = parsed.session_id;
              sessionLogger.info('Got session ID from Claude', { sessionId });
            }
          } catch (e) {
            // Not valid JSON, might be initial output
          }
        }
      };
      
      // Handle stderr
      const stderrHandler = (data) => {
        const error = data.toString();
        sessionLogger.error('Claude CLI error during init', { error });
        
        if (!initComplete) {
          initComplete = true;
          claudeProcess.kill('SIGTERM');
          reject(new Error(`Claude CLI error: ${error}`));
        }
      };
      
      // Handle process exit during initialization
      const exitHandler = (code) => {
        if (!initComplete) {
          initComplete = true;
          reject(new Error(`Claude CLI exited during initialization with code ${code}`));
        }
      };
      
      // Attach handlers
      claudeProcess.stdout.on('data', stdoutHandler);
      claudeProcess.stderr.on('data', stderrHandler);
      claudeProcess.on('exit', exitHandler);
      
      // In interactive mode, create session immediately with temporary ID
      const tempSessionId = `temp-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
      
      // Store session immediately
      const sessionInfo = {
        sessionId: tempSessionId,
        process: claudeProcess,
        projectPath,
        createdAt: Date.now(),
        lastActivity: Date.now(),
        messageCount: 0,
        pid: claudeProcess.pid,
        pendingRealId: true, // Flag indicating we're waiting for real session ID
      };
      
      this.sessions.set(tempSessionId, sessionInfo);
      this.sessionMetadata.set(tempSessionId, {
        warningsSent: [],
        expiresAt: Date.now() + this.sessionTimeout,
      });
      
      // Set up ongoing stream handling
      this.setupSessionHandlers(tempSessionId, claudeProcess);
      
      sessionLogger.info('Interactive session created with temporary ID', {
        sessionId: tempSessionId,
        pid: claudeProcess.pid,
      });
      
      // Resolve immediately so caller can send first message
      initComplete = true;
      resolve(sessionInfo);
      
      // Note: The real session ID from Claude will be captured when the first response arrives
    });
  }
  
  /**
   * Set up ongoing handlers for an established session
   */
  setupSessionHandlers(sessionId, claudeProcess) {
    const sessionLogger = logger.child({ sessionId });
    
    // Remove initialization handlers (they're one-time use)
    claudeProcess.removeAllListeners('exit');
    
    // Set up process exit handler
    claudeProcess.on('exit', (code) => {
      sessionLogger.info('Interactive session process exited', { code });
      
      // Clean up session
      this.sessions.delete(sessionId);
      this.sessionMetadata.delete(sessionId);
      
      // Emit event for notification
      this.emit('sessionClosed', {
        sessionId,
        reason: 'process_exit',
        code,
      });
    });
    
    // Handle unexpected errors
    claudeProcess.on('error', (error) => {
      sessionLogger.error('Process error', { error: error.message });
      
      // Clean up session
      this.sessions.delete(sessionId);
      this.sessionMetadata.delete(sessionId);
      
      this.emit('sessionError', {
        sessionId,
        error: error.message,
      });
    });
  }
  
  /**
   * Send a message to an existing interactive session
   */
  async sendMessage(sessionId, message) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }
    
    const sessionLogger = logger.child({ sessionId });
    const { process: claudeProcess } = session;
    
    // Update activity
    session.lastActivity = Date.now();
    session.messageCount++;
    
    return new Promise((resolve, reject) => {
      let responseComplete = false;
      const responses = [];
      const timeout = 120000; // 2 minutes per message
      
      // Set up one-time listeners for this message
      const dataHandler = (data) => {
        const chunk = data.toString();
        const lines = chunk.split('\n');
        
        for (const line of lines) {
          if (!line.trim()) continue;
          
          try {
            const parsed = JSON.parse(line);
            responses.push(parsed);
            
            // Check if this is the final result
            if (parsed.type === 'result') {
              responseComplete = true;
              claudeProcess.stdout.removeListener('data', dataHandler);
              
              sessionLogger.info('Got complete response', {
                responseCount: responses.length,
                messageCount: session.messageCount,
              });
              
              // Return the result
              resolve({
                result: parsed.result,
                sessionId,
                responses,
                success: !parsed.is_error,
                sessionExpiresAt: this.sessionMetadata.get(sessionId)?.expiresAt,
              });
            }
          } catch (e) {
            // Not valid JSON, continue collecting
          }
        }
      };
      
      const errorHandler = (data) => {
        const error = data.toString();
        sessionLogger.error('Error during message send', { error });
        claudeProcess.stderr.removeListener('data', errorHandler);
        reject(new Error(`Claude error: ${error}`));
      };
      
      // Attach handlers
      claudeProcess.stdout.on('data', dataHandler);
      claudeProcess.stderr.once('data', errorHandler);
      
      // Send the message
      sessionLogger.info('Sending message to interactive session', {
        messageLength: message.length,
        messageCount: session.messageCount,
      });
      
      claudeProcess.stdin.write(`${message}\n`, (err) => {
        if (err) {
          sessionLogger.error('Failed to write to stdin', { error: err.message });
          claudeProcess.stdout.removeListener('data', dataHandler);
          claudeProcess.stderr.removeListener('data', errorHandler);
          reject(err);
        }
      });
      
      // Set timeout for response
      setTimeout(() => {
        if (!responseComplete) {
          claudeProcess.stdout.removeListener('data', dataHandler);
          claudeProcess.stderr.removeListener('data', errorHandler);
          reject(new Error('Timeout waiting for Claude response'));
        }
      }, timeout);
    });
  }
  
  /**
   * Extend a session's lifetime
   */
  async extendSession(sessionId, sendRecap = false) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new Error(`Session ${sessionId} not found`);
    }
    
    const metadata = this.sessionMetadata.get(sessionId);
    if (metadata) {
      // Reset expiry time
      metadata.expiresAt = Date.now() + this.sessionTimeout;
      metadata.warningsSent = [];
      
      logger.info('Session extended', {
        sessionId,
        newExpiresAt: new Date(metadata.expiresAt).toISOString(),
      });
    }
    
    // Optionally send recap prompt
    if (sendRecap) {
      try {
        const recapResult = await this.sendMessage(
          sessionId,
          "Please provide a brief summary of our conversation so far."
        );
        return { extended: true, recap: recapResult.result };
      } catch (error) {
        logger.error('Failed to get recap', { sessionId, error: error.message });
        return { extended: true, recap: null, error: error.message };
      }
    }
    
    return { extended: true };
  }
  
  /**
   * Kill a session
   */
  async killSession(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return false;
    }
    
    logger.info('Killing interactive session', { sessionId, pid: session.process.pid });
    
    // Kill the process
    session.process.kill('SIGTERM');
    
    // Force kill after 5 seconds if still running
    setTimeout(() => {
      if (session.process && !session.process.killed) {
        session.process.kill('SIGKILL');
      }
    }, 5000);
    
    // Clean up immediately
    this.sessions.delete(sessionId);
    this.sessionMetadata.delete(sessionId);
    
    this.emit('sessionKilled', { sessionId });
    
    return true;
  }
  
  /**
   * Check if a session exists
   */
  hasSession(sessionId) {
    return this.sessions.has(sessionId);
  }
  
  /**
   * Get active sessions list
   */
  getActiveSessions() {
    const sessions = [];
    for (const [sessionId, session] of this.sessions) {
      const metadata = this.sessionMetadata.get(sessionId);
      sessions.push({
        sessionId,
        projectPath: session.projectPath,
        createdAt: session.createdAt,
        lastActivity: session.lastActivity,
        messageCount: session.messageCount,
        expiresAt: metadata?.expiresAt,
        pid: session.pid,
      });
    }
    return sessions;
  }
  
  /**
   * Get session status
   */
  getSessionStatus(sessionId) {
    const session = this.sessions.get(sessionId);
    if (!session) {
      return null;
    }
    
    const metadata = this.sessionMetadata.get(sessionId);
    const now = Date.now();
    const timeRemaining = metadata ? metadata.expiresAt - now : 0;
    
    return {
      sessionId,
      projectPath: session.projectPath,
      createdAt: session.createdAt,
      lastActivity: session.lastActivity,
      messageCount: session.messageCount,
      expiresAt: metadata?.expiresAt,
      timeRemaining,
      isExpired: timeRemaining <= 0,
      needsWarning: timeRemaining > 0 && timeRemaining <= this.warningTime,
      pid: session.pid,
    };
  }
  
  /**
   * Get resource statistics
   */
  getResourceStats() {
    // TODO: Implement actual resource monitoring
    return {
      sessionCount: this.sessions.size,
      maxSessions: this.maxSessions,
      memoryUsage: '0 MB', // TODO: Calculate actual memory
      cpuUsage: '0%', // TODO: Calculate actual CPU
      oldestSession: this.getOldestSession(),
    };
  }
  
  getOldestSession() {
    let oldest = null;
    for (const [sessionId, session] of this.sessions) {
      if (!oldest || session.createdAt < oldest.createdAt) {
        oldest = { sessionId, createdAt: session.createdAt };
      }
    }
    return oldest;
  }
  
  /**
   * Start health monitoring
   */
  startHealthMonitoring() {
    if (this.healthMonitor) {
      return; // Already monitoring
    }
    
    this.healthMonitor = setInterval(() => {
      this.checkSessionHealth();
    }, this.healthCheckInterval);
    
    logger.info('Health monitoring started');
  }
  
  /**
   * Check health of all sessions
   */
  async checkSessionHealth() {
    const now = Date.now();
    
    for (const [sessionId, session] of this.sessions) {
      const metadata = this.sessionMetadata.get(sessionId);
      if (!metadata) continue;
      
      // Check if expired
      if (now >= metadata.expiresAt) {
        logger.info('Session expired, killing', { sessionId });
        await this.killSession(sessionId);
        
        this.emit('sessionExpired', {
          sessionId,
          reason: 'timeout',
        });
        continue;
      }
      
      // Check if warning needed
      const timeRemaining = metadata.expiresAt - now;
      if (timeRemaining <= this.warningTime && !metadata.warningsSent.includes('20hr')) {
        metadata.warningsSent.push('20hr');
        
        this.emit('sessionWarning', {
          sessionId,
          type: 'timeout',
          message: `Session will expire in ${Math.floor(timeRemaining / (60 * 60 * 1000))} hours`,
          timeRemaining,
        });
      }
      
      // Check if process is still alive
      if (session.process && session.process.killed) {
        logger.warn('Found dead session process, cleaning up', { sessionId });
        this.sessions.delete(sessionId);
        this.sessionMetadata.delete(sessionId);
        
        this.emit('sessionClosed', {
          sessionId,
          reason: 'process_dead',
        });
      }
    }
  }
  
  /**
   * Stop health monitoring
   */
  stopHealthMonitoring() {
    if (this.healthMonitor) {
      clearInterval(this.healthMonitor);
      this.healthMonitor = null;
      logger.info('Health monitoring stopped');
    }
  }
  
  /**
   * Shutdown the pool
   */
  async shutdown() {
    logger.info('Shutting down interactive session pool');
    
    // Stop health monitoring
    this.stopHealthMonitoring();
    
    // Kill all sessions
    const killPromises = [];
    for (const [sessionId] of this.sessions) {
      killPromises.push(this.killSession(sessionId));
    }
    
    await Promise.all(killPromises);
    
    logger.info('Interactive session pool shut down complete');
  }
}

// Export singleton instance
export const sessionPool = new InteractiveSessionPool();