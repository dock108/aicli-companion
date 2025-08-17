import { sessionPool } from './interactive-session-pool.js';
import { InputValidator } from './aicli-utils.js';
import { createLogger } from '../utils/logger.js';
import path from 'path';
import fs from 'fs/promises';
import { v4 as uuidv4 } from 'uuid';
import os from 'os';
import { execSync } from 'child_process';

const logger = createLogger('AICLIInteractive');

/**
 * Simplified AICLI service that uses interactive session pool
 * This replaces the complex sendPrompt flow with direct pool usage
 */
export class AICLIInteractiveService {
  constructor() {
    this.pool = sessionPool;
    this.tempDir = path.join(os.tmpdir(), 'aicli-attachments');
  }
  
  /**
   * Process attachments and save to temp files
   */
  async processAttachments(attachments) {
    if (!attachments || attachments.length === 0) {
      return { filePaths: [], cleanup: () => {} };
    }
    
    // Ensure temp directory exists
    await fs.mkdir(this.tempDir, { recursive: true });
    
    const filePaths = [];
    const tempFiles = [];
    
    for (const attachment of attachments) {
      try {
        // Decode base64 data
        const buffer = Buffer.from(attachment.data, 'base64');
        
        // Generate temp file path
        const tempFileName = `${uuidv4()}-${attachment.name}`;
        const tempFilePath = path.join(this.tempDir, tempFileName);
        
        // Write file
        await fs.writeFile(tempFilePath, buffer);
        filePaths.push(tempFilePath);
        tempFiles.push(tempFilePath);
        
        logger.info('Saved attachment to temp file', {
          originalName: attachment.name,
          tempPath: tempFilePath,
          size: buffer.length,
        });
      } catch (error) {
        logger.error('Failed to process attachment', {
          name: attachment.name,
          error: error.message,
        });
      }
    }
    
    // Cleanup function
    const cleanup = async () => {
      for (const tempFile of tempFiles) {
        try {
          await fs.unlink(tempFile);
          logger.debug('Cleaned up temp file', { path: tempFile });
        } catch (error) {
          logger.warn('Failed to cleanup temp file', {
            path: tempFile,
            error: error.message,
          });
        }
      }
    };
    
    return { filePaths, cleanup };
  }
  
  /**
   * Send a prompt using the interactive session pool
   */
  async sendPrompt(prompt, options = {}) {
    const {
      sessionId = null,
      requestId = null,
      workingDirectory = process.cwd(),
      attachments = null,
    } = options;
    
    let attachmentData = { filePaths: [], cleanup: () => {} };
    
    try {
      // Validate inputs
      const sanitizedPrompt = InputValidator.sanitizePrompt(prompt);
      const validatedWorkingDir = await InputValidator.validateWorkingDirectory(
        workingDirectory
      );
      
      // Process attachments if provided
      if (attachments && attachments.length > 0) {
        logger.info('Processing attachments', { count: attachments.length });
        attachmentData = await this.processAttachments(attachments);
        
        // Add attachment references to prompt
        if (attachmentData.filePaths.length > 0) {
          const fileList = attachmentData.filePaths.map(fp => path.basename(fp)).join(', ');
          prompt = `${sanitizedPrompt}\n\nAttached files: ${fileList}`;
        }
      }
      
      let activeSessionId = sessionId;
      let result;
      
      // Use interactive session pool
      if (sessionId && this.pool.hasSession(sessionId)) {
        // Use existing session
        logger.info('Using existing interactive session', {
          sessionId,
          requestId,
        });
        
        result = await this.pool.sendMessage(sessionId, prompt);
      } else {
        // Create new interactive session
        logger.info('Creating new interactive session', {
          workingDirectory: validatedWorkingDir,
          requestId,
        });
        
        const newSession = await this.pool.createSession(validatedWorkingDir);
        activeSessionId = newSession.sessionId;
        
        // Send the message to the new session
        result = await this.pool.sendMessage(activeSessionId, prompt);
      }
      
      // Format response for compatibility
      return {
        sessionId: activeSessionId,
        success: result.success !== false,
        response: {
          result: result.result || '',
          session_id: activeSessionId,
        },
        requestId,
        sessionExpiresAt: result.sessionExpiresAt,
      };
      
    } catch (error) {
      logger.error('Error in sendPrompt', {
        error: error.message,
        sessionId,
        requestId,
      });
      
      throw new Error(`Interactive session failed: ${error.message}`);
    } finally {
      // Always cleanup temp files
      await attachmentData.cleanup();
    }
  }
  
  /**
   * Check if service is available
   */
  isAvailable() {
    // Check if Claude command exists
    try {
      execSync('which claude', { stdio: 'ignore' });
      return true;
    } catch {
      return false;
    }
  }
  
  /**
   * Get active sessions from pool
   */
  getActiveSessions() {
    return this.pool.getActiveSessions();
  }
  
  /**
   * Shutdown the service
   */
  async shutdown() {
    logger.info('Shutting down interactive service');
    await this.pool.shutdown();
  }
}

// Export singleton instance
export const aicliInteractiveService = new AICLIInteractiveService();