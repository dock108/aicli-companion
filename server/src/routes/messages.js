/**
 * Messages route - for fetching large messages without session ID
 */

import express from 'express';
import {
  sendSuccessResponse,
  sendNotFoundResponse,
} from '../utils/response-utils.js';
const router = express.Router();

// Global message store (messageId -> message content)
// This is a simple in-memory store for now
// In production, you might want to use Redis or a database
const messageStore = new Map();

// Cleanup old messages after 1 hour
const MESSAGE_TTL = 60 * 60 * 1000; // 1 hour in milliseconds

/**
 * Store a message with a unique ID
 * @param {string} messageId - Unique message identifier
 * @param {string} content - Message content
 * @param {object} metadata - Additional metadata
 */
function storeMessage(messageId, content, metadata = {}) {
  messageStore.set(messageId, {
    content,
    metadata,
    timestamp: Date.now(),
  });

  // Schedule cleanup after TTL
  setTimeout(() => {
    messageStore.delete(messageId);
    console.log(`🧹 Cleaned up expired message: ${messageId}`);
  }, MESSAGE_TTL);

  console.log(`💾 Stored message ${messageId} (${content.length} chars)`);
}

/**
 * GET /api/messages/:messageId - Get a message by ID (no session required)
 */
router.get('/:messageId', async (req, res) => {
  const { messageId } = req.params;

  const message = messageStore.get(messageId);

  if (!message) {
    return sendNotFoundResponse(res, 'Message');
  }

  // Return the message content
  sendSuccessResponse(res, {
    id: messageId,
    content: message.content,
    timestamp: message.timestamp,
    metadata: message.metadata,
  });

  console.log(`📤 Delivered message ${messageId} (${message.content.length} chars)`);
});

/**
 * Export the storeMessage function so other modules can use it
 */
export { router, storeMessage };
