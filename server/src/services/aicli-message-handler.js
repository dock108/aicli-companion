// Pure business logic for AICLI message processing and content analysis
// Extracted from aicli.js to improve testability

import { randomUUID } from 'crypto';

export class AICLIMessageHandler {
  /**
   * Generate a unique message ID
   */
  static generateMessageId() {
    return randomUUID();
  }

  /**
   * Process different types of AICLI CLI responses
   * Pure function - no side effects, only returns processing results
   */
  static processResponse(response, buffer, options = {}) {
    try {
      if (!buffer) {
        return {
          action: 'error',
          reason: 'No message buffer provided',
          error: new Error('Message buffer is required for processing'),
        };
      }

      if (!response) {
        return {
          action: 'error',
          reason: 'No response to process',
          error: new Error('Response object is required'),
        };
      }

      // Validate response structure
      if (typeof response !== 'object') {
        return {
          action: 'error',
          reason: 'Invalid response format',
          error: new Error(`Response must be an object, got ${typeof response}`),
        };
      }

      // Process different types of AICLI CLI responses
      switch (response.type) {
        case 'system':
          return this.processSystemResponse(response, buffer);

        case 'assistant':
          return this.processAssistantResponse(response, buffer);

        case 'user':
          // User messages are tool results - don't send to iOS
          return { action: 'buffer', reason: 'User/tool result message' };

        case 'result':
          return this.processFinalResult(response, buffer, options);

        default:
          console.warn(`Unknown response type: ${response.type}`, { response });
          return { action: 'skip', reason: `Unknown message type: ${response.type}` };
      }
    } catch (error) {
      console.error('Error processing response:', error);
      return {
        action: 'error',
        reason: `Processing failed: ${error.message}`,
        error,
      };
    }
  }

  /**
   * Process system response messages
   */
  static processSystemResponse(response, buffer) {
    // Extract Claude's session ID if present
    if (response.session_id) {
      console.log(`🔑 Extracted Claude CLI session ID: ${response.session_id}`);
      buffer.claudeSessionId = response.session_id;
    }

    if (response.subtype === 'init') {
      // Store system init but don't send to iOS immediately
      buffer.systemInit = response;
      return { action: 'buffer', reason: 'System init message buffered' };
    }

    return { action: 'skip', reason: 'Non-init system message' };
  }

  /**
   * Process assistant response messages
   */
  static processAssistantResponse(response, buffer) {
    try {
      if (!response.message || !response.message.content) {
        return { action: 'skip', reason: 'Assistant message has no content' };
      }

      // Validate content is an array
      if (!Array.isArray(response.message.content)) {
        console.warn('Assistant message content is not an array:', typeof response.message.content);
        // Try to convert to array format
        if (typeof response.message.content === 'string') {
          response.message.content = [{ type: 'text', text: response.message.content }];
        } else {
          return {
            action: 'error',
            reason: 'Invalid assistant message content format',
            error: new Error('Assistant message content must be an array'),
          };
        }
      }

      // Check if this contains permission requests or immediate action items
      const hasPermissionRequest = this.containsPermissionRequest(response.message.content);
      const hasToolUse = this.containsToolUse(response.message.content);
      const codeBlocks = this.extractCodeBlocks(response.message.content);

      if (hasPermissionRequest) {
        // Permission requests should be sent immediately
        buffer.permissionRequestSent = true;

        // Extract the permission prompt text safely
        const textContent = response.message.content
          .filter((c) => c && typeof c === 'object')
          .map((c) => c.text || '')
          .join(' ');

        const permissionPrompt = this.extractPermissionPrompt(textContent);

        return {
          action: 'permission_request',
          data: {
            sessionId: response.session_id,
            prompt: permissionPrompt,
            options: ['y', 'n'],
            default: 'n',
            messageId: response.message.id,
            content: response.message.content,
            model: response.message.model,
            usage: response.message.usage,
          },
        };
      }

      // Add to buffer for aggregation
      buffer.assistantMessages.push(response.message);

      if (codeBlocks.length > 0) {
        buffer.deliverables = buffer.deliverables || [];
        buffer.deliverables.push(...codeBlocks);
      }

      if (hasToolUse) {
        buffer.toolUseInProgress = true;
        return {
          action: 'tool_use',
          data: {
            messageId: response.message.id,
            content: response.message.content,
            model: response.message.model,
            usage: response.message.usage,
          },
        };
      }

      return { action: 'buffer', reason: 'Assistant message buffered for aggregation' };
    } catch (error) {
      console.error('Error processing assistant response:', error);
      return {
        action: 'error',
        reason: `Failed to process assistant response: ${error.message}`,
        error,
      };
    }
  }

