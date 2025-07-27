import os from 'os';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

export class ProcessMonitor {
  constructor() {
    this.metrics = new Map();
    this.thresholds = {
      memoryWarning: 500 * 1024 * 1024, // 500MB
      memoryCritical: 1024 * 1024 * 1024, // 1GB
      cpuWarning: 80, // 80%
      cpuCritical: 95, // 95%
    };
  }

  // Get system resource information
  async getSystemResources() {
    const totalMemory = os.totalmem();
    const freeMemory = os.freemem();
    const usedMemory = totalMemory - freeMemory;
    const memoryUsagePercent = (usedMemory / totalMemory) * 100;

    const cpus = os.cpus();
    const loadAverage = os.loadavg();

    return {
      memory: {
        total: totalMemory,
        free: freeMemory,
        used: usedMemory,
        percent: memoryUsagePercent,
      },
      cpu: {
        cores: cpus.length,
        model: cpus[0]?.model || 'Unknown',
        loadAverage: {
          '1min': loadAverage[0],
          '5min': loadAverage[1],
          '15min': loadAverage[2],
        },
      },
      uptime: os.uptime(),
    };
  }

  // Monitor a specific process
  async monitorProcess(pid) {
    if (!pid) return null;

    try {
      // Platform-specific process monitoring
      if (process.platform === 'darwin' || process.platform === 'linux') {
        // Use ps command to get process info
        const { stdout } = await execAsync(`ps -p ${pid} -o pid,rss,vsz,%cpu,%mem,etime,command`);
        const lines = stdout.trim().split('\n');
        
        if (lines.length < 2) {
          return null; // Process not found
        }

        const header = lines[0].trim().split(/\s+/);
        const data = lines[1].trim().split(/\s+/);
        
        const processInfo = {
          pid: parseInt(data[0]),
          rss: parseInt(data[1]) * 1024, // RSS in bytes (ps gives KB)
          vsz: parseInt(data[2]) * 1024, // VSZ in bytes
          cpu: parseFloat(data[3]),
          memory: parseFloat(data[4]),
          elapsed: data[5],
          command: data.slice(6).join(' '),
          timestamp: new Date().toISOString(),
        };

        // Store metrics
        this.updateMetrics(pid, processInfo);

        return processInfo;
      } else if (process.platform === 'win32') {
        // Windows process monitoring
        const { stdout } = await execAsync(
          `wmic process where ProcessId=${pid} get ProcessId,WorkingSetSize,VirtualSize,PercentProcessorTime /format:csv`
        );
        
        // Parse Windows output
        const lines = stdout.trim().split('\n').filter(line => line.trim());
        if (lines.length < 2) {
          return null;
        }

        const data = lines[lines.length - 1].split(',');
        
        return {
          pid: parseInt(pid),
          rss: parseInt(data[4]) || 0, // WorkingSetSize
          vsz: parseInt(data[5]) || 0, // VirtualSize
          cpu: 0, // Windows doesn't provide CPU % easily
          memory: 0,
          elapsed: 'N/A',
          command: 'Claude CLI',
          timestamp: new Date().toISOString(),
        };
      }
    } catch (error) {
      // Process likely doesn't exist
      return null;
    }
  }

  // Update metrics history
  updateMetrics(pid, info) {
    if (!this.metrics.has(pid)) {
      this.metrics.set(pid, {
        history: [],
        maxMemory: 0,
        maxCpu: 0,
        startTime: new Date(),
      });
    }

    const metrics = this.metrics.get(pid);
    metrics.history.push(info);
    
    // Keep only last 100 data points
    if (metrics.history.length > 100) {
      metrics.history.shift();
    }

    // Update max values
    metrics.maxMemory = Math.max(metrics.maxMemory, info.rss);
    metrics.maxCpu = Math.max(metrics.maxCpu, info.cpu);
  }

  // Check if process exceeds thresholds
  checkHealth(processInfo) {
    const warnings = [];
    const critical = [];

    if (processInfo.rss > this.thresholds.memoryCritical) {
      critical.push({
        type: 'memory',
        message: `Process using ${(processInfo.rss / 1024 / 1024).toFixed(2)}MB (critical threshold: ${(this.thresholds.memoryCritical / 1024 / 1024).toFixed(0)}MB)`,
      });
    } else if (processInfo.rss > this.thresholds.memoryWarning) {
      warnings.push({
        type: 'memory',
        message: `Process using ${(processInfo.rss / 1024 / 1024).toFixed(2)}MB (warning threshold: ${(this.thresholds.memoryWarning / 1024 / 1024).toFixed(0)}MB)`,
      });
    }

    if (processInfo.cpu > this.thresholds.cpuCritical) {
      critical.push({
        type: 'cpu',
        message: `Process using ${processInfo.cpu.toFixed(1)}% CPU (critical threshold: ${this.thresholds.cpuCritical}%)`,
      });
    } else if (processInfo.cpu > this.thresholds.cpuWarning) {
      warnings.push({
        type: 'cpu',
        message: `Process using ${processInfo.cpu.toFixed(1)}% CPU (warning threshold: ${this.thresholds.cpuWarning}%)`,
      });
    }

    return {
      healthy: critical.length === 0,
      warnings,
      critical,
    };
  }

  // Get process metrics summary
  getMetricsSummary(pid) {
    const metrics = this.metrics.get(pid);
    if (!metrics) return null;

    const recent = metrics.history.slice(-10);
    const avgMemory = recent.reduce((sum, m) => sum + m.rss, 0) / recent.length;
    const avgCpu = recent.reduce((sum, m) => sum + m.cpu, 0) / recent.length;

    return {
      pid,
      samples: metrics.history.length,
      duration: Date.now() - metrics.startTime.getTime(),
      memory: {
        current: recent[recent.length - 1]?.rss || 0,
        average: avgMemory,
        max: metrics.maxMemory,
      },
      cpu: {
        current: recent[recent.length - 1]?.cpu || 0,
        average: avgCpu,
        max: metrics.maxCpu,
      },
    };
  }

  // Clean up old metrics
  cleanup(activePids) {
    const pidsToKeep = new Set(activePids);
    
    for (const [pid, _] of this.metrics) {
      if (!pidsToKeep.has(pid)) {
        this.metrics.delete(pid);
      }
    }
  }
}

// Singleton instance
export const processMonitor = new ProcessMonitor();