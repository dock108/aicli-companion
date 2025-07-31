import { v4 as uuidv4 } from 'uuid';
import { pushNotificationService } from './push-notification.js';
import { messageQueueService } from './message-queue.js';

export function setupWebSocket(wss, aicliService, authToken) {
  const clients = new Map();

  // Make clients accessible globally for push notifications
  global.webSocketClients = clients;

  wss.on('connection', (ws, request) => {
    const clientId = uuidv4();
    const clientIP = request.socket.remoteAddress;
    const clientFamily = request.socket.remoteFamily;
    const userAgent = request.headers['user-agent'] || 'unknown';

    console.log(`WebSocket client connected: ${clientId} from ${clientIP} (${clientFamily})`);
    console.log(`   User-Agent: ${userAgent}`);
    console.log(`   Total clients: ${clients.size + 1}`);

    // Authentication check
    if (authToken) {
      const url = new URL(request.url, `http://${request.headers.host}`);
      const token =
        url.searchParams.get('token') || request.headers.authorization?.replace('Bearer ', '');

      if (!token || token !== authToken) {
        ws.close(1008, 'Authentication required');
        return;
      }
    }

    // Store client info
    clients.set(clientId, {
      ws,
      sessionIds: new Set(),
      isAlive: true,
      subscribedEvents: new Set(),
      connectedAt: new Date(),
      lastActivity: new Date(),
    });

    // Set up ping/pong for connection health
    ws.isAlive = true;
    ws.on('pong', () => {
      ws.isAlive = true;
      const client = clients.get(clientId);
      if (client) {
        client.lastActivity = new Date();
      }
    });

    // Check for queued messages when client connects
    const checkQueuedMessages = () => {
      console.log(`🔍 Checking for queued messages for client ${clientId}`);
      const clientInfo = clients.get(clientId);
      if (clientInfo && clientInfo.sessionIds.size > 0) {
        clientInfo.sessionIds.forEach((sessionId) => {
          const undeliveredMessages = messageQueueService.getUndeliveredMessages(
            sessionId,
            clientId
          );
          if (undeliveredMessages.length > 0) {
            console.log(
              `📬 Delivering ${undeliveredMessages.length} queued messages for session ${sessionId}`
            );

            // Send a notification about queued messages
            sendMessage(
              clientId,
              {
                type: 'queuedMessagesAvailable',
                requestId: null,
                timestamp: new Date().toISOString(),
                data: {
                  sessionId,
                  messageCount: undeliveredMessages.length,
                  oldestMessageAge: Date.now() - undeliveredMessages[0].timestamp.getTime(),
                },
              },
              clients
            );

            // Deliver each queued message
            const messageIds = [];
            undeliveredMessages.forEach((queuedMsg) => {
              sendMessage(clientId, queuedMsg.message, clients);
              messageIds.push(queuedMsg.id);
            });

            // Mark as delivered
            messageQueueService.markAsDelivered(messageIds, clientId);
          }
        });
      }
    };

    // Send welcome message
    getAICLICodeVersion()
      .then((aicliCodeVersion) => {
        sendMessage(
          clientId,
          {
            type: 'welcome',
            requestId: null,
            timestamp: new Date().toISOString(),
            data: {
              clientId,
              serverVersion: '1.0.0',
              aicliCodeVersion,
              capabilities: ['streaming', 'permissions', 'multiSession'],
              maxSessions: 5,
            },
          },
          clients
        );

        // Check for queued messages after welcome
        setTimeout(checkQueuedMessages, 100);
      })
      .catch((error) => {
        console.warn('Failed to get AICLI Code version:', error);
        sendMessage(
          clientId,
          {
            type: 'welcome',
            requestId: null,
            timestamp: new Date().toISOString(),
            data: {
              clientId,
              serverVersion: '1.0.0',
              aicliCodeVersion: null,
              capabilities: ['streaming', 'permissions', 'multiSession'],
              maxSessions: 5,
            },
          },
          clients
        );

        // Check for queued messages after welcome
        setTimeout(checkQueuedMessages, 100);
      });

    // Handle incoming messages
    ws.on('message', async (data) => {
      try {
        const rawMessage = data.toString();
        console.log(`🔍 Raw message from ${clientId}:`, rawMessage);

        const message = JSON.parse(rawMessage);
        console.log(`📨 Parsed message from ${clientId}:`, JSON.stringify(message, null, 2));

        // Update client activity
        const client = clients.get(clientId);
        if (client) {
          client.lastActivity = new Date();
        }

        // Validate message structure
        if (!message.type) {
          throw new Error('Message missing required field: type');
        }

        await handleWebSocketMessage(clientId, message, aicliService, clients);
      } catch (error) {
        console.error('WebSocket message error:', error);
        console.error('Failed to parse message:', data.toString());
        sendErrorMessage(clientId, null, 'INVALID_REQUEST', error.message, clients);
      }
    });

    // Handle client disconnect
    ws.on('close', (code, reason) => {
      const client = clients.get(clientId);
      const connectionDuration = client ? Date.now() - client.connectedAt.getTime() : 0;

      console.log(`WebSocket client disconnected: ${clientId} (${code}: ${reason})`);
      console.log(`   Connection duration: ${Math.round(connectionDuration / 1000)}s`);
      console.log(`   Active sessions: ${client?.sessionIds.size || 0}`);

      // Don't close sessions on disconnect - let them continue processing in background
      // Sessions will timeout naturally after inactivity period
      if (client) {
        console.log(`   Preserving ${client.sessionIds.size} AICLI sessions for background processing`);
        client.sessionIds.forEach((sessionId) => {
          console.log(`   Session ${sessionId} will continue in background`);
        });

        // Unregister device token (can re-register on reconnect)
        pushNotificationService.unregisterDevice(clientId);
      }

      clients.delete(clientId);
      console.log(`   Remaining clients: ${clients.size}`);
    });

    ws.on('error', (error) => {
      console.error(`WebSocket error for client ${clientId}:`, error);
    });
  });

  // Set up AICLI Code event listeners for rich message types
  aicliService.on('streamData', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ streamData event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'streamData',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: {
          sessionId: data.sessionId,
          streamType: determineStreamType(data.data),
          content: formatStreamContent(data.data),
          isComplete: data.isComplete || false,
          originalMessage: data.originalMessage,
        },
      },
      clients
    );
  });

  // Handle system initialization messages
  aicliService.on('systemInit', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ systemInit event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'systemInit',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: data.data,
      },
      clients
    );
  });

  // Handle assistant responses with rich content
  aicliService.on('assistantMessage', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ assistantMessage event missing data or sessionId');
      return;
    }
    console.log(`📢 Broadcasting assistantMessage for session ${data.sessionId}`);
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'assistantMessage',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: data.data,
      },
      clients
    );
  });

  // Handle tool usage notifications
  aicliService.on('toolUse', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ toolUse event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'toolUse',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: data.data,
      },
      clients
    );
  });

  // Handle tool results
  aicliService.on('toolResult', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ toolResult event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'toolResult',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: data.data,
      },
      clients
    );
  });

  // Handle conversation results
  aicliService.on('conversationResult', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ conversationResult event missing data or sessionId');
      return;
    }
    // Skip sending conversationResult to avoid duplicate messages
    // The content is already sent via streamChunk events
    console.log('📝 conversationResult received but not forwarded (using streamChunk instead)');
    // broadcastToSessionClients(
    //   data.sessionId,
    //   {
    //     type: 'conversationResult',
    //     requestId: null,
    //     timestamp: new Date().toISOString(),
    //     data: data.data,
    //   },
    //   clients
    // );
  });

  aicliService.on('streamError', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ streamError event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'error',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: {
          code: 'CLAUDE_ERROR',
          message: data.error,
          details: { sessionId: data.sessionId },
        },
      },
      clients
    );
  });

  aicliService.on('sessionClosed', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ sessionClosed event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'streamComplete',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: {
          sessionId: data.sessionId,
          finalResult: 'Session ended',
          duration: 0,
          cost: null,
          usage: null,
        },
      },
      clients
    );
  });

  aicliService.on('permissionRequired', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ permissionRequired event missing data or sessionId');
      return;
    }
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'permissionRequest',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: {
          sessionId: data.sessionId,
          prompt: data.prompt,
          options: data.options || ['y', 'n'],
          defaultOption: data.default || 'n',
          timeout: 30000,
        },
      },
      clients
    );
  });

  // Handle structured stream chunks
  aicliService.on('streamChunk', (data) => {
    if (!data) {
      console.warn('⚠️ streamChunk event received with undefined data');
      return;
    }

    const { sessionId, chunk, timestamp } = data;

    if (!sessionId || !chunk) {
      console.warn('⚠️ streamChunk event missing required fields:', { sessionId, chunk });
      return;
    }

    // Broadcast the chunk to connected clients
    broadcastToSessionClients(
      sessionId,
      {
        type: 'streamChunk',
        requestId: null,
        timestamp: timestamp || new Date().toISOString(),
        data: {
          sessionId,
          chunk: {
            id: chunk.id,
            type: chunk.type,
            content: chunk.content,
            isFinal: chunk.isFinal || false,
            metadata: {
              language: chunk.language,
              level: chunk.level,
              ...chunk,
            },
          },
        },
      },
      clients
    );

    // If this is the final chunk, send push notifications
    if (chunk.isFinal) {
      console.log(`🔔 Final chunk received for session ${sessionId}, sending push notifications`);

      // Find all clients subscribed to this session
      clients.forEach((client, clientId) => {
        if (client.sessionIds.has(sessionId) && client.deviceToken) {
          // Get project info from session
          const sessionParts = sessionId.split('_');
          const projectName = sessionParts[1] || 'Project';

          // Send push notification
          pushNotificationService.sendClaudeResponseNotification(clientId, {
            sessionId,
            projectName,
            message: chunk.content || 'Claude has responded',
            totalChunks: 1,
          });
        }
      });
    }
  });

  // Handle command progress for real-time updates
  aicliService.on('commandProgress', (data) => {
    if (!data || !data.sessionId) {
      console.warn('⚠️ commandProgress event missing data or sessionId');
      return;
    }

    const progressInfo = parseProgressFromOutput(data.data);

    if (progressInfo) {
      broadcastToSessionClients(
        data.sessionId,
        {
          type: 'progress',
          requestId: null,
          timestamp: new Date().toISOString(),
          data: {
            sessionId: data.sessionId,
            stage: progressInfo.stage,
            progress: progressInfo.progress,
            message: progressInfo.message,
            estimatedTimeRemaining: progressInfo.estimatedTimeRemaining,
          },
        },
        clients
      );
    }
  });

  // Health check ping interval - more frequent for better connection monitoring
  const pingInterval = setInterval(() => {
    clients.forEach((client, clientId) => {
      if (!client.isAlive) {
        console.log(`WebSocket client ${clientId} failed ping test, terminating connection`);
        client.ws.terminate();
        clients.delete(clientId);
        return;
      }
      // Don't fail clients that are actively processing commands
      const recentActivity = Date.now() - client.lastActivity.getTime();
      if (recentActivity < 30000) {
        // 30 seconds grace period for active clients
        console.log(
          `Skipping ping test for active client ${clientId} (last activity: ${Math.round(recentActivity / 1000)}s ago)`
        );
        return;
      }

      console.log(`Sending ping to client ${clientId}`);
      client.isAlive = false;
      client.ws.ping();
    });
  }, 15000); // Reduced from 30s to 15s for faster detection

  wss.on('close', () => {
    clearInterval(pingInterval);
    // Note: messageQueueService cleanup is handled by its own interval
  });
}

