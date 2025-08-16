import { EventEmitter } from 'events';
import { AICLIConfig } from './aicli-utils.js';
import { pushNotificationService } from './push-notification.js';

/**
 * Manages long-running AICLI CLI tasks with background processing and push notifications
 */
export class AICLILongRunningTaskManager extends EventEmitter {
  constructor() {
    super();
  }

  /**
   * Handle a potentially long-running task
   * Returns either immediate acknowledgment or delegates to regular processing
   */
  async handlePotentialLongRunningTask(sessionId, prompt, executeFunction) {
    // Calculate dynamic timeout based on command complexity
    const timeoutMs = AICLIConfig.calculateTimeoutForCommand(prompt);

    // Check if this is a long-running operation (> 5 minutes)
    if (timeoutMs > 300000) {
      const estimatedMinutes = Math.round(timeoutMs / 60000);
      console.log(`🕐 Long-running operation detected (${estimatedMinutes} min timeout)`);

      // Send immediate status response
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: [
            {
              type: 'text',
              text: `🔍 **Processing Complex Request**\n\nI'm working on your request: "${prompt.substring(0, 100)}${prompt.length > 100 ? '...' : ''}"\n\n⏱️ **Estimated time:** ${estimatedMinutes} minutes\n📊 **Status:** Starting analysis...\n\nI'll send you the complete results when finished. You can continue using the chat - I'm working in the background!`,
            },
          ],
          timestamp: new Date().toISOString(),
        },
        isComplete: false,
      });

      // Run the process in the background and send results when complete
      this.runLongRunningProcess(sessionId, prompt, executeFunction, timeoutMs);

      // Return immediate acknowledgment
      return {
        type: 'status',
        subtype: 'long_running_started',
        is_error: false,
        result: `Long-running operation started. Estimated completion: ${estimatedMinutes} minutes.`,
        session_id: sessionId,
        estimated_duration_ms: timeoutMs,
        status: 'processing',
      };
    }

    // Not a long-running task, execute normally
    return executeFunction();
  }

  /**
   * Run a long-running process in the background with status updates
   */
  async runLongRunningProcess(sessionId, originalPrompt, executeFunction, _timeoutMs) {
    console.log(`🔄 Starting long-running background process for session ${sessionId}`);

    // Send periodic status updates
    const statusUpdateInterval = setInterval(() => {
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: [
            {
              type: 'text',
              text: `⏳ Still working on your request: "${originalPrompt.substring(0, 60)}..."\n\n📊 **Status:** Processing in background...`,
            },
          ],
          timestamp: new Date().toISOString(),
        },
        isComplete: false,
      });
    }, 120000); // Send update every 2 minutes

    try {
      // Run the actual AICLI process
      const result = await executeFunction();

      // Clear the status updates
      clearInterval(statusUpdateInterval);

      // Log the result structure for debugging
      console.log(`📊 Long-running result structure:`, {
        type: result?.type,
        hasResult: !!result?.result,
        resultLength: result?.result?.length,
        isError: result?.is_error,
      });

      // For long-running processes, just send the actual results directly
      if (result && result.type === 'result' && result.result) {
        // Process and send the assistant message immediately
        this.emit('assistantMessage', {
          sessionId,
          data: {
            type: 'assistant_response',
            content: [
              {
                type: 'text',
                text: result.result,
              },
            ],
            timestamp: new Date().toISOString(),
          },
          isComplete: true,
        });
      } else {
        console.error(`❌ Unexpected result type from long-running process:`, result?.type);
      }

      console.log(`✅ Long-running process completed for session ${sessionId}`);

      // Send push notification for task completion
      this.sendLongRunningCompletionNotification(sessionId, originalPrompt, false);
    } catch (error) {
      // Clear the status updates
      clearInterval(statusUpdateInterval);

      console.error(`❌ Long-running process failed for session ${sessionId}:`, error);

      // Send error notification
      this.emit('assistantMessage', {
        sessionId,
        data: {
          type: 'assistant_response',
          content: [
            {
              type: 'text',
              text: `❌ **Complex Request Failed**\n\nYour request: "${originalPrompt.substring(0, 80)}${originalPrompt.length > 80 ? '...' : ''}"\n\n🔍 **Error:** ${error.message}\n\n💡 **Suggestion:** Try breaking this into smaller, more specific requests.`,
            },
          ],
          timestamp: new Date().toISOString(),
        },
        isComplete: true,
      });

      // Also emit error through normal channels
      this.emit('streamError', {
        sessionId,
        error: error.message,
      });

      // Send push notification for task failure
      this.sendLongRunningCompletionNotification(sessionId, originalPrompt, true, error.message);
    }
  }

  /**
   * Send push notification when long-running task completes
   */
  async sendLongRunningCompletionNotification(
    sessionId,
    prompt,
    isError = false,
    errorMessage = null
  ) {
    // Extract project name from session ID (format: project_name_uuid)
    const sessionParts = sessionId.split('_');
    const projectName = sessionParts.slice(0, -1).join('_') || 'Project';

    // Device tokens are now managed via HTTP/push notification registration
    const deviceTokens = [];

    // Prepare notification data
    const notificationData = {
      sessionId,
      projectName,
      message: isError
        ? `Task failed: ${prompt.substring(0, 50)}...\n${errorMessage || 'Unknown error'}`
        : `Task completed: ${prompt.substring(0, 50)}...\nTap to view results`,
      totalChunks: 1,
      isLongRunningCompletion: true,
    };

    // Send notifications to all connected clients with improved retry logic
    const clientIds = deviceTokens.map(({ clientId }) => clientId);
    await pushNotificationService.sendToMultipleClients(clientIds, notificationData);
  }

  /**
   * Check if a command should be considered long-running
   */
  isLongRunningCommand(prompt) {
    const timeoutMs = AICLIConfig.calculateTimeoutForCommand(prompt);
    return timeoutMs > 300000; // > 5 minutes
  }

  /**
   * Get estimated completion time for a command in minutes
   */
  getEstimatedCompletionTime(prompt) {
    const timeoutMs = AICLIConfig.calculateTimeoutForCommand(prompt);
    return Math.round(timeoutMs / 60000);
  }
}
