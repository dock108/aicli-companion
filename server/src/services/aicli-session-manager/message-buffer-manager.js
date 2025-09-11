/**
 * Message Buffer Manager
 * Manages message buffers for sessions
 */

import { createLogger } from '../../utils/logger.js';
import { AICLIMessageHandler } from '../aicli-message-handler.js';

const logger = createLogger('MessageBufferManager');

export class MessageBufferManager {
  constructor(storage) {
    this.storage = storage;
  }

  /**
   * Get or create message buffer for a session
   */
  getBuffer(sessionId) {
    let buffer = this.storage.getMessageBuffer(sessionId);

    if (!buffer) {
      buffer = AICLIMessageHandler.createSessionBuffer();
      this.storage.addMessageBuffer(sessionId, buffer);
      logger.debug('Created new message buffer', { sessionId });
    }

    return buffer;
  }

  /**
   * Store a message in the session buffer
   */
  storeMessage(sessionId, role, content, metadata = {}) {
    const buffer = this.getBuffer(sessionId);

    const message = {
      role,
      content,
      timestamp: new Date().toISOString(),
      ...metadata,
    };

    if (role === 'user') {
      buffer.userMessages.push(message);
      logger.debug('Stored user message', {
        sessionId,
        messageLength: content?.length,
      });
    } else if (role === 'assistant') {
      buffer.assistantMessages.push(message);
      logger.debug('Stored assistant message', {
        sessionId,
        messageLength: content?.length,
      });
    } else {
      logger.warn('Unknown message role', { sessionId, role });
      return false;
    }

    // Update thinking metadata if provided
    if (metadata.thinkingMetadata) {
      buffer.thinkingMetadata = {
        ...buffer.thinkingMetadata,
        ...metadata.thinkingMetadata,
      };
    }

    // Update session activity if session exists
    const session = this.storage.getSession(sessionId);
    if (session) {
      session.lastActivity = Date.now();
    }

    return true;
  }

  /**
   * Get messages from session buffer
   */
  getMessages(sessionId, limit = 50, offset = 0) {
    const buffer = this.storage.getMessageBuffer(sessionId);

    if (!buffer) {
      logger.debug('No message buffer found', { sessionId });
      return [];
    }

    // Combine and sort messages chronologically
    const allMessages = [
      ...buffer.userMessages.map((msg) => ({ ...msg, type: 'user' })),
      ...buffer.assistantMessages.map((msg) => ({ ...msg, type: 'assistant' })),
    ];

    // Sort by timestamp
    allMessages.sort((a, b) => {
      const timeA = new Date(a.timestamp).getTime();
      const timeB = new Date(b.timestamp).getTime();
      return timeA - timeB;
    });

    // Apply pagination
    const paginatedMessages = allMessages.slice(offset, offset + limit);

    logger.debug('Retrieved messages', {
      sessionId,
      total: allMessages.length,
      returned: paginatedMessages.length,
      offset,
      limit,
    });

    return paginatedMessages;
  }

  /**
   * Set buffer for a session (for backward compatibility)
   */
  setBuffer(sessionId, buffer) {
    if (!buffer || typeof buffer !== 'object') {
      logger.warn('Invalid buffer provided', { sessionId });
      return false;
    }

    // Store the buffer
    this.storage.addMessageBuffer(sessionId, buffer);

    logger.debug('Buffer set for session', {
      sessionId,
      messageCount: buffer.messages?.length || 0,
    });

    return true;
  }

  /**
   * Clear message buffer for a session
   */
  clearBuffer(sessionId) {
    const buffer = this.storage.getMessageBuffer(sessionId);

    if (buffer) {
      buffer.userMessages = [];
      buffer.assistantMessages = [];
      buffer.thinkingMetadata = {};
      logger.debug('Cleared message buffer', { sessionId });
      return true;
    }

    return false;
  }

  /**
   * Get buffer statistics
   */
  getBufferStats(sessionId) {
    const buffer = this.storage.getMessageBuffer(sessionId);

    if (!buffer) {
      return null;
    }

    return {
      userMessageCount: buffer.userMessages.length,
      assistantMessageCount: buffer.assistantMessages.length,
      totalMessages: buffer.userMessages.length + buffer.assistantMessages.length,
      hasThinkingMetadata:
        !!buffer.thinkingMetadata && Object.keys(buffer.thinkingMetadata).length > 0,
    };
  }

  /**
   * Export session messages
   */
  exportSessionMessages(sessionId) {
    const buffer = this.storage.getMessageBuffer(sessionId);

    if (!buffer) {
      return null;
    }

    return {
      sessionId,
      exportedAt: new Date().toISOString(),
      messages: this.getMessages(sessionId, Number.MAX_SAFE_INTEGER, 0),
      metadata: {
        userMessageCount: buffer.userMessages.length,
        assistantMessageCount: buffer.assistantMessages.length,
        thinkingMetadata: buffer.thinkingMetadata,
      },
    };
  }

  /**
   * Import session messages
   */
  importSessionMessages(sessionId, exportedData) {
    if (!exportedData || !exportedData.messages) {
      logger.error('Invalid import data', { sessionId });
      return false;
    }

    const buffer = this.getBuffer(sessionId);

    // Clear existing messages
    buffer.userMessages = [];
    buffer.assistantMessages = [];

    // Import messages
    for (const message of exportedData.messages) {
      if (message.type === 'user' || message.role === 'user') {
        buffer.userMessages.push({
          role: 'user',
          content: message.content,
          timestamp: message.timestamp,
        });
      } else if (message.type === 'assistant' || message.role === 'assistant') {
        buffer.assistantMessages.push({
          role: 'assistant',
          content: message.content,
          timestamp: message.timestamp,
        });
      }
    }

    // Import metadata if available
    if (exportedData.metadata?.thinkingMetadata) {
      buffer.thinkingMetadata = exportedData.metadata.thinkingMetadata;
    }

    logger.info('Imported session messages', {
      sessionId,
      messageCount: exportedData.messages.length,
    });

    return true;
  }
}

export default MessageBufferManager;