async function handleWebSocketMessage(clientId, message, aicliService, clients) {
  const { type, requestId, data } = message;

  try {
    switch (type) {
      case 'ask':
        await handleAskMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'streamStart':
        await handleStreamStartMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'streamSend':
        await handleStreamSendMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'streamClose':
        await handleStreamCloseMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'permission':
        await handlePermissionMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'ping':
        handlePingMessage(clientId, requestId, data, clients);
        break;

      case 'subscribe':
        handleSubscribeMessage(clientId, requestId, data, clients);
        break;

      case 'setWorkingDirectory':
        await handleSetWorkingDirectoryMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'aicliCommand':
        await handleAICLICommandMessage(clientId, requestId, data, aicliService, clients);
        break;

      case 'client_backgrounding':
        handleClientBackgroundingMessage(clientId, requestId, data, clients);
        break;

      case 'registerDevice':
        handleRegisterDeviceMessage(clientId, requestId, data, clients);
        break;

      default:
        sendErrorMessage(
          clientId,
          requestId,
          'INVALID_REQUEST',
          `Unknown message type: ${type}`,
          clients
        );
    }
  } catch (error) {
    console.error(`Error handling message type ${type}:`, error);
    sendErrorMessage(clientId, requestId, 'INTERNAL_ERROR', error.message, clients);
  }
}

