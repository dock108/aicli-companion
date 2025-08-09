export function errorHandler(error, req, res, _next) {
  console.error('API Error:', error);

  // Handle different types of errors
  if (error.type === 'entity.parse.failed') {
    return res.status(400).json({
      error: 'Invalid JSON',
      message: 'The request body contains invalid JSON',
    });
  }

  if (error.code === 'ENOTFOUND') {
    return res.status(503).json({
      error: 'Service unavailable',
      message: 'Claude Code CLI not found or not accessible',
    });
  }

  if (error.code === 'ECONNREFUSED') {
    return res.status(503).json({
      error: 'Connection refused',
      message: 'Unable to connect to Claude Code service',
    });
  }

  // Default error response
  res.status(500).json({
    error: 'Internal server error',
    message:
      process.env.NODE_ENV === 'development' ? error.message : 'An unexpected error occurred',
  });
}
