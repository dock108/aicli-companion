import fs from 'fs/promises';
import path from 'path';
import os from 'os';
import crypto from 'crypto';

export class AttachmentProcessor {
  /**
   * Process attachments by creating temporary files
   * @param {Array} attachments - Array of attachment objects with base64 data
   * @returns {Object} Object with filePaths and cleanup function
   */
  static async processAttachments(attachments) {
    if (!attachments || attachments.length === 0) {
      return { filePaths: [], cleanup: () => {} };
    }

    const tempDir = path.join(os.tmpdir(), 'claude-attachments');
    await fs.mkdir(tempDir, { recursive: true });

    const tempFiles = [];

    for (const attachment of attachments) {
      try {
        // Sanitize filename and add timestamp for uniqueness
        const timestamp = Date.now();
        const sanitizedName = attachment.name.replace(/[^a-zA-Z0-9.-]/g, '_');
        const randomSuffix = crypto.randomBytes(4).toString('hex');
        const tempFileName = `${timestamp}_${randomSuffix}_${sanitizedName}`;
        const tempFilePath = path.join(tempDir, tempFileName);

        // Write the file
        const buffer = Buffer.from(attachment.data, 'base64');
        await fs.writeFile(tempFilePath, buffer);

        tempFiles.push(tempFilePath);

        console.log(`📎 Created temp file for attachment: ${tempFileName}`);
      } catch (error) {
        console.error(`Failed to process attachment ${attachment.name}:`, error);
      }
    }

    // Return file paths and cleanup function
    return {
      filePaths: tempFiles,
      cleanup: async () => {
        for (const file of tempFiles) {
          try {
            await fs.unlink(file);
            console.log(`🗑️ Cleaned up temp file: ${path.basename(file)}`);
          } catch (error) {
            console.warn(`Failed to cleanup temp file ${file}:`, error.message);
          }
        }
      },
    };
  }

  /**
   * Build enhanced prompt with attachment references
   * @param {string} prompt - Original prompt
   * @param {Array} filePaths - Array of attachment file paths
   * @returns {string} Enhanced prompt with file references
   */
  static buildEnhancedPrompt(prompt, filePaths) {
    if (!filePaths || filePaths.length === 0) {
      return prompt;
    }

    const fileList = filePaths.map((fp) => path.basename(fp)).join(', ');
    const enhancedPrompt = `[Files attached: ${fileList}]\n${prompt}`;
    console.log(`📎 Enhanced prompt with ${filePaths.length} file reference(s)`);

    return enhancedPrompt;
  }
}