async function handleAskMessage(clientId, requestId, data, aicliService, clients) {
  const { prompt, workingDirectory, options } = data;

  console.log(`🤖 Processing ask message for client ${clientId}`);
  console.log(`   Prompt: "${prompt}"`);
  console.log(`   Working dir: ${workingDirectory || process.cwd()}`);

  try {
    const response = await aicliService.sendPrompt(prompt, {
      format: options?.format || 'json',
      workingDirectory: workingDirectory || process.cwd(),
      timeout: options?.timeout || 60000,
    });

    console.log(`✅ Ask completed for client ${clientId}`);

    sendMessage(
      clientId,
      {
        type: 'askResponse',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          success: true,
          response,
          error: null,
        },
      },
      clients
    );
  } catch (error) {
    console.log(`❌ Ask failed for client ${clientId}: ${error.message}`);

    sendMessage(
      clientId,
      {
        type: 'askResponse',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          success: false,
          response: null,
          error: error.message,
        },
      },
      clients
    );
  }
}

async function handleStreamStartMessage(clientId, requestId, data, aicliService, clients) {
  const { prompt, workingDirectory, options } = data;

  try {
    const sessionId = uuidv4();
    const finalWorkingDirectory =
      workingDirectory || aicliService.defaultWorkingDirectory || process.cwd();

    console.log(`🚀 Starting AICLI conversation session ${sessionId}`);
    console.log(`   Working directory: ${finalWorkingDirectory}`);
    console.log(
      `   Initial prompt: "${prompt?.substring(0, 100)}${prompt?.length > 100 ? '...' : ''}"`
    );

    const _response = await aicliService.sendStreamingPrompt(prompt, {
      sessionId,
      workingDirectory: finalWorkingDirectory,
    });

    // Associate this session with the client
    const client = clients.get(clientId);
    if (client) {
      client.sessionIds.add(sessionId);
      // Track this client-session association for message delivery
      messageQueueService.trackSessionClient(sessionId, clientId);
    }

    sendMessage(
      clientId,
      {
        type: 'streamStarted',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          sessionId,
          sessionName: options?.sessionName || null,
          workingDirectory: workingDirectory || process.cwd(),
        },
      },
      clients
    );
  } catch (error) {
    sendErrorMessage(clientId, requestId, 'CLAUDE_ERROR', error.message, clients);
  }
}

