#!/usr/bin/env node

import WebSocket from 'ws';
import { setTimeout } from 'timers/promises';

const SERVER_URL = process.env.SERVER_URL || 'ws://localhost:3001/ws';
const AUTH_TOKEN = process.env.AUTH_TOKEN || '889491aef84d2cd5aad12f99c3b161bf5ee623751a1aff07ca48a6c2e8330b9d';
const CONCURRENT_CLIENTS = parseInt(process.env.CONCURRENT_CLIENTS) || 10;
const MESSAGES_PER_CLIENT = parseInt(process.env.MESSAGES_PER_CLIENT) || 100;
const MESSAGE_INTERVAL = parseInt(process.env.MESSAGE_INTERVAL) || 100; // ms

class LoadTestClient {
  constructor(id) {
    this.id = id;
    this.ws = null;
    this.connected = false;
    this.messagesSent = 0;
    this.messagesReceived = 0;
    this.errors = 0;
    this.latencies = [];
    this.startTime = null;
  }

  async connect() {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(`${SERVER_URL}?token=${AUTH_TOKEN}`);
      
      this.ws.on('open', () => {
        this.connected = true;
        this.startTime = Date.now();
        resolve();
      });
      
      this.ws.on('message', (data) => {
        try {
          const message = JSON.parse(data.toString());
          this.handleMessage(message);
        } catch (error) {
          this.errors++;
        }
      });
      
      this.ws.on('error', (error) => {
        console.error(`Client ${this.id} error:`, error.message);
        this.errors++;
      });
      
      this.ws.on('close', () => {
        this.connected = false;
      });
      
      setTimeout(5000).then(() => reject(new Error('Connection timeout')));
    });
  }

  handleMessage(message) {
    if (message.requestId && message.requestId.startsWith(`client-${this.id}-`)) {
      const requestTime = parseInt(message.requestId.split('-').pop());
      const latency = Date.now() - requestTime;
      this.latencies.push(latency);
      this.messagesReceived++;
    }
  }

  async sendMessages() {
    for (let i = 0; i < MESSAGES_PER_CLIENT; i++) {
      if (!this.connected) break;
      
      const requestId = `client-${this.id}-msg-${i}-${Date.now()}`;
      
      // Alternate between different message types
      const messageType = i % 3;
      let message;
      
      switch (messageType) {
        case 0: // Ping
          message = {
            type: 'ping',
            requestId,
            timestamp: new Date().toISOString(),
            data: {},
          };
          break;
          
        case 1: // Ask
          message = {
            type: 'ask',
            requestId,
            timestamp: new Date().toISOString(),
            data: {
              prompt: `Test message ${i} from client ${this.id}`,
              workingDirectory: '/tmp',
              options: { format: 'json' },
            },
          };
          break;
          
        case 2: // Working directory
          message = {
            type: 'setWorkingDirectory',
            requestId,
            timestamp: new Date().toISOString(),
            data: {
              workingDirectory: `/tmp/client-${this.id}`,
            },
          };
          break;
      }
      
      try {
        this.ws.send(JSON.stringify(message));
        this.messagesSent++;
      } catch (error) {
        this.errors++;
      }
      
      await setTimeout(MESSAGE_INTERVAL);
    }
  }

  disconnect() {
    if (this.ws) {
      this.ws.close();
    }
  }

  getStats() {
    const duration = Date.now() - this.startTime;
    const avgLatency = this.latencies.length > 0 
      ? this.latencies.reduce((a, b) => a + b, 0) / this.latencies.length 
      : 0;
    const minLatency = this.latencies.length > 0 ? Math.min(...this.latencies) : 0;
    const maxLatency = this.latencies.length > 0 ? Math.max(...this.latencies) : 0;
    
    return {
      id: this.id,
      duration,
      messagesSent: this.messagesSent,
      messagesReceived: this.messagesReceived,
      errors: this.errors,
      avgLatency: Math.round(avgLatency),
      minLatency,
      maxLatency,
      throughput: Math.round((this.messagesSent / duration) * 1000),
    };
  }
}

class LoadTestRunner {
  constructor() {
    this.clients = [];
    this.startTime = null;
  }

