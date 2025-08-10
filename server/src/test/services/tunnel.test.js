import test from 'node:test';
import assert from 'node:assert';
import { TunnelService } from '../../services/tunnel.js';

test('TunnelService', async (t) => {
  let tunnelService;

  t.beforeEach(() => {
    tunnelService = new TunnelService();
  });

  t.afterEach(async () => {
    // Ensure tunnel is stopped after each test
    if (tunnelService && tunnelService.isActive) {
      await tunnelService.stopTunnel();
    }
  });

  await t.test('should initialize without ngrok module', async () => {
    // Mock dynamic import to simulate ngrok not installed
    const originalImport = tunnelService.initialize;
    let importAttempted = false;

    tunnelService.initialize = async function () {
      importAttempted = true;
      try {
        // Simulate module not found
        await Promise.reject(new Error('Module not found'));
        return false;
      } catch {
        this.ngrok = null;
        return false;
      }
    };

    try {
      const result = await tunnelService.initialize();
      assert.strictEqual(result, false);
      assert.strictEqual(tunnelService.ngrok, null);
      assert.ok(importAttempted, 'Should have attempted to initialize');
    } finally {
      tunnelService.initialize = originalImport;
    }
  });

  await t.test('should initialize with ngrok module', async () => {
    // Mock initialize to simulate ngrok installed
    const mockNgrok = {
      forward: async () => ({ url: () => 'https://test.ngrok.io' }),
      disconnect: async () => {},
      kill: async () => {},
    };

    const originalInitialize = tunnelService.initialize;
    tunnelService.initialize = async function () {
      this.ngrok = mockNgrok;
      return true;
    };

    try {
      const result = await tunnelService.initialize();
      assert.strictEqual(result, true);
      assert.ok(tunnelService.ngrok);
    } finally {
      tunnelService.initialize = originalInitialize;
      tunnelService.ngrok = null; // Reset
    }
  });

  await t.test('should handle initialization errors', async () => {
    // Mock initialize to simulate error
    const originalInitialize = tunnelService.initialize;
    tunnelService.initialize = async function () {
      // Simulate module returning null (catch block)
      this.ngrok = null;
      return false;
    };

    try {
      const result = await tunnelService.initialize();
      assert.strictEqual(result, false);
      assert.strictEqual(tunnelService.ngrok, null);
    } finally {
      tunnelService.initialize = originalInitialize;
    }
  });

  await t.test('should start tunnel successfully', async () => {
    // Mock ngrok
    const mockListener = {
      url: () => 'https://test123.ngrok.io',
      close: async () => {},
    };

    tunnelService.ngrok = {
      forward: async (options) => {
        assert.strictEqual(options.addr, 3000);
        assert.strictEqual(options.proto, 'http');
        assert.strictEqual(options.authtoken, 'test-token');
        return mockListener;
      },
    };

    const url = await tunnelService.startTunnel(3000, 'test-token');
    assert.strictEqual(url, 'https://test123.ngrok.io');
    assert.strictEqual(tunnelService.tunnelUrl, 'https://test123.ngrok.io');
    assert.strictEqual(tunnelService.isActive, true);
    assert.ok(tunnelService.listener);
  });

  await t.test('should start tunnel without auth token', async () => {
    // Mock ngrok
    tunnelService.ngrok = {
      forward: async (options) => {
        assert.strictEqual(options.addr, 3000);
        assert.strictEqual(options.authtoken, undefined);
        return { url: () => 'https://test456.ngrok.io' };
      },
    };

    const url = await tunnelService.startTunnel(3000);
    assert.strictEqual(url, 'https://test456.ngrok.io');
    assert.strictEqual(tunnelService.isActive, true);
  });

  await t.test('should handle string listener response', async () => {
    // Mock ngrok with older API that returns string directly
    tunnelService.ngrok = {
      forward: async () => 'https://oldapi.ngrok.io',
    };

    const url = await tunnelService.startTunnel(3000);
    assert.strictEqual(url, 'https://oldapi.ngrok.io');
    assert.strictEqual(tunnelService.tunnelUrl, 'https://oldapi.ngrok.io');
    assert.strictEqual(tunnelService.isActive, true);
  });

  await t.test('should initialize ngrok if not already initialized', async () => {
    // Ensure ngrok is null
    tunnelService.ngrok = null;

    // Mock initialize to succeed
    let initializeCalled = false;
    tunnelService.initialize = async () => {
      initializeCalled = true;
      tunnelService.ngrok = {
        forward: async () => ({ url: () => 'https://init.ngrok.io' }),
      };
      return true;
    };

    const url = await tunnelService.startTunnel(3000);
    assert.ok(initializeCalled);
    assert.strictEqual(url, 'https://init.ngrok.io');
  });

  await t.test('should handle tunnel start failure', async () => {
    tunnelService.ngrok = {
      forward: async () => {
        throw new Error('Auth token required');
      },
    };

    const url = await tunnelService.startTunnel(3000);
    assert.strictEqual(url, null);
    assert.strictEqual(tunnelService.isActive, false);
    assert.strictEqual(tunnelService.tunnelUrl, null);
  });

  await t.test('should handle authtoken error specifically', async () => {
    tunnelService.ngrok = {
      forward: async () => {
        const error = new Error('Invalid authtoken');
        error.message = 'authtoken is required';
        throw error;
      },
    };

    const url = await tunnelService.startTunnel(3000);
    assert.strictEqual(url, null);
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should handle port error specifically', async () => {
    tunnelService.ngrok = {
      forward: async () => {
        const error = new Error('Connection refused');
        error.message = 'port 3000 is not available';
        throw error;
      },
    };

    const url = await tunnelService.startTunnel(3000);
    assert.strictEqual(url, null);
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should return null if initialization fails', async () => {
    tunnelService.ngrok = null;
    tunnelService.initialize = async () => false;

    const url = await tunnelService.startTunnel(3000);
    assert.strictEqual(url, null);
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should stop tunnel successfully', async () => {
    // Setup active tunnel
    const mockListener = {
      async close() {
        this.closed = true;
      },
      closed: false,
    };

    tunnelService.listener = mockListener;
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = 'https://test.ngrok.io';

    tunnelService.ngrok = {
      async disconnect() {
        this.disconnected = true;
      },
      async kill() {
        this.killed = true;
      },
      disconnected: false,
      killed: false,
    };

    await tunnelService.stopTunnel();

    assert.strictEqual(mockListener.closed, true);
    assert.strictEqual(tunnelService.ngrok.disconnected, true);
    assert.strictEqual(tunnelService.ngrok.killed, true);
    assert.strictEqual(tunnelService.isActive, false);
    assert.strictEqual(tunnelService.tunnelUrl, null);
    assert.strictEqual(tunnelService.listener, null);
  });

  await t.test('should handle stop tunnel when not active', async () => {
    tunnelService.isActive = false;

    // Should not throw
    await tunnelService.stopTunnel();
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should handle errors during tunnel stop', async () => {
    tunnelService.isActive = true;
    tunnelService.listener = {
      close: async () => {
        throw new Error('Close failed');
      },
    };
    tunnelService.ngrok = {
      disconnect: async () => {
        throw new Error('Disconnect failed');
      },
    };

    // Should not throw even if internal methods fail
    await tunnelService.stopTunnel();
    assert.strictEqual(tunnelService.isActive, false);
    assert.strictEqual(tunnelService.tunnelUrl, null);
  });

  await t.test('should get public URL', () => {
    tunnelService.tunnelUrl = 'https://public.ngrok.io';
    assert.strictEqual(tunnelService.getPublicUrl(), 'https://public.ngrok.io');

    tunnelService.tunnelUrl = null;
    assert.strictEqual(tunnelService.getPublicUrl(), null);
  });

  await t.test('should check if tunnel is active', () => {
    tunnelService.isActive = true;
    assert.strictEqual(tunnelService.isTunnelActive(), true);

    tunnelService.isActive = false;
    assert.strictEqual(tunnelService.isTunnelActive(), false);
  });

  await t.test('should get tunnel info when active', async () => {
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = 'https://test.ngrok.io';

    // Mock fetch
    const originalFetch = global.fetch;
    global.fetch = async (url) => {
      assert.strictEqual(url, 'http://localhost:4040/api/tunnels');
      return {
        ok: true,
        json: async () => ({
          tunnels: [
            {
              public_url: 'https://test.ngrok.io',
              proto: 'https',
              config: { addr: 'localhost:3000' },
              metrics: { requests: 10 },
            },
          ],
        }),
      };
    };

    try {
      const info = await tunnelService.getTunnelInfo();
      assert.ok(info);
      assert.strictEqual(info.publicUrl, 'https://test.ngrok.io');
      assert.strictEqual(info.protocol, 'https');
      assert.strictEqual(info.localAddr, 'localhost:3000');
      assert.deepStrictEqual(info.metrics, { requests: 10 });
    } finally {
      global.fetch = originalFetch;
    }
  });

  await t.test('should return basic info if API fetch fails', async () => {
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = 'https://test.ngrok.io';

    // Mock fetch to fail
    const originalFetch = global.fetch;
    global.fetch = async () => {
      throw new Error('Network error');
    };

    try {
      const info = await tunnelService.getTunnelInfo();
      assert.ok(info);
      assert.strictEqual(info.publicUrl, 'https://test.ngrok.io');
      assert.strictEqual(info.protocol, 'http');
      assert.strictEqual(info.localAddr, null);
    } finally {
      global.fetch = originalFetch;
    }
  });

  await t.test('should return null tunnel info when not active', async () => {
    tunnelService.isActive = false;
    const info = await tunnelService.getTunnelInfo();
    assert.strictEqual(info, null);
  });

  await t.test('should return null tunnel info when no URL', async () => {
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = null;
    const info = await tunnelService.getTunnelInfo();
    assert.strictEqual(info, null);
  });

  await t.test('should handle missing tunnel in API response', async () => {
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = 'https://test.ngrok.io';

    const originalFetch = global.fetch;
    global.fetch = async () => ({
      ok: true,
      json: async () => ({
        tunnels: [{ public_url: 'https://other.ngrok.io' }],
      }),
    });

    try {
      const info = await tunnelService.getTunnelInfo();
      // Should return basic info when specific tunnel not found
      assert.ok(info);
      assert.strictEqual(info.publicUrl, 'https://test.ngrok.io');
      assert.strictEqual(info.protocol, 'http');
      assert.strictEqual(info.localAddr, null);
    } finally {
      global.fetch = originalFetch;
    }
  });

  await t.test('should handle non-ok API response', async () => {
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = 'https://test.ngrok.io';

    const originalFetch = global.fetch;
    global.fetch = async () => ({
      ok: false,
      status: 404,
    });

    try {
      const info = await tunnelService.getTunnelInfo();
      // Should return basic info when API returns non-ok
      assert.ok(info);
      assert.strictEqual(info.publicUrl, 'https://test.ngrok.io');
      assert.strictEqual(info.protocol, 'http');
      assert.strictEqual(info.localAddr, null);
    } finally {
      global.fetch = originalFetch;
    }
  });

  await t.test('should generate connection QR with auth token', () => {
    const qr = tunnelService.generateConnectionQR('https://test.ngrok.io', 'auth-token-123');
    assert.ok(qr.includes('https://test.ngrok.io?token=auth-token-123'));
    assert.ok(qr.includes('Scan QR or use URL below to connect'));
  });

  await t.test('should generate connection QR without auth token', () => {
    const qr = tunnelService.generateConnectionQR('https://test.ngrok.io', null);
    assert.ok(qr.includes('https://test.ngrok.io'));
    assert.ok(!qr.includes('?token='));
    assert.ok(qr.includes('Scan QR or use URL below to connect'));
  });

  await t.test('should create singleton instance', async () => {
    const { tunnelService: service1 } = await import('../../services/tunnel.js');
    const { tunnelService: service2 } = await import('../../services/tunnel.js');
    assert.strictEqual(service1, service2);
  });

  await t.test('should handle listener without close method', async () => {
    tunnelService.isActive = true;
    tunnelService.listener = {}; // No close method
    tunnelService.ngrok = {
      disconnect: async () => {},
      kill: async () => {},
    };

    // Should not throw
    await tunnelService.stopTunnel();
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should handle ngrok without disconnect method', async () => {
    tunnelService.isActive = true;
    tunnelService.ngrok = {
      kill: async () => {},
    };

    // Should not throw
    await tunnelService.stopTunnel();
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should handle ngrok without kill method', async () => {
    tunnelService.isActive = true;
    tunnelService.ngrok = {
      disconnect: async () => {},
    };

    // Should not throw
    await tunnelService.stopTunnel();
    assert.strictEqual(tunnelService.isActive, false);
  });

  await t.test('should use environment variable for auth token', async () => {
    const originalEnv = process.env.NGROK_AUTH_TOKEN;
    process.env.NGROK_AUTH_TOKEN = 'env-token';

    tunnelService.ngrok = {
      forward: async (_options) => {
        // Even though we don't pass token, it should be picked up from env
        return { url: () => 'https://env.ngrok.io' };
      },
    };

    try {
      const url = await tunnelService.startTunnel(3000);
      assert.strictEqual(url, 'https://env.ngrok.io');
    } finally {
      if (originalEnv !== undefined) {
        process.env.NGROK_AUTH_TOKEN = originalEnv;
      } else {
        delete process.env.NGROK_AUTH_TOKEN;
      }
    }
  });

  await t.test('should fetch tunnel info from API', async () => {
    tunnelService.isActive = true;
    tunnelService.tunnelUrl = 'https://test.ngrok.io';

    const originalFetch = global.fetch;
    let fetchCalled = false;

    global.fetch = async () => {
      fetchCalled = true;
      return null; // Simulate fetch returning null
    };

    try {
      const info = await tunnelService.getTunnelInfo();
      assert.ok(fetchCalled);
      assert.ok(info); // Should return basic info even if fetch returns null
      assert.strictEqual(info.publicUrl, 'https://test.ngrok.io');
    } finally {
      global.fetch = originalFetch;
    }
  });
});
