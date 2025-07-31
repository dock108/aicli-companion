/**
 * Utility functions for WebSocket message handling and formatting
 */
export class WebSocketUtilities {
  /**
   * Send a message to a specific client
   */
  static sendMessage(clientId, message, clients) {
    const client = clients.get(clientId);
    if (!client || client.ws.readyState !== 1) {
      console.warn(`Cannot send message to client ${clientId}: client not available or not connected`);
      return false;
    }

    try {
      const messageData = JSON.stringify(message);
      client.ws.send(messageData);
      
      // Update client activity
      client.lastActivity = new Date();
      
      return true;
    } catch (error) {
      console.error(`Error sending message to client ${clientId}:`, error);
      return false;
    }
  }

  /**
   * Send an error message to a client
   */
  static sendErrorMessage(clientId, requestId, code, message, clients, details = {}) {
    const errorMessage = {
      type: 'error',
      requestId,
      timestamp: new Date().toISOString(),
      error: {
        code,
        message,
        ...details,
      },
    };

    return this.sendMessage(clientId, errorMessage, clients);
  }

  /**
   * Broadcast a message to all clients associated with a session
   */
  static broadcastToSessionClients(sessionId, message, clients) {
    const sessionClients = [];
    
    clients.forEach((client, clientId) => {
      if (client.sessionIds && client.sessionIds.has(sessionId)) {
        sessionClients.push(clientId);
      }
    });

    if (sessionClients.length === 0) {
      console.log(`📤 No connected clients for session ${sessionId}, queuing message`);
      
      // Import messageQueueService here to avoid circular dependency
      import('./message-queue.js').then(({ messageQueueService }) => {
        messageQueueService.queueMessage(sessionId, message);
      }).catch(error => {
        console.error('Failed to queue message:', error);
      });
      
      return;
    }

    console.log(`📤 Broadcasting to ${sessionClients.length} clients for session ${sessionId}`);

    let successCount = 0;
    sessionClients.forEach(clientId => {
      if (this.sendMessage(clientId, message, clients)) {
        successCount++;
      }
    });

    // Log delivery stats for debugging
    if (message.type !== 'ping' && message.type !== 'pong') {
      console.log(`📊 Message delivery: ${successCount}/${sessionClients.length} clients reached`);
      
      if (message.type === 'streamChunk' && message.data?.chunk?.isFinal) {
        console.log(`🏁 Final stream chunk delivered to ${successCount} clients`);
      } else if (message.type === 'assistantMessage' && message.data?.isComplete) {
        console.log(`✅ Complete assistant message delivered to ${successCount} clients`);
      }
    }
  }

  /**
   * Determine the type of stream data
   */
  static determineStreamType(data) {
    if (!data) return 'unknown';

    if (typeof data === 'string') {
      if (data.includes('error') || data.includes('Error')) return 'error';
      if (data.includes('warning') || data.includes('Warning')) return 'warning';
      return 'text';
    }

    if (typeof data === 'object') {
      if (data.type) return data.type;
      if (data.error) return 'error';
      if (data.text) return 'text';
    }

    return 'data';
  }

  /**
   * Format stream content for consistent client consumption
   */
  static formatStreamContent(data) {
    if (!data) return { text: '', metadata: {} };

    if (typeof data === 'string') {
      return {
        text: data,
        metadata: {
          length: data.length,
          formatted: true,
        },
      };
    }

    if (typeof data === 'object') {
      // Handle structured data
      if (data.text || data.content) {
        return {
          text: data.text || data.content,
          metadata: {
            type: data.type || 'text',
            model: data.model,
            usage: data.usage,
            formatted: true,
            ...data.metadata,
          },
        };
      }

      // Handle raw object data
      return {
        text: JSON.stringify(data, null, 2),
        metadata: {
          type: 'json',
          original: data,
          formatted: true,
        },
      };
    }

    // Fallback for other data types
    return {
      text: String(data),
      metadata: {
        type: typeof data,
        formatted: true,
      },
    };
  }

