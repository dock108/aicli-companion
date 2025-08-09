/**
 * Test cleanup helper to ensure services are properly shut down
 */
import { getTelemetryService } from '../../services/telemetry.js';
import { getMessageQueueService } from '../../services/message-queue.js';

export function cleanupServices() {
  // Shutdown telemetry service if it was initialized
  try {
    const telemetryService = getTelemetryService();
    if (telemetryService && telemetryService.cleanupInterval) {
      telemetryService.shutdown();
    }
  } catch (error) {
    // Ignore errors during cleanup
  }

  // Shutdown message queue service if it was initialized
  try {
    const messageQueueService = getMessageQueueService();
    if (messageQueueService && messageQueueService.cleanupInterval) {
      messageQueueService.shutdown();
    }
  } catch (error) {
    // Ignore errors during cleanup
  }
}

// Register cleanup on process exit for tests
if (process.env.NODE_ENV === 'test') {
  process.on('exit', cleanupServices);
  process.on('SIGINT', () => {
    cleanupServices();
    process.exit(0);
  });
  process.on('SIGTERM', () => {
    cleanupServices();
    process.exit(0);
  });
}
