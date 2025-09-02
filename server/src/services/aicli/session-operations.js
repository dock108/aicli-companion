export class SessionOperations {
  constructor(sessionManager, processRunner, eventEmitter) {
    this.sessionManager = sessionManager;
    this.processRunner = processRunner;
    this.emit = eventEmitter.emit.bind(eventEmitter);
  }

  async sendStreamingPrompt(
    prompt,
    { sessionId = null, skipPermissions = false, attachmentPaths = [], retryCount = 3 }
  ) {
    // Check if we have an existing session
    if (sessionId && this.sessionManager.hasSession(sessionId)) {
      const session = this.sessionManager.getSession(sessionId);
      console.log(`📤 Sending prompt to existing session ${sessionId}`);
      return this.processRunner.sendToInteractiveSession(session, prompt);
    }

    // Check if we need to route to an existing Claude session
    if (sessionId) {
      // Check if we have an active session
      const session = this.sessionManager.getSession(sessionId);
      if (session && session.conversationStarted) {
        console.log(`📤 Sending prompt to existing session ${sessionId}`);
        // For existing sessions, we need to use executeAICLICommand with the session
        // since we don't maintain persistent processes anymore
        return this.executeAICLICommand(session, prompt, attachmentPaths);
      }
    }

    // Start a new session
    console.log(`🆕 Starting new Claude session${sessionId ? ` (requested: ${sessionId})` : ''}`);
    return this.sendPromptToClaude(prompt, {
      sessionId,
      skipPermissions,
      attachmentPaths, // Pass attachment file paths
      retryCount,
    });
  }

  async sendPromptToClaude(
    prompt,
    {
      sessionId = null,
      skipPermissions = false,
      attachmentPaths = [],
      defaultWorkingDirectory = process.cwd(),
      retryCount = 3,
    }
  ) {
    try {
      // Create a new session
      const session = await this.sessionManager.createInteractiveSession(
        sessionId,
        prompt,
        defaultWorkingDirectory,
        { skipPermissions, attachmentPaths }
      );

      console.log(`🚀 Starting Claude session: ${session.sessionId}`);

      // Execute the AICLI command
      const response = await this.executeAICLICommand(session, prompt, attachmentPaths, retryCount);

      // Track the Claude session if it gave us a different ID
      if (response.claudeSessionId && response.claudeSessionId !== session.sessionId) {
        console.log(
          `🔄 Claude assigned session ID: ${response.claudeSessionId} (our ID: ${session.sessionId})`
        );
        // Store mapping if mapClaudeSession method exists
        if (this.sessionManager.mapClaudeSession) {
          await this.sessionManager.mapClaudeSession(session.sessionId, response.claudeSessionId);
        }
      }

      return response;
    } catch (error) {
      // Check if error is due to expired session
      if (
        error.message &&
        (error.message.includes('Session expired') || error.message.includes('session not found'))
      ) {
        console.log('🔄 Session expired, creating new session...');

        // Clean up the expired session
        if (sessionId) {
          await this.sessionManager.cleanupDeadSession(sessionId);
        }

        // Retry with a new session
        const newSession = await this.sessionManager.createInteractiveSession(
          null, // Force new session ID
          prompt,
          defaultWorkingDirectory,
          { skipPermissions, attachmentPaths }
        );

        console.log(`🆕 Created fresh session: ${newSession.sessionId}`);
        const response = await this.executeAICLICommand(
          newSession,
          prompt,
          attachmentPaths,
          retryCount
        );

        // Track the new Claude session if method exists
        if (response.claudeSessionId && this.sessionManager.mapClaudeSession) {
          await this.sessionManager.mapClaudeSession(
            newSession.sessionId,
            response.claudeSessionId
          );

          // Also track that the new session handles messages for the old session
          if (sessionId && sessionId !== newSession.sessionId) {
            await this.sessionManager.mapClaudeSession(sessionId, response.claudeSessionId);
          }
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
