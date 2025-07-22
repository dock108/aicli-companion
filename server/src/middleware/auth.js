import { createHash, timingSafeEqual } from 'crypto';

function constantTimeCompare(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') {
    return false;
  }

  const aHash = createHash('sha256').update(a).digest();
  const bHash = createHash('sha256').update(b).digest();

  if (aHash.length !== bHash.length) {
    return false;
  }

  return timingSafeEqual(aHash, bHash);
}

function sanitizeToken(token) {
  if (typeof token !== 'string') {
    return null;
  }

  // Remove any control characters and limit length
  // eslint-disable-next-line no-control-regex
  const sanitized = token.replace(/[\x00-\x1F\x7F]/g, '').substring(0, 1024);

  // Basic validation - must be alphanumeric with allowed special chars
  if (!/^[a-zA-Z0-9_\-=+/]+$/.test(sanitized)) {
    return null;
  }

  return sanitized;
}

export function authMiddleware(expectedToken) {
  if (!expectedToken || typeof expectedToken !== 'string') {
    throw new Error('Expected token must be a non-empty string');
  }

  return (req, res, next) => {
    // Skip auth for health check
    if (req.path === '/health') {
      return next();
    }

    const authHeader = req.headers.authorization;
    const rawToken = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : req.query.token;

    const token = sanitizeToken(rawToken);

    if (!token) {
      return res.status(401).json({
        error: 'Authentication required',
        message: 'Please provide a valid auth token',
      });
    }

    // Use constant-time comparison to prevent timing attacks
    if (!constantTimeCompare(token, expectedToken)) {
      return res.status(401).json({
        error: 'Invalid token',
        message: 'The provided auth token is not valid',
      });
    }

    next();
  };
}
