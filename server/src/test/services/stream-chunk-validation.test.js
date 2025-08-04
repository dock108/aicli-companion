import test from 'node:test';
import assert from 'node:assert';
import { WebSocketUtilities } from '../../services/websocket-utilities.js';

test('Stream chunk validation', async (t) => {
  await t.test('validateStreamChunk - should reject invalid structures', () => {
    // Null or undefined
    assert.strictEqual(WebSocketUtilities.validateStreamChunk(null), false);
    assert.strictEqual(WebSocketUtilities.validateStreamChunk(undefined), false);

    // Non-objects
    assert.strictEqual(WebSocketUtilities.validateStreamChunk('string'), false);
    assert.strictEqual(WebSocketUtilities.validateStreamChunk(123), false);
    assert.strictEqual(WebSocketUtilities.validateStreamChunk(true), false);

    // Missing required fields
    assert.strictEqual(WebSocketUtilities.validateStreamChunk({}), false);
    assert.strictEqual(WebSocketUtilities.validateStreamChunk({ type: 'content' }), false);
    assert.strictEqual(WebSocketUtilities.validateStreamChunk({ data: {} }), false);
  });

  await t.test('validateStreamChunk - should filter empty content chunks', () => {
    // Empty content
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'content',
        data: { content: '' },
      }),
      false
    );

    // Whitespace only content
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'content',
        data: { content: '   \n\t  ' },
      }),
      false
    );

    // Missing content field
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'content',
        data: {},
      }),
      false
    );

    // Valid content should pass
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'content',
        data: { content: 'Hello' },
      }),
      true
    );
  });

  await t.test('validateStreamChunk - should filter incomplete tool_use chunks', () => {
    // Missing name
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'tool_use',
        data: { id: '123' },
      }),
      false
    );

    // Empty data
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'tool_use',
        data: {},
      }),
      false
    );

    // Valid tool_use should pass
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'tool_use',
        data: { name: 'calculator', id: '123' },
      }),
      true
    );
  });

  await t.test('validateStreamChunk - should handle other chunk types', () => {
    // Other types should currently pass validation
    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'error',
        data: { message: 'Error occurred' },
      }),
      true
    );

    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'metadata',
        data: { info: 'some metadata' },
      }),
      true
    );

    assert.strictEqual(
      WebSocketUtilities.validateStreamChunk({
        type: 'tool_result',
        data: { result: 'success' },
      }),
      true
    );
  });

  await t.test('performance - should validate quickly', () => {
    const chunk = {
      type: 'content',
      data: { content: 'Test content' },
    };

    const iterations = 10000;
    const start = process.hrtime.bigint();

    for (let i = 0; i < iterations; i++) {
      WebSocketUtilities.validateStreamChunk(chunk);
    }

    const end = process.hrtime.bigint();
    const totalMs = Number(end - start) / 1000000;
    const avgMs = totalMs / iterations;

    // Should be very fast - less than 0.01ms per validation
    assert.ok(avgMs < 0.01, `Average validation time ${avgMs}ms is too slow`);
  });
});
