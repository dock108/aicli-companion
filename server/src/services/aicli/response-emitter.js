import { AICLIMessageHandler } from '../aicli-message-handler.js';

export class ResponseEmitter {
  constructor(sessionManager, eventEmitter) {
    this.sessionManager = sessionManager;
    this.emit = eventEmitter.emit.bind(eventEmitter);
  }

  async emitAICLIResponse(sessionId, response, _isComplete = false, options = {}) {
    // In stateless architecture, handle null sessionId for first messages
    if (!sessionId) {
      console.debug('Skipping message buffer processing for null sessionId (first message)');
      return;
    }

    let buffer = this.sessionManager.getSessionBuffer(sessionId);
    if (!buffer) {
      // Create buffer on-demand if it doesn't exist
      // This happens when Claude generates a new session ID we don't know about yet
      console.log(`📝 Creating message buffer on-demand for session ${sessionId}`);

      // Check if we have an active session for this ID
      const session = await this.sessionManager.getSession(sessionId);
      if (!session) {
        // Create a minimal tracking entry for this session
        // We don't know the working directory, so use current directory as fallback
        await this.sessionManager.trackSessionForRouting(sessionId, process.cwd());
      }

      // Create the buffer
      buffer = AICLIMessageHandler.createSessionBuffer();
      this.sessionManager.setSessionBuffer(sessionId, buffer);
    }

    // Use extracted message handler for pure business logic
    const result = AICLIMessageHandler.processResponse(response, buffer, options);

    // Persist buffer after processing if messages were added
    // Server is stateless - no message buffering or persistence

    // Handle the processing result and emit appropriate events
    switch (result.action) {
      case 'permission_request':
        console.log(`🔐 Sending permission request immediately for session ${sessionId}`);
        this.emit('permissionRequired', {
          sessionId,
          prompt: result.data.prompt,
          options: result.data.options,
          default: result.data.default,
        });
        this.emit('assistantMessage', {
          sessionId,
          data: {
            type: 'permission_request',
            messageId: result.data.messageId,
            content: result.data.content,
            model: result.data.model,
            usage: result.data.usage,
            timestamp: new Date().toISOString(),
          },
        });
        break;

      case 'tool_use':
        console.log(`🔧 Tool use in progress for session ${sessionId}`);
        this.emit('assistantMessage', {
          sessionId,
          data: {
            type: 'tool_use',
            messageId: result.data.messageId,
            content: result.data.content,
            model: result.data.model,
            usage: result.data.usage,
            timestamp: new Date().toISOString(),
          },
        });
        break;

      case 'final_result':
        await this.handleFinalResultEmission(sessionId, result.data, options);
        break;

      case 'buffer':
        console.log(`📝 ${result.reason} for session ${sessionId}`);
        break;

      case 'skip':
        console.log(`🤷 ${result.reason}, skipping`);
        break;
    }
  }

  async handleFinalResultEmission(sessionId, data, options = {}) {
    const buffer = this.sessionManager.getSessionBuffer(sessionId);

    // Check if we have a pending permission request
    if (buffer && buffer.pendingPermission) {
      console.log(`⏳ Buffering final response for session ${sessionId} (awaiting permission)`);
      buffer.pendingFinalResponse = true;
      buffer.finalResponseData = data;
      return;
    }

    // Check for deferred emission (used in testing)
    if (options.deferEmission) {
      console.log(`⏸️ Deferring final result emission for session ${sessionId}`);
      if (buffer) {
        buffer.deferredFinalResult = data;
      }
      return;
    }

    // Emit the final result immediately
    console.log(`📤 Sending final response for session ${sessionId}`);
    this.emit('conversationResult', {
      sessionId,
      data,
    });

    // Clear the buffer after final emission
    this.sessionManager.clearSessionBuffer(sessionId);
  }

  async emitDeferredResult(sessionId) {
    const buffer = this.sessionManager.getSessionBuffer(sessionId);
    if (buffer && buffer.deferredFinalResult) {
      console.log(`▶️ Emitting deferred final result for session ${sessionId}`);
      await this.handleFinalResultEmission(sessionId, buffer.deferredFinalResult, {
        deferEmission: false,
      });
      buffer.deferredFinalResult = null;
    }
  }

  getSessionBuffer(sessionId) {
    // Get buffer data for debugging/testing
    if (this.sessionManager?.sessionMessageBuffers?.has(sessionId)) {
      const buffer = this.sessionManager.sessionMessageBuffers.get(sessionId);
      if (buffer && typeof buffer === 'object') {
        return {
          messages: buffer.messages || [],
          pendingPermission: buffer.pendingPermission || false,
          pendingFinalResponse: buffer.pendingFinalResponse || false,
          finalResponseData: buffer.finalResponseData || null,
        };
      }
    }
    return null;
  }

  clearSessionBuffer(sessionId) {
    if (this.sessionManager?.clearSessionBuffer) {
      this.sessionManager.clearSessionBuffer(sessionId);
    }
  }
}