async function handleStreamSendMessage(clientId, requestId, data, aicliService, clients) {
  const { sessionId, prompt } = data;

  try {
    await aicliService.sendToExistingSession(sessionId, prompt);

    sendMessage(
      clientId,
      {
        type: 'streamSent',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          sessionId,
          success: true,
        },
      },
      clients
    );
  } catch (error) {
    sendErrorMessage(clientId, requestId, 'SESSION_ERROR', error.message, clients, { sessionId });
  }
}

async function handleStreamCloseMessage(clientId, requestId, data, aicliService, clients) {
  const { sessionId, reason } = data;

  try {
    await aicliService.closeSession(sessionId);

    // Remove session from client
    const client = clients.get(clientId);
    if (client) {
      client.sessionIds.delete(sessionId);
    }

    sendMessage(
      clientId,
      {
        type: 'streamClosed',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          sessionId,
          reason: reason || 'user_requested',
        },
      },
      clients
    );
  } catch (error) {
    sendErrorMessage(clientId, requestId, 'SESSION_ERROR', error.message, clients, { sessionId });
  }
}

async function handlePermissionMessage(clientId, requestId, data, aicliService, clients) {
  const { sessionId, response, _remember } = data;

  try {
    await aicliService.handlePermissionPrompt(sessionId, response);

    sendMessage(
      clientId,
      {
        type: 'permissionHandled',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          sessionId,
          response,
          success: true,
        },
      },
      clients
    );
  } catch (error) {
    sendErrorMessage(clientId, requestId, 'PERMISSION_ERROR', error.message, clients, {
      sessionId,
    });
  }
}

function handlePingMessage(clientId, requestId, data, clients) {
  sendMessage(
    clientId,
    {
      type: 'pong',
      requestId,
      timestamp: new Date().toISOString(),
      data: {
        serverTime: new Date().toISOString(),
      },
    },
    clients
  );
}

function handleSubscribeMessage(clientId, requestId, data, clients) {
  const { events, sessionIds } = data;
  const client = clients.get(clientId);

  if (client) {
    // Subscribe to events
    if (events && Array.isArray(events)) {
      events.forEach((event) => client.subscribedEvents.add(event));
    }

    // Associate sessions with this client
    if (sessionIds && Array.isArray(sessionIds)) {
      sessionIds.forEach((sessionId) => {
        client.sessionIds.add(sessionId);
        // Track this client-session association for message delivery
        messageQueueService.trackSessionClient(sessionId, clientId);
        console.log(`✅ Client ${clientId} subscribed to session ${sessionId}`);
      });
    }

    sendMessage(
      clientId,
      {
        type: 'subscribed',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          events: events || [],
          sessionIds: sessionIds || [],
          success: true,
        },
      },
      clients
    );

    // Check for queued messages after subscription
    if (sessionIds && sessionIds.length > 0) {
      setTimeout(() => {
        sessionIds.forEach((sessionId) => {
          const undeliveredMessages = messageQueueService.getUndeliveredMessages(
            sessionId,
            clientId
          );
          if (undeliveredMessages.length > 0) {
            console.log(
              `📬 Delivering ${undeliveredMessages.length} queued messages for session ${sessionId}`
            );

            // Send a notification about queued messages
            sendMessage(
              clientId,
              {
                type: 'queuedMessagesAvailable',
                requestId: null,
                timestamp: new Date().toISOString(),
                data: {
                  sessionId,
                  messageCount: undeliveredMessages.length,
                  oldestMessageAge: Date.now() - undeliveredMessages[0].timestamp.getTime(),
                },
              },
              clients
            );

            // Deliver each queued message
            const messageIds = [];
            undeliveredMessages.forEach((queuedMsg) => {
              sendMessage(clientId, queuedMsg.message, clients);
              messageIds.push(queuedMsg.id);
            });

            // Mark as delivered
            messageQueueService.markAsDelivered(messageIds, clientId);
          }
        });
      }, 100);
    }
  }
}

