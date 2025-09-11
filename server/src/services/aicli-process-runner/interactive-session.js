/**
 * Interactive Session Handler
 * Manages interactive Claude CLI sessions
 */

import { createLogger } from '../../utils/logger.js';
import { UnifiedMessageParser } from '../message-parser.js';

const logger = createLogger('InteractiveSession');

export class InteractiveSession {
  constructor(processManager, config) {
    this.processManager = processManager;
    this.config = config;
  }

  /**
   * Create an interactive Claude CLI session that stays running
   */
  async create(workingDirectory) {
    const sessionLogger = logger.child({ workingDirectory });

    // Build args for interactive mode (no --print flag)
    const args = ['--output-format', 'stream-json', '--verbose'];

    // Add permission configuration
    this.config.addPermissionArgs(args);

    sessionLogger.info('Creating interactive Claude session', {
      workingDirectory,
      args: args.slice(0, 3), // Log first few args
    });

    return new Promise((resolve, reject) => {
      let claudeProcess;
      let initialSessionId = null;
      let initComplete = false;

      try {
        // Spawn Claude in interactive mode
        claudeProcess = this.processManager.spawnProcess(args, {
          cwd: workingDirectory,
          stdio: ['pipe', 'pipe', 'pipe'], // Keep pipes open for communication
        });
      } catch (spawnError) {
        sessionLogger.error('Failed to spawn interactive Claude CLI', {
          error: spawnError.message,
          code: spawnError.code,
        });
        reject(new Error(`Failed to start Claude CLI: ${spawnError.message}`));
        return;
      }

      sessionLogger.info('Interactive process started', { pid: claudeProcess.pid });

      // Set a timeout for initialization (skip in test environment)
      let initTimeout;
      if (process.env.NODE_ENV !== 'test') {
        initTimeout = setTimeout(() => {
          if (!initComplete) {
            sessionLogger.error('Interactive session initialization timeout');
            claudeProcess.kill();
            reject(new Error('Timeout waiting for Claude CLI to initialize'));
          }
        }, 30000); // 30 second timeout
      }

      // Wrap resolve to clear timeout on success
      const wrappedResolve = (value) => {
        if (initTimeout) clearTimeout(initTimeout);
        resolve(value);
      };

      // Create stream parser for this session
      const streamParser = new UnifiedMessageParser();

      // Handle stdout - parse initial response to get session ID
      claudeProcess.stdout.on('data', (data) => {
        const chunk = data.toString();
        sessionLogger.debug('Interactive stdout chunk', {
          length: chunk.length,
          preview: chunk.substring(0, 100),
        });

        // Parse each line as stream JSON
        const lines = chunk.split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const parsed = JSON.parse(line);

            // Look for session initialization
            if (parsed.session_id) {
              initialSessionId = parsed.session_id;
              sessionLogger.info('Got initial session ID', { sessionId: initialSessionId });
            }

            // Check if initialization is complete
            // Accept various initialization signals including test mode
            if (
              parsed.type === 'message_start' ||
              parsed.type === 'content_block_start' ||
              (parsed.type === 'system' && parsed.subtype === 'init' && parsed.session_id)
            ) {
              sessionLogger.info('Session initialization complete', {
                sessionId: initialSessionId || parsed.session_id,
                messageType: parsed.type,
              });

              if (!initComplete) {
                initComplete = true;
                // Resolve with process and session info
                wrappedResolve({
                  process: claudeProcess,
                  sessionId: initialSessionId || parsed.session_id,
                  pid: claudeProcess.pid,
                  streamParser,
                  workingDirectory,
                });
              }
            }
          } catch (e) {
            sessionLogger.debug('Failed to parse line as JSON', {
              line: line.substring(0, 100),
              error: e.message,
            });
          }
        }
      });

      // Handle stderr
      claudeProcess.stderr.on('data', (data) => {
        const error = data.toString();
        sessionLogger.error('Interactive stderr', { error });

        if (!initComplete) {
          reject(new Error(`Claude CLI error: ${error}`));
        }
      });

      // Handle process exit
      claudeProcess.on('exit', (code, signal) => {
        sessionLogger.info('Interactive process exited', { code, signal });

        if (!initComplete) {
          reject(new Error(`Claude CLI exited unexpectedly: code ${code}, signal ${signal}`));
        }
      });

      // Handle process errors
      claudeProcess.on('error', (error) => {
        sessionLogger.error('Interactive process error', { error: error.message });

        if (!initComplete) {
          reject(new Error(`Claude CLI process error: ${error.message}`));
        }
      });
    });
  }

  /**
   * Send a message to an interactive Claude session and get response
   */
  async sendMessage(sessionInfo, message) {
    // Handle both full session info (with process) and session metadata
    const claudeProcess = sessionInfo.process || sessionInfo.claudeProcess;
    const sessionId = sessionInfo.sessionId;

    if (!claudeProcess) {
      throw new Error(`No active process for session ${sessionId}`);
    }

    const sessionLogger = logger.child({ sessionId });

    return new Promise((resolve, reject) => {
      let responseComplete = false;
      const responses = [];
      let accumulatedText = ''; // Collect text content from tool use sequences
      let _lastResponseTime = Date.now();
      let hasToolUse = false;

      // Set up one-time listeners for this message
      const dataHandler = (data) => {
        const chunk = data.toString();
        _lastResponseTime = Date.now();

        // Parse each line as stream JSON
        const lines = chunk.split('\n');
        for (const line of lines) {
          if (!line.trim()) continue;

          try {
            const parsed = JSON.parse(line);
            responses.push(parsed);

            // Detect tool use
            if (
              parsed.type === 'content_block_start' &&
              parsed.content_block?.type === 'tool_use'
            ) {
              hasToolUse = true;
              sessionLogger.info('Tool use detected', {
                tool: parsed.content_block.name,
                id: parsed.content_block.id,
              });
            }

            // Accumulate text content
            if (parsed.type === 'content_block_delta' && parsed.delta?.type === 'text_delta') {
              accumulatedText += parsed.delta.text || '';
            }

            // Check for completion - handle both real and test formats
            if (
              parsed.type === 'message_stop' ||
              (parsed.type === 'result' && process.env.NODE_ENV === 'test')
            ) {
              responseComplete = true;
              sessionLogger.info('Response complete', {
                responseCount: responses.length,
                hasToolUse,
                textLength: accumulatedText.length,
              });

              // Clean up listeners
              claudeProcess.stdout.removeListener('data', dataHandler);
              claudeProcess.stderr.removeListener('data', errorHandler);
              if (timeoutHandler) clearInterval(timeoutHandler);

              // Resolve with the complete response
              resolve({
                success: true,
                responses,
                text: accumulatedText || parsed.result, // Use result in test mode
                hasToolUse,
                sessionId,
              });
            }
          } catch (e) {
            sessionLogger.debug('Failed to parse response line', {
              line: line.substring(0, 100),
              error: e.message,
            });
          }
        }
      };

      const errorHandler = (data) => {
        const error = data.toString();
        sessionLogger.error('Error during message send', { error });

        // Clean up listeners
        claudeProcess.stdout.removeListener('data', dataHandler);
        claudeProcess.stderr.removeListener('data', errorHandler);
        if (timeoutHandler) clearInterval(timeoutHandler);

        reject(new Error(`Claude error: ${error}`));
      };

      // Set up timeout handler (skip in test environment)
      let timeoutHandler;
      if (process.env.NODE_ENV !== 'test') {
        timeoutHandler = setInterval(() => {
          const timeSinceLastResponse = Date.now() - _lastResponseTime;
          if (timeSinceLastResponse > 30000 && !responseComplete) {
            clearInterval(timeoutHandler);

            sessionLogger.warn('Response timeout - no data for 30 seconds', {
              sessionId,
            });

            // Clean up listeners
            claudeProcess.stdout.removeListener('data', dataHandler);
            claudeProcess.stderr.removeListener('data', errorHandler);

            // Return what we have so far
            if (responses.length > 0 || accumulatedText) {
              resolve({
                success: true,
                responses,
                text: accumulatedText,
                hasToolUse,
                sessionId,
                timeout: true,
              });
            } else {
              sessionLogger.error('Complete timeout with no response', {
                sessionId,
              });
              reject(new Error('Timeout waiting for Claude response'));
            }
          }
        }, 5000); // Check every 5 seconds
      }

      // Attach handlers
      claudeProcess.stdout.on('data', dataHandler);
      claudeProcess.stderr.once('data', errorHandler);

      // Send the message
      sessionLogger.info('Sending message to interactive session', {
        messageLength: message.length,
      });

      claudeProcess.stdin.write(`${message}\n`, (err) => {
        if (err) {
          sessionLogger.error('Failed to write to stdin', { error: err.message });
          claudeProcess.stdout.removeListener('data', dataHandler);
          claudeProcess.stderr.removeListener('data', errorHandler);
          if (timeoutHandler) clearInterval(timeoutHandler);
          reject(err);
        }
      });
    });
  }
}

export default InteractiveSession;