  /**
   * Process final result messages
   */
  static processFinalResult(response, buffer, options = {}) {
    const result = {
      action: 'final_result',
      data: {
        response,
        buffer,
        aggregatedContent: null,
        sendAggregated: false,
      },
    };

    if (options.isLongRunningCompletion) {
      // For long-running commands, aggregate all buffered content
      result.data.aggregatedContent = this.aggregateBufferedContent(buffer);
      result.data.sendAggregated = true;
    }

    if (buffer.permissionRequestSent) {
      // If we sent a permission request, check if the result contains an embedded permission
      const hasEmbeddedPermission = this.containsPermissionRequest([
        {
          type: 'text',
          text: response.result || '',
        },
      ]);

      if (hasEmbeddedPermission) {
        const permissionPrompt = this.extractPermissionPrompt(response.result);
        result.data.embeddedPermission = {
          prompt: permissionPrompt,
          options: ['y', 'n'],
          default: 'n',
        };
      }
    }

    return result;
  }

  /**
   * Generate aggregated response data
   */
  static generateAggregatedResponse(response, buffer) {
    const aggregatedContent = this.aggregateBufferedContent(buffer);

    // Use Claude's session ID if available, otherwise fall back to response session_id
    const sessionId = buffer.claudeSessionId || response.session_id;

    return {
      assistantMessage: {
        type: 'assistant_response',
        content: aggregatedContent,
        deliverables: buffer.deliverables || [],
        aggregated: true,
        messageCount: buffer.assistantMessages.length,
        timestamp: new Date().toISOString(),
        claudeSessionId: sessionId,
      },
      conversationResult: {
        type: 'final_result',
        success: !response.is_error,
        sessionId,
        claudeSessionId: sessionId,
        duration: response.duration_ms,
        cost: response.total_cost_usd,
        usage: response.usage,
        timestamp: new Date().toISOString(),
      },
    };
  }

  /**
   * Extract permission prompt from text
   */
  static extractPermissionPrompt(resultText) {
    if (!resultText) return null;

    // Look for the specific permission question in the text
    const lines = resultText.split('\n');

    // Find lines that contain permission-related questions
    const permissionLines = lines.filter((line) => {
      const lowerLine = line.toLowerCase();
      return (
        lowerLine.includes('would you like') ||
        lowerLine.includes('should i') ||
        lowerLine.includes('need permission') ||
        lowerLine.includes('need write') ||
        lowerLine.includes('proceed') ||
        line.endsWith('?')
      );
    });

    if (permissionLines.length > 0) {
      return permissionLines.join(' ').trim();
    }

    // Fallback - return last paragraph if it seems like a question
    const lastParagraph = resultText.split('\n\n').pop();
    if (lastParagraph && lastParagraph.includes('?')) {
      return lastParagraph.trim();
    }

    return 'Permission required to proceed';
  }

  /**
   * Check if content contains permission requests
   */
  static containsPermissionRequest(content) {
    if (!Array.isArray(content)) return false;

    return content.some((block) => {
      if (block.type === 'text' && block.text) {
        const text = block.text.toLowerCase();

        // Traditional permission patterns
        if (
          text.includes('permission') ||
          text.includes('approve') ||
          text.includes('(y/n)') ||
          text.includes('[y/n]') ||
          text.includes('confirm')
        ) {
          return true;
        }

        // Conversational permission patterns - must include action words
        const conversationalPatterns = [
          'would you like me to proceed',
          'should i proceed',
          'should i continue',
          'would you like me to continue',
          'shall i proceed',
          'shall i continue',
          'may i proceed',
          'may i continue',
          'do you want me to proceed',
          'do you want me to continue',
          'would you like me to go ahead',
          'should i go ahead',
          'can i proceed',
          'can i continue',
          'want me to proceed',
          'want me to continue',
          'would you like me to make',
          'would you like me to create',
          'would you like me to implement',
          'would you like me to write',
          'would you like me to modify',
          'would you like me to update',
          'would you like me to fix',
          'would you like me to start',
        ];

        const hasConversationalPattern = conversationalPatterns.some((pattern) =>
          text.includes(pattern)
        );

        if (hasConversationalPattern) {
          return true;
        }

        // Question patterns that indicate permission - must have action context
        const permissionActionWords = [
          'proceed',
          'continue',
          'start',
          'begin',
          'implement',
          'create',
          'make',
          'write',
          'modify',
          'update',
          'fix',
          'change',
          'delete',
          'remove',
          'add',
          'install',
          'run',
          'execute',
          'perform',
          'apply',
        ];

        // Check if question patterns are followed by action words
        const questionPatterns = [
          /should\s+i\s+(\w+)/,
          /would\s+you\s+like\s+me\s+to\s+(\w+)/,
          /do\s+you\s+want\s+me\s+to\s+(\w+)/,
          /may\s+i\s+(\w+)/,
          /can\s+i\s+(\w+)/,
          /shall\s+i\s+(\w+)/,
        ];

        let hasPermissionQuestion = false;
        for (const pattern of questionPatterns) {
          const match = text.match(pattern);
          if (match && match[1]) {
            // Check if the captured word is an action word
            const actionWord = match[1].toLowerCase();
            if (permissionActionWords.some((word) => actionWord.startsWith(word))) {
              hasPermissionQuestion = true;
              break;
            }
          }
        }

        if (hasPermissionQuestion) {
          return true;
        }

        // Exclude general questions that are just asking for user input
        const exclusionPatterns = [
          /what would you like me to help/,
          /what can i help you with/,
          /how can i assist you/,
          /what do you need help with/,
          /what would you like to/,
          /what brings you here/,
        ];

        // If it matches an exclusion pattern, it's not a permission request
        if (exclusionPatterns.some((pattern) => pattern.test(text))) {
          return false;
        }
      }

      return false;
    });
  }

