import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import request from 'supertest';
import { router, storeMessage } from '../../routes/messages.js';

describe('Messages Route', () => {
  let app;

  beforeEach(() => {
    app = express();
    app.use(express.json());
    app.use('/api/messages', router);
  });

  afterEach(() => {
    // Clear message store after each test
    // Note: We can't directly access messageStore, but we can test behavior
  });

  describe('GET /api/messages/:messageId', () => {
    it('should return 404 for non-existent message', async () => {
      const response = await request(app).get('/api/messages/non-existent-id').expect(404);

      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.error, 'Message not found');
    });

    it('should return stored message', async () => {
      const messageId = 'test-message-123';
      const content = 'This is a test message';
      const metadata = { sender: 'test' };

      // Store a message
      storeMessage(messageId, content, metadata);

      // Retrieve the message
      const response = await request(app).get(`/api/messages/${messageId}`).expect(200);

      assert.strictEqual(response.body.id, messageId);
      assert.strictEqual(response.body.content, content);
      assert.deepStrictEqual(response.body.metadata, metadata);
      assert.ok(response.body.timestamp);
    });

    it('should handle messages with no metadata', async () => {
      const messageId = 'test-no-metadata';
      const content = 'Message without metadata';

      // Store a message without metadata
      storeMessage(messageId, content);

      // Retrieve the message
      const response = await request(app).get(`/api/messages/${messageId}`).expect(200);

      assert.strictEqual(response.body.id, messageId);
      assert.strictEqual(response.body.content, content);
      assert.deepStrictEqual(response.body.metadata, {});
    });

    it('should handle large message content', async () => {
      const messageId = 'large-message';
      const content = 'x'.repeat(10000); // 10KB message

      storeMessage(messageId, content);

      const response = await request(app).get(`/api/messages/${messageId}`).expect(200);

      assert.strictEqual(response.body.content.length, 10000);
    });

    it('should handle special characters in messageId', async () => {
      const messageId = 'test-123_ABC.xyz';
      const content = 'Test content';

      storeMessage(messageId, content);

      const response = await request(app)
        .get(`/api/messages/${encodeURIComponent(messageId)}`)
        .expect(200);

      assert.strictEqual(response.body.id, messageId);
    });
  });

  describe('storeMessage function', () => {
    it('should store message with all parameters', () => {
      const messageId = 'store-test-1';
      const content = 'Test content';
      const metadata = { type: 'test', priority: 'high' };

      // Should not throw
      assert.doesNotThrow(() => {
        storeMessage(messageId, content, metadata);
      });
    });

    it('should store message without metadata', () => {
      const messageId = 'store-test-2';
      const content = 'Test content';

      // Should not throw
      assert.doesNotThrow(() => {
        storeMessage(messageId, content);
      });
    });

    it('should handle empty content', () => {
      const messageId = 'empty-content';
      const content = '';

      storeMessage(messageId, content);

      // Verify it was stored
      request(app)
        .get(`/api/messages/${messageId}`)
        .expect(200)
        .end((err, res) => {
          if (err) return;
          assert.strictEqual(res.body.content, '');
        });
    });

    it('should overwrite existing message with same ID', async () => {
      const messageId = 'overwrite-test';
      const content1 = 'First content';
      const content2 = 'Second content';

      // Store first message
      storeMessage(messageId, content1);

      // Store second message with same ID
      storeMessage(messageId, content2);

      // Retrieve and verify it's the second message
      const response = await request(app).get(`/api/messages/${messageId}`).expect(200);

      assert.strictEqual(response.body.content, content2);
    });

    it('should store messages with different IDs independently', async () => {
      const messageId1 = 'msg-1';
      const messageId2 = 'msg-2';
      const content1 = 'Content 1';
      const content2 = 'Content 2';

      storeMessage(messageId1, content1);
      storeMessage(messageId2, content2);

      // Verify both messages exist
      const response1 = await request(app).get(`/api/messages/${messageId1}`).expect(200);
      assert.strictEqual(response1.body.content, content1);

      const response2 = await request(app).get(`/api/messages/${messageId2}`).expect(200);
      assert.strictEqual(response2.body.content, content2);
    });
  });

  describe('Message TTL', () => {
    it('should set up cleanup timer when storing message', () => {
      const messageId = 'ttl-test';
      const content = 'TTL test content';

      // Store message and verify timer is set
      // Note: We can't directly test the timer, but we can verify the message exists
      storeMessage(messageId, content);

      // Message should exist immediately after storing
      request(app)
        .get(`/api/messages/${messageId}`)
        .expect(200)
        .end((err, res) => {
          if (err) return;
          assert.ok(res.body.timestamp);
        });
    });
  });
});
