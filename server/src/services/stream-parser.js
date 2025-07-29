/**
 * Stream parser for Claude output
 * Intelligently chunks Claude's responses into meaningful message segments
 */

export class ClaudeStreamParser {
  constructor() {
    this.buffer = '';
    this.chunkId = 0;
    this.inCodeBlock = false;
    this.codeBlockBuffer = '';
    this.codeBlockLanguage = '';
    this.jsonBuffer = '';
  }

  /**
   * Parse incoming data and return array of chunks
   * @param {string} data - Incoming data from Claude
   * @param {boolean} isComplete - Whether this is the final data
   * @returns {Array<Object>} Array of parsed chunks
   */
  parseData(data, isComplete = false) {
    this.buffer += data;
    const chunks = [];

    // Check if this is stream-json format (newline-delimited JSON)
    if (this.looksLikeStreamJson(this.buffer)) {
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

          // Only process result messages
          if (parsed.type === 'result' && parsed.result) {
            console.log('📦 Found result in stream-json, extracting text content');
            chunks.push(
              this.createChunk('text', parsed.result, {
                isFinal: isComplete,
              })
            );
          }
          // Skip all other message types (system, assistant, tool_use, etc.)
        } catch (e) {
          // Not valid JSON, skip this line
          console.log('⚠️ Failed to parse JSON line:', trimmedLine.substring(0, 100));
        }
      }

