import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import http from 'http';
import WebSocket from 'ws';
import { AICLICompanionServer } from '../index.js';

/**
 * UAT Test Suite: Performance & Load Testing
 *
 * Tests the performance characteristics and load handling capabilities:
 * - Response time benchmarks
 * - Memory usage monitoring
 * - Concurrent connection handling
 * - Large message processing
 * - Resource cleanup efficiency
 */

describe('UAT: Performance & Load Testing', () => {
  let server;
  let serverInstance;
  let testPort;
  let baseUrl;
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

    baseUrl = `http://localhost:${testPort}`;
    wsUrl = `ws://localhost:${testPort}/ws`;

    server = new AICLICompanionServer();

    // Start server and wait for it to be ready
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Server startup timeout'));
      }, 10000);

      const originalStart = server.start.bind(server);
      server.start = async function () {
        try {
          await originalStart();
          clearTimeout(timeout);
          resolve();
        } catch (error) {
          clearTimeout(timeout);
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

  describe('Response Time Benchmarks', () => {
    it('should respond to health check within 100ms', async () => {
      const startTime = Date.now();

      await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/health`, (res) => {
          const responseTime = Date.now() - startTime;

          let _data = '';
          res.on('data', (chunk) => {
            _data += chunk;
          });
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              assert.ok(
                responseTime < 100,
                `Health check took ${responseTime}ms, should be < 100ms`
              );
              console.log(`Health check response time: ${responseTime}ms`);
              resolve();
            } catch (error) {
              reject(error);
            }
          });
        });

        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Health check timeout'));
        });
      });
    });

    it('should establish WebSocket connections within 200ms', async () => {
      const startTime = Date.now();

      return new Promise((resolve, reject) => {
        const ws = new WebSocket(wsUrl);

        const timeout = setTimeout(() => {
          ws.close();
          reject(new Error('WebSocket connection timeout'));
        }, 5000);

        ws.on('open', () => {
          const connectionTime = Date.now() - startTime;
          clearTimeout(timeout);

          assert.ok(
            connectionTime < 200,
            `WebSocket connection took ${connectionTime}ms, should be < 200ms`
          );
          console.log(`WebSocket connection time: ${connectionTime}ms`);

          ws.close();
          resolve();
        });

        ws.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });

    it('should handle WebSocket ping-pong within 50ms', async () => {
      const ws = new WebSocket(wsUrl);

      // Wait for connection
      await new Promise((resolve, reject) => {
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

      // Test ping-pong response time
      const startTime = Date.now();

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          ws.close();
          reject(new Error('Ping-pong timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'pong') {
              const responseTime = Date.now() - startTime;
              clearTimeout(timeout);

              assert.ok(responseTime < 50, `Ping-pong took ${responseTime}ms, should be < 50ms`);
              console.log(`Ping-pong response time: ${responseTime}ms`);

              ws.close();
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            ws.close();
            reject(error);
          }
        });

        // Send ping
        ws.send(
          JSON.stringify({
            type: 'ping',
            data: { timestamp: startTime },
          })
        );
      });
    });
  });

  describe('Concurrent Connection Handling', () => {
    it('should handle 20 concurrent HTTP requests efficiently', async () => {
      const numRequests = 20;
      const startTime = Date.now();
      const promises = [];

      for (let i = 0; i < numRequests; i++) {
        promises.push(
          new Promise((resolve, reject) => {
            const requestStart = Date.now();
            const req = http.get(`${baseUrl}/health`, (res) => {
              const requestTime = Date.now() - requestStart;

              let _data = '';
              res.on('data', (chunk) => {
                _data += chunk;
              });
              res.on('end', () => {
                try {
                  assert.strictEqual(res.statusCode, 200);
                  resolve(requestTime);
                } catch (error) {
                  reject(error);
                }
              });
            });

            req.on('error', reject);
            req.setTimeout(5000, () => {
              req.destroy();
              reject(new Error(`Request ${i} timeout`));
            });
          })
        );
      }

      const responseTimes = await Promise.all(promises);
      const totalTime = Date.now() - startTime;
      const avgResponseTime = responseTimes.reduce((a, b) => a + b, 0) / responseTimes.length;
      const maxResponseTime = Math.max(...responseTimes);

      console.log(`Concurrent HTTP test: ${numRequests} requests in ${totalTime}ms`);
      console.log(`Average response time: ${avgResponseTime.toFixed(2)}ms`);
      console.log(`Max response time: ${maxResponseTime}ms`);

      // All requests should complete within reasonable time
      assert.ok(totalTime < 5000, `Total time ${totalTime}ms should be < 5000ms`);
      assert.ok(
        avgResponseTime < 200,
        `Average response time ${avgResponseTime}ms should be < 200ms`
      );
      assert.ok(maxResponseTime < 500, `Max response time ${maxResponseTime}ms should be < 500ms`);
    });

    it('should handle 10 concurrent WebSocket connections', async () => {
      const numConnections = 10;
      const connections = [];
      const connectionTimes = [];
      const startTime = Date.now();

      try {
        // Create connections
        const connectionPromises = [];

        for (let i = 0; i < numConnections; i++) {
          connectionPromises.push(
            new Promise((resolve, reject) => {
              const connectionStart = Date.now();
              const ws = new WebSocket(wsUrl);
              connections.push(ws);

              const timeout = setTimeout(() => {
                reject(new Error(`Connection ${i} timeout`));
              }, 5000);

              ws.on('open', () => {
                const connectionTime = Date.now() - connectionStart;
                connectionTimes.push(connectionTime);
                clearTimeout(timeout);
                resolve(ws);
              });

              ws.on('error', (error) => {
                clearTimeout(timeout);
                reject(error);
              });
            })
          );
        }

        await Promise.all(connectionPromises);
        const totalConnectionTime = Date.now() - startTime;

        console.log(
          `Concurrent WebSocket test: ${numConnections} connections in ${totalConnectionTime}ms`
        );
        console.log(
          `Average connection time: ${(connectionTimes.reduce((a, b) => a + b, 0) / connectionTimes.length).toFixed(2)}ms`
        );

        // All connections should be established quickly
        assert.ok(
          totalConnectionTime < 3000,
          `Total connection time ${totalConnectionTime}ms should be < 3000ms`
        );

        // Test ping-pong on all connections simultaneously
        const pingStartTime = Date.now();
        const pingPromises = connections.map((ws, index) => {
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
        const totalPingTime = Date.now() - pingStartTime;

        console.log(`All ping-pong completed in: ${totalPingTime}ms`);
        assert.ok(
          totalPingTime < 1000,
          `Total ping-pong time ${totalPingTime}ms should be < 1000ms`
        );
      } finally {
        // Clean up all connections
        connections.forEach((ws) => {
          if (ws.readyState === WebSocket.OPEN) {
            ws.close();
          }
        });
      }
    });
  });

  describe('Large Message Processing', () => {
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

    it('should handle large JSON messages efficiently', async () => {
      // Create a large message (100KB)
      const largeData = 'x'.repeat(100 * 1024);
      const startTime = Date.now();

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Large message timeout'));
        }, 10000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'error' && message.data.error.includes('Unknown message type')) {
              // Expected response for our test message
              const processingTime = Date.now() - startTime;
              clearTimeout(timeout);

              console.log(`Large message processing time: ${processingTime}ms`);
              assert.ok(
                processingTime < 1000,
                `Large message processing took ${processingTime}ms, should be < 1000ms`
              );
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send large message
        ws.send(
          JSON.stringify({
            type: 'testLargeMessage',
            data: { payload: largeData },
          })
        );
      });
    });

    it('should handle rapid message bursts', async () => {
      const numMessages = 50;
      const _messages = [];
      const startTime = Date.now();

      return new Promise((resolve, reject) => {
        let responseCount = 0;

        const timeout = setTimeout(() => {
          reject(new Error(`Only received ${responseCount}/${numMessages} responses`));
        }, 10000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'pong') {
              responseCount++;

              if (responseCount === numMessages) {
                const totalTime = Date.now() - startTime;
                clearTimeout(timeout);

                console.log(`Message burst test: ${numMessages} messages in ${totalTime}ms`);
                console.log(`Average message time: ${(totalTime / numMessages).toFixed(2)}ms`);

                assert.ok(
                  totalTime < 5000,
                  `Message burst took ${totalTime}ms, should be < 5000ms`
                );
                resolve();
              }
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        // Send message burst
        for (let i = 0; i < numMessages; i++) {
          ws.send(
            JSON.stringify({
              type: 'ping',
              data: { timestamp: Date.now(), sequence: i },
            })
          );
        }
      });
    });
  });

  describe('Memory Usage Monitoring', () => {
    it('should not leak memory with connection cycles', async () => {
      const initialMemory = process.memoryUsage();
      console.log(`Initial memory usage: ${Math.round(initialMemory.heapUsed / 1024 / 1024)}MB`);

      // Create and destroy connections multiple times
      for (let cycle = 0; cycle < 5; cycle++) {
        const connections = [];

        // Create 10 connections
        for (let i = 0; i < 10; i++) {
          const ws = new WebSocket(wsUrl);
          connections.push(ws);

          await new Promise((resolve, reject) => {
            const timeout = setTimeout(() => {
              reject(new Error(`Connection ${i} in cycle ${cycle} timeout`));
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
        }

        // Send messages on each connection
        for (const ws of connections) {
          ws.send(
            JSON.stringify({
              type: 'ping',
              data: { timestamp: Date.now() },
            })
          );
        }

        // Wait a bit
        await new Promise((resolve) => setTimeout(resolve, 100));

        // Close all connections
        connections.forEach((ws) => ws.close());

        // Wait for cleanup
        await new Promise((resolve) => setTimeout(resolve, 100));
      }

      // Force garbage collection if available
      if (global.gc) {
        global.gc();
      }

      const finalMemory = process.memoryUsage();
      const memoryIncrease = (finalMemory.heapUsed - initialMemory.heapUsed) / 1024 / 1024;

      console.log(`Final memory usage: ${Math.round(finalMemory.heapUsed / 1024 / 1024)}MB`);
      console.log(`Memory increase: ${memoryIncrease.toFixed(2)}MB`);

      // Memory increase should be reasonable (less than 10MB for this test)
      assert.ok(
        memoryIncrease < 10,
        `Memory increase ${memoryIncrease.toFixed(2)}MB should be < 10MB`
      );
    });
  });

  describe('Resource Cleanup Efficiency', () => {
    it('should clean up WebSocket connections promptly', async () => {
      const connections = [];

      // Create connections
      for (let i = 0; i < 5; i++) {
        const ws = new WebSocket(wsUrl);
        connections.push(ws);

        await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => {
            reject(new Error(`Connection ${i} timeout`));
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
      }

      // Close connections
      const closeStartTime = Date.now();
      const closePromises = connections.map((ws) => {
        return new Promise((resolve) => {
          ws.on('close', resolve);
          ws.close();
        });
      });

      await Promise.all(closePromises);
      const closeTime = Date.now() - closeStartTime;

      console.log(`Connection cleanup time: ${closeTime}ms`);
      assert.ok(closeTime < 1000, `Connection cleanup took ${closeTime}ms, should be < 1000ms`);
    });

    it('should handle abrupt connection termination gracefully', async () => {
      const connections = [];

      // Create connections
      for (let i = 0; i < 3; i++) {
        const ws = new WebSocket(wsUrl);
        connections.push(ws);

        await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => {
            reject(new Error(`Connection ${i} timeout`));
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
      }

      // Terminate connections abruptly
      connections.forEach((ws) => {
        ws.terminate(); // Abrupt termination vs close()
      });

      // Wait for server to clean up
      await new Promise((resolve) => setTimeout(resolve, 500));

      // Server should still be responsive
      const healthCheck = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/health`, (res) => {
          assert.strictEqual(res.statusCode, 200);
          resolve(true);
        });

        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Health check after termination timeout'));
        });
      });

      assert.ok(healthCheck);
    });
  });
});
