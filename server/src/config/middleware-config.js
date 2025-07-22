import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { authMiddleware } from '../middleware/auth.js';

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

    // CORS configuration
    app.use(cors(config.getCorsConfig()));

    // Logging (skip in test environment)
    if (!config.isTest()) {
      app.use(morgan('combined'));
    }

    // Body parsing
    app.use(express.json({ limit: '10mb' }));
    app.use(express.urlencoded({ extended: true }));
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
