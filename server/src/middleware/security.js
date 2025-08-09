import rateLimit from 'express-rate-limit';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('Security');

// Track failed auth attempts per IP
const failedAuthAttempts = new Map();

/**
 * Create rate limiter for API endpoints
 * @param {boolean} isPublic - Whether server is publicly exposed
 * @returns {Function} Express middleware
 */
export function createRateLimiter(isPublic = false) {
  // More restrictive limits for public exposure
  const windowMs = 1 * 60 * 1000; // 1 minute
  const maxRequests = isPublic ? 50 : 100; // 50/min for public, 100/min for local
  
  return rateLimit({
    windowMs,
    max: maxRequests,
    message: 'Too many requests, please try again later',
    standardHeaders: true,
    legacyHeaders: false,
    handler: (req, res) => {
      logger.warn(`Rate limit exceeded for IP: ${req.ip}`);
      res.status(429).json({
        error: 'Too Many Requests',
        message: 'Rate limit exceeded. Please wait before making more requests.',
        retryAfter: Math.ceil(windowMs / 1000),
      });
    },
  });
}

/**
 * Create strict rate limiter for auth endpoints
 * @returns {Function} Express middleware
 */
export function createAuthRateLimiter() {
  return rateLimit({
    windowMs: 15 * 60 * 1000, // 15 minutes
    max: 5, // 5 attempts per 15 minutes
    skipSuccessfulRequests: true, // Only count failed attempts
    message: 'Too many failed authentication attempts',
    handler: (req, res) => {
      const ip = req.ip;
      logger.error(`Auth rate limit exceeded for IP: ${ip}`);
      
      // Track failed attempts
      const attempts = failedAuthAttempts.get(ip) || 0;
      failedAuthAttempts.set(ip, attempts + 1);
      
      // Block IP after too many failures
      if (attempts >= 10) {
        logger.error(`IP ${ip} blocked after ${attempts} failed auth attempts`);
      }
      
      res.status(429).json({
        error: 'Too Many Authentication Attempts',
        message: 'Account temporarily locked. Please try again later.',
        retryAfter: 900, // 15 minutes
      });
    },
  });
}

/**
 * Middleware to check if IP is blocked
 * @returns {Function} Express middleware
 */
export function blockListMiddleware() {
  return (req, res, next) => {
    const ip = req.ip;
    const attempts = failedAuthAttempts.get(ip) || 0;
    
    if (attempts >= 10) {
      logger.warn(`Blocked request from banned IP: ${ip}`);
      return res.status(403).json({
        error: 'Forbidden',
        message: 'Your IP has been temporarily blocked due to suspicious activity',
      });
    }
    
    next();
  };
}

/**
 * Clear failed attempts for an IP (on successful auth)
 * @param {string} ip - IP address to clear
 */
export function clearFailedAttempts(ip) {
  if (failedAuthAttempts.has(ip)) {
    failedAuthAttempts.delete(ip);
    logger.info(`Cleared failed auth attempts for IP: ${ip}`);
  }
}

/**
 * Track failed authentication attempt
 * @param {string} ip - IP address
 */
export function trackFailedAuth(ip) {
  const attempts = failedAuthAttempts.get(ip) || 0;
  failedAuthAttempts.set(ip, attempts + 1);
  logger.warn(`Failed auth attempt from IP ${ip} (attempt ${attempts + 1})`);
  
  if (attempts + 1 >= 5) {
    logger.warn(`⚠️ IP ${ip} has ${attempts + 1} failed auth attempts`);
  }
}

/**
 * Security headers middleware
 * @param {boolean} isPublic - Whether server is publicly exposed
 * @returns {Function} Express middleware
 */
export function securityHeaders(isPublic = false) {
  return (req, res, next) => {
    // Additional security headers for public exposure
    if (isPublic) {
      res.setHeader('X-Content-Type-Options', 'nosniff');
      res.setHeader('X-Frame-Options', 'DENY');
      res.setHeader('X-XSS-Protection', '1; mode=block');
      res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
      res.setHeader('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
    }
    
    next();
  };
}

/**
 * Request validation middleware
 * @returns {Function} Express middleware
 */
export function validateRequest() {
  return (req, res, next) => {
    // Validate content-type for POST/PUT requests
    if (['POST', 'PUT', 'PATCH'].includes(req.method)) {
      const contentType = req.get('content-type');
      if (!contentType || !contentType.includes('application/json')) {
        return res.status(400).json({
          error: 'Bad Request',
          message: 'Content-Type must be application/json',
        });
      }
    }
    
    // Validate request size (already handled by express.json limit)
    // Additional validation can be added here
    
    next();
  };
}

/**
 * Configure all security middleware
 * @param {Express} app - Express application
 * @param {Object} config - Server configuration
 */
export function configureSecurity(app, config) {
  const isPublic = config.isInternetExposed;
  
  // Apply security headers
  app.use(securityHeaders(isPublic));
  
  // Apply block list check
  app.use(blockListMiddleware());
  
  // Apply rate limiting
  app.use('/api', createRateLimiter(isPublic));
  
  // Strict rate limiting for auth endpoints
  app.use('/api/auth', createAuthRateLimiter());
  
  // Request validation
  app.use('/api', validateRequest());
  
  logger.info(`Security middleware configured (public: ${isPublic})`);
}