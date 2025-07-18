import { v4 as uuidv4 } from 'uuid';
import jwt from 'jsonwebtoken';

export function setupWebSocket(wss, claudeService, authToken) {
  const clients = new Map();
  
  wss.on('connection', (ws, request) => {
    const clientId = uuidv4();
    console.log(`WebSocket client connected: ${clientId}`);
    
    // Authentication check
    if (authToken) {
      const url = new URL(request.url, `http://${request.headers.host}`);
      const token = url.searchParams.get('token') || 
                   request.headers.authorization?.replace('Bearer ', '');
      
      if (!token || token !== authToken) {
        ws.close(1008, 'Authentication required');
        return;
      }
    }
    
    // Store client info
    clients.set(clientId, {
      ws,
      sessionIds: new Set(),
      isAlive: true
    });
    
    // Set up ping/pong for connection health
    ws.isAlive = true;
    ws.on('pong', () => {
      ws.isAlive = true;
    });
    
    // Handle incoming messages
    ws.on('message', async (data) => {
      try {
        const message = JSON.parse(data);
        await handleWebSocketMessage(clientId, message, claudeService, clients);
      } catch (error) {
        console.error('WebSocket message error:', error);
        sendToClient(clientId, {
          type: 'error',
          message: error.message
        }, clients);
      }
    });
    
    // Handle client disconnect
    ws.on('close', () => {
      console.log(`WebSocket client disconnected: ${clientId}`);
      
      // Clean up any active sessions for this client
      const client = clients.get(clientId);
      if (client) {
        client.sessionIds.forEach(sessionId => {
          claudeService.closeSession(sessionId);
        });
      }
      
      clients.delete(clientId);
    });
    
    ws.on('error', (error) => {
      console.error(`WebSocket error for client ${clientId}:`, error);
    });
    
    // Send welcome message
    sendToClient(clientId, {
      type: 'connected',
      clientId,
      message: 'Connected to Claude Companion Server'
    }, clients);
  });
  
  // Set up Claude Code event listeners
  claudeService.on('streamData', (data) => {
    broadcastToSessionClients(data.sessionId, {
      type: 'streamData',
      sessionId: data.sessionId,
      data: data.data
    }, clients);
  });
  
  claudeService.on('streamError', (data) => {
    broadcastToSessionClients(data.sessionId, {
      type: 'streamError',
      sessionId: data.sessionId,
      error: data.error
    }, clients);
  });
  
  claudeService.on('sessionClosed', (data) => {
    broadcastToSessionClients(data.sessionId, {
      type: 'sessionClosed',
      sessionId: data.sessionId,
      code: data.code
    }, clients);
  });
  
  claudeService.on('sessionError', (data) => {
    broadcastToSessionClients(data.sessionId, {
      type: 'sessionError',
      sessionId: data.sessionId,
      error: data.error
    }, clients);
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
  const { type, ...payload } = message;
  
  switch (type) {
    case 'ask':
      await handleAskMessage(clientId, payload, claudeService, clients);
      break;
      
    case 'streamStart':
      await handleStreamStartMessage(clientId, payload, claudeService, clients);
      break;
      
    case 'streamSend':
      await handleStreamSendMessage(clientId, payload, claudeService, clients);
      break;
      
    case 'streamClose':
      await handleStreamCloseMessage(clientId, payload, claudeService, clients);
      break;
      
    case 'permission':
      await handlePermissionMessage(clientId, payload, claudeService, clients);
      break;
      
    case 'ping':
      sendToClient(clientId, { type: 'pong' }, clients);
      break;
      
    default:
      sendToClient(clientId, {
        type: 'error',
        message: `Unknown message type: ${type}`
      }, clients);
  }
}

async function handleAskMessage(clientId, payload, claudeService, clients) {
  const { prompt, workingDirectory, requestId } = payload;
  
  try {
    const response = await claudeService.sendPrompt(prompt, {
      format: 'json',
      workingDirectory
    });
    
    sendToClient(clientId, {
      type: 'askResponse',
      requestId,
      data: response
    }, clients);
  } catch (error) {
    sendToClient(clientId, {
      type: 'askError',
      requestId,
      error: error.message
    }, clients);
  }
}

async function handleStreamStartMessage(clientId, payload, claudeService, clients) {
  const { prompt, workingDirectory, requestId } = payload;
  
  try {
    const response = await claudeService.sendStreamingPrompt(prompt, {
      sessionId: uuidv4(),
      workingDirectory
    });
    
    // Associate this session with the client
    const client = clients.get(clientId);
    if (client) {
      client.sessionIds.add(response.sessionId);
    }
    
    sendToClient(clientId, {
      type: 'streamStarted',
      requestId,
      sessionId: response.sessionId
    }, clients);
  } catch (error) {
    sendToClient(clientId, {
      type: 'streamError',
      requestId,
      error: error.message
    }, clients);
  }
}

async function handleStreamSendMessage(clientId, payload, claudeService, clients) {
  const { sessionId, prompt, requestId } = payload;
  
  try {
    const response = await claudeService.sendToExistingSession(sessionId, prompt);
    
    sendToClient(clientId, {
      type: 'streamSent',
      requestId,
      sessionId
    }, clients);
  } catch (error) {
    sendToClient(clientId, {
      type: 'streamError',
      requestId,
      sessionId,
      error: error.message
    }, clients);
  }
}

async function handleStreamCloseMessage(clientId, payload, claudeService, clients) {
  const { sessionId, requestId } = payload;
  
  try {
    await claudeService.closeSession(sessionId);
    
    // Remove session from client
    const client = clients.get(clientId);
    if (client) {
      client.sessionIds.delete(sessionId);
    }
    
    sendToClient(clientId, {
      type: 'streamClosed',
      requestId,
      sessionId
    }, clients);
  } catch (error) {
    sendToClient(clientId, {
      type: 'streamError',
      requestId,
      sessionId,
      error: error.message
    }, clients);
  }
}

async function handlePermissionMessage(clientId, payload, claudeService, clients) {
  const { sessionId, response, requestId } = payload;
  
  try {
    await claudeService.handlePermissionPrompt(sessionId, response);
    
    sendToClient(clientId, {
      type: 'permissionHandled',
      requestId,
      sessionId
    }, clients);
  } catch (error) {
    sendToClient(clientId, {
      type: 'permissionError',
      requestId,
      sessionId,
      error: error.message
    }, clients);
  }
}

function sendToClient(clientId, message, clients) {
  const client = clients.get(clientId);
  if (client && client.ws.readyState === 1) { // WebSocket.OPEN
    client.ws.send(JSON.stringify(message));
  }
}

function broadcastToSessionClients(sessionId, message, clients) {
  clients.forEach((client, clientId) => {
    if (client.sessionIds.has(sessionId)) {
      sendToClient(clientId, message, clients);
    }
  });
}