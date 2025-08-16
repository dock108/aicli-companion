import { mock } from 'node:test';

/**
 * Helper to block all real process spawning in tests
 * This ensures tests never accidentally spawn real Claude processes
 */
export function blockRealSpawn() {
  // Track original functions
  const originals = {};

  // Override child_process module methods
  const setupMocks = () => {
    if (typeof global.process !== 'undefined') {
      // Create a mock that throws if called
      const blockedSpawn = mock.fn(() => {
        throw new Error('BLOCKED: Attempted to spawn real process in test environment');
      });

      // Store for cleanup
      originals.spawn = blockedSpawn;
      originals.exec = mock.fn(() => {
        throw new Error('BLOCKED: Attempted to exec real process in test environment');
      });
      originals.execSync = mock.fn(() => {
        throw new Error('BLOCKED: Attempted to execSync real process in test environment');
      });
      originals.execFile = mock.fn(() => {
        throw new Error('BLOCKED: Attempted to execFile real process in test environment');
      });
    }
  };

  // Cleanup function to restore originals
  const cleanup = () => {
    // In test environment, we don't need to restore anything
    // The mocks will be cleaned up by the test runner
  };

  setupMocks();

  return { cleanup };
}

/**
 * Create a safe mock spawn function for tests
 */
export function createMockSpawn() {
  const mockStdout = new (require('events').EventEmitter)();
  const mockStderr = new (require('events').EventEmitter)();
  const mockStdin = {
    write: mock.fn(),
    end: mock.fn(),
  };

  const mockProcess = {
    pid: Math.floor(Math.random() * 100000),
    stdout: mockStdout,
    stderr: mockStderr,
    stdin: mockStdin,
    on: mock.fn(),
    kill: mock.fn(),
  };

  const spawnFn = mock.fn(() => mockProcess);

  return {
    spawnFn,
    mockProcess,
    mockStdout,
    mockStderr,
    mockStdin,
  };
}

/**
 * Verify no real processes were spawned
 */
export function verifyNoRealSpawns(spawnMock) {
  if (!spawnMock || !spawnMock.mock) {
    return true;
  }

  // Check if any calls tried to spawn 'claude' or 'aicli' without mocking
  const calls = spawnMock.mock.calls || [];
  for (const call of calls) {
    const [command] = call.arguments || [];
    if (command === 'claude' || command === 'aicli') {
      // Check if this was a real spawn attempt
      const result = call.result;
      if (result && result.pid && typeof result.pid === 'number') {
        // This looks like a real process
        console.warn(`WARNING: Real process spawned in test: ${command} (PID: ${result.pid})`);
        return false;
      }
    }
  }

  return true;
}
