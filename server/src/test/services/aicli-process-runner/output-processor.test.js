import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import { OutputProcessor } from '../../../services/aicli-process-runner/output-processor.js';

describe('OutputProcessor', () => {
  let processor;
  let mockParser;

  beforeEach(() => {
    // Mock console methods
    mock.method(console, 'log', () => {});
    mock.method(console, 'debug', () => {});
    mock.method(console, 'info', () => {});
    mock.method(console, 'warn', () => {});
    mock.method(console, 'error', () => {});

    processor = new OutputProcessor();
    
    // Mock the parser
    mockParser = {
      parse: mock.fn(() => ({})),
    };
    processor.parser = mockParser;
  });

  afterEach(() => {
    mock.restoreAll();
  });

  describe('processOutput', () => {
    it('should process streaming JSON response', () => {
      const jsonOutput = JSON.stringify({ 
        type: 'message', 
        content: [{ type: 'text', text: 'Hello' }],
        session_id: 'session123' 
      });
      const sessionId = 'test-session';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      const reject = () => {};

      const result = processor.processOutput(jsonOutput, sessionId, promiseResolve, reject);

      assert.strictEqual(result, true);
      assert(resolvedValue);
      assert.strictEqual(resolvedValue.success, true);
      assert.strictEqual(resolvedValue.isStreaming, true);
      assert.strictEqual(resolvedValue.claudeSessionId, 'session123');
    });

    it('should handle test format responses', () => {
      process.env.NODE_ENV = 'test';
      const jsonOutput = JSON.stringify({ type: 'result', data: 'test data' });
      const sessionId = 'test-session';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      const reject = () => {};

      const result = processor.processOutput(jsonOutput, sessionId, promiseResolve, reject);

      assert.strictEqual(result, true);
      assert.deepStrictEqual(resolvedValue, { type: 'result', data: 'test data' });
      
      process.env.NODE_ENV = undefined;
    });

    it('should process plain text output', () => {
      const plainOutput = 'This is plain text response';
      const sessionId = 'test-session';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      const reject = () => {};

      const result = processor.processOutput(plainOutput, sessionId, promiseResolve, reject);

      assert.strictEqual(result, true);
      assert(resolvedValue);
      assert.strictEqual(resolvedValue.success, true);
      assert.strictEqual(resolvedValue.response, plainOutput);
      assert.strictEqual(resolvedValue.isStreaming, false);
    });

    it('should handle empty output', () => {
      const emptyOutput = '';
      const sessionId = 'test-session';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      const reject = () => {};

      const result = processor.processOutput(emptyOutput, sessionId, promiseResolve, reject);

      assert.strictEqual(result, true);
      assert(resolvedValue);
      assert.strictEqual(resolvedValue.success, false);
      assert.strictEqual(resolvedValue.error, 'No valid response from Claude');
    });

    it('should handle multiple JSON lines', () => {
      const multiLine = [
        JSON.stringify({ type: 'message_start', message: { model: 'claude-3' } }),
        JSON.stringify({ type: 'content_block_delta', delta: { type: 'text_delta', text: 'Hello ' } }),
        JSON.stringify({ type: 'content_block_delta', delta: { type: 'text_delta', text: 'World' } }),
        JSON.stringify({ type: 'message_delta', delta: { stop_reason: 'end_turn' } })
      ].join('\n');
      const sessionId = 'test-session';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      const reject = () => {};

      const result = processor.processOutput(multiLine, sessionId, promiseResolve, reject);

      assert.strictEqual(result, true);
      assert(resolvedValue);
      assert.strictEqual(resolvedValue.success, true);
      assert.strictEqual(resolvedValue.response.result, 'Hello World');
    });

    it('should handle errors during processing', () => {
      const invalidJson = '[{ "type": "invalid" }]'; // Valid JSON that will trigger processStreamingResponse
      const sessionId = 'test-session';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      let rejectedError;
      const reject = (error) => { rejectedError = error; };

      // Force an error by overriding processStreamingResponse
      processor.processStreamingResponse = () => {
        throw new Error('Processing failed');
      };

      const result = processor.processOutput(invalidJson, sessionId, promiseResolve, reject);

      assert.strictEqual(result, true);
      assert(rejectedError);
      assert(rejectedError.message.includes('Failed to process Claude response'));
    });

    it('should include requestId in processing', () => {
      const jsonOutput = JSON.stringify({ type: 'message', content: [{ type: 'text', text: 'Test' }] });
      const sessionId = 'test-session';
      const requestId = 'req123';
      let resolvedValue;
      const promiseResolve = (value) => { resolvedValue = value; };
      const reject = () => {};

      processor.processOutput(jsonOutput, sessionId, promiseResolve, reject, requestId);

      assert(resolvedValue);
      assert.strictEqual(resolvedValue.success, true);
    });
  });

  describe('processStreamingResponse', () => {
    it('should extract text from content blocks', () => {
      const jsonObjects = [
        { type: 'content_block_delta', delta: { type: 'text_delta', text: 'Part 1 ' } },
        { type: 'content_block_delta', delta: { type: 'text_delta', text: 'Part 2' } }
      ];

      const result = processor.processStreamingResponse(jsonObjects, 'session123');

      assert.strictEqual(result.response.result, 'Part 1 Part 2');
    });

    it('should extract session ID', () => {
      const jsonObjects = [
        { session_id: 'claude-session-456' },
        { type: 'message', content: [{ type: 'text', text: 'Hello' }] }
      ];

      const result = processor.processStreamingResponse(jsonObjects, 'session123');

      assert.strictEqual(result.claudeSessionId, 'claude-session-456');
    });

    it('should extract metadata', () => {
      const jsonObjects = [
        { type: 'message_start', message: { model: 'claude-3', usage: { tokens: 100 } } },
        { type: 'content_block_start', content_block: { type: 'tool_use', name: 'calculator', id: 'tool1' } },
        { type: 'message_delta', delta: { stop_reason: 'max_length' }, usage: { tokens: 150 } }
      ];

      const result = processor.processStreamingResponse(jsonObjects, 'session123');

      assert.strictEqual(result.metadata.model, 'claude-3');
      assert.strictEqual(result.metadata.usage.tokens, 150);
      assert.strictEqual(result.metadata.stopReason, 'max_length');
      assert.strictEqual(result.metadata.toolUse.length, 1);
      assert.strictEqual(result.metadata.toolUse[0].name, 'calculator');
    });

    it('should handle array content blocks', () => {
      const jsonObjects = [
        { 
          type: 'message', 
          content: [
            { type: 'text', text: 'First ' },
            { type: 'text', text: 'Second' }
          ]
        }
      ];

      const result = processor.processStreamingResponse(jsonObjects, 'session123');

      assert.strictEqual(result.response.result, 'First Second');
    });

    it('should handle result type messages', () => {
      const jsonObjects = [
        { type: 'result', result: 'Final result text' }
      ];

      const result = processor.processStreamingResponse(jsonObjects, 'session123');

      assert.strictEqual(result.response.result, 'Final result text');
    });

    it('should handle empty jsonObjects array', () => {
      const result = processor.processStreamingResponse([], 'session123');

      assert.strictEqual(result.response.result, '');
      assert.strictEqual(result.claudeSessionId, null);
    });
  });

  describe('processPlainTextOutput', () => {
    it('should clean ANSI codes', () => {
      const ansiOutput = '\x1b[31mRed text\x1b[0m Normal text';

      const result = processor.processPlainTextOutput(ansiOutput, 'session123');

      assert.strictEqual(result.response, 'Red text Normal text');
    });

    it('should remove carriage returns', () => {
      const output = '  Line 1\r\nLine 2\rLine 3  ';

      const result = processor.processPlainTextOutput(output, 'session123');

      // Note: \r is removed (not replaced with \n), and output is trimmed
      assert.strictEqual(result.response, 'Line 1\nLine 2Line 3');
    });

    it('should handle null output', () => {
      const result = processor.processPlainTextOutput(null, 'session123');

      assert.strictEqual(result, null);
    });

    it('should handle empty string', () => {
      const result = processor.processPlainTextOutput('', 'session123');

      assert.strictEqual(result, null);
    });

    it('should handle whitespace-only string', () => {
      const result = processor.processPlainTextOutput('   \n\t  ', 'session123');

      assert.strictEqual(result, null);
    });
  });

  describe('extractError', () => {
    it('should extract error patterns', () => {
      const outputs = [
        { input: 'Error: Something went wrong', expected: 'Something went wrong' },
        { input: 'Failed: Operation failed', expected: 'Operation failed' },
        { input: 'Exception: Null pointer', expected: 'Null pointer' },
        { input: 'rate_limit_error occurred', expected: 'rate_limit_error' },
        { input: 'session expired', expected: 'session expired' },
        { input: 'Session not found', expected: 'session not found' } // Case insensitive match
      ];

      for (const { input, expected } of outputs) {
        const result = processor.extractError(input);
        assert(result, `No error extracted for input: ${input}`);
        assert(
          result.message.toLowerCase().includes(expected.toLowerCase()) || 
          result.message.toLowerCase() === expected.toLowerCase(),
          `Expected "${expected}" but got "${result.message}" for input: ${input}`
        );
      }
    });

    it('should classify error types', () => {
      const result1 = processor.extractError('rate_limit_error');
      assert.strictEqual(result1.type, 'RATE_LIMIT');

      const result2 = processor.extractError('session expired');
      assert.strictEqual(result2.type, 'SESSION_EXPIRED');
    });

    it('should return null for non-error text', () => {
      const result = processor.extractError('This is normal text');
      assert.strictEqual(result, null);
    });
  });

  describe('classifyError', () => {
    it('should classify rate limit errors', () => {
      assert.strictEqual(processor.classifyError('rate limit exceeded'), 'RATE_LIMIT');
    });

    it('should classify session errors', () => {
      assert.strictEqual(processor.classifyError('session expired'), 'SESSION_EXPIRED');
      assert.strictEqual(processor.classifyError('session not found'), 'SESSION_EXPIRED');
    });

    it('should classify permission errors', () => {
      assert.strictEqual(processor.classifyError('permission denied'), 'PERMISSION_DENIED');
    });

    it('should classify timeout errors', () => {
      assert.strictEqual(processor.classifyError('request timeout'), 'TIMEOUT');
    });

    it('should return UNKNOWN for unrecognized errors', () => {
      assert.strictEqual(processor.classifyError('something else'), 'UNKNOWN');
    });
  });
});