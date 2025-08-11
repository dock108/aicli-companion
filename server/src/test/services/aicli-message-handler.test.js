import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import { AICLIMessageHandler } from '../../services/aicli-message-handler.js';

describe('AICLIMessageHandler', () => {
  let buffer;

  beforeEach(() => {
    buffer = {
      assistantMessages: [],
      deliverables: [],
      toolUseInProgress: false,
      permissionRequestSent: false,
      systemInit: null,
    };
  });

  describe('processResponse', () => {
    it('should return error when no buffer provided', () => {
      const response = { type: 'assistant' };
      const result = AICLIMessageHandler.processResponse(response, null);

      assert.strictEqual(result.action, 'error');
      assert.strictEqual(result.reason, 'No message buffer provided');
    });

    it('should process system responses', () => {
      const response = { type: 'system', subtype: 'init' };
      const result = AICLIMessageHandler.processResponse(response, buffer);

      assert.strictEqual(result.action, 'buffer');
      assert.strictEqual(buffer.systemInit, response);
    });

    it('should process assistant responses', () => {
      const response = {
        type: 'assistant',
        message: {
          content: [{ type: 'text', text: 'Hello world' }],
        },
      };
      const result = AICLIMessageHandler.processResponse(response, buffer);

      assert.strictEqual(result.action, 'buffer');
      assert.strictEqual(buffer.assistantMessages.length, 1);
    });

    it('should skip user messages', () => {
      const response = { type: 'user' };
      const result = AICLIMessageHandler.processResponse(response, buffer);

      assert.strictEqual(result.action, 'buffer');
      assert.strictEqual(result.reason, 'User/tool result message');
    });

    it('should process result messages', () => {
      const response = { type: 'result', result: 'Done' };
      const result = AICLIMessageHandler.processResponse(response, buffer);

      assert.strictEqual(result.action, 'final_result');
      assert.ok(result.data);
    });

    it('should skip unknown message types', () => {
      const response = { type: 'unknown' };
      const result = AICLIMessageHandler.processResponse(response, buffer);

      assert.strictEqual(result.action, 'skip');
      assert.ok(result.reason.includes('Unknown message type'));
    });
  });

  describe('processSystemResponse', () => {
    it('should buffer system init messages', () => {
      const response = { subtype: 'init', data: 'test' };
      const result = AICLIMessageHandler.processSystemResponse(response, buffer);

      assert.strictEqual(result.action, 'buffer');
      assert.strictEqual(buffer.systemInit, response);
    });

    it('should skip non-init system messages', () => {
      const response = { subtype: 'other' };
      const result = AICLIMessageHandler.processSystemResponse(response, buffer);

      assert.strictEqual(result.action, 'skip');
      assert.strictEqual(result.reason, 'Non-init system message');
    });
  });

  describe('processAssistantResponse', () => {
    it('should skip messages without content', () => {
      const response = { message: {} };
      const result = AICLIMessageHandler.processAssistantResponse(response, buffer);

      assert.strictEqual(result.action, 'skip');
      assert.strictEqual(result.reason, 'Assistant message has no content');
    });

    it('should handle permission requests', () => {
      const response = {
        message: {
          id: 'msg-123',
          content: [{ type: 'text', text: 'Would you like me to proceed with the changes? (y/n)' }],
          model: 'claude-3',
          usage: { tokens: 100 },
        },
        session_id: 'session-123',
      };
      const result = AICLIMessageHandler.processAssistantResponse(response, buffer);

      assert.strictEqual(result.action, 'permission_request');
      assert.ok(result.data);
      assert.strictEqual(result.data.sessionId, 'session-123');
      assert.ok(result.data.prompt);
      assert.ok(buffer.permissionRequestSent);
    });

    it('should handle tool use', () => {
      const response = {
        message: {
          id: 'msg-123',
          content: [
            { type: 'text', text: 'I will use a tool' },
            { type: 'tool_use', id: 'tool-1', name: 'read_file' },
          ],
          model: 'claude-3',
          usage: { tokens: 100 },
        },
      };
      const result = AICLIMessageHandler.processAssistantResponse(response, buffer);

      assert.strictEqual(result.action, 'tool_use');
      assert.ok(result.data);
      assert.ok(buffer.toolUseInProgress);
    });

    it('should extract code blocks', () => {
      const response = {
        message: {
          content: [
            { type: 'text', text: 'Here is the code:\n```javascript\nconsole.log("hello");\n```' },
          ],
        },
      };
      const result = AICLIMessageHandler.processAssistantResponse(response, buffer);

      assert.strictEqual(result.action, 'buffer');
      assert.ok(buffer.deliverables);
      assert.ok(buffer.deliverables.length > 0);
    });

    it('should buffer regular messages', () => {
      const response = {
        message: {
          content: [{ type: 'text', text: 'Regular message' }],
        },
      };
      const result = AICLIMessageHandler.processAssistantResponse(response, buffer);

      assert.strictEqual(result.action, 'buffer');
      assert.strictEqual(buffer.assistantMessages.length, 1);
    });
  });

  describe('processFinalResult', () => {
    it('should return final result data', () => {
      const response = { result: 'Task completed', session_id: 'session-123' };
      const result = AICLIMessageHandler.processFinalResult(response, buffer);

      assert.strictEqual(result.action, 'final_result');
      assert.ok(result.data);
      assert.strictEqual(result.data.response, response);
      assert.strictEqual(result.data.buffer, buffer);
    });

    it('should handle long-running completion', () => {
      buffer.assistantMessages = [
        { content: [{ type: 'text', text: 'Message 1' }] },
        { content: [{ type: 'text', text: 'Message 2' }] },
      ];

      const response = { result: 'Done' };
      const options = { isLongRunningCompletion: true };
      const result = AICLIMessageHandler.processFinalResult(response, buffer, options);

      assert.strictEqual(result.action, 'final_result');
      assert.ok(result.data.aggregatedContent);
      assert.ok(result.data.sendAggregated);
    });

    it('should handle embedded permissions', () => {
      buffer.permissionRequestSent = true;

      const response = { result: 'Would you like to continue? (y/n)' };
      const result = AICLIMessageHandler.processFinalResult(response, buffer);

      assert.strictEqual(result.action, 'final_result');
      assert.ok(result.data.embeddedPermission);
      assert.ok(result.data.embeddedPermission.prompt);
    });
  });

  describe('generateAggregatedResponse', () => {
    it('should generate aggregated response data', () => {
      buffer.assistantMessages = [
        { content: [{ type: 'text', text: 'Message 1' }] },
        { content: [{ type: 'text', text: 'Message 2' }] },
      ];
      buffer.deliverables = ['code1', 'code2'];

      const response = {
        session_id: 'session-123',
        duration_ms: 1000,
        total_cost_usd: 0.01,
        usage: { tokens: 100 },
        is_error: false,
      };

      const result = AICLIMessageHandler.generateAggregatedResponse(response, buffer);

      assert.ok(result.assistantMessage);
      assert.strictEqual(result.assistantMessage.type, 'assistant_response');
      assert.ok(result.assistantMessage.content);
      assert.strictEqual(result.assistantMessage.messageCount, 2);

      assert.ok(result.conversationResult);
      assert.strictEqual(result.conversationResult.type, 'final_result');
      assert.strictEqual(result.conversationResult.success, true);
      assert.strictEqual(result.conversationResult.sessionId, 'session-123');
    });
  });

  describe('extractPermissionPrompt', () => {
    it('should extract permission prompt from text', () => {
      const text =
        'I found the file.\nWould you like me to make the changes?\nThis will update the code.';
      const prompt = AICLIMessageHandler.extractPermissionPrompt(text);

      assert.ok(prompt);
      assert.ok(prompt.includes('Would you like'));
    });

    it('should return null for empty text', () => {
      const prompt = AICLIMessageHandler.extractPermissionPrompt('');
      assert.strictEqual(prompt, null);
    });

    it('should find permission patterns', () => {
      const text = 'Should I proceed with the installation?';
      const prompt = AICLIMessageHandler.extractPermissionPrompt(text);

      assert.ok(prompt);
      assert.ok(prompt.includes('Should I proceed'));
    });

    it('should return fallback for text without clear permission', () => {
      const text = 'This is just some text';
      const prompt = AICLIMessageHandler.extractPermissionPrompt(text);

      assert.strictEqual(prompt, 'Permission required to proceed');
    });

    it('should extract last paragraph if it has a question', () => {
      const text = 'First paragraph.\n\nReady to continue?';
      const prompt = AICLIMessageHandler.extractPermissionPrompt(text);

      assert.strictEqual(prompt, 'Ready to continue?');
    });
  });

  describe('containsPermissionRequest', () => {
    it('should detect traditional permission patterns', () => {
      const content = [{ type: 'text', text: 'Need permission to continue (y/n)' }];
      const result = AICLIMessageHandler.containsPermissionRequest(content);

      assert.strictEqual(result, true);
    });

    it('should detect conversational permission patterns', () => {
      const content = [{ type: 'text', text: 'Would you like me to proceed with the changes?' }];
      const result = AICLIMessageHandler.containsPermissionRequest(content);

      assert.strictEqual(result, true);
    });

    it('should return false for non-permission text', () => {
      const content = [{ type: 'text', text: 'Here is the result of the operation.' }];
      const result = AICLIMessageHandler.containsPermissionRequest(content);

      assert.strictEqual(result, false);
    });

    it('should return false for non-array content', () => {
      const result = AICLIMessageHandler.containsPermissionRequest('not an array');

      assert.strictEqual(result, false);
    });

    it('should handle empty content', () => {
      const result = AICLIMessageHandler.containsPermissionRequest([]);

      assert.strictEqual(result, false);
    });
  });

  describe('containsToolUse', () => {
    it('should detect tool use blocks', () => {
      const content = [
        { type: 'text', text: 'Let me check that' },
        { type: 'tool_use', id: 'tool-1', name: 'read_file' },
      ];
      const result = AICLIMessageHandler.containsToolUse(content);

      assert.strictEqual(result, true);
    });

    it('should return false when no tool use', () => {
      const content = [{ type: 'text', text: 'Just text' }];
      const result = AICLIMessageHandler.containsToolUse(content);

      assert.strictEqual(result, false);
    });
  });

  describe('extractCodeBlocks', () => {
    it('should extract code blocks from content', () => {
      const content = [
        {
          type: 'text',
          text: 'Here is code:\n```javascript\nconst x = 1;\n```\nAnd more:\n```python\nprint("hi")\n```',
        },
      ];
      const blocks = AICLIMessageHandler.extractCodeBlocks(content);

      assert.strictEqual(blocks.length, 2);
      assert.ok(blocks[0].code.includes('const x = 1'));
      assert.strictEqual(blocks[0].language, 'javascript');
      assert.ok(blocks[1].code.includes('print("hi")'));
      assert.strictEqual(blocks[1].language, 'python');
    });

    it('should handle content without code blocks', () => {
      const content = [{ type: 'text', text: 'No code here' }];
      const blocks = AICLIMessageHandler.extractCodeBlocks(content);

      assert.strictEqual(blocks.length, 0);
    });
  });

  describe('aggregateBufferedContent', () => {
    it('should aggregate messages from buffer', () => {
      buffer.assistantMessages = [
        { content: [{ type: 'text', text: 'First message' }] },
        { content: [{ type: 'text', text: 'Second message' }] },
      ];

      const result = AICLIMessageHandler.aggregateBufferedContent(buffer);

      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'text');
      assert.ok(result[0].text.includes('First message'));
      assert.ok(result[0].text.includes('Second message'));
    });

    it('should handle empty buffer', () => {
      const result = AICLIMessageHandler.aggregateBufferedContent(buffer);

      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 0);
    });

    it('should include system init if present', () => {
      buffer.systemInit = { data: 'System initialized' };
      buffer.assistantMessages = [{ content: [{ type: 'text', text: 'Assistant message' }] }];

      const result = AICLIMessageHandler.aggregateBufferedContent(buffer);

      assert.ok(Array.isArray(result));
      assert.strictEqual(result.length, 1);
      assert.strictEqual(result[0].type, 'text');
      assert.ok(result[0].text.includes('Assistant message'));
    });
  });
});
