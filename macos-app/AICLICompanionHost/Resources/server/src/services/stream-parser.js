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
    this.lastStatusMessage = null;
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

          // Process system messages to extract session IDs
          if (parsed.type === 'system') {
            console.log('🔐 Found system message:', parsed);
            if (parsed.session_id) {
              console.log(`🔑 Claude CLI session ID detected: ${parsed.session_id}`);
              // Emit a special chunk for session ID
              chunks.push(
                this.createChunk('session_id', parsed.session_id, {
                  metadata: {
                    system: parsed.system,
                    sessionId: parsed.session_id,
                    isClaudeGenerated: true,
                  },
                })
              );
            }
          }
          // Process tool_use messages for activity updates
          else if (parsed.type === 'tool_use' && parsed.tool_name) {
            console.log('🔧 Found tool use:', parsed.tool_name);
            chunks.push(
              this.createChunk('tool_use', '', {
                metadata: { toolName: parsed.tool_name },
              })
            );
          }
          // Skip result messages - they contain metadata, not assistant responses
          else if (parsed.type === 'result') {
            console.log('📦 Skipping result message (metadata)');
          }
          // Process assistant messages - these contain the actual responses
          else if (parsed.type === 'assistant' && parsed.message) {
            console.log('💬 Found assistant message');
            // Assistant messages contain the actual content to display
            // We don't emit these as chunks since they're handled elsewhere
          }
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

      // Check for Claude CLI status messages
      const statusMatch = this.detectClaudeStatusMessage(trimmedLine);
      if (statusMatch) {
        // If we have accumulated content, emit it first
        if (this.hasAccumulatedContent()) {
          chunks.push(this.createChunk('text', this.getAccumulatedContent()));
        }

        // Emit status chunk
        chunks.push(
          this.createChunk('status', statusMatch.originalText, {
            statusType: statusMatch.type,
            duration: statusMatch.duration,
            tokens: statusMatch.tokens,
            stage: statusMatch.stage,
            canInterrupt: statusMatch.canInterrupt,
          })
        );

        this.lastStatusMessage = statusMatch;
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
   * Detect Claude CLI status messages like "Creating… (1096s · ⚒ 27.7k tokens · esc to interrupt)"
   */
  detectClaudeStatusMessage(line) {
    // Pattern for Claude CLI status messages
    const patterns = [
      // "Creating… (1096s · ⚒ 27.7k tokens · esc to interrupt)"
      {
        regex:
          /(Creating|Thinking|Working|Processing)…?\s*\((\d+(?:\.\d+)?)s\s*·\s*⚒\s*([\d.]+k?)\s*tokens?\s*·\s*esc to interrupt\)/,
        type: 'progress',
        extractData: (match) => ({
          stage: match[1].toLowerCase(),
          duration: parseFloat(match[2]),
          tokens: this.parseTokenCount(match[3]),
          canInterrupt: true,
        }),
      },
      // "Thinking… (45.2s)"
      {
        regex: /(Creating|Thinking|Working|Processing)…?\s*\((\d+(?:\.\d+)?)s\)/,
        type: 'progress',
        extractData: (match) => ({
          stage: match[1].toLowerCase(),
          duration: parseFloat(match[2]),
          tokens: null,
          canInterrupt: false,
        }),
      },
      // "⚒ Using tools: Read, Write, Edit"
      {
        regex: /⚒\s*Using tools?:\s*(.+)/,
        type: 'tools',
        extractData: (match) => ({
          stage: 'tool_use',
          duration: null,
          tokens: null,
          tools: match[1].split(',').map((t) => t.trim()),
          canInterrupt: false,
        }),
      },
      // "✓ Task completed in 45.2s"
      {
        regex: /[✓✅]?\s*(Task completed|Finished|Done)\s*(?:in\s*(\d+(?:\.\d+)?)s)?/,
        type: 'completion',
        extractData: (match) => ({
          stage: 'completed',
          duration: match[2] ? parseFloat(match[2]) : null,
          tokens: null,
          canInterrupt: false,
        }),
      },
      // "⏹ Interrupted by user"
      {
        regex: /[⏹⏸]\s*(Interrupted|Stopped|Cancelled)\s*(?:by user)?/,
        type: 'interruption',
        extractData: (_match) => ({
          stage: 'interrupted',
          duration: null,
          tokens: null,
          canInterrupt: false,
        }),
      },
    ];

    for (const pattern of patterns) {
      const match = line.match(pattern.regex);
      if (match) {
        const data = pattern.extractData(match);
        return {
          type: pattern.type,
          originalText: line,
          stage: data.stage,
          duration: data.duration,
          tokens: data.tokens,
          tools: data.tools,
          canInterrupt: data.canInterrupt,
          timestamp: new Date().toISOString(),
        };
      }
    }

    return null;
  }

  /**
   * Parse token count from strings like "27.7k", "1234", "1.5k"
   */
  parseTokenCount(tokenStr) {
    if (!tokenStr) return null;

    const cleanStr = tokenStr.toLowerCase().replace(/[^\d.k]/g, '');

    if (cleanStr.includes('k')) {
      const num = parseFloat(cleanStr.replace('k', ''));
      return Math.round(num * 1000);
    }

    return parseInt(cleanStr) || null;
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
    this.lastStatusMessage = null;
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

    case 'status':
      // Format status messages for display
      return formatStatusMessage(chunk);

    default:
      return chunk.content;
  }
}

/**
 * Format a status chunk for display
 */
export function formatStatusMessage(chunk) {
  const { statusType, stage, duration, tokens, tools, canInterrupt } = chunk;

  switch (statusType) {
    case 'progress': {
      let message = `${stage.charAt(0).toUpperCase() + stage.slice(1)}`;

      if (duration !== null) {
        message += ` (${duration}s`;

        if (tokens) {
          const tokenStr = tokens >= 1000 ? `${(tokens / 1000).toFixed(1)}k` : tokens.toString();
          message += ` · ⚒ ${tokenStr} tokens`;
        }

        if (canInterrupt) {
          message += ' · esc to interrupt';
        }

        message += ')';
      }

      return message;
    }

    case 'tools':
      return `⚒ Using tools: ${tools ? tools.join(', ') : 'unknown'}`;

    case 'completion': {
      let completionMsg = '✅ Task completed';
      if (duration !== null) {
        completionMsg += ` in ${duration}s`;
      }
      return completionMsg;
    }

    case 'interruption':
      return '⏹ Interrupted by user';

    default:
      return chunk.content;
  }
}