function handleClientBackgroundingMessage(clientId, requestId, data, clients) {
  const sessionId = data?.sessionId || null;
  const client = clients.get(clientId);

  if (client) {
    console.log(`📱 Client ${clientId} entering background mode`);
    if (sessionId) {
      console.log(`   Associated with session: ${sessionId}`);
    }

    // Mark client as backgrounded but keep connection
    client.isBackgrounded = true;
    client.lastActivity = new Date();

    // Send acknowledgment
    sendMessage(
      clientId,
      {
        type: 'backgroundingAcknowledged',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          sessionId: sessionId || '',
          success: true,
        },
      },
      clients
    );
  }
}

function handleRegisterDeviceMessage(clientId, requestId, data, clients) {
  const { token, platform } = data || {};
  const client = clients.get(clientId);

  if (!client) {
    sendErrorMessage(clientId, requestId, 'CLIENT_ERROR', 'Client not found', clients);
    return;
  }

  if (!token) {
    sendErrorMessage(clientId, requestId, 'INVALID_REQUEST', 'Device token is required', clients);
    return;
  }

  try {
    // Register the device token
    pushNotificationService.registerDevice(clientId, token, platform || 'ios');

    // Store token info on client
    client.deviceToken = token;
    client.platform = platform || 'ios';

    sendMessage(
      clientId,
      {
        type: 'deviceRegistered',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          success: true,
          message: 'Device token registered successfully',
        },
      },
      clients
    );
  } catch (error) {
    console.error('Error registering device:', error);
    sendErrorMessage(clientId, requestId, 'REGISTRATION_ERROR', error.message, clients);
  }
}

async function handleSetWorkingDirectoryMessage(clientId, requestId, data, aicliService, clients) {
  const { workingDirectory } = data;

  try {
    // Validate input
    if (!workingDirectory || typeof workingDirectory !== 'string') {
      sendErrorMessage(
        clientId,
        requestId,
        'INVALID_INPUT',
        'Working directory must be a valid string',
        clients
      );
      return;
    }

    // Validate the directory exists and is safe
    const fs = await import('fs');
    const path = await import('path');

    const resolvedPath = path.resolve(workingDirectory);

    // Security checks for path traversal
    const normalizedPath = path.normalize(resolvedPath);

    // Prevent access to sensitive system directories
    const forbiddenPaths = [
      '/etc/',
      '/proc/',
      '/sys/',
      '/dev/',
      '/root/',
      '/usr/bin/',
      '/sbin/',
      '/bin/',
      '/boot/',
      'C:\\Windows\\',
      'C:\\Program Files\\',
      'C:\\Program Files (x86)\\',
      'C:\\System32\\',
    ];

    for (const forbidden of forbiddenPaths) {
      if (normalizedPath.toLowerCase().includes(forbidden.toLowerCase())) {
        sendErrorMessage(
          clientId,
          requestId,
          'FORBIDDEN_PATH',
          'Access to system directories is not allowed',
          clients
        );
        return;
      }
    }

    // Prevent path traversal attacks
    if (normalizedPath.includes('..') || normalizedPath.includes('~')) {
      sendErrorMessage(
        clientId,
        requestId,
        'INVALID_PATH',
        'Path traversal is not allowed',
        clients
      );
      return;
    }

    // Ensure the path is absolute and within allowed bounds
    if (!path.isAbsolute(normalizedPath)) {
      sendErrorMessage(clientId, requestId, 'INVALID_PATH', 'Path must be absolute', clients);
      return;
    }

    // Check if directory exists
    if (!fs.existsSync(normalizedPath)) {
      sendErrorMessage(
        clientId,
        requestId,
        'DIRECTORY_NOT_FOUND',
        `Directory does not exist: ${normalizedPath}`,
        clients
      );
      return;
    }

    // Check if it's actually a directory
    const stats = fs.statSync(normalizedPath);
    if (!stats.isDirectory()) {
      sendErrorMessage(
        clientId,
        requestId,
        'NOT_A_DIRECTORY',
        `Path is not a directory: ${normalizedPath}`,
        clients
      );
      return;
    }

    // Check directory permissions
    try {
      fs.accessSync(normalizedPath, fs.constants.R_OK | fs.constants.W_OK);
    } catch (error) {
      sendErrorMessage(
        clientId,
        requestId,
        'PERMISSION_DENIED',
        'Insufficient permissions for directory access',
        clients
      );
      return;
    }

    // Update the default working directory for future sessions
    aicliService.defaultWorkingDirectory = normalizedPath;

    sendMessage(
      clientId,
      {
        type: 'workingDirectorySet',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          workingDirectory: normalizedPath,
          success: true,
        },
      },
      clients
    );
  } catch (error) {
    console.error('Working directory validation error:', error);
    sendErrorMessage(
      clientId,
      requestId,
      'WORKING_DIRECTORY_ERROR',
      'Failed to validate working directory',
      clients
    );
  }
}

