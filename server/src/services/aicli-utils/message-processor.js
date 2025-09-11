/**
 * Message Processing and Parsing Utilities
 * Handles JSON parsing, message classification, and content extraction
 */

import { AICLIMessageHandler } from '../aicli-message-handler.js';

export class MessageProcessor {
  static isValidCompleteJSON(jsonString) {
    if (!jsonString || jsonString.length === 0) {
      console.log(`JSON validation: Empty or null input`);
      return false;
    }

    try {
      // First, try basic JSON parsing
      const parsed = JSON.parse(jsonString);

      // Additional checks for completeness
      const trimmed = jsonString.trim();

      // Check that it starts and ends properly
      if (trimmed.startsWith('[')) {
        if (!trimmed.endsWith(']')) {
          console.log(`JSON validation: Array doesn't end with ]`);
          return false;
        }
      } else if (trimmed.startsWith('{')) {
        if (!trimmed.endsWith('}')) {
          console.log(`JSON validation: Object doesn't end with }`);
          return false;
        }
      } else {
        console.log(`JSON validation: Doesn't start with [ or {`);
        return false;
      }

      // Check for common truncation indicators
      if (!trimmed.endsWith('}') && !trimmed.endsWith(']')) {
        console.log(`JSON validation: Doesn't end with } or ]`);
        return false;
      }

      // Simplified truncation detection
      if (
        trimmed.endsWith(',') ||
        trimmed.endsWith(':') ||
        (trimmed.endsWith('"') && !trimmed.endsWith('"}') && !trimmed.endsWith('"]'))
      ) {
        console.log(`JSON validation: Ends with incomplete syntax`);
        return false;
      }

      // For arrays, check if the parsed result looks complete
      if (Array.isArray(parsed)) {
        // Basic validation - if we got here, JSON.parse succeeded
        return true;
      }

      // For objects, check basic structure
      if (typeof parsed === 'object' && parsed !== null) {
        return true;
      }

      console.log(`JSON validation: Parsed value is not object or array`);
      return false;
    } catch (error) {
      console.log(`JSON validation: Parse error - ${error.message}`);
      return false;
    }
  }

  static parseStreamJsonOutput(output) {
    if (!output || typeof output !== 'string') {
      return [];
    }

    const results = [];
    const lines = output.split('\n');

    for (const line of lines) {
      const trimmedLine = line.trim();
      if (trimmedLine.length === 0) continue;

      // Try to extract complete JSON objects from this line
      const objects = this.extractCompleteObjectsFromLine(trimmedLine);
      results.push(...objects);
    }

    return results;
  }

  static extractCompleteObjectsFromLine(line) {
    if (!line || typeof line !== 'string') {
      return [];
    }

    const objects = [];
    let currentPos = 0;

    while (currentPos < line.length) {
      // Find the start of the next JSON object or array
      const objectStart = line.indexOf('{', currentPos);
      const arrayStart = line.indexOf('[', currentPos);

      let nextStart = -1;
      if (objectStart !== -1 && arrayStart !== -1) {
        nextStart = Math.min(objectStart, arrayStart);
      } else if (objectStart !== -1) {
        nextStart = objectStart;
      } else if (arrayStart !== -1) {
        nextStart = arrayStart;
      }

      if (nextStart === -1) break;

      // Try to find the complete JSON from this position
      const remaining = line.substring(nextStart);
      let depth = 0;
      let inString = false;
      let escaped = false;

      for (let i = 0; i < remaining.length; i++) {
        const char = remaining[i];

        if (escaped) {
          escaped = false;
          continue;
        }

        if (char === '\\' && inString) {
          escaped = true;
          continue;
        }

        if (char === '"') {
          inString = !inString;
          continue;
        }

        if (!inString) {
          if (char === '{' || char === '[') {
            depth++;
          } else if (char === '}' || char === ']') {
            depth--;
            if (depth === 0) {
              // Found complete JSON
              const jsonStr = remaining.substring(0, i + 1);
              if (this.isValidCompleteJSON(jsonStr)) {
                try {
                  const parsed = JSON.parse(jsonStr);
                  objects.push(parsed);
                } catch (error) {
                  // Continue searching
                }
              }
              currentPos = nextStart + i + 1;
              break;
            }
          }
        }
      }

      if (depth > 0) {
        // Incomplete JSON, move to next potential start
        currentPos = nextStart + 1;
      }
    }

    return objects;
  }

