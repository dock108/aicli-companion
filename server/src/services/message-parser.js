/**
 * Unified message parser for Claude output
 * Combines functionality from claude-output-parser.js and stream-parser.js
 */

export class UnifiedMessageParser {
  constructor() {
    this.buffer = '';
    this.chunkId = 0;
    this.inCodeBlock = false;
    this.codeBlockBuffer = '';
    this.codeBlockLanguage = '';
    this.jsonBuffer = '';
    this.lastStatusMessage = null;
    // Thinking indicator tracking
    this.thinkingStartTime = null;
    this.currentActivity = null;
    this.tokenCount = 0;
  }

  /**
   * Parse any type of Claude output (stream or complete)
   * @param {string} data - Incoming data from Claude
   * @param {boolean} isComplete - Whether this is the final data
   * @returns {Array<Object>} Array of parsed chunks
   */
  parse(data, isComplete = false) {
    // Try to parse as structured JSON first
    const structuredResult = this.parseStructuredOutput(data);
    if (structuredResult) {
      return [structuredResult];
    }

    // Otherwise parse as stream
    return this.parseStreamData(data, isComplete);
  }

  /**
   * Parse stream data and return array of chunks
   * @param {string} data - Incoming data from Claude
   * @param {boolean} isComplete - Whether this is the final data
   * @returns {Array<Object>} Array of parsed chunks
   */
  parseStreamData(data, isComplete = false) {
    this.buffer += data;
    const chunks = [];

    // Check if this is stream-json format (newline-delimited JSON)
    if (this.looksLikeStreamJson(this.buffer)) {
      return this.parseStreamJson(isComplete);
    }

    // Parse as regular text stream
    return this.parseTextStream(isComplete);
  }

  /**
   * Parse stream-json format
   */
  parseStreamJson(isComplete) {
    const chunks = [];
    const lines = this.buffer.split('\n');

    // Keep the last line in buffer if stream is not complete (might be partial)
    if (!isComplete && lines.length > 0) {
      this.buffer = lines.pop();
    } else {
      this.buffer = '';
    }

    // Process each JSON line
    for (const line of lines) {
      const trimmedLine = line.trim();
      if (!trimmedLine) continue;

      try {
        const parsed = JSON.parse(trimmedLine);
        chunks.push(this.processJsonChunk(parsed));
      } catch (e) {
        // Not valid JSON, treat as text
        if (trimmedLine) {
          chunks.push({
            id: this.chunkId++,
            type: 'text',
            content: trimmedLine,
            timestamp: Date.now()
          });
        }
      }
    }

    return chunks;
  }

  /**
   * Parse regular text stream
   */
  parseTextStream(isComplete) {
    const chunks = [];
    
    // Process buffer looking for natural break points
    while (this.buffer.length > 0 || isComplete) {
      const chunk = this.extractNextChunk(isComplete);
      if (chunk) {
        chunks.push(chunk);
      } else {
        break;
      }
    }

    return chunks;
  }

  /**
   * Extract the next meaningful chunk from buffer
   */
  extractNextChunk(isComplete) {
    // Check for code blocks
    const codeBlockMatch = this.buffer.match(/^```(\w*)\n([\s\S]*?)```/);
    if (codeBlockMatch) {
      const [fullMatch, language, code] = codeBlockMatch;
      this.buffer = this.buffer.slice(fullMatch.length);
      return {
        id: this.chunkId++,
        type: 'code',
        language: language || 'plaintext',
        content: code.trim(),
        timestamp: Date.now()
      };
    }

    // Check for progress indicators
    const progressMatch = this.buffer.match(/^(Thinking|Analyzing|Processing|Working on).*?\n/);
    if (progressMatch) {
      const [fullMatch] = progressMatch;
      this.buffer = this.buffer.slice(fullMatch.length);
      return {
        id: this.chunkId++,
        type: 'progress',
        content: fullMatch.trim(),
        timestamp: Date.now()
      };
    }

    // Extract paragraph or sentence
    const breakPoint = this.findNaturalBreakPoint(this.buffer, isComplete);
    if (breakPoint > 0) {
      const content = this.buffer.slice(0, breakPoint).trim();
      this.buffer = this.buffer.slice(breakPoint);
      if (content) {
        return {
          id: this.chunkId++,
          type: 'text',
          content,
          timestamp: Date.now()
        };
      }
    }

    // If complete and buffer has content, flush it
    if (isComplete && this.buffer.trim()) {
      const content = this.buffer.trim();
      this.buffer = '';
      return {
        id: this.chunkId++,
        type: 'text',
        content,
        timestamp: Date.now()
      };
    }

    return null;
  }

