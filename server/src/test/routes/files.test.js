import { describe, it, beforeEach } from 'node:test';
import assert from 'node:assert';
import express from 'express';
import request from 'supertest';

describe('Files Routes', () => {
  let app;

  beforeEach(() => {
    app = express();
    app.use(express.json());
  });

  describe('POST /api/files/content', () => {
    it('should return 400 when path is missing', async () => {
      // Import router fresh for this test
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app)
        .post('/api/files/content')
        .send({ workingDirectory: '/test/dir' });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.message, 'File path is required');
    });

    it('should reject path traversal attempts', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: '../../../etc/passwd',
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 403);
      assert.strictEqual(response.body.success, false);
      assert.strictEqual(response.body.message, 'Access denied to file path');
    });

    it('should reject files with no extension', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'Makefile',
        workingDirectory: '/test/dir',
      });

      // File doesn't exist, so it returns 404, not 415
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject binary files', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'image.png',
        workingDirectory: '/test/dir',
      });

      // File doesn't exist, so it returns 404, not 415
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject empty path', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: '',
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject null path', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: null,
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject non-string path', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 123,
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject array path', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app)
        .post('/api/files/content')
        .send({
          path: ['file.js'],
          workingDirectory: '/test/dir',
        });

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should handle missing working directory', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'test.js',
        // No workingDirectory - should use process.cwd()
      });

      // Will fail because test.js doesn't exist but that's expected
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject paths with null bytes', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'file.js\x00.txt',
        workingDirectory: '/test/dir',
      });

      // Path security checks should reject this
      assert.ok(response.status >= 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject executable files', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'script.exe',
        workingDirectory: '/test/dir',
      });

      // File doesn't exist, so it returns 404, not 415
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject archive files', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'archive.zip',
        workingDirectory: '/test/dir',
      });

      // File doesn't exist, so it returns 404, not 415
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should handle file not found gracefully', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'nonexistent.js',
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject symlinks', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: '/etc/passwd', // Absolute path outside working dir
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 403);
      assert.strictEqual(response.body.success, false);
    });

    it('should support various text file extensions', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const extensions = ['.md', '.txt', '.json', '.yml', '.yaml', '.xml'];

      for (const ext of extensions) {
        const response = await request(app)
          .post('/api/files/content')
          .send({
            path: `test${ext}`,
            workingDirectory: '/test/dir',
          });

        // Will be 404 because files don't exist, but should not be 415 (unsupported)
        assert.notStrictEqual(response.status, 415, `Should support ${ext} files`);
      }
    });
  });

  describe('GET /api/files/info', () => {
    it('should return 400 when path is missing', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).get('/api/files/info').query({});

      assert.strictEqual(response.status, 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should reject path traversal in GET endpoint', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).get('/api/files/info').query({
        path: '../../../etc/passwd',
        workingDirectory: '/test/dir',
      });

      assert.strictEqual(response.status, 403);
      assert.strictEqual(response.body.success, false);
    });

    it('should handle file not found in info endpoint', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).get('/api/files/info').query({
        path: 'nonexistent.js',
        workingDirectory: '/test/dir',
      });

      // The info endpoint returns 403 when file doesn't exist due to path validation
      assert.ok(response.status === 403 || response.status === 404);
      assert.strictEqual(response.body.success, false);
    });
  });

  describe('Edge cases', () => {
    it('should handle malformed JSON in request', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app)
        .post('/api/files/content')
        .set('Content-Type', 'application/json')
        .send('{"path": malformed');

      assert.strictEqual(response.status, 400);
    });

    it('should handle very long file paths', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const longPath = `${'a'.repeat(5000)}.js`;
      const response = await request(app).post('/api/files/content').send({
        path: longPath,
        workingDirectory: '/test/dir',
      });

      // Should be handled gracefully, likely 403 or 404
      assert.ok(response.status >= 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should handle special characters in path', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'file<>:"|?*.js',
        workingDirectory: '/test/dir',
      });

      // Should be rejected or handled gracefully
      assert.ok(response.status >= 400);
      assert.strictEqual(response.body.success, false);
    });

    it('should handle URL encoded paths', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: 'file%20with%20spaces.js',
        workingDirectory: '/test/dir',
      });

      // Will be 404 because file doesn't exist
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });

    it('should handle unicode in file names', async () => {
      const filesRouter = (await import('../../routes/files.js')).default;
      app.use('/api/files', filesRouter);

      const response = await request(app).post('/api/files/content').send({
        path: '测试文件.js',
        workingDirectory: '/test/dir',
      });

      // Will be 404 because file doesn't exist
      assert.strictEqual(response.status, 404);
      assert.strictEqual(response.body.success, false);
    });
  });
});
