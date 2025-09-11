/**
 * Singleton instance of AICLIService
 * This allows the service to be imported and used across different modules
 */

import { AICLIService } from './aicli.js';

// Create singleton instance
export const aicliService = new AICLIService();

// Also export the class for testing
export { AICLIService };
