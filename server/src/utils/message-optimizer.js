/**
 * Message optimization utilities for improved performance
 */

class MessageOptimizer {
  constructor() {
    // Cache for processed messages
    this.messageCache = new Map();
    this.cacheMaxSize = 1000;
    this.cacheHits = 0;
    this.cacheMisses = 0;
  }

  /**
   * Optimize message for transmission
   * Reduces payload size while preserving essential information
   */
  optimizeMessage(message) {
    // Check cache first
    const cacheKey = this.getCacheKey(message);
    if (this.messageCache.has(cacheKey)) {
      this.cacheHits++;
      return this.messageCache.get(cacheKey);
    }

    this.cacheMisses++;

    // Optimize the message
    const optimized = {
      id: message.id || this.generateId(),
      content: this.compressContent(message.content),
      type: message.type || 'text',
      timestamp: message.timestamp || Date.now(),
      sender: message.sender,
      // Only include metadata if present and non-empty
      ...(message.metadata &&
        Object.keys(message.metadata).length > 0 && {
          metadata: this.optimizeMetadata(message.metadata),
        }),
    };

    // Add to cache
    this.addToCache(cacheKey, optimized);

    return optimized;
  }

  /**
   * Compress message content for faster transmission
   */
  compressContent(content) {
    if (!content || typeof content !== 'string') {
      return content;
    }

    // Remove excessive whitespace
    let compressed = content.replace(/\s+/g, ' ').trim();

    // Truncate very long messages (streaming will handle full content)
    const maxLength = 10000;
    if (compressed.length > maxLength) {
      compressed = `${compressed.substring(0, maxLength)}... [truncated]`;
    }

    return compressed;
  }

  /**
   * Optimize metadata by removing unnecessary fields
   */
  optimizeMetadata(metadata) {
    const optimized = {};

    // Only keep essential metadata
    const essentialFields = ['sessionId', 'requestId', 'projectPath', 'isFinal'];

    for (const field of essentialFields) {
      if (metadata[field] !== undefined && metadata[field] !== null) {
        optimized[field] = metadata[field];
      }
    }

    return optimized;
  }

  /**
   * Batch optimize multiple messages
   */
  optimizeBatch(messages) {
    if (!Array.isArray(messages)) {
      return [];
    }

    // Process in parallel for better performance
    return messages.map((msg) => this.optimizeMessage(msg));
  }

  /**
   * Generate cache key for message
   */
  getCacheKey(message) {
    return `${message.id}-${message.timestamp}-${message.content?.length || 0}`;
  }

  /**
   * Add to cache with size limit
   */
  addToCache(key, value) {
    // Implement LRU cache - remove oldest if at capacity
    if (this.messageCache.size >= this.cacheMaxSize) {
      const firstKey = this.messageCache.keys().next().value;
      this.messageCache.delete(firstKey);
    }

    this.messageCache.set(key, value);
  }

  /**
   * Generate unique ID for messages without one
   */
  generateId() {
    return `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  /**
   * Get cache statistics
   */
  getCacheStats() {
    const total = this.cacheHits + this.cacheMisses;
    return {
      size: this.messageCache.size,
      hits: this.cacheHits,
      misses: this.cacheMisses,
      hitRate: total > 0 ? `${((this.cacheHits / total) * 100).toFixed(2)}%` : '0%',
    };
  }

  /**
   * Clear cache
   */
  clearCache() {
    this.messageCache.clear();
    this.cacheHits = 0;
    this.cacheMisses = 0;
  }

  /**
   * Stream optimizer for real-time messages
   */
  createStreamOptimizer() {
    let buffer = '';
    let chunkCount = 0;
    const maxBufferSize = 1000;
    const _flushInterval = 50; // ms

    return {
      addChunk: (chunk) => {
        buffer += chunk;
        chunkCount++;

        // Auto-flush if buffer is large or enough chunks accumulated
        if (buffer.length > maxBufferSize || chunkCount > 10) {
          const optimized = this.optimizeStreamChunk(buffer);
          buffer = '';
          chunkCount = 0;
          return optimized;
        }

        return null;
      },

      flush: () => {
        if (buffer.length > 0) {
          const optimized = this.optimizeStreamChunk(buffer);
          buffer = '';
          chunkCount = 0;
          return optimized;
        }
        return null;
      },
    };
  }

  /**
   * Optimize stream chunk
   */
  optimizeStreamChunk(chunk) {
    return {
      content: this.compressContent(chunk),
      timestamp: Date.now(),
      type: 'stream',
    };
  }
}

// Create singleton instance
const messageOptimizer = new MessageOptimizer();

// Export
export { MessageOptimizer, messageOptimizer };
