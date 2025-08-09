/**
 * Global test setup to ensure clean test environment
 */

// Ensure NODE_ENV is set to test
process.env.NODE_ENV = 'test';

// Track all intervals created during tests
const originalSetInterval = global.setInterval;
const activeIntervals = new Set();

global.setInterval = function (callback, delay, ...args) {
  const intervalId = originalSetInterval(callback, delay, ...args);
  activeIntervals.add(intervalId);
  return intervalId;
};

const originalClearInterval = global.clearInterval;
global.clearInterval = function (intervalId) {
  activeIntervals.delete(intervalId);
  return originalClearInterval(intervalId);
};

// Clean up on exit
process.on('exit', () => {
  // Clear any remaining intervals
  for (const intervalId of activeIntervals) {
    clearInterval(intervalId);
  }
});

// Import cleanup helper to register cleanup handlers
import './cleanup.js';
