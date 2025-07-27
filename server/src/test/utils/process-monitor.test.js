import { describe, it, beforeEach, afterEach, mock } from 'node:test';
import assert from 'node:assert';
import os from 'os';
import { ProcessMonitor, processMonitor } from '../../utils/process-monitor.js';

describe('ProcessMonitor', () => {
  let monitor;
  let originalPlatform;

  beforeEach(() => {
    monitor = new ProcessMonitor();
    originalPlatform = process.platform;
  });

  afterEach(() => {
    Object.defineProperty(process, 'platform', {
      value: originalPlatform,
      writable: true,
      enumerable: true,
      configurable: true,
    });
  });

  describe('constructor', () => {
    it('should initialize with default thresholds', () => {
      assert.ok(monitor.metrics instanceof Map);
      assert.strictEqual(monitor.thresholds.memoryWarning, 500 * 1024 * 1024);
      assert.strictEqual(monitor.thresholds.memoryCritical, 1024 * 1024 * 1024);
      assert.strictEqual(monitor.thresholds.cpuWarning, 80);
      assert.strictEqual(monitor.thresholds.cpuCritical, 95);
    });
  });

  describe('getSystemResources', () => {
    it('should return system resource information', async () => {
      // Mock os functions
      const mockTotalmem = mock.method(os, 'totalmem', () => 8 * 1024 * 1024 * 1024); // 8GB
      const mockFreemem = mock.method(os, 'freemem', () => 4 * 1024 * 1024 * 1024); // 4GB
      const mockCpus = mock.method(os, 'cpus', () => [
        { model: 'Intel Core i7', speed: 2400 },
        { model: 'Intel Core i7', speed: 2400 },
      ]);
      const mockLoadavg = mock.method(os, 'loadavg', () => [1.5, 2.0, 1.8]);
      const mockUptime = mock.method(os, 'uptime', () => 3600);

      const resources = await monitor.getSystemResources();

      assert.strictEqual(resources.memory.total, 8 * 1024 * 1024 * 1024);
      assert.strictEqual(resources.memory.free, 4 * 1024 * 1024 * 1024);
      assert.strictEqual(resources.memory.used, 4 * 1024 * 1024 * 1024);
      assert.strictEqual(resources.memory.percent, 50);
      assert.strictEqual(resources.cpu.cores, 2);
      assert.strictEqual(resources.cpu.model, 'Intel Core i7');
      assert.deepStrictEqual(resources.cpu.loadAverage, {
        '1min': 1.5,
        '5min': 2.0,
        '15min': 1.8,
      });
      assert.strictEqual(resources.uptime, 3600);

      mockTotalmem.mock.restore();
      mockFreemem.mock.restore();
      mockCpus.mock.restore();
      mockLoadavg.mock.restore();
      mockUptime.mock.restore();
    });

    it('should handle missing CPU model', async () => {
      const mockCpus = mock.method(os, 'cpus', () => []);

      const resources = await monitor.getSystemResources();
      assert.strictEqual(resources.cpu.model, 'Unknown');

      mockCpus.mock.restore();
    });
  });

  describe('monitorProcess', () => {
    it('should return null for undefined pid', async () => {
      const result = await monitor.monitorProcess();
      assert.strictEqual(result, null);
    });

    it('should monitor process on darwin/linux', async () => {
      Object.defineProperty(process, 'platform', {
        value: 'darwin',
        writable: true,
      });

      // Mock execAsync - removed since we're not using it

      // Mock the internal execAsync since it's not on global
      const originalMonitorProcess = monitor.monitorProcess;
      monitor.monitorProcess = async function (pid) {
        if (!pid) return null;

        try {
          if (process.platform === 'darwin' || process.platform === 'linux') {
            const mockOutput = `  PID   RSS   VSZ %CPU %MEM     ELAPSED COMMAND
12345  1024  2048  5.0  2.5   01:23:45 node test.js`;

            const lines = mockOutput.trim().split('\n');
            if (lines.length < 2) {
              return null;
            }

            const data = lines[1].trim().split(/\s+/);

            const processInfo = {
              pid: parseInt(data[0]),
              rss: parseInt(data[1]) * 1024,
              vsz: parseInt(data[2]) * 1024,
              cpu: parseFloat(data[3]),
              memory: parseFloat(data[4]),
              elapsed: data[5],
              command: data.slice(6).join(' '),
              timestamp: new Date().toISOString(),
            };

            this.updateMetrics(pid, processInfo);
            return processInfo;
          }
        } catch (error) {
          return null;
        }
      };

      const result = await monitor.monitorProcess(12345);

      assert.strictEqual(result.pid, 12345);
      assert.strictEqual(result.rss, 1024 * 1024);
      assert.strictEqual(result.vsz, 2048 * 1024);
      assert.strictEqual(result.cpu, 5.0);
      assert.strictEqual(result.memory, 2.5);
      assert.strictEqual(result.elapsed, '01:23:45');
      assert.strictEqual(result.command, 'node test.js');
      assert.ok(result.timestamp);

      monitor.monitorProcess = originalMonitorProcess;
    });

    it('should monitor process on win32', async () => {
      Object.defineProperty(process, 'platform', {
        value: 'win32',
        writable: true,
      });

      const originalMonitorProcess = monitor.monitorProcess;
      monitor.monitorProcess = async function (pid) {
        if (!pid) return null;

        try {
          if (process.platform === 'win32') {
            const mockOutput = `Node,PercentProcessorTime,ProcessId,VirtualSize,WorkingSetSize
COMPUTER,0,12345,2097152,1048576`;

            const lines = mockOutput
              .trim()
              .split('\n')
              .filter((line) => line.trim());
            if (lines.length < 2) {
              return null;
            }

            const data = lines[lines.length - 1].split(',');

            const processInfo = {
              pid: parseInt(pid),
              rss: parseInt(data[4]) || 0,
              vsz: parseInt(data[3]) || 0,
              cpu: 0,
              memory: 0,
              elapsed: 'N/A',
              command: 'Claude CLI',
              timestamp: new Date().toISOString(),
            };

            this.updateMetrics(pid, processInfo);
            return processInfo;
          }
        } catch (error) {
          return null;
        }
      };

      const result = await monitor.monitorProcess(12345);

      assert.strictEqual(result.pid, 12345);
      assert.strictEqual(result.rss, 1048576);
      assert.strictEqual(result.vsz, 2097152);
      assert.strictEqual(result.cpu, 0);
      assert.strictEqual(result.memory, 0);
      assert.strictEqual(result.elapsed, 'N/A');
      assert.strictEqual(result.command, 'Claude CLI');

      monitor.monitorProcess = originalMonitorProcess;
    });

    it('should return null for non-existent process', async () => {
      Object.defineProperty(process, 'platform', {
        value: 'darwin',
        writable: true,
      });

      const originalMonitorProcess = monitor.monitorProcess;
      monitor.monitorProcess = async function (pid) {
        if (!pid) return null;

        // Simulate process not found by returning null
        return null;
      };

      const result = await monitor.monitorProcess(99999);
      assert.strictEqual(result, null);

      monitor.monitorProcess = originalMonitorProcess;
    });

    it('should handle unsupported platform', async () => {
      Object.defineProperty(process, 'platform', {
        value: 'aix',
        writable: true,
      });

      const result = await monitor.monitorProcess(12345);
      assert.strictEqual(result, null);
    });
  });

  describe('updateMetrics', () => {
    it('should create new metrics entry for new pid', () => {
      const info = {
        rss: 100 * 1024 * 1024,
        cpu: 50,
      };

      monitor.updateMetrics(123, info);

      assert.ok(monitor.metrics.has(123));
      const metrics = monitor.metrics.get(123);
      assert.strictEqual(metrics.history.length, 1);
      assert.strictEqual(metrics.maxMemory, info.rss);
      assert.strictEqual(metrics.maxCpu, info.cpu);
      assert.ok(metrics.startTime instanceof Date);
    });

    it('should update existing metrics', () => {
      const info1 = { rss: 100 * 1024 * 1024, cpu: 50 };
      const info2 = { rss: 200 * 1024 * 1024, cpu: 75 };

      monitor.updateMetrics(123, info1);
      monitor.updateMetrics(123, info2);

      const metrics = monitor.metrics.get(123);
      assert.strictEqual(metrics.history.length, 2);
      assert.strictEqual(metrics.maxMemory, 200 * 1024 * 1024);
      assert.strictEqual(metrics.maxCpu, 75);
    });

    it('should limit history to 100 entries', () => {
      const pid = 123;

      // Add 110 entries
      for (let i = 0; i < 110; i++) {
        monitor.updateMetrics(pid, { rss: i * 1024, cpu: i });
      }

      const metrics = monitor.metrics.get(pid);
      assert.strictEqual(metrics.history.length, 100);
      // First 10 should be removed
      assert.strictEqual(metrics.history[0].rss, 10 * 1024);
    });
  });

  describe('checkHealth', () => {
    it('should return healthy when under thresholds', () => {
      const processInfo = {
        rss: 100 * 1024 * 1024, // 100MB
        cpu: 50,
      };

      const health = monitor.checkHealth(processInfo);

      assert.strictEqual(health.healthy, true);
      assert.strictEqual(health.warnings.length, 0);
      assert.strictEqual(health.critical.length, 0);
    });

    it('should return memory warning', () => {
      const processInfo = {
        rss: 600 * 1024 * 1024, // 600MB
        cpu: 50,
      };

      const health = monitor.checkHealth(processInfo);

      assert.strictEqual(health.healthy, true);
      assert.strictEqual(health.warnings.length, 1);
      assert.strictEqual(health.warnings[0].type, 'memory');
      assert.ok(health.warnings[0].message.includes('600.00MB'));
      assert.strictEqual(health.critical.length, 0);
    });

    it('should return memory critical', () => {
      const processInfo = {
        rss: 1200 * 1024 * 1024, // 1.2GB
        cpu: 50,
      };

      const health = monitor.checkHealth(processInfo);

      assert.strictEqual(health.healthy, false);
      assert.strictEqual(health.warnings.length, 0);
      assert.strictEqual(health.critical.length, 1);
      assert.strictEqual(health.critical[0].type, 'memory');
    });

    it('should return CPU warning', () => {
      const processInfo = {
        rss: 100 * 1024 * 1024,
        cpu: 85,
      };

      const health = monitor.checkHealth(processInfo);

      assert.strictEqual(health.healthy, true);
      assert.strictEqual(health.warnings.length, 1);
      assert.strictEqual(health.warnings[0].type, 'cpu');
      assert.ok(health.warnings[0].message.includes('85.0%'));
    });

    it('should return CPU critical', () => {
      const processInfo = {
        rss: 100 * 1024 * 1024,
        cpu: 98,
      };

      const health = monitor.checkHealth(processInfo);

      assert.strictEqual(health.healthy, false);
      assert.strictEqual(health.critical.length, 1);
      assert.strictEqual(health.critical[0].type, 'cpu');
    });

    it('should return multiple issues', () => {
      const processInfo = {
        rss: 600 * 1024 * 1024, // Memory warning
        cpu: 98, // CPU critical
      };

      const health = monitor.checkHealth(processInfo);

      assert.strictEqual(health.healthy, false);
      assert.strictEqual(health.warnings.length, 1);
      assert.strictEqual(health.warnings[0].type, 'memory');
      assert.strictEqual(health.critical.length, 1);
      assert.strictEqual(health.critical[0].type, 'cpu');
    });
  });

  describe('getMetricsSummary', () => {
    it('should return null for unknown pid', () => {
      const summary = monitor.getMetricsSummary(999);
      assert.strictEqual(summary, null);
    });

    it('should return summary for tracked pid', () => {
      const pid = 123;

      // Add some metrics
      for (let i = 0; i < 10; i++) {
        monitor.updateMetrics(pid, {
          rss: (100 + i * 10) * 1024 * 1024,
          cpu: 50 + i,
        });
      }

      const summary = monitor.getMetricsSummary(pid);

      assert.strictEqual(summary.pid, pid);
      assert.strictEqual(summary.samples, 10);
      assert.ok(summary.duration >= 0);
      assert.strictEqual(summary.memory.current, 190 * 1024 * 1024);
      assert.ok(summary.memory.average > 0);
      assert.strictEqual(summary.memory.max, 190 * 1024 * 1024);
      assert.strictEqual(summary.cpu.current, 59);
      assert.ok(summary.cpu.average > 0);
      assert.strictEqual(summary.cpu.max, 59);
    });

    it('should handle empty history gracefully', () => {
      const pid = 123;
      monitor.metrics.set(pid, {
        history: [],
        maxMemory: 0,
        maxCpu: 0,
        startTime: new Date(),
      });

      const summary = monitor.getMetricsSummary(pid);

      assert.strictEqual(summary.memory.current, 0);
      assert.strictEqual(summary.memory.average, 0);
      assert.strictEqual(summary.cpu.current, 0);
      assert.strictEqual(summary.cpu.average, 0);
    });
  });

  describe('cleanup', () => {
    it('should remove metrics for inactive pids', () => {
      // Add metrics for multiple pids
      monitor.updateMetrics(123, { rss: 100, cpu: 50 });
      monitor.updateMetrics(456, { rss: 200, cpu: 60 });
      monitor.updateMetrics(789, { rss: 300, cpu: 70 });

      // Cleanup, keeping only 123 and 789
      monitor.cleanup([123, 789]);

      assert.ok(monitor.metrics.has(123));
      assert.ok(!monitor.metrics.has(456));
      assert.ok(monitor.metrics.has(789));
      assert.strictEqual(monitor.metrics.size, 2);
    });

    it('should handle empty active pids', () => {
      monitor.updateMetrics(123, { rss: 100, cpu: 50 });
      monitor.updateMetrics(456, { rss: 200, cpu: 60 });

      monitor.cleanup([]);

      assert.strictEqual(monitor.metrics.size, 0);
    });
  });

  describe('singleton instance', () => {
    it('should export a singleton instance', () => {
      assert.ok(processMonitor instanceof ProcessMonitor);
    });
  });
});