  static extractLastCompleteJSON(truncatedJSON) {
    if (!truncatedJSON || typeof truncatedJSON !== 'string') {
      return null;
    }

    // Find the last complete JSON object/array in the string
    const lastBraceIndex = this.findLastCompleteJSONStart(truncatedJSON);
    if (lastBraceIndex === -1) {
      return null;
    }

    const candidate = truncatedJSON.substring(lastBraceIndex);
    if (this.isValidCompleteJSON(candidate)) {
      try {
        return JSON.parse(candidate);
      } catch (error) {
        return null;
      }
    }

    return null;
  }

  static findLastCompleteJSONStart(text) {
    if (!text || typeof text !== 'string') {
      return -1;
    }

    // Search backwards for the last '{' or '['
    for (let i = text.length - 1; i >= 0; i--) {
      if (text[i] === '{' || text[i] === '[') {
        return i;
      }
    }

    return -1;
  }

  static extractCompleteObjectsFromArray(arrayText) {
    if (!arrayText || typeof arrayText !== 'string') {
      return [];
    }

    try {
      // Remove outer array brackets and split by objects
      const content = arrayText.trim();
      if (!content.startsWith('[') || !content.endsWith(']')) {
        return [];
      }

      const inner = content.slice(1, -1).trim();
      if (inner.length === 0) {
        return [];
      }

      // Try to parse as complete array first
      if (this.isValidCompleteJSON(content)) {
        const parsed = JSON.parse(content);
        return Array.isArray(parsed) ? parsed : [];
      }

      // If that fails, try to extract individual objects
      const objects = [];
      let depth = 0;
      let start = 0;
      let inString = false;
      let escaped = false;

      for (let i = 0; i < inner.length; i++) {
        const char = inner[i];

        if (escaped) {
          escaped = false;
          continue;
        }

        if (char === '\\' && inString) {
          escaped = true;
          continue;
        }

        if (char === '"') {
          inString = !inString;
          continue;
        }

        if (!inString) {
          if (char === '{') {
            if (depth === 0) start = i;
            depth++;
          } else if (char === '}') {
            depth--;
            if (depth === 0) {
              const objStr = inner.substring(start, i + 1);
              if (this.isValidCompleteJSON(objStr)) {
                try {
                  const parsed = JSON.parse(objStr);
                  objects.push(parsed);
                } catch (error) {
                  // Continue
                }
              }
            }
          }
        }
      }

      return objects;
    } catch (error) {
      return [];
    }
  }

  static classifyAICLIMessage(message) {
    if (typeof message === 'string' || message === null || message === undefined) {
      return {
        eventType: 'streamData',
        data: message,
      };
    }

    if (typeof message !== 'object') {
      return {
        eventType: 'streamData',
        data: message,
      };
    }

    // Handle system messages
    if (message.type === 'system') {
      return this.handleSystemMessage(message);
    }

    // Handle assistant messages
    if (message.type === 'assistant') {
      return this.handleAssistantMessage(message);
    }

    // Handle tool use
    if (message.type === 'tool_use') {
      return this.handleToolUseMessage(message);
    }

    // Handle tool results
    if (message.type === 'tool_result') {
      return this.handleToolResultMessage(message);
    }

    // Handle final results
    if (message.type === 'result') {
      return this.handleResultMessage(message);
    }

    // Default: treat as stream data
    return {
      eventType: 'streamData',
      data: message,
    };
  }

  static handleSystemMessage(message) {
    // Handle system init messages specially
    if (message.subtype === 'init') {
      return {
        eventType: 'systemInit',
        data: {
          type: 'system_init',
          sessionId: message.session_id,
          workingDirectory: message.cwd,
          availableTools: message.tools || [],
          mcpServers: message.mcp_servers || [],
          model: message.model,
          timestamp: new Date().toISOString(),
        },
      };
    }

    // Regular system message
    return {
      eventType: 'streamData',
      data: {
        type: 'system',
        content: message.content || message.result || message.text,
        timestamp: new Date().toISOString(),
      },
    };
  }