async function handleAICLICommandMessage(clientId, requestId, data, aicliService, clients) {
  const { command, projectPath, sessionId } = data;

  console.log(`📬 Received aicliCommand from client ${clientId}`);
  console.log(`   Command: "${command}"`);
  console.log(`   Session ID: ${sessionId}`);
  console.log(`   Project Path: ${projectPath}`);

  try {
    // Validate input
    if (!command || typeof command !== 'string') {
      sendErrorMessage(
        clientId,
        requestId,
        'INVALID_INPUT',
        'Command must be a valid string',
        clients
      );
      return;
    }

    if (!sessionId || typeof sessionId !== 'string') {
      sendErrorMessage(clientId, requestId, 'INVALID_INPUT', 'Session ID is required', clients);
      return;
    }

    console.log(`🤖 Sending command to AICLI session ${sessionId}: ${command.substring(0, 50)}...`);

    // Check if session exists first
    if (!aicliService.hasSession(sessionId)) {
      const errorMsg = `Session ${sessionId} does not exist. Please start a AICLI CLI session first.`;
      console.error(`❌ ${errorMsg}`);
      sendErrorMessage(clientId, requestId, 'SESSION_NOT_FOUND', errorMsg, clients, { sessionId });
      return;
    }

    // Associate this client with the session BEFORE executing the command
    const client = clients.get(clientId);
    if (client) {
      console.log(
        `🔗 Associating client ${clientId} with session ${sessionId} BEFORE command execution`
      );
      console.log(`   Client sessions before: [${Array.from(client.sessionIds).join(', ')}]`);
      client.sessionIds.add(sessionId);
      console.log(`   Client sessions after: [${Array.from(client.sessionIds).join(', ')}]`);

      // Track this client-session association
      messageQueueService.trackSessionClient(sessionId, clientId);

      // Check for any queued messages for this session
      const undeliveredMessages = messageQueueService.getUndeliveredMessages(sessionId, clientId);
      if (undeliveredMessages.length > 0) {
        console.log(
          `📬 Found ${undeliveredMessages.length} queued messages for newly associated session ${sessionId}`
        );

        // Deliver queued messages with a slight delay to ensure client is ready
        setTimeout(() => {
          const messageIds = [];
          undeliveredMessages.forEach((queuedMsg) => {
            console.log(
              `📤 Delivering queued message ${queuedMsg.id} (type: ${queuedMsg.message.type})`
            );
            sendMessage(clientId, queuedMsg.message, clients);
            messageIds.push(queuedMsg.id);
          });
          messageQueueService.markAsDelivered(messageIds, clientId);
        }, 500);
      }
    } else {
      console.error(
        `❌ Client ${clientId} not found when trying to associate with session ${sessionId}`
      );
      sendErrorMessage(
        clientId,
        requestId,
        'CLIENT_ERROR',
        'Client not found for session association',
        clients,
        { sessionId }
      );
      return;
    }

    // Verify client is now associated with the session
    console.log(`🔍 Verifying client association before command execution:`);
    console.log(
      `   Client ${clientId} has sessions: [${Array.from(client.sessionIds).join(', ')}]`
    );
    console.log(`   Client is subscribed to target session: ${client.sessionIds.has(sessionId)}`);

    // Send the command to the AICLI CLI session
    try {
      const result = await aicliService.sendToExistingSession(sessionId, command);
      console.log(`✅ Command sent successfully:`, result);

      // If this was a long-running operation that started in background,
      // send immediate response to clear iOS loading state
      if (result && result.subtype === 'long_running_started') {
        console.log(`🔄 Long-running operation started, sending immediate response to client`);
        // The background process will send the actual results when complete
        // iOS app should exit loading state now
      }
    } catch (error) {
      console.error(`❌ Failed to send command to AICLI session ${sessionId}:`, error.message);
      throw error;
    }

    // The actual response will come through the event listeners (assistantMessage, etc.)
  } catch (error) {
    console.error('Error handling AICLI command:', error);

    // Create user-friendly error messages based on error type
    let userFriendlyMessage = error.message || 'Failed to send command to AICLI';
    let suggestions = [];

    if (error.message.includes('timed out')) {
      if (error.message.includes('silence')) {
        userFriendlyMessage =
          'AICLI CLI stopped responding during processing. This can happen with very complex requests.';
        suggestions = [
          'Try breaking your request into smaller, more specific parts',
          'Use simpler commands to test if AICLI CLI is working',
          'Check if the request requires too many resources',
        ];
      } else {
        userFriendlyMessage = 'AICLI CLI took too long to complete your request.';
        suggestions = [
          'Try using a simpler or more specific command',
          'Break complex requests into smaller parts',
          'Try again - sometimes complex operations need multiple attempts',
        ];
      }
    } else if (error.message.includes('not found') || error.message.includes('SESSION_NOT_FOUND')) {
      userFriendlyMessage = 'The AICLI CLI session was not found or has expired.';
      suggestions = [
        'Try refreshing the chat to create a new session',
        'Make sure the server is running properly',
      ];
    } else if (error.message.includes('permission') || error.message.includes('access')) {
      userFriendlyMessage = 'AICLI CLI does not have the necessary permissions.';
      suggestions = [
        'Check file and directory permissions',
        'Make sure AICLI CLI is properly installed',
        'Try running the server with appropriate permissions',
      ];
    }

    // Include suggestions in the error details if we have any
    const errorDetails =
      suggestions.length > 0
        ? {
            originalError: error.message,
            suggestions,
            sessionId,
          }
        : { sessionId };

    sendErrorMessage(
      clientId,
      requestId,
      'COMMAND_ERROR',
      userFriendlyMessage,
      clients,
      errorDetails
    );
  }
}

