import { describe, it } from 'node:test';
import assert from 'node:assert';
import { MessageClassifier } from '../../../services/aicli/message-classifier.js';

describe('MessageClassifier', () => {
  describe('classifyAICLIMessage', () => {
    it('should classify system messages', () => {
      const message = { type: 'system', content: 'test' };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'streamData');
      assert.equal(result.data.type, 'system');
    });

    it('should classify system init messages', () => {
      const message = {
        type: 'system',
        subtype: 'init',
        session_id: 'test-session',
        cwd: '/test/dir',
        tools: ['tool1'],
        model: 'claude-3',
      };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'systemInit');
      assert.equal(result.data.type, 'system_init');
      assert.equal(result.data.sessionId, 'test-session');
    });

    it('should classify assistant messages', () => {
      const message = { type: 'assistant', message: { content: 'test' } };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'streamData');
      assert.equal(result.data.type, 'assistant');
    });

    it('should classify assistant messages with array content', () => {
      const message = {
        type: 'assistant',
        message: {
          id: 'msg-123',
          content: [{ type: 'text', text: 'test' }],
          model: 'claude-3',
          usage: { input_tokens: 10, output_tokens: 20 },
        },
      };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'assistantMessage');
      assert.equal(result.data.type, 'assistant_response');
    });

    it('should classify tool use messages', () => {
      const message = {
        type: 'tool_use',
        tool_name: 'calculator',
        tool_input: { operation: 'add' },
        tool_id: 'tool-123',
      };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'toolUse');
      assert.equal(result.data.type, 'tool_use');
      assert.equal(result.data.toolName, 'calculator');
    });

    it('should classify tool result messages', () => {
      const message = {
        type: 'tool_result',
        tool_name: 'calculator',
        tool_id: 'tool-123',
        result: '42',
      };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'toolResult');
      assert.equal(result.data.type, 'tool_result');
    });

    it('should classify result messages', () => {
      const message = {
        type: 'result',
        result: 'Success',
        is_error: false,
        session_id: 'test-session',
        duration_ms: 1000,
        total_cost_usd: 0.01,
        usage: { input_tokens: 10, output_tokens: 20 },
      };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'conversationResult');
      assert.equal(result.data.type, 'final_result');
      assert.equal(result.data.success, true);
    });

    it('should handle unknown message types', () => {
      const message = { type: 'unknown', content: 'test' };
      const result = MessageClassifier.classifyAICLIMessage(message);
      assert.equal(result.eventType, 'streamData');
      assert.equal(result.data.type, 'unknown');
    });

    it('should handle non-object messages', () => {
      const result = MessageClassifier.classifyAICLIMessage('string message');
      assert.equal(result.eventType, 'streamData');
      assert.equal(result.data, 'string message');
    });

    it('should handle null messages', () => {
      const result = MessageClassifier.classifyAICLIMessage(null);
      assert.equal(result.eventType, 'streamData');
      assert.equal(result.data, null);
    });
  });

  describe('extractTextFromMessage', () => {
    it('should extract text from string message', () => {
      const text = MessageClassifier.extractTextFromMessage('test message');
      assert.equal(text, 'test message');
    });

    it('should extract text from result property', () => {
      const message = { result: 'test result' };
      const text = MessageClassifier.extractTextFromMessage(message);
      assert.equal(text, 'test result');
    });

    it('should extract text from text property', () => {
      const message = { text: 'test text' };
      const text = MessageClassifier.extractTextFromMessage(message);
      assert.equal(text, 'test text');
    });

    it('should extract text from message content blocks', () => {
      const message = {
        message: {
          content: [
            { type: 'text', text: 'test block' },
            { type: 'tool_use', name: 'tool' },
          ],
        },
      };
      const text = MessageClassifier.extractTextFromMessage(message);
      assert.equal(text, 'test block');
    });

    it('should extract text from string content', () => {
      const message = {
        message: {
          content: 'test content',
        },
      };
      const text = MessageClassifier.extractTextFromMessage(message);
      assert.equal(text, 'test content');
    });

    it('should return null for unrecognized format', () => {
      const message = { unknown: 'property' };
      const text = MessageClassifier.extractTextFromMessage(message);
      assert.equal(text, null);
    });
  });

  describe('containsPermissionRequest', () => {
    it('should detect permission keyword', () => {
      assert.equal(MessageClassifier.containsPermissionRequest('Do you grant permission?'), true);
      assert.equal(MessageClassifier.containsPermissionRequest('Permission required'), true);
      assert.equal(MessageClassifier.containsPermissionRequest('No permissions here'), true);
    });

    it('should handle objects with content', () => {
      assert.equal(
        MessageClassifier.containsPermissionRequest({ content: 'permission needed' }),
        true
      );
      assert.equal(MessageClassifier.containsPermissionRequest({ text: 'grant permission' }), true);
    });

    it('should return false for non-permission content', () => {
      assert.equal(MessageClassifier.containsPermissionRequest('regular message'), false);
      assert.equal(MessageClassifier.containsPermissionRequest(null), false);
      assert.equal(MessageClassifier.containsPermissionRequest({}), false);
    });
  });

  describe('containsToolUse', () => {
    it('should detect tool keyword', () => {
      assert.equal(MessageClassifier.containsToolUse('Using tool now'), true);
      assert.equal(MessageClassifier.containsToolUse('Tool execution'), true);
    });

    it('should return false for non-tool content', () => {
      assert.equal(MessageClassifier.containsToolUse('regular message'), false);
      assert.equal(MessageClassifier.containsToolUse(null), false);
    });
  });

  describe('containsApprovalResponse', () => {
    it('should detect approval responses', () => {
      assert.equal(MessageClassifier.containsApprovalResponse('y'), true);
      assert.equal(MessageClassifier.containsApprovalResponse('Y'), true);
      assert.equal(MessageClassifier.containsApprovalResponse('yes'), true);
      assert.equal(MessageClassifier.containsApprovalResponse('YES'), true);
      assert.equal(MessageClassifier.containsApprovalResponse('approve'), true);
      assert.equal(MessageClassifier.containsApprovalResponse('APPROVE'), true);
    });

    it('should reject non-approval responses', () => {
      assert.equal(MessageClassifier.containsApprovalResponse('n'), false);
      assert.equal(MessageClassifier.containsApprovalResponse('no'), false);
      assert.equal(MessageClassifier.containsApprovalResponse('deny'), false);
      assert.equal(MessageClassifier.containsApprovalResponse('maybe'), false);
    });
  });

  describe('extractCodeBlocks', () => {
    it('should extract code blocks', () => {
      const content = 'Text before\n```js\nconst x = 1;\n```\nText after';
      const blocks = MessageClassifier.extractCodeBlocks(content);
      assert.equal(blocks.length, 1);
      assert.equal(blocks[0], '```js\nconst x = 1;\n```');
    });

    it('should extract multiple code blocks', () => {
      const content = '```js\ncode1\n```\nMiddle\n```py\ncode2\n```';
      const blocks = MessageClassifier.extractCodeBlocks(content);
      assert.equal(blocks.length, 2);
    });

    it('should return empty array when no code blocks', () => {
      const content = 'No code blocks here';
      const blocks = MessageClassifier.extractCodeBlocks(content);
      assert.equal(blocks.length, 0);
    });
  });

  describe('isPermissionPrompt', () => {
    it('should detect permission prompt messages', () => {
      assert.equal(MessageClassifier.isPermissionPrompt({ type: 'permission_request' }), true);
    });

    it('should reject non-permission messages', () => {
      assert.equal(MessageClassifier.isPermissionPrompt({ type: 'other' }), false);
      assert.equal(MessageClassifier.isPermissionPrompt(null), false);
      assert.equal(MessageClassifier.isPermissionPrompt('string'), false);
    });
  });
});