      // If we found result chunks, return them
      if (chunks.length > 0) {
        if (isComplete && chunks.length > 0) {
          chunks[chunks.length - 1].isFinal = true;
        }
        return chunks;
      }
    }

    // If no JSON detected, process normally line by line
    const lines = this.buffer.split('\n');

    // Keep the last line in buffer if stream is not complete (might be partial)
    if (!isComplete && lines.length > 0) {
      this.buffer = lines.pop();
    } else {
      this.buffer = '';
    }

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      const trimmedLine = line.trim();

      // Handle code blocks
      if (trimmedLine.startsWith('```')) {
        if (!this.inCodeBlock) {
          // Starting a code block
          this.inCodeBlock = true;
          this.codeBlockLanguage = trimmedLine.slice(3).trim() || 'text';
          this.codeBlockBuffer = '';

          // If we have accumulated content, emit it first
          if (this.hasAccumulatedContent()) {
            chunks.push(this.createChunk('text', this.getAccumulatedContent()));
          }
        } else {
          // Ending a code block
          this.inCodeBlock = false;
          chunks.push(
            this.createChunk('code', this.codeBlockBuffer.trim(), {
              language: this.codeBlockLanguage,
            })
          );
          this.codeBlockBuffer = '';
          this.codeBlockLanguage = '';
        }
        continue;
      }

      // If in code block, accumulate
      if (this.inCodeBlock) {
        this.codeBlockBuffer += `${line}\n`;
        continue;
      }

      // Check for section headers
      const sectionMatch = this.detectSectionHeader(trimmedLine);
      if (sectionMatch) {
        // Emit any accumulated content first
        if (this.hasAccumulatedContent()) {
          chunks.push(this.createChunk('text', this.getAccumulatedContent()));
        }

        // Emit section header
        chunks.push(
          this.createChunk('section', sectionMatch.title, {
            level: sectionMatch.level,
          })
        );
        continue;
      }

      // Check for markdown headers
      if (trimmedLine.startsWith('#')) {
        const headerMatch = trimmedLine.match(/^(#+)\s+(.+)$/);
        if (headerMatch) {
          // Emit accumulated content
          if (this.hasAccumulatedContent()) {
            chunks.push(this.createChunk('text', this.getAccumulatedContent()));
          }

          chunks.push(
            this.createChunk('header', headerMatch[2], {
              level: headerMatch[1].length,
            })
          );
          continue;
        }
      }

      // Check for list items
      const listMatch = trimmedLine.match(/^(\d+\.|[-*+])\s+(.+)$/);
      if (listMatch) {
        // For lists, we'll accumulate them together
        this.accumulateContent(line);

        // Check if next line is not a list item, then emit
        if (i + 1 >= lines.length || !this.isListItem(lines[i + 1])) {
          chunks.push(this.createChunk('list', this.getAccumulatedContent()));
        }
        continue;
      }

      // Check for horizontal rules
      if (trimmedLine.match(/^[-*_]{3,}$/)) {
        if (this.hasAccumulatedContent()) {
          chunks.push(this.createChunk('text', this.getAccumulatedContent()));
        }
        chunks.push(this.createChunk('divider', ''));
        continue;
      }

      // Skip "init" messages (chain-of-thought indicators)
      if (trimmedLine.toLowerCase() === 'init') {
        continue;
      }

      // Regular content - accumulate
      if (trimmedLine.length > 0) {
        this.accumulateContent(line);
      } else if (this.hasAccumulatedContent()) {
        // Empty line - emit accumulated content as a paragraph
        chunks.push(this.createChunk('text', this.getAccumulatedContent()));
      }
    }

    // Handle final chunk
    if (isComplete) {
      // Emit any remaining content
      if (this.inCodeBlock && this.codeBlockBuffer) {
        chunks.push(
          this.createChunk('code', this.codeBlockBuffer.trim(), {
            language: this.codeBlockLanguage,
          })
        );
      } else if (this.hasAccumulatedContent()) {
        chunks.push(this.createChunk('text', this.getAccumulatedContent()));
      }

      // Mark the last chunk as final
      if (chunks.length > 0) {
        chunks[chunks.length - 1].isFinal = true;
      } else {
        // If no chunks but stream is complete, send a final empty chunk
        chunks.push(this.createChunk('complete', '', { isFinal: true }));
      }

      // Reset parser state
      this.reset();
    }

    return chunks;
  }

  /**
   * Detect section headers like "Plan:", "Code:", etc.
   */
  detectSectionHeader(line) {
    const patterns = [
      { regex: /^(Plan|Planning):?\s*$/i, title: 'Plan', level: 1 },
      { regex: /^(Code|Implementation):?\s*$/i, title: 'Code', level: 1 },
      { regex: /^(Summary|Conclusion):?\s*$/i, title: 'Summary', level: 1 },
      { regex: /^(Error|Errors):?\s*$/i, title: 'Error', level: 1 },
      { regex: /^(Warning|Warnings):?\s*$/i, title: 'Warning', level: 1 },
      { regex: /^(Note|Notes):?\s*$/i, title: 'Note', level: 2 },
      { regex: /^(TODO|TODOs):?\s*$/i, title: 'TODO', level: 2 },
      { regex: /^(Result|Results):?\s*$/i, title: 'Result', level: 1 },
    ];

    for (const pattern of patterns) {
      if (pattern.regex.test(line)) {
        return { title: line.replace(/:\s*$/, ''), level: pattern.level };
      }
    }

    return null;
  }

  /**
   * Check if a line is a list item
   */
  isListItem(line) {
    const trimmed = line.trim();
    return /^(\d+\.|[-*+])\s+/.test(trimmed);
  }

  /**
   * Create a chunk object
   */
  createChunk(type, content, metadata = {}) {
    return {
      id: `chunk-${this.chunkId++}`,
      type,
      content,
      timestamp: new Date().toISOString(),
      isFinal: false,
      ...metadata,
    };
  }

  /**
   * Temporary content accumulator
   */
  accumulatedContent = [];

  accumulateContent(line) {
    this.accumulatedContent.push(line);
  }

  hasAccumulatedContent() {
    return this.accumulatedContent.length > 0;
  }

  getAccumulatedContent() {
    const content = this.accumulatedContent.join('\n').trim();
    this.accumulatedContent = [];
    return content;
  }

  /**
   * Check if the buffer looks like stream-json format
   */
  looksLikeStreamJson(buffer) {
    if (!buffer || buffer.length < 10) return false;

    // Check if first non-empty line starts with { and contains "type":
    const firstLine = buffer.split('\n').find((line) => line.trim());
    if (!firstLine) return false;

    const trimmed = firstLine.trim();
    return trimmed.startsWith('{') && trimmed.includes('"type":');
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
    this.accumulatedContent = [];
    this.jsonBuffer = '';
  }
}

/**
 * Format a chunk for display
 */
export function formatChunkForDisplay(chunk) {
  switch (chunk.type) {
    case 'section':
      // Remove trailing colon if present
      return chunk.content.replace(/:$/, '');

    case 'header':
      return chunk.content;

    case 'code':
      return chunk.content;

    case 'list':
    case 'text':
      return chunk.content;

    case 'divider':
      return '---';

    case 'complete':
      return '';

    default:
      return chunk.content;
  }
}
