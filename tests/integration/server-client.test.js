#!/usr/bin/env node

import { spawn } from 'child_process';
import WebSocket from 'ws';
import { setTimeout } from 'timers/promises';
import assert from 'assert';

const SERVER_PORT = 3002; // Use different port for testing
const WS_URL = `ws://localhost:${SERVER_PORT}/ws`;
const AUTH_TOKEN = '889491aef84d2cd5aad12f99c3b161bf5ee623751a1aff07ca48a6c2e8330b9d';

class IntegrationTestRunner {
  constructor() {
    this.serverProcess = null;
    this.ws = null;
    this.testResults = [];
  }

  async startServer() {
    console.log('🚀 Starting server...');
    
    return new Promise((resolve, reject) => {
      this.serverProcess = spawn('node', ['src/index.js'], {
        cwd: process.cwd() + '/server',
        env: {
          ...process.env,
          PORT: SERVER_PORT,
          AUTH_TOKEN: AUTH_TOKEN,
        },
      });

      this.serverProcess.stdout.on('data', (data) => {
        const output = data.toString();
        console.log('Server:', output.trim());
        if (output.includes('Server listening')) {
          resolve();
        }
      });

      this.serverProcess.stderr.on('data', (data) => {
        console.error('Server Error:', data.toString());
      });

      this.serverProcess.on('error', reject);
      
      // Timeout if server doesn't start
      setTimeout(10000).then(() => reject(new Error('Server startup timeout')));
    });
  }

