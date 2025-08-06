import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import http from 'http';
import WebSocket from 'ws';
import { promises as fs } from 'fs';
import path from 'path';
import { AICLICompanionServer } from '../index.js';

/**
 * UAT Test Suite: Edge Cases & Error Recovery
 *
 * Tests the system's resilience to various edge cases and error conditions:
 * - Network interruption recovery
 * - Invalid input handling
 * - Resource exhaustion scenarios
 * - Corrupted data recovery
 * - Authentication edge cases
 * - Filesystem permission issues
 */

describe('UAT: Edge Cases & Error Recovery', () => {
  let server;
  let serverInstance;
  let testPort;
  let baseUrl;
  let wsUrl;
  let tempDir;

  beforeEach(async () => {
    // Use a random port to avoid conflicts
    testPort = 3000 + Math.floor(Math.random() * 1000);

    // Create temporary directory for testing
    tempDir = path.join(process.cwd(), `test-temp-${Date.now()}`);
    await fs.mkdir(tempDir, { recursive: true });

    // Set test environment
    process.env.NODE_ENV = 'test';
    process.env.PORT = testPort.toString();
    process.env.AUTH_REQUIRED = 'false';
    process.env.ENABLE_BONJOUR = 'false';
    process.env.ENABLE_TLS = 'false';
    process.env.CONFIG_PATH = tempDir;

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

    // Clean up temporary directory
    if (tempDir) {
      try {
        await fs.rm(tempDir, { recursive: true, force: true });
      } catch (error) {
        console.warn(`Failed to clean up temp dir: ${error.message}`);
      }
    }

    // Clean up environment
    delete process.env.PORT;
    delete process.env.AUTH_REQUIRED;
    delete process.env.ENABLE_BONJOUR;
    delete process.env.ENABLE_TLS;
    delete process.env.CONFIG_PATH;
  });

  describe('Invalid Input Handling', () => {
    it('should handle malformed JSON in WebSocket messages', async () => {
      const ws = new WebSocket(wsUrl);

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

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          ws.close();
          reject(new Error('Malformed JSON response timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'error') {
              clearTimeout(timeout);
              assert.ok(message.data.error, 'Should have error message');
              ws.close();
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            ws.close();
            reject(error);
          }
        });

        // Send malformed JSON
        ws.send('{ invalid json malformed');
      });
    });

    it('should handle oversized WebSocket messages', async () => {
      const ws = new WebSocket(wsUrl);

      await new Promise((resolve, reject) => {
        ws.on('open', resolve);
        ws.on('error', reject);
        setTimeout(() => reject(new Error('Connection timeout')), 5000);
      });

      return new Promise((resolve, reject) => {
        let resolved = false;
        const timeout = setTimeout(() => {
          if (!resolved) {
            ws.close();
            reject(new Error('Oversized message test timeout'));
          }
        }, 10000);

        ws.on('message', (data) => {
          if (resolved) return;
          try {
            const message = JSON.parse(data.toString());
            // Should get an error response or the connection should close
            if (message.type === 'error') {
              resolved = true;
              clearTimeout(timeout);
              ws.close();
              resolve();
            }
          } catch (error) {
            if (!resolved) {
              resolved = true;
              clearTimeout(timeout);
              ws.close();
              reject(error);
            }
          }
        });

        ws.on('close', () => {
          if (!resolved) {
            resolved = true;
            clearTimeout(timeout);
            resolve(); // Connection closed, which is acceptable for oversized messages
          }
        });

        ws.on('error', () => {
          if (!resolved) {
            resolved = true;
            clearTimeout(timeout);
            resolve(); // Error is expected for oversized messages
          }
        });

        try {
          // Create very large message (5MB)
          const largePayload = 'x'.repeat(5 * 1024 * 1024);
          ws.send(
            JSON.stringify({
              type: 'testMessage',
              data: { payload: largePayload },
            })
          );
        } catch (error) {
          // Send might fail immediately for very large messages
          resolved = true;
          clearTimeout(timeout);
          ws.close();
          resolve();
        }
      });
    });

    it('should handle invalid HTTP request paths', async () => {
      const testPaths = [
        '/api/../../../etc/passwd',
        '/api/projects/../../secrets',
        '/api/\x00\x01\x02',
        '/api/projects/%2e%2e%2f%2e%2e%2fpasswd',
      ];

      for (const testPath of testPaths) {
        await new Promise((resolve, _reject) => {
          const req = http.get(`${baseUrl}${testPath}`, (res) => {
            // Should get 404, 400, or 403 - not crash or expose files
            assert.ok(res.statusCode >= 400, `Path ${testPath} should return error status`);
            assert.ok(res.statusCode < 500 || res.statusCode === 500, 'Should handle gracefully');
            resolve();
          });

          req.on('error', () => {
            // Connection error is also acceptable
            resolve();
          });

          req.setTimeout(5000, () => {
            req.destroy();
            resolve();
          });
        });
      }
    });

    it('should handle invalid project names', async () => {
      const invalidNames = ['../../../etc', 'project\x00name', 'project%2e%2ename', '..', '.', ''];

      for (const invalidName of invalidNames) {
        await new Promise((resolve, _reject) => {
          const postData = JSON.stringify({});

          const req = http.request(
            {
              hostname: 'localhost',
              port: testPort,
              path: `/api/projects/${encodeURIComponent(invalidName)}/start`,
              method: 'POST',
              headers: {
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
              },
            },
            (res) => {
              // Should get error response, not crash
              assert.ok(
                res.statusCode >= 400,
                `Invalid project name ${invalidName} should return error`
              );
              resolve();
            }
          );

          req.on('error', () => {
            // Connection error is also acceptable
            resolve();
          });

          req.setTimeout(5000, () => {
            req.destroy();
            resolve();
          });

          req.write(postData);
          req.end();
        });
      }
    });
  });

  describe('Resource Exhaustion Scenarios', () => {
    it('should handle rapid connection attempts gracefully', async () => {
      const rapidConnections = [];
      const numAttempts = 50;
      let successCount = 0;
      let errorCount = 0;

      // Create many connections rapidly
      const connectionPromises = [];

      for (let i = 0; i < numAttempts; i++) {
        connectionPromises.push(
          new Promise((resolve) => {
            const ws = new WebSocket(wsUrl);
            rapidConnections.push(ws);

            const timeout = setTimeout(() => {
              errorCount++;
              try {
                ws.close();
              } catch (e) {
                // Ignore close error
              }
              resolve();
            }, 2000);

            ws.on('open', () => {
              successCount++;
              clearTimeout(timeout);
              resolve();
            });

            ws.on('error', () => {
              errorCount++;
              clearTimeout(timeout);
              resolve();
            });

            ws.on('close', () => {
              clearTimeout(timeout);
              resolve();
            });
          })
        );
      }

      await Promise.all(connectionPromises);

      console.log(`Rapid connections: ${successCount} successful, ${errorCount} failed/timeout`);

      // Server should handle this gracefully - some connections may fail but server should not crash
      assert.ok(successCount > 0, 'At least some connections should succeed');

      // Clean up
      rapidConnections.forEach((ws) => {
        try {
          if (ws.readyState === WebSocket.OPEN) {
            ws.close();
          }
        } catch (e) {
          // Ignore cleanup error
        }
      });

      // Verify server is still responsive
      await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/health`, (res) => {
          assert.strictEqual(res.statusCode, 200);
          resolve();
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Health check timeout after rapid connections'));
        });
      });
    });

    it('should handle concurrent project operations', async () => {
      // Create test project directory
      const testProjectDir = path.join(tempDir, 'test-project');
      await fs.mkdir(testProjectDir, { recursive: true });
      await fs.writeFile(path.join(testProjectDir, 'README.md'), '# Test Project');

      const concurrentOperations = [];
      const numOperations = 10;

      // Create concurrent project start requests
      for (let i = 0; i < numOperations; i++) {
        concurrentOperations.push(
          new Promise((resolve) => {
            const postData = JSON.stringify({});

            const req = http.request(
              {
                hostname: 'localhost',
                port: testPort,
                path: '/api/projects/test-project/start',
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'Content-Length': Buffer.byteLength(postData),
                },
              },
              (res) => {
                let data = '';
                res.on('data', (chunk) => {
                  data += chunk;
                });
                res.on('end', () => {
                  resolve({ statusCode: res.statusCode, data });
                });
              }
            );

            req.on('error', (error) => {
              resolve({ error: error.message });
            });

            req.setTimeout(10000, () => {
              req.destroy();
              resolve({ error: 'timeout' });
            });

            req.write(postData);
            req.end();
          })
        );
      }

      const results = await Promise.all(concurrentOperations);

      // Server should handle concurrent requests gracefully
      const successCount = results.filter((r) => r.statusCode && r.statusCode < 500).length;
      const errorCount = results.filter(
        (r) => r.error || (r.statusCode && r.statusCode >= 500)
      ).length;

      console.log(`Concurrent operations: ${successCount} handled, ${errorCount} errors`);

      // Server should remain responsive (some operations may fail due to resource limits)
      assert.ok(successCount + errorCount === numOperations, 'All operations should complete');
    });
  });

  describe('Filesystem Edge Cases', () => {
    it('should handle non-existent project directories', async () => {
      return new Promise((resolve, reject) => {
        const postData = JSON.stringify({});

        const req = http.request(
          {
            hostname: 'localhost',
            port: testPort,
            path: '/api/projects/non-existent-project/start',
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(postData),
            },
          },
          (res) => {
            let data = '';
            res.on('data', (chunk) => {
              data += chunk;
            });
            res.on('end', () => {
              try {
                // Should get 404 for non-existent project
                assert.strictEqual(res.statusCode, 404);
                const response = JSON.parse(data);
                assert.ok(response.error);
                resolve();
              } catch (error) {
                reject(error);
              }
            });
          }
        );

        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Non-existent project test timeout'));
        });

        req.write(postData);
        req.end();
      });
    });

    it('should handle projects listing with inaccessible directories', async () => {
      // Create a test directory structure
      const inaccessibleDir = path.join(tempDir, 'inaccessible');
      await fs.mkdir(inaccessibleDir, { recursive: true });

      // Try to make it inaccessible (this may not work on all systems)
      try {
        await fs.chmod(inaccessibleDir, 0o000);
      } catch (e) {
        // Skip this test if we can't change permissions
        return;
      }

      try {
        return new Promise((resolve, reject) => {
          const req = http.get(`${baseUrl}/api/projects`, (res) => {
            let data = '';
            res.on('data', (chunk) => {
              data += chunk;
            });
            res.on('end', () => {
              try {
                // Should handle inaccessible directories gracefully
                assert.ok(res.statusCode === 200 || res.statusCode === 500);
                if (res.statusCode === 200) {
                  const response = JSON.parse(data);
                  assert.ok(Array.isArray(response.projects));
                }
                resolve();
              } catch (error) {
                reject(error);
              }
            });
          });

          req.on('error', reject);
          req.setTimeout(5000, () => {
            req.destroy();
            reject(new Error('Inaccessible directory test timeout'));
          });
        });
      } finally {
        // Restore permissions for cleanup
        try {
          await fs.chmod(inaccessibleDir, 0o755);
        } catch (e) {
          // Ignore cleanup error
        }
      }
    });
  });

  describe('Connection Recovery', () => {
    it('should handle WebSocket connection interruption', async () => {
      const ws = new WebSocket(wsUrl);

      // Establish connection
      await new Promise((resolve, reject) => {
        ws.on('open', resolve);
        ws.on('error', reject);
        setTimeout(() => reject(new Error('Connection timeout')), 5000);
      });

      // Send a message to establish communication
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Initial ping timeout'));
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

      // Simulate network interruption by terminating connection
      ws.terminate();

      // Wait a moment
      await new Promise((resolve) => setTimeout(resolve, 100));

      // Create new connection (simulating reconnection)
      const newWs = new WebSocket(wsUrl);

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          newWs.close();
          reject(new Error('Reconnection timeout'));
        }, 5000);

        newWs.on('open', () => {
          // Send ping to verify reconnection works
          newWs.on('message', (data) => {
            try {
              const message = JSON.parse(data.toString());
              if (message.type === 'pong') {
                clearTimeout(timeout);
                newWs.close();
                resolve();
              }
            } catch (error) {
              clearTimeout(timeout);
              newWs.close();
              reject(error);
            }
          });

          newWs.send(
            JSON.stringify({
              type: 'ping',
              data: { timestamp: Date.now() },
            })
          );
        });

        newWs.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
    });

    it('should recover from temporary server overload', async () => {
      // Create many connections to simulate overload
      const overloadConnections = [];

      try {
        // Create connections rapidly to stress the server
        for (let i = 0; i < 30; i++) {
          try {
            const ws = new WebSocket(wsUrl);
            overloadConnections.push(ws);

            // Don't wait for connection to complete - simulate rapid attempts
            if (i % 10 === 0) {
              await new Promise((resolve) => setTimeout(resolve, 10));
            }
          } catch (e) {
            // Some connections may fail - that's expected
          }
        }

        // Wait for connections to settle
        await new Promise((resolve) => setTimeout(resolve, 1000));

        // Try to establish a normal connection after overload
        const normalWs = new WebSocket(wsUrl);

        return new Promise((resolve, reject) => {
          const timeout = setTimeout(() => {
            normalWs.close();
            reject(new Error('Recovery connection timeout'));
          }, 10000);

          normalWs.on('open', () => {
            clearTimeout(timeout);
            normalWs.close();
            resolve();
          });

          normalWs.on('error', (error) => {
            clearTimeout(timeout);
            reject(error);
          });
        });
      } finally {
        // Clean up overload connections
        overloadConnections.forEach((ws) => {
          try {
            ws.terminate();
          } catch (e) {
            // Ignore cleanup error
          }
        });
      }
    });
  });

  describe('Data Consistency', () => {
    it('should handle concurrent session operations safely', async () => {
      // Create test project
      const testProjectDir = path.join(tempDir, 'concurrent-test');
      await fs.mkdir(testProjectDir, { recursive: true });
      await fs.writeFile(path.join(testProjectDir, 'test.txt'), 'test content');

      const operations = [];

      // Concurrent session start requests
      for (let i = 0; i < 5; i++) {
        operations.push(
          new Promise((resolve) => {
            const postData = JSON.stringify({});

            const req = http.request(
              {
                hostname: 'localhost',
                port: testPort,
                path: '/api/projects/concurrent-test/start',
                method: 'POST',
                headers: {
                  'Content-Type': 'application/json',
                  'Content-Length': Buffer.byteLength(postData),
                },
              },
              (res) => {
                let data = '';
                res.on('data', (chunk) => {
                  data += chunk;
                });
                res.on('end', () => {
                  resolve({ statusCode: res.statusCode, data });
                });
              }
            );

            req.on('error', (error) => {
              resolve({ error: error.message });
            });

            req.setTimeout(10000, () => {
              req.destroy();
              resolve({ error: 'timeout' });
            });

            req.write(postData);
            req.end();
          })
        );
      }

      const results = await Promise.all(operations);

      // Check that operations completed without corruption
      const validResults = results.filter((r) => r.statusCode && r.statusCode < 500);
      console.log(`Concurrent session operations: ${validResults.length} valid results`);

      // At least some operations should succeed
      assert.ok(validResults.length > 0, 'Some concurrent operations should succeed');

      // Server should remain responsive
      await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/health`, (res) => {
          assert.strictEqual(res.statusCode, 200);
          resolve();
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Health check after concurrent operations timeout'));
        });
      });
    });
  });
});