function sendMessage(clientId, message, clients) {
  const client = clients.get(clientId);
  if (!client) {
    console.warn(`Attempted to send message to non-existent client: ${clientId}`);
    return false;
  }

  const ws = client.ws;
  if (ws.readyState === 1) {
    // WebSocket.OPEN
    try {
      ws.send(JSON.stringify(message));
      client.lastActivity = new Date();
      return true;
    } catch (error) {
      console.error(`Failed to send message to client ${clientId}:`, error);
      // Remove invalid client
      clients.delete(clientId);
      return false;
    }
  } else {
    console.warn(`WebSocket not open for client ${clientId}, readyState: ${ws.readyState}`);
    if (ws.readyState === 3) {
      // WebSocket.CLOSED
      clients.delete(clientId);
    }
    return false;
  }
}

function sendErrorMessage(clientId, requestId, code, message, clients, details = {}) {
  sendMessage(
    clientId,
    {
      type: 'error',
      requestId,
      timestamp: new Date().toISOString(),
      data: {
        code,
        message,
        details,
      },
    },
    clients
  );
}

function broadcastToSessionClients(sessionId, message, clients) {
  console.log(`📡 Broadcasting ${message.type} to session ${sessionId}`);
  console.log(`   Total clients: ${clients.size}`);
  console.log(`   Message data:`, JSON.stringify(message, null, 2).substring(0, 500));

  let sentCount = 0;
  let failedCount = 0;
  let clientsWithSession = 0;

  clients.forEach((client, clientId) => {
    console.log(`   Checking client ${clientId}:`);
    console.log(`     Has sessions: [${Array.from(client.sessionIds).join(', ')}]`);
    console.log(`     Target session: ${sessionId}`);
    console.log(`     Has target session: ${client.sessionIds.has(sessionId)}`);
    console.log(`     WebSocket state: ${client.ws.readyState}`);

    if (client.sessionIds.has(sessionId)) {
      clientsWithSession++;
      console.log(`   ✅ Sending to client ${clientId}`);
      const success = sendMessage(clientId, message, clients);
      if (success) {
        sentCount++;
        console.log(`   📤 Successfully sent to client ${clientId}`);
      } else {
        failedCount++;
        console.log(`   ❌ Failed to send to client ${clientId}`);
      }
    } else {
      console.log(`   ⏭️  Skipping client ${clientId} (not subscribed to session)`);
    }
  });

  console.log(`📊 Broadcast summary for session ${sessionId}:`);
  console.log(`   Clients with session: ${clientsWithSession}`);
  console.log(`   Messages sent: ${sentCount}`);
  console.log(`   Messages failed: ${failedCount}`);

  if (clientsWithSession === 0) {
    console.warn(`⚠️  No clients subscribed to session ${sessionId}!`);

    // Queue the message for later delivery
    if (message.type !== 'ping' && message.type !== 'pong') {
      console.log(`📥 Queueing message for session ${sessionId} (no clients connected)`);
      messageQueueService.queueMessage(sessionId, message, {
        ttl: 86400000, // 24 hours
      });

      // Check if this is a final message or important update that should trigger a push notification
      if (message.type === 'streamChunk' && message.data?.chunk?.isFinal) {
        console.log(`🔔 Final chunk received with no clients - should send push notification`);
        // Push notification is already handled in the streamChunk event handler
      } else if (message.type === 'assistantMessage' && message.data?.isComplete) {
        console.log(`🔔 Complete assistant message with no clients - queueing for later delivery`);
      }
    }
  }

  if (failedCount > 0) {
    console.warn(`❌ Broadcast to session ${sessionId}: ${sentCount} sent, ${failedCount} failed`);
  }
}

