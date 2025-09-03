export class SessionOperations {
  constructor(sessionManager, processRunner, eventEmitter) {
    this.sessionManager = sessionManager;
    this.processRunner = processRunner;
    this.emit = eventEmitter.emit.bind(eventEmitter);
  }

  async sendStreamingPrompt(
    prompt,
    { sessionId = null, skipPermissions = false, attachmentPaths = [], retryCount = 3, workingDirectory = process.cwd() }
  ) {
    // The sessionId from iOS is the Claude session ID from previous response
    // We just use it directly - no internal session IDs needed
    const claudeSessionId = sessionId;
    
    if (claudeSessionId && claudeSessionId !== 'new' && claudeSessionId !== 'null') {
      console.log(`📤 Continuing Claude conversation with session: ${claudeSessionId}`);
      // Create a simple session object with just what we need
      const session = {
        sessionId: claudeSessionId,  // This will be used for logging
        claudeSessionId: claudeSessionId,  // This will be used for --resume flag
        workingDirectory: workingDirectory,
        conversationStarted: true
      };
      return this.executeAICLICommand(session, prompt, attachmentPaths);
    }

    // Start a new conversation (no Claude session ID yet)
    console.log(`🆕 Starting new Claude conversation`);
    return this.sendPromptToClaude(prompt, {
      sessionId: null,  // No Claude session ID yet
      skipPermissions,
      attachmentPaths,
      workingDirectory,
      retryCount,
    });
  }

  async sendPromptToClaude(
    prompt,
    {
      sessionId = null,
      skipPermissions = false,
      attachmentPaths = [],
      workingDirectory = process.cwd(),
      defaultWorkingDirectory = process.cwd(),
      retryCount = 3,
    }
  ) {
    try {
      // Create a minimal session object for a new conversation
      const session = {
        sessionId: null,  // No session ID yet - will get from Claude
        claudeSessionId: null,  // No Claude session yet
        workingDirectory: workingDirectory || defaultWorkingDirectory,
        skipPermissions,
        attachmentPaths
      };

      console.log(`🚀 Starting new Claude conversation`);

      // Execute the AICLI command
      const response = await this.executeAICLICommand(session, prompt, attachmentPaths, retryCount);

      // Log the Claude session ID we got back
      if (response.claudeSessionId) {
        console.log(`🔑 Claude session ID: ${response.claudeSessionId}`);
      }

      return response;
    } catch (error) {
      // For session errors, just retry without a session
      if (
        error.message &&
        (error.message.includes('Session expired') || error.message.includes('session not found'))
      ) {
        console.log('🔄 Session expired, starting fresh conversation...');

        // Retry with no session
        const newSession = {
          sessionId: null,  // No session ID - will get from Claude
          claudeSessionId: null,
          workingDirectory: workingDirectory || defaultWorkingDirectory,
          skipPermissions,
          attachmentPaths
        };

        const response = await this.executeAICLICommand(
          newSession,
          prompt,
          attachmentPaths,
          retryCount
        );

        if (response.claudeSessionId) {
          console.log(`🔑 New Claude session ID: ${response.claudeSessionId}`);
        }

        return response;
      }

      // Re-throw other errors
      throw error;
    }
  }

  async executeAICLICommand(session, prompt, attachmentPaths = [], retryCount = 3) {
    let attempts = 0;
    const maxAttempts = retryCount;

    while (attempts < maxAttempts) {
      try {
        attempts++;
        // Delegate to process runner
        return await this.processRunner.executeAICLICommand(session, prompt, attachmentPaths);
      } catch (error) {
        // Check if error is due to expired session
        if (
          error.message &&
          (error.message.includes('Session expired') || error.message.includes('session not found'))
        ) {
          console.log('🔄 Session expired during execution, cleaning up...');

          // Let the error bubble up so caller can handle cleanup and retry
          throw error;
        }

        // Check if error is due to rate limiting
        if (error.code === 'RATE_LIMITED' && attempts < maxAttempts) {
          console.log(`🔄 Rate limited, retrying attempt ${attempts}/${maxAttempts}...`);
          // Wait before retrying (exponential backoff)
          const delay = Math.min(1000 * Math.pow(2, attempts - 1), 5000);
          await new Promise((resolve) => setTimeout(resolve, delay));
          continue;
        }

        // Check for init response in error (happens when Claude auto-creates session)
        if (
          error.response &&
          error.response.type === 'system' &&
          error.response.subtype === 'init'
        ) {
          console.log('🔄 Claude auto-created session, tracking it...');

          // Extract the Claude session ID
          const claudeSessionId = error.response.session_id;
          if (claudeSessionId) {
            // Track session for routing
            await this.sessionManager.trackSessionForRouting(
              claudeSessionId,
              session.workingDirectory || process.cwd()
            );

            // Also track activity
            this.sessionManager.trackClaudeSessionActivity(claudeSessionId);
          }

          // Return the init response as success
          return {
            success: true,
            claudeSessionId,
            response: error.response,
          };
        }

        // For other errors or if we've exhausted retries, throw
        throw error;
      }
    }
  }

  async closeSession(sessionId) {
    const session = this.sessionManager.getSession(sessionId);
    if (session) {
      // Kill the process using sessionId
      await this.processRunner.killProcess(sessionId);
      this.sessionManager.removeSession(sessionId);
    }
  }

  async killSession(sessionId, reason = 'User requested cancellation') {
    const session = this.sessionManager.getSession(sessionId);
    if (!session) {
      // Check Claude session mapping
      // Try to find the session with the given ID
      // (Session manager doesn't have findClaudeSessionForOurSession method)

      console.warn(`⚠️ No session found to kill: ${sessionId}`);
      return false;
    }

    console.log(`🔫 Killing session ${sessionId}: ${reason}`);

    try {
      // Kill the process using sessionId
      if (session.process) {
        await this.processRunner.killProcess(sessionId, reason);
      }

      // Clean up session
      this.sessionManager.removeSession(sessionId);

      // Emit cancellation event
      this.emit('sessionCancelled', {
        sessionId,
        reason,
        timestamp: new Date().toISOString(),
      });

      return true;
    } catch (error) {
      console.error(`❌ Failed to kill session ${sessionId}:`, error);
      throw error;
    }
  }

  hasSession(sessionId) {
    return this.sessionManager.hasSession(sessionId);
  }

  getSession(sessionId) {
    return this.sessionManager.getSession(sessionId);
  }

  getActiveSessions() {
    return this.sessionManager.getActiveSessions();
  }

  async markSessionBackgrounded(sessionId, reason = null, metadata = {}) {
    return this.sessionManager.markSessionBackgrounded(sessionId, reason, metadata);
  }

  async markSessionForegrounded(sessionId, metadata = {}) {
    return this.sessionManager.markSessionForegrounded(sessionId, metadata);
  }
}
