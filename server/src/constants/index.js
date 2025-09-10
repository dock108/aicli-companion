/**
 * Application constants
 */

export const SERVER_VERSION = '1.0.0';

export const ERROR_CODES = {
  // Authentication errors
  AUTH_REQUIRED: 'AUTH_REQUIRED',
  INVALID_TOKEN: 'INVALID_TOKEN',

  // Request errors
  INVALID_REQUEST: 'INVALID_REQUEST',
  INVALID_JSON: 'INVALID_JSON',
  INVALID_INPUT: 'INVALID_INPUT',

  // Claude Code errors
  CLAUDE_ERROR: 'CLAUDE_ERROR',
  SESSION_ERROR: 'SESSION_ERROR',
  PERMISSION_ERROR: 'PERMISSION_ERROR',

  // File system errors
  DIRECTORY_NOT_FOUND: 'DIRECTORY_NOT_FOUND',
  NOT_A_DIRECTORY: 'NOT_A_DIRECTORY',
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  FORBIDDEN_PATH: 'FORBIDDEN_PATH',
  INVALID_PATH: 'INVALID_PATH',
  WORKING_DIRECTORY_ERROR: 'WORKING_DIRECTORY_ERROR',

  // Server errors
  INTERNAL_ERROR: 'INTERNAL_ERROR',
  SERVICE_UNAVAILABLE: 'SERVICE_UNAVAILABLE',
  CONNECTION_REFUSED: 'CONNECTION_REFUSED',
};

export const HTTP_STATUS_CODES = {
  OK: 200,
  BAD_REQUEST: 400,
  UNAUTHORIZED: 401,
  NOT_FOUND: 404,
  INTERNAL_SERVER_ERROR: 500,
  SERVICE_UNAVAILABLE: 503,
};

export const WEBSOCKET_EVENTS = {
  // Client to server
  ASK: 'ask',
  STREAM_START: 'streamStart',
  STREAM_SEND: 'streamSend',
  STREAM_CLOSE: 'streamClose',
  PERMISSION: 'permission',
  PING: 'ping',
  SUBSCRIBE: 'subscribe',
  SET_WORKING_DIRECTORY: 'setWorkingDirectory',
  CLAUDE_COMMAND: 'claudeCommand',

  // Server to client
  WELCOME: 'welcome',
  ASK_RESPONSE: 'askResponse',
  STREAM_STARTED: 'streamStarted',
  STREAM_SENT: 'streamSent',
  STREAM_CLOSED: 'streamClosed',
  STREAM_COMPLETE: 'streamComplete',
  STREAM_DATA: 'streamData',
  PONG: 'pong',
  SUBSCRIBED: 'subscribed',
  PERMISSION_REQUEST: 'permissionRequest',
  PERMISSION_HANDLED: 'permissionHandled',
  WORKING_DIRECTORY_SET: 'workingDirectorySet',
  CLAUDE_RESPONSE: 'claudeResponse',
  ERROR: 'error',

  // Claude Code events
  SYSTEM_INIT: 'systemInit',
  ASSISTANT_MESSAGE: 'assistantMessage',
  TOOL_USE: 'toolUse',
  TOOL_RESULT: 'toolResult',
  CONVERSATION_RESULT: 'conversationResult',
};

export const DEFAULT_CONFIG = {
  PORT: 3001,
  HOST: '0.0.0.0',
  MAX_SESSIONS: 10,
  SESSION_TIMEOUT: 30 * 60 * 1000, // 30 minutes
  BODY_LIMIT: '10mb',
  PING_INTERVAL: 30000, // 30 seconds
};

export const FORBIDDEN_PATHS = [
  '/etc/',
  '/proc/',
  '/sys/',
  '/dev/',
  '/root/',
  '/usr/bin/',
  '/sbin/',
  '/bin/',
  '/boot/',
  'C:\\Windows\\',
  'C:\\Program Files\\',
  'C:\\Program Files (x86)\\',
  'C:\\System32\\',
];
