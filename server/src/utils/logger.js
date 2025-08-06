/**
 * Simple logger utility with log levels and session context
 * Supports: debug, info, warn, error levels
 */

class Logger {
  constructor(module) {
    this.module = module;
    this.logLevel = process.env.LOG_LEVEL || 'info';
    this.levels = {
      debug: 0,
      info: 1,
      warn: 2,
      error: 3
    };
  }

  shouldLog(level) {
    return this.levels[level] >= this.levels[this.logLevel];
  }

  formatMessage(level, message, context = {}) {
    const timestamp = new Date().toISOString();
    const levelEmoji = {
      debug: '🔍',
      info: '📘',
      warn: '⚠️',
      error: '❌'
    }[level] || '';

    let output = `${timestamp} ${levelEmoji} [${level.toUpperCase()}] [${this.module}]`;
    
    // Add session context if available
    if (context.sessionId) {
      output += ` [Session: ${context.sessionId.substring(0, 8)}]`;
    }
    
    // Add request ID if available
    if (context.requestId) {
      output += ` [Req: ${context.requestId.substring(0, 8)}]`;
    }

    output += ` ${message}`;

    // Add any additional context as JSON
    const { sessionId, requestId, ...extraContext } = context;
    if (Object.keys(extraContext).length > 0) {
      output += ` ${JSON.stringify(extraContext)}`;
    }

    return output;
  }

  debug(message, context) {
    if (this.shouldLog('debug')) {
      console.log(this.formatMessage('debug', message, context));
    }
  }

  info(message, context) {
    if (this.shouldLog('info')) {
      console.log(this.formatMessage('info', message, context));
    }
  }

  warn(message, context) {
    if (this.shouldLog('warn')) {
      console.warn(this.formatMessage('warn', message, context));
    }
  }

  error(message, context) {
    if (this.shouldLog('error')) {
      console.error(this.formatMessage('error', message, context));
    }
  }

  // Helper for logging session operations
  session(operation, sessionId, details = {}) {
    const sessionShort = sessionId ? sessionId.substring(0, 8) : 'no-session';
    this.info(`Session ${operation}: ${sessionShort}`, {
      sessionId,
      ...details
    });
  }

  // Helper for logging stream operations (reduces verbosity)
  stream(operation, sessionId, details = {}) {
    // Only log stream operations at debug level to reduce noise
    this.debug(`Stream ${operation}`, {
      sessionId,
      ...details
    });
  }

  // Helper for logging chunks (only logs summaries)
  chunk(sessionId, chunk, chunkCount = 0) {
    // Only log every 10th chunk or final chunks
    if (chunkCount % 10 === 0 || chunk.isFinal) {
      this.debug(`Stream chunk #${chunkCount}${chunk.isFinal ? ' (final)' : ''}`, {
        sessionId,
        size: chunk.content?.length || 0,
        type: chunk.type
      });
    }
  }

  // Create a child logger with default context
  child(defaultContext) {
    const childLogger = new Logger(this.module);
    
    // Wrap all methods to include default context
    const methods = ['debug', 'info', 'warn', 'error', 'session', 'stream'];
    methods.forEach(method => {
      const originalMethod = childLogger[method].bind(childLogger);
      childLogger[method] = (message, context = {}) => {
        originalMethod(message, { ...defaultContext, ...context });
      };
    });

    return childLogger;
  }
}

// Factory function to create loggers
function createLogger(module) {
  return new Logger(module);
}

// Export singleton instances for common modules
export { createLogger };

// Pre-configured loggers for major services
export const wsLogger = createLogger('WebSocket');
export const aicliLogger = createLogger('AICLI');
export const sessionLogger = createLogger('SessionManager');
export const queueLogger = createLogger('MessageQueue');

// Log level helpers
export const setLogLevel = (level) => {
  process.env.LOG_LEVEL = level;
};

export const getLogLevel = () => {
  return process.env.LOG_LEVEL || 'info';
};