  /**
   * Check if content contains tool use
   */
  static containsToolUse(content) {
    if (!Array.isArray(content)) return false;
    return content.some((block) => block.type === 'tool_use');
  }

  /**
   * Check if text contains approval response
   */
  static containsApprovalResponse(text) {
    if (!text || typeof text !== 'string') return false;

    const normalizedText = text.toLowerCase().trim();

    // Direct approval phrases
    const directApprovals = [
      'yes',
      'y',
      'yep',
      'yeah',
      'yup',
      'approved',
      'approve',
      'approval',
      'ok',
      'okay',
      'k',
      'sure',
      'fine',
      'good',
      'proceed',
      'continue',
      'go ahead',
      'go for it',
      'do it',
      'execute',
      'run it',
      'confirm',
      'confirmed',
      'accept',
      'accepted',
      'allow',
      'allowed',
    ];

    const hasDirectApproval = directApprovals.includes(normalizedText);

    if (hasDirectApproval) {
      console.log(`✅ Detected approval response: "${text}"`);
      return true;
    }

    // Phrase-based approvals
    const phraseApprovals = [
      'yes please',
      'yes, please',
      'go for it',
      'sounds good',
      'looks good',
      'that works',
      "that's fine",
      'that is fine',
      'go ahead',
      'please proceed',
      'please continue',
      'make the changes',
      'apply the changes',
      'yes, do it',
      'yes do it',
    ];

    const hasPhraseApproval = phraseApprovals.some((phrase) => normalizedText.includes(phrase));

    if (hasPhraseApproval) {
      console.log(`✅ Detected phrase-based approval: "${text}"`);
      return true;
    }

    return false;
  }

  /**
   * Extract code blocks from content
   */
  static extractCodeBlocks(content) {
    if (!Array.isArray(content)) return [];

    const codeBlocks = [];
    content.forEach((block) => {
      if (block.type === 'text' && block.text) {
        // Look for code blocks in text (```language...```)
        const codeBlockRegex = /```(\w+)?\n([\s\S]*?)```/g;
        let match;
        while ((match = codeBlockRegex.exec(block.text)) !== null) {
          codeBlocks.push({
            type: 'code_block',
            language: match[1] || 'text',
            code: match[2].trim(),
          });
        }
      }
    });

    return codeBlocks;
  }

  /**
   * Aggregate buffered content into a single response
   */
  static aggregateBufferedContent(buffer) {
    if (!buffer || !buffer.assistantMessages) {
      return [];
    }

    const aggregatedContent = [];

    // Combine all text content from assistant messages
    const textBlocks = [];

    buffer.assistantMessages.forEach((message) => {
      if (message.content && Array.isArray(message.content)) {
        message.content.forEach((block) => {
          if (block.type === 'text' && block.text) {
            textBlocks.push(block.text);
          }
        });
      }
    });

    // Combine text blocks, removing duplicates and tool usage details
    const combinedText = textBlocks
      .filter((text) => text.trim().length > 0)
      .filter((text, index, array) => array.indexOf(text) === index) // Remove duplicates
      .join('\n\n');

    if (combinedText) {
      aggregatedContent.push({
        type: 'text',
        text: combinedText,
      });
    }

    return aggregatedContent;
  }

  /**
   * Clear session buffer state
   */
  static clearSessionBuffer(buffer) {
    if (!buffer) return;

    buffer.assistantMessages = [];
    buffer.toolUseInProgress = false;
    buffer.permissionRequests = [];
    buffer.deliverables = [];
    buffer.permissionRequestSent = false;
    buffer.pendingFinalResponse = null;
  }

  /**
   * Create initial session buffer
   */
  static createSessionBuffer() {
    return {
      assistantMessages: [],
      toolUseInProgress: false,
      permissionRequests: [],
      deliverables: [],
      permissionRequestSent: false,
      systemInit: null,
      pendingFinalResponse: null,
      claudeSessionId: null,
      // Enhanced for message fetching
      messagesById: new Map(), // Store messages by ID for retrieval
      userMessages: [], // Track user messages too
    };
  }

  /**
   * Store a message with ID for later retrieval
   */
  static storeMessageWithId(buffer, content, metadata = {}) {
    const messageId = this.generateMessageId();
    const message = {
      id: messageId,
      content,
      timestamp: new Date().toISOString(),
      sessionId: buffer.claudeSessionId,
      requestId: metadata.requestId,
      type: metadata.type || 'assistant',
      ...metadata,
    };

    // Store in map for quick retrieval
    if (!buffer.messagesById) {
      buffer.messagesById = new Map();
    }
    buffer.messagesById.set(messageId, message);

    // Also add to appropriate array
    if (message.type === 'user') {
      if (!buffer.userMessages) buffer.userMessages = [];
      buffer.userMessages.push(message);
    } else {
      buffer.assistantMessages.push(message);
    }

    return messageId;
  }
}
