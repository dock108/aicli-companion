import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import WebSocket from 'ws';
import { AICLICompanionServer } from '../index.js';

/**
 * UAT Test Suite: Message Flow
 *
 * Tests the complete end-to-end message flow from WebSocket clients to server,
 * including session management, message persistence, and client synchronization.
 */

describe('UAT: Message Flow', () => {
  let server;
  let serverInstance;
  let testPort;
  let wsUrl;

  beforeEach(async () => {
    // Use a random port to avoid conflicts
    testPort = 3000 + Math.floor(Math.random() * 1000);

    // Set test environment
    process.env.NODE_ENV = 'test';
    process.env.PORT = testPort.toString();
    process.env.AUTH_REQUIRED = 'false';
    process.env.ENABLE_BONJOUR = 'false';
    process.env.ENABLE_TLS = 'false';

    wsUrl = `ws://localhost:${testPort}/ws`;

    server = new AICLICompanionServer();

    // Start server and wait for it to be ready
    await new Promise((resolve, reject) => {
      const originalStart = server.start.bind(server);
      server.start = async function () {
        try {
          await originalStart();
          resolve();
        } catch (error) {
          reject(error);
        }
      };
      server.start();
    });

    serverInstance = server;
  });

  afterEach(async () => {
    if (serverInstance && serverInstance.server) {
      await new Promise((resolve) => {
        serverInstance.server.close(() => {
          resolve();
        });
      });
    }

    // Clean up environment
    delete process.env.PORT;
    delete process.env.AUTH_REQUIRED;
    delete process.env.ENABLE_BONJOUR;
    delete process.env.ENABLE_TLS;
  });

  describe('WebSocket Connection', () => {
    it('should establish WebSocket connection successfully', async () => {
      return new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);

        const timeout = setTimeout(() => {
          ws.close();
          reject(new Error('Connection timeout'));
        }, 5000);

        ws.on('open', () => {
          clearTimeout(timeout);
          ws.close();
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });

    it('should receive welcome message on connection', async () => {
      return new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);
        let welcomeReceived = false;

        const timeout = setTimeout(() => {
          ws.close();
          reject(new Error('Welcome message not received within timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'welcome') {
              welcomeReceived = true;
              assert.ok(message.data, 'Welcome message should have data');
              assert.ok(message.data.message, 'Welcome message should have message text');
              clearTimeout(timeout);
              ws.close();
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            ws.close();
            reject(error);
          }
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });
  });

  describe('Message Types', () => {
    let ws;

    beforeEach(async () => {
      return new Promise((resolve, reject) => {
        ws = new WebSocket(wsUrl);

        const timeout = setTimeout(() => {
          reject(new Error('WebSocket connection timeout'));
        }, 5000);

        ws.on('open', () => {
          clearTimeout(timeout);
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });

    afterEach(() => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    });

    it('should handle ping message', async () => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Ping response timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'pong') {
              clearTimeout(timeout);
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send ping message
        ws.send(
          JSON.stringify({
            type: 'ping',
            data: { timestamp: Date.now() },
          })
        );
      });
    });

    it('should handle subscribe message', async () => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Subscribe response timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'subscribeSuccess') {
              clearTimeout(timeout);
              assert.ok(message.data, 'Subscribe success should have data');
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send subscribe message
        ws.send(
          JSON.stringify({
            type: 'subscribe',
            data: {
              events: ['streamData', 'streamComplete'],
              sessions: [],
            },
          })
        );
      });
    });
  });

  describe('Session Management', () => {
    let ws;
    let sessionId;

    beforeEach(async () => {
      // Establish WebSocket connection
      return new Promise((resolve, reject) => {
        ws = new WebSocket(wsUrl);

        const timeout = setTimeout(() => {
          reject(new Error('WebSocket connection timeout'));
        }, 5000);

        ws.on('open', () => {
          clearTimeout(timeout);
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });

    afterEach(() => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    });

    it('should handle working directory setting', async () => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Working directory response timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'workingDirectorySet' || message.type === 'error') {
              clearTimeout(timeout);
              // Either success or expected error (if directory doesn't exist)
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send working directory message
        ws.send(
          JSON.stringify({
            type: 'setWorkingDirectory',
            data: {
              directory: process.cwd(), // Use current working directory
            },
          })
        );
      });
    });
  });

  describe('Error Handling', () => {
    let ws;

    beforeEach(async () => {
      return new Promise((resolve, reject) => {
        ws = new WebSocket(wsUrl);

        const timeout = setTimeout(() => {
          reject(new Error('WebSocket connection timeout'));
        }, 5000);

        ws.on('open', () => {
          clearTimeout(timeout);
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });

    afterEach(() => {
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
    });

    it('should handle invalid message format', async () => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Error response timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'error') {
              clearTimeout(timeout);
              assert.ok(message.data.error, 'Error message should have error field');
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send invalid message
        ws.send('invalid json message');
      });
    });

    it('should handle unknown message type', async () => {
      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Error response timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'error') {
              clearTimeout(timeout);
              assert.ok(
                message.data.error.includes('Unknown message type'),
                'Should indicate unknown message type'
              );
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send unknown message type
        ws.send(
          JSON.stringify({
            type: 'unknownMessageType',
            data: {},
          })
        );
      });
    });
  });

  describe('Connection Stability', () => {
    it('should handle multiple concurrent connections', async () => {
      const numConnections = 5;
      const connections = [];
      const connectionPromises = [];

      try {
        // Create multiple connections
        for (let i = 0; i < numConnections; i++) {
          const promise = new Promise((resolve, reject) => {
            const ws = new WebSocket(wsUrl);
            connections.push(ws);

            const timeout = setTimeout(() => {
              reject(new Error(`Connection ${i} timeout`));
            }, 5000);

            ws.on('open', () => {
              clearTimeout(timeout);
              resolve(ws);
            });

            ws.on('error', (error) => {
              clearTimeout(timeout);
              reject(error);
            });
          });

          connectionPromises.push(promise);
        }

        // Wait for all connections to establish
        const establishedConnections = await Promise.all(connectionPromises);
        assert.strictEqual(
          establishedConnections.length,
          numConnections,
          'All connections should be established'
        );

        // Send ping from each connection
        const pingPromises = establishedConnections.map((ws, index) => {
          return new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
              reject(new Error(`Ping ${index} timeout`));
            }, 5000);

            ws.on('message', (data) => {
              try {
                const message = JSON.parse(data.toString());
                if (message.type === 'pong') {
                  clearTimeout(timeout);
                  resolve();
                }
              } catch (error) {
                clearTimeout(timeout);
                reject(error);
              }
            });

            ws.send(
              JSON.stringify({
                type: 'ping',
                data: { timestamp: Date.now() },
              })
            );
          });
        });

        await Promise.all(pingPromises);
      } finally {
        // Clean up all connections
        connections.forEach((ws) => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.close();
          }
        });
      }
    });

    it('should handle connection reconnection', async () => {
      // First connection
      let ws = new WebSocket(wsUrl);

      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('First connection timeout'));
        }, 5000);

        ws.on('open', () => {
          clearTimeout(timeout);
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });

      // Close first connection
      ws.close();

      // Wait a bit
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Second connection (reconnection)
      ws = new WebSocket(wsUrl);

      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Reconnection timeout'));
        }, 5000);

        ws.on('open', () => {
          clearTimeout(timeout);
          ws.close();
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });
  });
});
