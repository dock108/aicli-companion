/**
 * Message Formatter for Push Notifications
 * Handles text processing, markdown stripping, and message truncation
 */

export class MessageFormatter {
  constructor() {
    this.MESSAGE_FETCH_THRESHOLD = 1500;
  }

  /**
   * Strip markdown formatting from text for cleaner notification display
   */
  stripMarkdown(text) {
    if (!text) return '';

    let cleanText = text;

    // Remove code blocks first (both backtick and indented)
    cleanText = cleanText.replace(/```[\s\S]*?```/g, '[code block]');
    cleanText = cleanText.replace(/`([^`]+)`/g, '$1');

    // Remove images
    cleanText = cleanText.replace(/!\[([^\]]*)\]\([^)]+\)/g, '[image: $1]');

    // Remove links but keep text
    cleanText = cleanText.replace(/\[([^\]]+)\]\([^)]+\)/g, '$1');

    // Remove headers
    cleanText = cleanText.replace(/^#{1,6}\s+(.+)$/gm, '$1');

    // Remove bold/italic markers
    cleanText = cleanText.replace(/(\*\*|__)(.*?)\1/g, '$2');
    cleanText = cleanText.replace(/(\*|_)(.*?)\1/g, '$2');

    // Remove blockquotes
    cleanText = cleanText.replace(/^>\s+(.+)$/gm, '$1');

    // Remove horizontal rules
    cleanText = cleanText.replace(/^[-*_]{3,}$/gm, '');

    // Remove list markers
    cleanText = cleanText.replace(/^[\s]*[-*+]\s+(.+)$/gm, '$1');
    cleanText = cleanText.replace(/^[\s]*\d+\.\s+(.+)$/gm, '$1');

    // Clean up extra whitespace
    cleanText = cleanText.replace(/\n{3,}/g, '\n\n');
    cleanText = cleanText.trim();

    return cleanText;
  }

  /**
   * Truncate a message for notification display
   */
  truncateMessage(message, maxLength = 150) {
    if (!message) return '';

    // First strip markdown formatting
    const cleanMessage = this.stripMarkdown(message);

    if (cleanMessage.length <= maxLength) {
      return cleanMessage;
    }

    // Try to truncate at a word boundary
    const truncated = cleanMessage.substring(0, maxLength);
    const lastSpace = truncated.lastIndexOf(' ');

    if (lastSpace > maxLength * 0.8) {
      return `${truncated.substring(0, lastSpace)}...`;
    }

    return `${truncated}...`;
  }

  /**
   * Format attachment text for notifications
   */
  formatAttachmentText(attachmentInfo) {
    if (!attachmentInfo || attachmentInfo.length === 0) {
      return '';
    }

    const count = attachmentInfo.length;
    return ` (${count} attachment${count > 1 ? 's' : ''})`;
  }

  /**
   * Format thinking metadata for title prefix
   */
  formatThinkingPrefix(thinkingMetadata) {
    if (!thinkingMetadata || !thinkingMetadata.isThinking) {
      return '';
    }

    const activity = thinkingMetadata.activity || 'Thinking';
    const duration = thinkingMetadata.duration || 0;
    return `${activity}... (${duration}s) `;
  }

  /**
   * Format token count for display
   */
  formatTokenText(tokenCount) {
    if (!tokenCount) return '';

    return tokenCount > 1000 ? `${(tokenCount / 1000).toFixed(1)}k tokens` : `${tokenCount} tokens`;
  }

  /**
   * Determine if message requires fetch-based delivery
   */
  requiresFetch(message) {
    return message && message.length > this.MESSAGE_FETCH_THRESHOLD;
  }

  /**
   * Create preview text for large messages
   */
  createPreview(message, maxLength = 100) {
    return this.truncateMessage(message, maxLength);
  }
}
