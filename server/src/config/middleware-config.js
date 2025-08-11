import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { authMiddleware } from '../middleware/auth.js';
import { configureSecurity } from '../middleware/security.js';

/**
 * Middleware configuration manager
 */
export class MiddlewareConfig {
  /**
   * Configure basic middleware for the Express app (excluding auth)
   * @param {Express} app - Express application instance
   * @param {ServerConfig} config - Server configuration
   */
  static configure(app, config) {
    // Security middleware
    app.use(helmet(config.getHelmetConfig()));

    // Additional security for public exposure
    configureSecurity(app, config);

    // CORS configuration
    app.use(cors(config.getCorsConfig()));

    // Logging (skip in test environment)
    if (!config.isTest()) {
      app.use(morgan('combined'));
    }

    // Body parsing with size limits
    app.use(express.json({ limit: '10mb' }));
    app.use(express.urlencoded({ extended: true, limit: '10mb' }));
  }

  /**
   * Configure authentication middleware
   * @param {Express} app - Express application instance
   * @param {string} authToken - Auth token
   */
  static configureAuth(app, authToken) {
    if (authToken) {
      app.use('/api', authMiddleware(authToken));
    }
  }
}