  async connectWebSocket() {
    console.log('🔌 Connecting WebSocket...');
    
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(`${WS_URL}?token=${AUTH_TOKEN}`);
      
      this.ws.on('open', () => {
        console.log('✅ WebSocket connected');
        resolve();
      });
      
      this.ws.on('error', reject);
      
      setTimeout(5000).then(() => reject(new Error('WebSocket connection timeout')));
    });
  }

  async runTest(name, testFn) {
    console.log(`\n📋 Running test: ${name}`);
    
    try {
      await testFn();
      console.log(`✅ ${name} - PASSED`);
      this.testResults.push({ name, status: 'passed' });
    } catch (error) {
      console.error(`❌ ${name} - FAILED:`, error.message);
      this.testResults.push({ name, status: 'failed', error: error.message });
    }
  }

  async testPingPong() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Ping timeout'));
      }, 5000);

      this.ws.once('message', (data) => {
        clearTimeout(timeout);
        try {
          const message = JSON.parse(data.toString());
          
          // Skip welcome message
          if (message.type === 'welcome') {
            this.ws.once('message', (pongData) => {
              const pong = JSON.parse(pongData.toString());
              assert.strictEqual(pong.type, 'pong');
              assert.strictEqual(pong.requestId, 'test-ping-1');
              resolve();
            });
            
            // Send ping
            this.ws.send(JSON.stringify({
              type: 'ping',
              requestId: 'test-ping-1',
              timestamp: new Date().toISOString(),
              data: {},
            }));
          }
        } catch (error) {
          clearTimeout(timeout);
          reject(error);
        }
      });
    });
  }

  async testAskEndpoint() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Ask timeout'));
      }, 10000);

      let welcomeReceived = false;

      const messageHandler = (data) => {
        try {
          const message = JSON.parse(data.toString());
          
          if (message.type === 'welcome' && !welcomeReceived) {
            welcomeReceived = true;
            // Send ask request
            this.ws.send(JSON.stringify({
              type: 'ask',
              requestId: 'test-ask-1',
              timestamp: new Date().toISOString(),
              data: {
                prompt: 'What is 2+2?',
                workingDirectory: process.cwd(),
                options: {
                  format: 'json',
                  timeout: 30000,
                },
              },
            }));
          } else if (message.type === 'askResponse') {
            clearTimeout(timeout);
            assert.ok(message.data);
            assert.strictEqual(message.requestId, 'test-ask-1');
            
            if (message.data.success) {
              console.log('Claude response:', message.data.response);
            }
            
            this.ws.removeListener('message', messageHandler);
            resolve();
          }
        } catch (error) {
          clearTimeout(timeout);
          reject(error);
        }
      };

      this.ws.on('message', messageHandler);
    });
  }

  async testStreamingSession() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Streaming timeout'));
      }, 15000);

      let sessionId = null;
      let streamData = [];

      const messageHandler = (data) => {
        try {
          const message = JSON.parse(data.toString());
          
          switch (message.type) {
            case 'streamStarted':
              sessionId = message.data.sessionId;
              console.log('Stream started:', sessionId);
              break;
              
            case 'streamData':
              streamData.push(message.data);
              console.log('Stream data:', message.data.content?.text || message.data);
              break;
              
            case 'streamComplete':
              clearTimeout(timeout);
              assert.ok(sessionId);
              assert.ok(streamData.length > 0);
              this.ws.removeListener('message', messageHandler);
              resolve();
              break;
              
            case 'error':
              clearTimeout(timeout);
              reject(new Error(message.data.message));
              break;
          }
        } catch (error) {
          clearTimeout(timeout);
          reject(error);
        }
      };

      // Skip welcome message
      this.ws.once('message', () => {
        this.ws.on('message', messageHandler);
        
        // Send stream start
        this.ws.send(JSON.stringify({
          type: 'streamStart',
          requestId: 'test-stream-1',
          timestamp: new Date().toISOString(),
          data: {
            prompt: 'Count from 1 to 3',
            workingDirectory: process.cwd(),
            options: {
              sessionName: 'Integration Test',
            },
          },
        }));
      });
    });
  }

  async testWorkingDirectory() {
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        reject(new Error('Working directory timeout'));
      }, 5000);

      const messageHandler = (data) => {
        try {
          const message = JSON.parse(data.toString());
          
          if (message.type === 'workingDirectorySet') {
            clearTimeout(timeout);
            assert.strictEqual(message.data.workingDirectory, '/tmp');
            this.ws.removeListener('message', messageHandler);
            resolve();
          }
        } catch (error) {
          clearTimeout(timeout);
          reject(error);
        }
      };

      // Skip welcome
      this.ws.once('message', () => {
        this.ws.on('message', messageHandler);
        
        // Send set working directory
        this.ws.send(JSON.stringify({
          type: 'setWorkingDirectory',
          requestId: 'test-wd-1',
          timestamp: new Date().toISOString(),
          data: {
            workingDirectory: '/tmp',
          },
        }));
      });
    });
  }

  async cleanup() {
    console.log('\n🧹 Cleaning up...');
    
    if (this.ws) {
      this.ws.close();
    }
    
    if (this.serverProcess) {
      this.serverProcess.kill('SIGTERM');
      await setTimeout(1000);
      if (!this.serverProcess.killed) {
        this.serverProcess.kill('SIGKILL');
      }
    }
  }

  printReport() {
    console.log('\n📊 Test Report:');
    console.log('================');
    
    const passed = this.testResults.filter(r => r.status === 'passed').length;
    const failed = this.testResults.filter(r => r.status === 'failed').length;
    
    this.testResults.forEach(result => {
      const icon = result.status === 'passed' ? '✅' : '❌';
      console.log(`${icon} ${result.name}`);
      if (result.error) {
        console.log(`   Error: ${result.error}`);
      }
    });
    
    console.log('\n Summary:');
    console.log(`  Passed: ${passed}`);
    console.log(`  Failed: ${failed}`);
    console.log(`  Total: ${this.testResults.length}`);
    
    return failed === 0;
  }
}

// Run integration tests
async function main() {
  const runner = new IntegrationTestRunner();
  
  try {
    console.log('🧪 Claude Companion Integration Tests');
    console.log('=====================================\n');
    
    await runner.startServer();
    await setTimeout(2000); // Wait for server to fully initialize
    await runner.connectWebSocket();
    
    // Run tests
    await runner.runTest('Ping/Pong', () => runner.testPingPong());
    await runner.runTest('Ask Endpoint', () => runner.testAskEndpoint());
    await runner.runTest('Streaming Session', () => runner.testStreamingSession());
    await runner.runTest('Working Directory', () => runner.testWorkingDirectory());
    
    const success = runner.printReport();
    process.exit(success ? 0 : 1);
    
  } catch (error) {
    console.error('💥 Fatal error:', error);
    process.exit(1);
  } finally {
    await runner.cleanup();
  }
}

// Handle process termination
process.on('SIGINT', async () => {
  console.log('\n⚠️  Interrupted, cleaning up...');
  process.exit(130);
});

main();