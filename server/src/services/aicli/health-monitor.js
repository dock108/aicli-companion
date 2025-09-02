import { processMonitor } from '../../utils/process-monitor.js';

export class HealthMonitor {
  constructor(sessionManager, eventEmitter) {
    this.sessionManager = sessionManager;
    this.emit = eventEmitter.emit.bind(eventEmitter);
    this.processHealthCheckInterval = null;
  }

  startProcessHealthMonitoring() {
    // Skip in test environment to avoid async timers
    if (process.env.NODE_ENV === 'test') {
      return;
    }

    this.processHealthCheckInterval = setInterval(() => {
      this.checkAllProcessHealth().catch((error) => {
        console.error('Health check error:', error);
      });
    }, 30000); // Check every 30 seconds
  }

  stopProcessHealthMonitoring() {
    if (this.processHealthCheckInterval) {
      clearInterval(this.processHealthCheckInterval);
      this.processHealthCheckInterval = null;
    }
  }

  async checkAllProcessHealth() {
    const unhealthySessions = [];

    for (const [sessionId, session] of this.sessionManager.activeSessions) {
      if (session.process && session.process.pid) {
        try {
          const processInfo = await processMonitor.monitorProcess(session.process.pid);

          // Process doesn't exist anymore
          if (processInfo) {
            const health = processMonitor.checkHealth(processInfo);

            // Log health issues
            if (health.warnings.length > 0) {
              console.warn(`⚠️ Process health warnings for session ${sessionId}:`, health.warnings);
            }

            if (health.critical.length > 0) {
              console.error(
                `🚨 Process health critical for session ${sessionId}:`,
                health.critical
              );
              unhealthySessions.push({ sessionId, reason: health.critical.join(', ') });
            }
          } else {
            console.warn(
              `Process ${session.process.pid} for session ${sessionId} no longer exists`
            );
            unhealthySessions.push({ sessionId, reason: 'Process terminated unexpectedly' });
          }
        } catch (error) {
          console.error(`Failed to check health for session ${sessionId}:`, error);
        }
      }
    }

    // Clean up unhealthy sessions
    for (const { sessionId, reason } of unhealthySessions) {
      await this.sessionManager.cleanupDeadSession(sessionId);
      this.emit('sessionUnhealthy', { sessionId, reason });
    }
  }

  async healthCheck() {
    const health = {
      status: 'healthy',
      checks: {
        aicli: false,
        sessions: false,
        memory: false,
      },
      details: {},
    };

    // Check AICLI availability
    try {
      const availability = await this.checkAvailability();
      health.checks.aicli = availability.available;
      health.details.aicli = availability;
    } catch (error) {
      health.checks.aicli = false;
      health.details.aicli = { error: error.message };
    }

    // Check session health
    const sessions = this.sessionManager.getActiveSessions();
    health.checks.sessions = true;
    health.details.sessions = {
      active: sessions.length,
      sessions: sessions.map((s) => ({
        id: s.sessionId,
        started: s.startTime,
        workingDirectory: s.workingDirectory,
      })),
    };

    // Check memory usage
    const memUsage = process.memoryUsage();
    health.checks.memory = memUsage.heapUsed < 500 * 1024 * 1024; // Warn if > 500MB
    health.details.memory = memUsage;

    // Overall status
    health.status = Object.values(health.checks).every((check) => check) ? 'healthy' : 'unhealthy';

    return health;
  }

  checkSessionTimeout(sessionId) {
    const session = this.sessionManager.getSession(sessionId);
    if (!session) {
      return { timedOut: true, reason: 'Session not found' };
    }

    const lastActivity = session.lastActivity || session.startTime;
    if (!lastActivity) {
      return { timedOut: false };
    }

    const timeSinceActivity = Date.now() - new Date(lastActivity).getTime();
    const timeout = this.sessionManager.sessionTimeout;

    if (timeSinceActivity > timeout) {
      return {
        timedOut: true,
        reason: `Session inactive for ${Math.round(timeSinceActivity / 1000 / 60)} minutes`,
        lastActivity,
      };
    }

    return {
      timedOut: false,
      timeRemaining: timeout - timeSinceActivity,
      lastActivity,
    };
  }

  // Need reference to parent's checkAvailability method
  setCheckAvailabilityFn(fn) {
    this.checkAvailability = fn;
  }
}