  async run() {
    console.log('🚀 Claude Companion Load Test');
    console.log('=============================');
    console.log(`Server: ${SERVER_URL}`);
    console.log(`Concurrent clients: ${CONCURRENT_CLIENTS}`);
    console.log(`Messages per client: ${MESSAGES_PER_CLIENT}`);
    console.log(`Message interval: ${MESSAGE_INTERVAL}ms`);
    console.log('');

    this.startTime = Date.now();

    // Create and connect clients
    console.log('📡 Connecting clients...');
    const connectionPromises = [];
    
    for (let i = 0; i < CONCURRENT_CLIENTS; i++) {
      const client = new LoadTestClient(i);
      this.clients.push(client);
      connectionPromises.push(client.connect());
    }

    try {
      await Promise.all(connectionPromises);
      console.log(`✅ ${this.clients.filter(c => c.connected).length} clients connected`);
    } catch (error) {
      console.error('❌ Some clients failed to connect:', error.message);
    }

    // Send messages
    console.log('\n📤 Sending messages...');
    const messagePromises = this.clients
      .filter(c => c.connected)
      .map(c => c.sendMessages());

    await Promise.all(messagePromises);

    // Wait for responses
    console.log('\n⏳ Waiting for responses...');
    await setTimeout(2000);

    // Disconnect all clients
    console.log('\n🔌 Disconnecting clients...');
    this.clients.forEach(c => c.disconnect());

    // Generate report
    this.generateReport();
  }

  generateReport() {
    const totalDuration = Date.now() - this.startTime;
    const stats = this.clients.map(c => c.getStats());
    
    console.log('\n📊 Load Test Report');
    console.log('==================');
    
    // Overall stats
    const totalMessagesSent = stats.reduce((sum, s) => sum + s.messagesSent, 0);
    const totalMessagesReceived = stats.reduce((sum, s) => sum + s.messagesReceived, 0);
    const totalErrors = stats.reduce((sum, s) => sum + s.errors, 0);
    const avgLatencies = stats.map(s => s.avgLatency).filter(l => l > 0);
    const overallAvgLatency = avgLatencies.length > 0
      ? avgLatencies.reduce((a, b) => a + b, 0) / avgLatencies.length
      : 0;
    
    console.log('\n Summary:');
    console.log(`  Test duration: ${(totalDuration / 1000).toFixed(2)}s`);
    console.log(`  Total messages sent: ${totalMessagesSent}`);
    console.log(`  Total messages received: ${totalMessagesReceived}`);
    console.log(`  Total errors: ${totalErrors}`);
    console.log(`  Success rate: ${((totalMessagesReceived / totalMessagesSent) * 100).toFixed(2)}%`);
    console.log(`  Overall throughput: ${Math.round((totalMessagesSent / totalDuration) * 1000)} msg/s`);
    console.log(`  Average latency: ${Math.round(overallAvgLatency)}ms`);
    
    // Per-client stats
    console.log('\n Per-Client Statistics:');
    console.log('  ID | Sent | Recv | Err | Avg Latency | Min | Max | Throughput');
    console.log('  ---|------|------|-----|-------------|-----|-----|------------');
    
    stats.forEach(s => {
      console.log(`  ${s.id.toString().padStart(2)} | ${s.messagesSent.toString().padStart(4)} | ${s.messagesReceived.toString().padStart(4)} | ${s.errors.toString().padStart(3)} | ${s.avgLatency.toString().padStart(9)}ms | ${s.minLatency.toString().padStart(3)} | ${s.maxLatency.toString().padStart(3)} | ${s.throughput.toString().padStart(8)} msg/s`);
    });
    
    // Performance analysis
    console.log('\n Performance Analysis:');
    if (totalErrors > 0) {
      console.log(`  ⚠️  ${totalErrors} errors occurred during the test`);
    }
    if (overallAvgLatency > 1000) {
      console.log(`  ⚠️  High average latency detected: ${Math.round(overallAvgLatency)}ms`);
    }
    const successRate = (totalMessagesReceived / totalMessagesSent) * 100;
    if (successRate < 95) {
      console.log(`  ⚠️  Low success rate: ${successRate.toFixed(2)}%`);
    }
    
    if (totalErrors === 0 && successRate >= 95 && overallAvgLatency < 1000) {
      console.log('  ✅ All performance metrics within acceptable ranges');
    }
  }
}

// Run load test
async function main() {
  const runner = new LoadTestRunner();
  
  try {
    await runner.run();
    process.exit(0);
  } catch (error) {
    console.error('💥 Fatal error:', error);
    process.exit(1);
  }
}

// Handle process termination
process.on('SIGINT', () => {
  console.log('\n⚠️  Load test interrupted');
  process.exit(130);
});

main();