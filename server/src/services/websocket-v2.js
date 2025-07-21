import { v4 as uuidv4 } from 'uuid';

export function setupWebSocket(wss, claudeService, authToken) {
  const clients = new Map();

  wss.on('connection', (ws, request) => {
    const clientId = uuidv4();
    console.log(`WebSocket client connected: ${clientId}`);

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
    });

    // Set up ping/pong for connection health
    ws.isAlive = true;
    ws.on('pong', () => {
      ws.isAlive = true;
    });

    // Send welcome message
    getClaudeCodeVersion()
      .then((claudeCodeVersion) => {
        sendMessage(
          clientId,
          {
            type: 'welcome',
            requestId: null,
            timestamp: new Date().toISOString(),
            data: {
              clientId,
              serverVersion: '1.0.0',
              claudeCodeVersion,
              capabilities: ['streaming', 'permissions', 'multiSession'],
              maxSessions: 5,
            },
          },
          clients
        );
      })
      .catch((error) => {
        console.warn('Failed to get Claude Code version:', error);
        sendMessage(
          clientId,
          {
            type: 'welcome',
            requestId: null,
            timestamp: new Date().toISOString(),
            data: {
              clientId,
              serverVersion: '1.0.0',
              claudeCodeVersion: null,
              capabilities: ['streaming', 'permissions', 'multiSession'],
              maxSessions: 5,
            },
          },
          clients
        );
      });

    // Handle incoming messages
    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data.toString());
        console.log(`📨 Received message from ${clientId}: ${message.type}`);
        await handleWebSocketMessage(clientId, message, claudeService, clients);
      } catch (error) {
        console.error('WebSocket message error:', error);
        sendErrorMessage(clientId, null, 'INVALID_REQUEST', error.message, clients);
      }
    });

    // Handle client disconnect
    ws.on('close', (code, reason) => {
      console.log(`WebSocket client disconnected: ${clientId} (${code}: ${reason})`);

      // Clean up any active sessions for this client
      const client = clients.get(clientId);
      if (client) {
        client.sessionIds.forEach((sessionId) => {
          claudeService.closeSession(sessionId);
        });
      }

      clients.delete(clientId);
    });

    ws.on('error', (error) => {
      console.error(`WebSocket error for client ${clientId}:`, error);
    });
  });

  // Set up Claude Code event listeners for rich message types
  claudeService.on('streamData', (data) => {
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
  claudeService.on('systemInit', (data) => {
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
  claudeService.on('assistantMessage', (data) => {
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
  claudeService.on('toolUse', (data) => {
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
  claudeService.on('toolResult', (data) => {
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
  claudeService.on('conversationResult', (data) => {
    broadcastToSessionClients(
      data.sessionId,
      {
        type: 'conversationResult',
        requestId: null,
        timestamp: new Date().toISOString(),
        data: data.data,
      },
      clients
    );
  });

  claudeService.on('streamError', (data) => {
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

  claudeService.on('sessionClosed', (data) => {
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

  claudeService.on('permissionRequired', (data) => {
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

  // Health check ping interval
  const pingInterval = setInterval(() => {
    clients.forEach((client, clientId) => {
      if (!client.isAlive) {
        client.ws.terminate();
        clients.delete(clientId);
        return;
      }

      client.isAlive = false;
      client.ws.ping();
    });
  }, 30000);

  wss.on('close', () => {
    clearInterval(pingInterval);
  });
}

async function handleWebSocketMessage(clientId, message, claudeService, clients) {
  const { type, requestId, data } = message;

  try {
    switch (type) {
      case 'ask':
        await handleAskMessage(clientId, requestId, data, claudeService, clients);
        break;

      case 'streamStart':
        await handleStreamStartMessage(clientId, requestId, data, claudeService, clients);
        break;

      case 'streamSend':
        await handleStreamSendMessage(clientId, requestId, data, claudeService, clients);
        break;

      case 'streamClose':
        await handleStreamCloseMessage(clientId, requestId, data, claudeService, clients);
        break;

      case 'permission':
        await handlePermissionMessage(clientId, requestId, data, claudeService, clients);
        break;

      case 'ping':
        handlePingMessage(clientId, requestId, data, clients);
        break;

      case 'subscribe':
        handleSubscribeMessage(clientId, requestId, data, clients);
        break;

      case 'setWorkingDirectory':
        await handleSetWorkingDirectoryMessage(clientId, requestId, data, claudeService, clients);
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

async function handleAskMessage(clientId, requestId, data, claudeService, clients) {
  const { prompt, workingDirectory, options } = data;

  console.log(`🤖 Processing ask message for client ${clientId}`);
  console.log(`   Prompt: "${prompt}"`);
  console.log(`   Working dir: ${workingDirectory || process.cwd()}`);

  try {
    const response = await claudeService.sendPrompt(prompt, {
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

async function handleStreamStartMessage(clientId, requestId, data, claudeService, clients) {
  const { prompt, workingDirectory, options } = data;

  try {
    const sessionId = uuidv4();
    const finalWorkingDirectory =
      workingDirectory || claudeService.defaultWorkingDirectory || process.cwd();

    console.log(`🚀 Starting Claude conversation session ${sessionId}`);
    console.log(`   Working directory: ${finalWorkingDirectory}`);
    console.log(
      `   Initial prompt: "${prompt?.substring(0, 100)}${prompt?.length > 100 ? '...' : ''}"`
    );

    const _response = await claudeService.sendStreamingPrompt(prompt, {
      sessionId,
      workingDirectory: finalWorkingDirectory,
    });

    // Associate this session with the client
    const client = clients.get(clientId);
    if (client) {
      client.sessionIds.add(sessionId);
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

async function handleStreamSendMessage(clientId, requestId, data, claudeService, clients) {
  const { sessionId, prompt } = data;

  try {
    await claudeService.sendToExistingSession(sessionId, prompt);

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

async function handleStreamCloseMessage(clientId, requestId, data, claudeService, clients) {
  const { sessionId, reason } = data;

  try {
    await claudeService.closeSession(sessionId);

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

async function handlePermissionMessage(clientId, requestId, data, claudeService, clients) {
  const { sessionId, response, _remember } = data;

  try {
    await claudeService.handlePermissionPrompt(sessionId, response);

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
    events.forEach((event) => client.subscribedEvents.add(event));

    sendMessage(
      clientId,
      {
        type: 'subscribed',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          events,
          sessionIds: sessionIds || [],
          success: true,
        },
      },
      clients
    );
  }
}

async function handleSetWorkingDirectoryMessage(clientId, requestId, data, claudeService, clients) {
  const { workingDirectory } = data;

  try {
    // Validate the directory exists
    const fs = await import('fs');
    const path = await import('path');

    const resolvedPath = path.resolve(workingDirectory);

    // Check if directory exists
    if (!fs.existsSync(resolvedPath)) {
      sendErrorMessage(
        clientId,
        requestId,
        'DIRECTORY_NOT_FOUND',
        `Directory does not exist: ${resolvedPath}`,
        clients
      );
      return;
    }

    // Check if it's actually a directory
    const stats = fs.statSync(resolvedPath);
    if (!stats.isDirectory()) {
      sendErrorMessage(
        clientId,
        requestId,
        'NOT_A_DIRECTORY',
        `Path is not a directory: ${resolvedPath}`,
        clients
      );
      return;
    }

    // Update the default working directory for future sessions
    claudeService.defaultWorkingDirectory = resolvedPath;

    sendMessage(
      clientId,
      {
        type: 'workingDirectorySet',
        requestId,
        timestamp: new Date().toISOString(),
        data: {
          workingDirectory: resolvedPath,
          success: true,
        },
      },
      clients
    );
  } catch (error) {
    sendErrorMessage(clientId, requestId, 'WORKING_DIRECTORY_ERROR', error.message, clients);
  }
}

function sendMessage(clientId, message, clients) {
  const client = clients.get(clientId);
  if (client && client.ws.readyState === 1) {
    // WebSocket.OPEN
    client.ws.send(JSON.stringify(message));
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
  clients.forEach((client, clientId) => {
    if (client.sessionIds.has(sessionId)) {
      sendMessage(clientId, message, clients);
    }
  });
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

async function getClaudeCodeVersion() {
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
