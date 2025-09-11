/**
 * WebSocket Service
 * Provides WebSocket broadcasting functionality that can be injected into other services
 */

import { createLogger } from '../utils/logger.js';

const logger = createLogger('WebSocketService');

class WebSocketService {
  constructor() {
    this.broadcastFunction = null;
  }

  /**
   * Initialize the WebSocket service with a broadcast function
   * This should be called by the main server when setting up WebSocket
   */
  setBroadcastFunction(broadcastFunction) {
    this.broadcastFunction = broadcastFunction;
    logger.info('WebSocket broadcast function configured');
  }

  /**
   * Broadcast a message to all WebSocket connections for a specific session
   * @param {string} sessionId - Session ID to broadcast to
   * @param {Object} message - Message to broadcast
   */
  broadcastToSession(sessionId, message) {
    if (!this.broadcastFunction) {
      logger.warn('WebSocket broadcast function not configured - message not sent', {
        sessionId,
        messageType: message.type,
      });
      return;
    }

    try {
      this.broadcastFunction(sessionId, message);
      logger.debug('Message broadcasted via WebSocket', {
        sessionId,
        messageType: message.type,
      });
    } catch (error) {
      logger.error('Failed to broadcast message via WebSocket', {
        sessionId,
        messageType: message.type,
        error: error.message,
      });
    }
  }

  /**
   * Send an error message via WebSocket
   * @param {string} sessionId - Session ID
   * @param {string} requestId - Request ID
   * @param {string} errorMessage - Error message
   * @param {string} errorType - Error type
   */
  sendError(sessionId, requestId, errorMessage, errorType = 'ERROR') {
    const message = {
      type: 'error',
      requestId,
      sessionId,
      error: {
        message: errorMessage,
        type: errorType,
        timestamp: new Date().toISOString(),
      },
    };

    this.broadcastToSession(sessionId, message);
  }
}

// Create and export singleton instance
export const webSocketService = new WebSocketService();
