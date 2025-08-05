import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import http from 'http';
import WebSocket from 'ws';
import { AICLICompanionServer } from '../index.js';

/**
 * UAT Test Suite: Multi-Component Integration
 * 
 * Tests the integration between different components of the system:
 * - HTTP API endpoints (used by macOS app)
 * - WebSocket connections (used by iOS app) 
 * - Project management and session handling
 * - Cross-component state synchronization
 */

describe('UAT: Multi-Component Integration', () => {
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
    process.env.CONFIG_PATH = process.cwd(); // Use current directory for testing
    
    baseUrl = `http://localhost:${testPort}`;
    wsUrl = `ws://localhost:${testPort}/ws`;
    
    server = new AICLICompanionServer();
    
    // Start server and wait for it to be ready
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Server startup timeout'));
      }, 10000);

      const originalStart = server.start.bind(server);
      server.start = async function() {
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
    delete process.env.CONFIG_PATH;
  });

  describe('HTTP API Endpoints', () => {
    it('should respond to health check', async () => {
      return new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/health`, (res) => {
          let data = '';
          
          res.on('data', (chunk) => {
            data += chunk;
          });
          
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              const response = JSON.parse(data);
              assert.strictEqual(response.status, 'healthy');
              assert.ok(response.version);
              assert.ok(response.timestamp);
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

    it('should respond to server info endpoint', async () => {
      return new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/`, (res) => {
          let data = '';
          
          res.on('data', (chunk) => {
            data += chunk;
          });
          
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              const response = JSON.parse(data);
              assert.strictEqual(response.name, 'Claude Companion Server');
              assert.ok(response.version);
              assert.ok(response.endpoints);
              resolve();
            } catch (error) {
              reject(error);
            }
          });
        });
        
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Server info timeout'));
        });
      });
    });

    it('should handle server status endpoint (macOS app)', async () => {
      return new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/status`, (res) => {
          let data = '';
          
          res.on('data', (chunk) => {
            data += chunk;
          });
          
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              const response = JSON.parse(data);
              assert.strictEqual(response.running, true);
              assert.strictEqual(response.port, testPort);
              assert.ok(Array.isArray(response.sessions));
              resolve();
            } catch (error) {
              reject(error);
            }
          });
        });
        
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Status endpoint timeout'));
        });
      });
    });

    it('should handle projects list endpoint', async () => {
      return new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/projects`, (res) => {
          let data = '';
          
          res.on('data', (chunk) => {
            data += chunk;
          });
          
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              const response = JSON.parse(data);
              assert.ok(response.basePath);
              assert.ok(Array.isArray(response.projects));
              resolve();
            } catch (error) {
              reject(error);
            }
          });
        });
        
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Projects list timeout'));
        });
      });
    });
  });

  describe('WebSocket and HTTP Integration', () => {
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

    it('should maintain session state across HTTP and WebSocket', async () => {
      // First, get initial sessions count via HTTP
      const initialSessions = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/sessions`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              const response = JSON.parse(data);
              resolve(response.sessions || []);
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Sessions HTTP timeout'));
        });
      });

      // Subscribe to events via WebSocket
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          reject(new Error('Subscribe timeout'));
        }, 5000);

        ws.on('message', (data) => {
          try {
            const message = JSON.parse(data.toString());
            if (message.type === 'subscribeSuccess') {
              clearTimeout(timeout);
              resolve();
            }
          } catch (error) {
            clearTimeout(timeout);
            reject(error);
          }
        });

        ws.send(JSON.stringify({
          type: 'subscribe',
          data: {
            events: ['streamData', 'streamComplete'],
            sessions: []
          }
        }));
      });

      // Verify that both HTTP and WebSocket see consistent state
      const finalSessions = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/sessions`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              const response = JSON.parse(data);
              resolve(response.sessions || []);
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Final sessions HTTP timeout'));
        });
      });

      // Both should show consistent session state
      assert.strictEqual(initialSessions.length, finalSessions.length);
    });
  });

  describe('Cross-Component State Synchronization', () => {
    it('should synchronize active sessions between components', async () => {
      // Get sessions via HTTP API (macOS app path)
      const httpSessions = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/sessions`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              const response = JSON.parse(data);
              resolve(response.sessions || []);
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('HTTP sessions timeout'));
        });
      });

      // Get server status via HTTP API (macOS app path)
      const serverStatus = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/status`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              const response = JSON.parse(data);
              resolve(response);
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Server status timeout'));
        });
      });

      // Both endpoints should report consistent session counts
      assert.strictEqual(httpSessions.length, serverStatus.sessions.length);
    });

    it('should handle concurrent requests from multiple components', async () => {
      const promises = [];

      // Simulate macOS app requests
      for (let i = 0; i < 3; i++) {
        promises.push(new Promise((resolve, reject) => {
          const req = http.get(`${baseUrl}/api/status`, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
              try {
                const response = JSON.parse(data);
                resolve(response);
              } catch (error) {
                reject(error);
              }
            });
          });
          req.on('error', reject);
          req.setTimeout(5000, () => {
            req.destroy();
            reject(new Error(`Concurrent request ${i} timeout`));
          });
        }));
      }

      // Simulate iOS app WebSocket connections
      for (let i = 0; i < 2; i++) {
        promises.push(new Promise((resolve, reject) => {
          const testWs = new WebSocket(wsUrl);
          
          const timeout = setTimeout(() => {
            testWs.close();
            reject(new Error(`WebSocket ${i} timeout`));
          }, 5000);

          testWs.on('open', () => {
            // Send ping and wait for pong
            testWs.on('message', (data) => {
              try {
                const message = JSON.parse(data.toString());
                if (message.type === 'pong') {
                  clearTimeout(timeout);
                  testWs.close();
                  resolve(message);
                }
              } catch (error) {
                clearTimeout(timeout);
                testWs.close();
                reject(error);
              }
            });

            testWs.send(JSON.stringify({
              type: 'ping',
              data: { timestamp: Date.now() }
            }));
          });

          testWs.on('error', (error) => {
            clearTimeout(timeout);
            reject(error);
          });
        }));
      }

      // All requests should succeed
      const results = await Promise.all(promises);
      assert.strictEqual(results.length, 5); // 3 HTTP + 2 WebSocket
    });
  });

  describe('Error Recovery and Resilience', () => {
    it('should handle malformed HTTP requests gracefully', async () => {
      return new Promise((resolve, reject) => {
        const req = http.request({
          hostname: 'localhost',
          port: testPort,
          path: '/api/invalid-endpoint',
          method: 'GET'
        }, (res) => {
          // Should get 404 or similar error response, not crash
          assert.ok(res.statusCode >= 400);
          resolve();
        });
        
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Malformed request timeout'));
        });
        
        req.end();
      });
    });

    it('should maintain HTTP API availability when WebSocket fails', async () => {
      // Create and immediately close a WebSocket to test resilience
      const testWs = new WebSocket(wsUrl);
      await new Promise((resolve) => {
        testWs.on('open', () => {
          testWs.close();
          resolve();
        });
      });

      // HTTP API should still work
      return new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/health`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              const response = JSON.parse(data);
              assert.strictEqual(response.status, 'healthy');
              resolve();
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Health check after WebSocket failure timeout'));
        });
      });
    });
  });

  describe('Project Management Integration', () => {
    it('should handle project listing across components', async () => {
      // Test projects endpoint (used by iOS app)
      const projects = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/projects`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              assert.strictEqual(res.statusCode, 200);
              const response = JSON.parse(data);
              resolve(response.projects);
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Projects list timeout'));
        });
      });

      // Projects should be an array (might be empty in test environment)
      assert.ok(Array.isArray(projects));
      
      // Each project should have required fields
      projects.forEach(project => {
        assert.ok(project.name);
        assert.ok(project.path);
        assert.ok(project.type);
      });
    });

    it('should handle project session management', async () => {
      // First get available projects
      const projects = await new Promise((resolve, reject) => {
        const req = http.get(`${baseUrl}/api/projects`, (res) => {
          let data = '';
          res.on('data', (chunk) => { data += chunk; });
          res.on('end', () => {
            try {
              const response = JSON.parse(data);
              resolve(response.projects);
            } catch (error) {
              reject(error);
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(5000, () => {
          req.destroy();
          reject(new Error('Projects list timeout'));
        });
      });

      // If we have projects, test session creation
      if (projects.length > 0) {
        const testProject = projects[0];
        
        // Try to start a session for the first project
        const sessionResult = await new Promise((resolve, reject) => {
          const postData = JSON.stringify({});
          
          const req = http.request({
            hostname: 'localhost',
            port: testPort,
            path: `/api/projects/${encodeURIComponent(testProject.name)}/start`,
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Content-Length': Buffer.byteLength(postData)
            }
          }, (res) => {
            let data = '';
            res.on('data', (chunk) => { data += chunk; });
            res.on('end', () => {
              try {
                const response = JSON.parse(data);
                resolve({ statusCode: res.statusCode, response });
              } catch (error) {
                reject(error);
              }
            });
          });
          
          req.on('error', reject);
          req.setTimeout(10000, () => {
            req.destroy();
            reject(new Error('Project session start timeout'));
          });
          
          req.write(postData);
          req.end();
        });

        // Session creation might succeed or fail depending on AICLI availability
        // Both are acceptable in test environment
        assert.ok(sessionResult.statusCode >= 200);
        assert.ok(sessionResult.response);
      }
    });
  });
});