export function authMiddleware(expectedToken) {
  return (req, res, next) => {
    // Skip auth for health check
    if (req.path === '/health') {
      return next();
    }
    
    const authHeader = req.headers.authorization;
    const token = authHeader?.startsWith('Bearer ') 
      ? authHeader.slice(7)
      : req.query.token;
    
    if (!token) {
      return res.status(401).json({
        error: 'Authentication required',
        message: 'Please provide a valid auth token'
      });
    }
    
    if (token !== expectedToken) {
      return res.status(401).json({
        error: 'Invalid token',
        message: 'The provided auth token is not valid'
      });
    }
    
    next();
  };
}