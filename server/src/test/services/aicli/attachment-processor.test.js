import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import { AttachmentProcessor } from '../../../services/aicli/attachment-processor.js';

describe('AttachmentProcessor', () => {
  const testTempDir = path.join(os.tmpdir(), 'claude-attachments-test');

  beforeEach(async () => {
    // Ensure test temp directory exists
    await fs.mkdir(testTempDir, { recursive: true });
  });

  afterEach(async () => {
    // Clean up test files
    try {
      const files = await fs.readdir(testTempDir);
      for (const file of files) {
        await fs.unlink(path.join(testTempDir, file));
      }
    } catch (error) {
      // Directory might not exist
    }
  });

  describe('processAttachments', () => {
    it('should return empty result for no attachments', async () => {
      const result = await AttachmentProcessor.processAttachments(null);
      assert.deepEqual(result.filePaths, []);
      assert.equal(typeof result.cleanup, 'function');
    });

    it('should return empty result for empty array', async () => {
      const result = await AttachmentProcessor.processAttachments([]);
      assert.deepEqual(result.filePaths, []);
      assert.equal(typeof result.cleanup, 'function');
    });

    it('should process single attachment', async () => {
      const attachment = {
        name: 'test.txt',
        data: Buffer.from('Hello World').toString('base64'),
      };

      const result = await AttachmentProcessor.processAttachments([attachment]);

      assert.equal(result.filePaths.length, 1);
      assert.ok(result.filePaths[0].includes('test.txt'));

      // Verify file was created
      const content = await fs.readFile(result.filePaths[0], 'utf-8');
      assert.equal(content, 'Hello World');

      // Clean up
      await result.cleanup();

      // Verify file was deleted
      await assert.rejects(fs.access(result.filePaths[0]));
    });

    it('should process multiple attachments', async () => {
      const attachments = [
        {
          name: 'file1.txt',
          data: Buffer.from('Content 1').toString('base64'),
        },
        {
          name: 'file2.txt',
          data: Buffer.from('Content 2').toString('base64'),
        },
      ];

      const result = await AttachmentProcessor.processAttachments(attachments);

      assert.equal(result.filePaths.length, 2);

      // Verify files were created
      const content1 = await fs.readFile(result.filePaths[0], 'utf-8');
      const content2 = await fs.readFile(result.filePaths[1], 'utf-8');
      assert.ok(content1 === 'Content 1' || content1 === 'Content 2');
      assert.ok(content2 === 'Content 1' || content2 === 'Content 2');

      // Clean up
      await result.cleanup();
    });

    it.skip('should sanitize dangerous filenames', async () => {
      const attachment = {
        name: '../../../etc/passwd',
        data: Buffer.from('test').toString('base64'),
      };

      const result = await AttachmentProcessor.processAttachments([attachment]);

      assert.equal(result.filePaths.length, 1);
      // Filename should be sanitized
      assert.ok(!result.filePaths[0].includes('..'));
      assert.ok(result.filePaths[0].includes('etc_passwd'));

      await result.cleanup();
    });

    it('should handle special characters in filenames', async () => {
      const attachment = {
        name: 'file with spaces & symbols!@#.txt',
        data: Buffer.from('test').toString('base64'),
      };

      const result = await AttachmentProcessor.processAttachments([attachment]);

      assert.equal(result.filePaths.length, 1);
      // Special characters should be replaced with underscores
      assert.ok(result.filePaths[0].includes('file_with_spaces___symbols___.txt'));

      await result.cleanup();
    });

    it.skip('should handle attachment processing errors gracefully', async () => {
      const attachments = [
        {
          name: 'good.txt',
          data: Buffer.from('good').toString('base64'),
        },
        {
          name: 'bad.txt',
          data: 'invalid-base64-!@#$%',
        },
        {
          name: 'good2.txt',
          data: Buffer.from('good2').toString('base64'),
        },
      ];

      const result = await AttachmentProcessor.processAttachments(attachments);

      // Should process the good attachments and skip the bad one
      assert.equal(result.filePaths.length, 2);

      await result.cleanup();
    });

    it('should generate unique filenames with timestamp and random suffix', async () => {
      const attachments = [
        {
          name: 'test.txt',
          data: Buffer.from('1').toString('base64'),
        },
        {
          name: 'test.txt',
          data: Buffer.from('2').toString('base64'),
        },
      ];

      const result = await AttachmentProcessor.processAttachments(attachments);

      assert.equal(result.filePaths.length, 2);
      // Files should have different paths despite same name
      assert.notEqual(result.filePaths[0], result.filePaths[1]);

      await result.cleanup();
    });

    it('should handle cleanup errors gracefully', async () => {
      const attachment = {
        name: 'test.txt',
        data: Buffer.from('test').toString('base64'),
      };

      const result = await AttachmentProcessor.processAttachments([attachment]);

      // Delete file manually to simulate error
      await fs.unlink(result.filePaths[0]);

      // Cleanup should not throw even if file doesn't exist
      await assert.doesNotReject(result.cleanup());
    });
  });

  describe('buildEnhancedPrompt', () => {
    it('should return original prompt when no files', () => {
      const prompt = 'Original prompt';
      const enhanced = AttachmentProcessor.buildEnhancedPrompt(prompt, null);
      assert.equal(enhanced, prompt);
    });

    it('should return original prompt for empty file array', () => {
      const prompt = 'Original prompt';
      const enhanced = AttachmentProcessor.buildEnhancedPrompt(prompt, []);
      assert.equal(enhanced, prompt);
    });

    it('should enhance prompt with single file', () => {
      const prompt = 'Analyze this';
      const files = ['/tmp/file1.txt'];
      const enhanced = AttachmentProcessor.buildEnhancedPrompt(prompt, files);
      assert.equal(enhanced, '[Files attached: file1.txt]\nAnalyze this');
    });

    it('should enhance prompt with multiple files', () => {
      const prompt = 'Process these';
      const files = ['/tmp/file1.txt', '/tmp/file2.pdf', '/tmp/file3.png'];
      const enhanced = AttachmentProcessor.buildEnhancedPrompt(prompt, files);
      assert.equal(enhanced, '[Files attached: file1.txt, file2.pdf, file3.png]\nProcess these');
    });

    it('should extract just the filename from full paths', () => {
      const prompt = 'Check';
      const files = ['/very/long/path/to/document.doc'];
      const enhanced = AttachmentProcessor.buildEnhancedPrompt(prompt, files);
      assert.equal(enhanced, '[Files attached: document.doc]\nCheck');
    });
  });
});
