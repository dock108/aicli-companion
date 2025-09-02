export class PermissionHandler {
  constructor(processRunner) {
    this.processRunner = processRunner;
    // Legacy permission properties (delegated to process runner)
    this.permissionMode = this.processRunner?.permissionMode;
    this.allowedTools = this.processRunner?.allowedTools || [];
    this.disallowedTools = this.processRunner?.disallowedTools || [];
    this.skipPermissions = this.processRunner?.skipPermissions || false;
  }

  // Configure permission settings (delegated to process runner)
  setPermissionMode(mode) {
    if (this.processRunner) {
      this.processRunner.setPermissionMode(mode);
      this.permissionMode = this.processRunner.permissionMode;
    }
  }

  setAllowedTools(tools) {
    if (this.processRunner) {
      this.processRunner.setAllowedTools(tools);
      this.allowedTools = this.processRunner.allowedTools;
    }
  }

  setDisallowedTools(tools) {
    if (this.processRunner) {
      this.processRunner.setDisallowedTools(tools);
      this.disallowedTools = this.processRunner.disallowedTools;
    }
  }

  setSkipPermissions(skip) {
    if (this.processRunner) {
      this.processRunner.setSkipPermissions(skip);
      this.skipPermissions = this.processRunner.skipPermissions;
    }
  }

  buildPermissionArgs(skipPermissions = false) {
    const args = [];

    // Add permission flags
    if (skipPermissions || this.skipPermissions) {
      args.push('--dangerously-skip-permissions');
    } else {
      // Only add permission configuration if not skipping permissions

      // Add permission mode if configured
      if (this.permissionMode && this.permissionMode !== 'default') {
        args.push('--permission-mode');
        args.push(this.permissionMode);
      }

      // Add allowed tools if configured
      if (this.allowedTools.length > 0) {
        args.push('--allow-tools');
        args.push(this.allowedTools.join(','));
      }

      // Add disallowed tools if configured
      if (this.disallowedTools.length > 0) {
        args.push('--disallow-tools');
        args.push(this.disallowedTools.join(','));
      }
    }

    return args;
  }

  async handlePermissionPrompt(sessionId, response, sessionManager, emitFunc) {
    const session = sessionManager.getSession(sessionId);
    if (!session) {
      throw new Error(`No active session found for ${sessionId}`);
    }

    const buffer = sessionManager.getSessionBuffer(sessionId);

    // Already handled by frontend or no final response yet
    if (buffer && buffer.pendingFinalResponse) {
      console.log(`📝 Processing permission response for session ${sessionId}`);

      if (this.containsApprovalResponse(response)) {
        console.log(`✅ Permission granted for session ${sessionId}`);

        // Clear permission flag and emit the buffered final response
        buffer.pendingPermission = false;
        buffer.pendingFinalResponse = false;

        // Process the buffered final response
        if (buffer.finalResponseData) {
          console.log(`📤 Emitting buffered final response for session ${sessionId}`);
          emitFunc('conversationResult', {
            sessionId,
            data: buffer.finalResponseData,
          });

          // Clear the buffer after emitting
          sessionManager.clearSessionBuffer(sessionId);
        }
      } else {
        console.log(`❌ Permission denied for session ${sessionId}`);

        // Clear the buffer and emit denial
        buffer.pendingPermission = false;
        buffer.pendingFinalResponse = false;
        buffer.finalResponseData = null;

        emitFunc('permissionDenied', {
          sessionId,
          message: 'Permission denied by user',
        });

        sessionManager.clearSessionBuffer(sessionId);
      }
    } else {
      console.log(
        `⚠️ No pending permission response for session ${sessionId}, treating as new prompt`
      );
      // Return false to indicate this should be treated as a new prompt
      return false;
    }

    return true;
  }

  containsApprovalResponse(text) {
    const normalizedText = text.toLowerCase().trim();
    return normalizedText === 'y' || normalizedText === 'yes' || normalizedText === 'approve';
  }
}