  /**
   * Parse progress information from command output
   */
  static parseProgressFromOutput(output) {
    if (!output || typeof output !== 'string') {
      return null;
    }

    const lowerOutput = output.toLowerCase();

    // Parse percentage progress
    const percentMatch = output.match(/(\d+)%/);
    if (percentMatch) {
      const progress = parseInt(percentMatch[1]) / 100;
      return {
        stage: 'processing',
        progress: Math.min(progress, 1.0),
        message: `Processing... ${percentMatch[1]}%`,
        estimatedTimeRemaining: null,
      };
    }

    // Parse step-based progress (e.g., "Step 3 of 10")
    const stepMatch = output.match(/step\s+(\d+)\s+of\s+(\d+)/i);
    if (stepMatch) {
      const current = parseInt(stepMatch[1]);
      const total = parseInt(stepMatch[2]);
      const progress = current / total;
      return {
        stage: 'processing',
        progress: Math.min(progress, 1.0),
        message: `Step ${current} of ${total}`,
        estimatedTimeRemaining: null,
      };
    }

    // Parse time estimates
    const timeMatch = output.match(/(\d+)\s*(min|minute|sec|second)/i);
    if (timeMatch) {
      const value = parseInt(timeMatch[1]);
      const unit = timeMatch[2].toLowerCase();
      const seconds = unit.startsWith('min') ? value * 60 : value;
      
      return {
        stage: 'processing',
        progress: null,
        message: `Estimated time: ${timeMatch[0]}`,
        estimatedTimeRemaining: seconds,
      };
    }

    // Parse stage indicators
    if (
      lowerOutput.includes('starting') ||
      lowerOutput.includes('initializing') ||
      lowerOutput.includes('beginning')
    ) {
      return {
        stage: 'starting',
        progress: 0.0,
        message: 'Starting...',
        estimatedTimeRemaining: null,
      };
    }

    if (
      lowerOutput.includes('analyzing') ||
      lowerOutput.includes('thinking') ||
      lowerOutput.includes('considering')
    ) {
      return {
        stage: 'analyzing',
        progress: null,
        message: 'Analyzing request...',
        estimatedTimeRemaining: null,
      };
    }

    // Parse completion indicators
    if (lowerOutput.includes('completed') || lowerOutput.includes('finished') || lowerOutput.includes('done')) {
      return {
        stage: 'completing',
        progress: 1.0,
        message: 'Finishing up...',
        estimatedTimeRemaining: null,
      };
    }

    return null;
  }

  /**
   * Validate message structure
   */
  static validateMessage(message) {
    if (!message || typeof message !== 'object') {
      return { valid: false, error: 'Message must be an object' };
    }

    if (!message.type || typeof message.type !== 'string') {
      return { valid: false, error: 'Message must have a string type field' };
    }

    if (message.requestId !== undefined && typeof message.requestId !== 'string') {
      return { valid: false, error: 'RequestId must be a string if provided' };
    }

    return { valid: true };
  }

  /**
   * Create standardized message response
   */
  static createResponse(type, requestId, data, options = {}) {
    const response = {
      type,
      requestId,
      timestamp: new Date().toISOString(),
      data,
    };

    // Add optional fields
    if (options.error) {
      response.error = options.error;
    }

    if (options.isComplete !== undefined) {
      response.isComplete = options.isComplete;
    }

    if (options.metadata) {
      response.metadata = options.metadata;
    }

    return response;
  }

  /**
   * Extract client info from WebSocket request
   */
  static extractClientInfo(request) {
    return {
      ip: request.socket.remoteAddress,
      family: request.socket.remoteFamily,
      userAgent: request.headers['user-agent'] || 'unknown',
      host: request.headers.host,
      origin: request.headers.origin,
      protocol: request.headers['sec-websocket-protocol'],
    };
  }

  /**
   * Check if WebSocket is in ready state
   */
  static isWebSocketReady(ws) {
    return ws && ws.readyState === 1; // WebSocket.OPEN = 1
  }

  /**
   * Safe JSON stringify with error handling
   */
  static safeStringify(obj, fallback = '{}') {
    try {
      return JSON.stringify(obj);
    } catch (error) {
      console.error('JSON stringify failed:', error);
      return fallback;
    }
  }

  /**
   * Safe JSON parse with error handling
   */
  static safeParse(str, fallback = null) {
    try {
      return JSON.parse(str);
    } catch (error) {
      console.error('JSON parse failed:', error);
      return fallback;
    }
  }
}