  static handleAssistantMessage(message) {
    // Handle structured message with array content
    if (message.message && Array.isArray(message.message.content)) {
      return {
        eventType: 'assistantMessage',
        data: {
          type: 'assistant_response',
          messageId: message.message.id,
          content: message.message.content,
          model: message.message.model,
          usage: message.message.usage,
          timestamp: new Date().toISOString(),
        },
      };
    }

    // Default assistant message handling
    return {
      eventType: 'streamData',
      data: {
        type: 'assistant',
        content: message.content || message.message?.content || message.text,
        timestamp: new Date().toISOString(),
      },
    };
  }

  static handleResultMessage(message) {
    return {
      eventType: 'conversationResult',
      data: {
        type: 'final_result',
        success: !message.is_error,
        result: message.result,
        sessionId: message.session_id,
        duration: message.duration_ms,
        cost: message.total_cost_usd,
        usage: message.usage,
        timestamp: new Date().toISOString(),
      },
    };
  }

  static handleToolUseMessage(message) {
    return {
      eventType: 'toolUse',
      data: {
        type: 'tool_use',
        toolName: message.tool_name,
        toolInput: message.tool_input,
        toolId: message.tool_id,
        timestamp: new Date().toISOString(),
      },
    };
  }

  static handleToolResultMessage(message) {
    return {
      eventType: 'toolResult',
      data: {
        type: 'tool_result',
        toolName: message.tool_name,
        toolId: message.tool_id,
        result: message.result || message.error,
        success: !message.is_error,
        error: message.is_error ? message.error : undefined,
        timestamp: new Date().toISOString(),
      },
    };
  }

  static isPermissionPrompt(message) {
    if (typeof message === 'string') {
      return this.containsPermissionPatterns(message);
    }

    if (!message || typeof message !== 'object') {
      return false;
    }

    const text = this.extractTextFromMessage(message);
    return text ? this.containsPermissionPatterns(text) : false;
  }

  static containsPermissionPatterns(text) {
    if (!text || typeof text !== 'string') {
      return false;
    }

    const permissionPatterns = [
      /\(y\/n\)/i,
      /\[y\/n\]/i,
      /\(Y\/n\)/i,
      /\[Y\/n\]/i,
      /allow/i,
      /continue\?/i,
      /proceed\?/i,
    ];

    return permissionPatterns.some((pattern) => pattern.test(text));
  }

  static extractPermissionPromptFromMessage(message) {
    const text = this.extractTextFromMessage(message);
    if (!text) return 'Permission required';

    // Clean up the prompt text
    return text.replace(/\s*\([yn]\/[yn]\)\s*$/i, '').trim();
  }

  static extractTextFromMessage(message) {
    if (typeof message === 'string') return message;

    if (!message || typeof message !== 'object') return null;

    if (message.result) return message.result;
    if (message.text) return message.text;

    // Handle structured content
    if (message.message && message.message.content) {
      if (typeof message.message.content === 'string') {
        return message.message.content;
      }

      if (Array.isArray(message.message.content)) {
        // Find first text block
        for (const block of message.message.content) {
          if (block.type === 'text' && block.text) {
            return block.text;
          }
        }
      }
    }

    return null;
  }

  static containsApprovalResponse(text) {
    // Delegate to AICLIMessageHandler for consistent behavior
    return AICLIMessageHandler.containsApprovalResponse(text);
  }

  static extractPermissionPrompt(resultText) {
    // Delegate to AICLIMessageHandler for consistent behavior
    return AICLIMessageHandler.extractPermissionPrompt(resultText);
  }

  static containsPermissionRequest(content) {
    // Delegate to AICLIMessageHandler for consistent behavior
    return AICLIMessageHandler.containsPermissionRequest(content);
  }

  static containsToolUse(content) {
    // Delegate to AICLIMessageHandler for consistent behavior
    return AICLIMessageHandler.containsToolUse(content);
  }

  static extractCodeBlocks(content) {
    // Delegate to AICLIMessageHandler for consistent behavior
    return AICLIMessageHandler.extractCodeBlocks(content);
  }

  static aggregateBufferedContent(buffer) {
    if (!buffer || !buffer.assistantMessages) {
      return [];
    }

    const aggregated = [];

    for (const msg of buffer.assistantMessages) {
      if (msg.content && Array.isArray(msg.content)) {
        aggregated.push(...msg.content);
      }
    }

    return aggregated;
  }
}