  /**
   * Process a JSON chunk
   */
  processJsonChunk(parsed) {
    // Handle different JSON formats
    if (parsed.type === 'system' || parsed.system_message) {
      return {
        id: this.chunkId++,
        type: 'system',
        content: parsed.message || parsed.system_message,
        sessionId: parsed.session_id,
        timestamp: Date.now()
      };
    }

    if (parsed.type === 'progress' || parsed.progress) {
      return {
        id: this.chunkId++,
        type: 'progress',
        content: parsed.message || parsed.progress.message,
        activity: parsed.progress?.activity,
        percentage: parsed.progress?.percentage,
        timestamp: Date.now()
      };
    }

    if (parsed.type === 'thinking' || parsed.thinking) {
      return {
        id: this.chunkId++,
        type: 'thinking',
        content: parsed.content || parsed.thinking,
        duration: parsed.duration,
        timestamp: Date.now()
      };
    }

    if (parsed.result || parsed.content) {
      return {
        id: this.chunkId++,
        type: 'content',
        content: parsed.result || parsed.content,
        sessionId: parsed.session_id,
        timestamp: Date.now()
      };
    }

    // Default handling
    return {
      id: this.chunkId++,
      type: 'data',
      content: JSON.stringify(parsed),
      timestamp: Date.now()
    };
  }

  /**
   * Parse structured output (complete JSON responses)
   * @param {string} text - Raw text that might contain JSON
   * @returns {Object|null} Parsed result
   */
  parseStructuredOutput(text) {
    if (!text || typeof text !== 'string') {
      return null;
    }

    // Try to detect JSON blocks in the text
    const jsonMatches = text.match(/\{[\s\S]*\}/g);
    if (!jsonMatches) {
      return null;
    }

    for (const jsonMatch of jsonMatches) {
      try {
        const parsed = JSON.parse(jsonMatch);

        // Check if this looks like Claude's structured output
        if (this.isClaudeStructuredOutput(parsed)) {
          // Extract the user-facing content
          const content = this.extractUserContent(parsed);
          return {
            id: this.chunkId++,
            type: 'structured',
            content,
            metadata: {
              type: parsed.type || 'unknown',
              hasThinking: !!parsed.thinking,
              hasToolUse: !!(parsed.tool_calls || parsed.tools_used),
            },
            timestamp: Date.now()
          };
        }
      } catch (e) {
        // Not valid JSON, continue
      }
    }

    return null;
  }

  /**
   * Check if the parsed object looks like Claude's structured output
   */
  isClaudeStructuredOutput(parsed) {
    // Check for known Claude response patterns
    return !!(
      parsed.result ||
      parsed.content ||
      parsed.thinking ||
      parsed.tool_calls ||
      parsed.tools_used ||
      (parsed.type && ['text', 'tool_use', 'thinking'].includes(parsed.type))
    );
  }

  /**
   * Extract user-facing content from structured output
   */
  extractUserContent(parsed) {
    // Priority order for content extraction
    if (parsed.result) return parsed.result;
    if (parsed.content) return parsed.content;
    if (parsed.text) return parsed.text;
    if (parsed.message) return parsed.message;
    
    // For tool use, format nicely
    if (parsed.tool_calls || parsed.tools_used) {
      return this.formatToolUse(parsed.tool_calls || parsed.tools_used);
    }

    // Default to stringifying
    return JSON.stringify(parsed, null, 2);
  }

  /**
   * Format tool use for display
   */
  formatToolUse(tools) {
    if (!Array.isArray(tools)) {
      tools = [tools];
    }

    return tools.map(tool => {
      const name = tool.name || tool.tool_name || 'Unknown Tool';
      const params = tool.parameters || tool.inputs || {};
      return `Using ${name}: ${JSON.stringify(params, null, 2)}`;
    }).join('\n\n');
  }

  /**
   * Check if buffer looks like stream-json format
   */
  looksLikeStreamJson(buffer) {
    // Check if first non-empty line is JSON
    const lines = buffer.split('\n');
    for (const line of lines) {
      const trimmed = line.trim();
      if (!trimmed) continue;
      
      try {
        JSON.parse(trimmed);
        return true;
      } catch {
        return false;
      }
    }
    return false;
  }

  /**
   * Find natural break point in text
   */
  findNaturalBreakPoint(text, isComplete) {
    // Look for paragraph breaks
    const doubleNewline = text.indexOf('\n\n');
    if (doubleNewline > 0) return doubleNewline + 2;

    // Look for sentence endings
    const sentenceEnd = text.search(/[.!?]\s+[A-Z]/);
    if (sentenceEnd > 0) return sentenceEnd + 1;

    // If complete, take everything
    if (isComplete) return text.length;

    // Otherwise wait for more data
    return -1;
  }

  /**
   * Reset parser state
   */
  reset() {
    this.buffer = '';
    this.chunkId = 0;
    this.inCodeBlock = false;
    this.codeBlockBuffer = '';
    this.codeBlockLanguage = '';
    this.jsonBuffer = '';
    this.lastStatusMessage = null;
    this.thinkingStartTime = null;
    this.currentActivity = null;
    this.tokenCount = 0;
  }
}

// Export singleton instance for backward compatibility
export const messageParser = new UnifiedMessageParser();

// Export helper functions for backward compatibility
export function parseClaudeOutput(text) {
  const parser = new UnifiedMessageParser();
  const result = parser.parseStructuredOutput(text);
  if (result) {
    return {
      isJson: true,
      content: result.content,
      metadata: result.metadata
    };
  }
  return null;
}

export function parseStreamData(data, isComplete = false) {
  const parser = new UnifiedMessageParser();
  return parser.parseStreamData(data, isComplete);
}