function determineStreamType(data) {
  if (data.type === 'assistant') {
    return 'assistant_message';
  } else if (data.type === 'user') {
    return 'user_message';
  } else if (data.type === 'system') {
    return 'system_message';
  } else {
    return 'unknown';
  }
}

function formatStreamContent(data) {
  if (data.message && data.message.content) {
    const content = data.message.content;

    if (Array.isArray(content)) {
      // Handle multiple content blocks
      for (const block of content) {
        if (block.type === 'text') {
          return {
            type: 'text',
            text: block.text,
            data: null,
          };
        } else if (block.type === 'tool_use') {
          return {
            type: 'tool_use',
            text: null,
            data: {
              tool_name: block.name,
              tool_input: block.input,
            },
          };
        }
      }
    } else if (typeof content === 'string') {
      return {
        type: 'text',
        text: content,
        data: null,
      };
    }
  }

  // Fallback
  return {
    type: 'text',
    text: data.result || JSON.stringify(data),
    data: null,
  };
}

async function getAICLICodeVersion() {
  try {
    const { exec } = await import('child_process');
    const { promisify } = await import('util');
    const execAsync = promisify(exec);

    const { stdout } = await execAsync('claude --version');
    return stdout.trim();
  } catch (error) {
    return null;
  }
}

function parseProgressFromOutput(output) {
  if (!output || typeof output !== 'string') return null;

  // Parse tool usage indicators
  const toolUseMatch = output.match(/Using tool: (\w+)/i);
  if (toolUseMatch) {
    return {
      stage: 'tool_use',
      progress: null,
      message: `Using ${toolUseMatch[1]} tool`,
      estimatedTimeRemaining: null,
    };
  }

  // Parse file operations
  const fileOpMatch = output.match(/(Reading|Writing|Creating|Analyzing) (.+)/i);
  if (fileOpMatch) {
    return {
      stage: 'file_operation',
      progress: null,
      message: `${fileOpMatch[1]} ${fileOpMatch[2]}`,
      estimatedTimeRemaining: null,
    };
  }

  // Parse search operations
  const searchMatch = output.match(/Searching (\d+) files?/i);
  if (searchMatch) {
    return {
      stage: 'searching',
      progress: null,
      message: `Searching ${searchMatch[1]} files`,
      estimatedTimeRemaining: null,
    };
  }

  // Parse bash command execution
  const bashMatch = output.match(/Executing command: (.+)/i);
  if (bashMatch) {
    return {
      stage: 'command_execution',
      progress: null,
      message: `Running: ${bashMatch[1].substring(0, 50)}${bashMatch[1].length > 50 ? '...' : ''}`,
      estimatedTimeRemaining: null,
    };
  }

  // Parse thinking/analyzing indicators
  if (
    output.includes('analyzing') ||
    output.includes('thinking') ||
    output.includes('considering')
  ) {
    return {
      stage: 'analyzing',
      progress: null,
      message: 'Analyzing request...',
      estimatedTimeRemaining: null,
    };
  }

  // Parse completion indicators
  if (output.includes('completed') || output.includes('finished') || output.includes('done')) {
    return {
      stage: 'completing',
      progress: 1.0,
      message: 'Finishing up...',
      estimatedTimeRemaining: null,
    };
  }

  return null;
}
