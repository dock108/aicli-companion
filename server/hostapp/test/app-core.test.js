import { describe, it, expect, vi, beforeEach } from 'vitest';
import * as appCore from '../src/app-core.js';

describe('Claude Companion Host App Core', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    localStorage.clear();
    
    // Reset state
    appCore.setServerStatus({
      running: false,
      port: 3001,
      pid: null,
      healthUrl: null,
      external: false
    });
    appCore.setLocalIp('');
    appCore.setConfigPath('');
    
    // Set up DOM elements
    appCore.setElements({
      configPathInput: { value: '', addEventListener: vi.fn() },
      browseBtn: { addEventListener: vi.fn(), disabled: false },
      portInput: { value: '3001', addEventListener: vi.fn() },
      statusDot: { classList: { add: vi.fn(), remove: vi.fn() } },
      statusText: { textContent: '' },
      serverInfo: { style: { display: 'none' } },
      serverUrl: { textContent: '' },
      serverPid: { textContent: '' },
      startBtn: { 
        addEventListener: vi.fn(), 
        disabled: false,
        classList: { add: vi.fn(), remove: vi.fn() }
      },
      stopBtn: { 
        addEventListener: vi.fn(), 
        disabled: true,
        title: ''
      },
      qrSection: { style: { display: 'none' } },
      qrCanvas: { innerHTML: '' },
      connectionString: { textContent: '' },
      externalNotice: { style: { display: 'none' } }
    });
  });

  describe('Config Management', () => {
    it('should load saved config from localStorage', async () => {
      const savedConfig = {
        configPath: '/custom/path',
        port: 3002
      };
      localStorage.setItem('claude-companion-config', JSON.stringify(savedConfig));
      
      await appCore.loadConfig();
      
      expect(appCore.getConfigPath()).toBe('/custom/path');
      expect(appCore.getServerStatus().port).toBe(3002);
      expect(appCore.getElements().configPathInput.value).toBe('/custom/path');
      expect(appCore.getElements().portInput.value).toBe(3002);
    });

    it('should use default path if no saved config', async () => {
      await appCore.loadConfig();
      
      expect(appCore.getConfigPath()).toContain('claude-companion');
      expect(appCore.getElements().configPathInput.value).toContain('claude-companion');
    });

    it('should save config to localStorage', async () => {
      appCore.setConfigPath('/test/path');
      appCore.getElements().portInput.value = '3003';
      
      await appCore.saveConfig();
      
      const saved = JSON.parse(localStorage.getItem('claude-companion-config'));
      expect(saved.configPath).toBe('/test/path');
      expect(saved.port).toBe(3003);
    });

    it('should get default path using appDataDir', async () => {
      const path = await appCore.getDefaultPath();
      
      expect(path).toBe('/Users/test/Library/Application Support/claude-companion');
    });
  });

  describe('Server Management', () => {
    it('should start server successfully', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      
      await appCore.startServer();
      
      expect(invoke).toHaveBeenCalledWith('start_server', { 
        port: 3001,
        authToken: null,
        configPath: ''
      });
      expect(appCore.getElements().startBtn.disabled).toBe(false);
      expect(appCore.getElements().startBtn.classList.remove).toHaveBeenCalledWith('loading');
    });

    it('should handle server start failure', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      invoke.mockRejectedValueOnce(new Error('Port already in use'));
      
      await appCore.startServer();
      
      expect(global.alert).toHaveBeenCalledWith('Failed to start server: Error: Port already in use');
    });

    it('should stop server successfully', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      appCore.setServerStatus({ ...appCore.getServerStatus(), running: true });
      
      await appCore.stopServer();
      
      expect(invoke).toHaveBeenCalledWith('stop_server', { force_external: false });
      expect(appCore.getServerStatus().running).toBe(false);
      expect(appCore.getServerStatus().pid).toBe(null);
    });

    it('should handle external server stop with confirmation', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      invoke.mockRejectedValueOnce(new Error('not started by this app'));
      global.confirm.mockReturnValueOnce(true);
      appCore.setServerStatus({ ...appCore.getServerStatus(), port: 3001 });
      
      await appCore.stopServer();
      
      expect(global.confirm).toHaveBeenCalled();
      expect(invoke).toHaveBeenCalledWith('stop_server', { force_external: true });
    });

    it('should cancel external server stop if not confirmed', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      invoke.mockRejectedValueOnce(new Error('not started by this app'));
      global.confirm.mockReturnValueOnce(false);
      
      await appCore.stopServer();
      
      expect(global.confirm).toHaveBeenCalled();
      expect(invoke).toHaveBeenCalledTimes(1);
    });

    it('should check server health', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      invoke.mockResolvedValueOnce(true);
      appCore.setServerStatus({ ...appCore.getServerStatus(), running: true, port: 3001 });
      
      await appCore.checkServerHealth();
      
      expect(invoke).toHaveBeenCalledWith('check_server_health', { port: 3001 });
      expect(appCore.getServerStatus().running).toBe(true);
    });

    it('should detect when server dies during health check', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      invoke.mockResolvedValueOnce(false);
      appCore.setServerStatus({ ...appCore.getServerStatus(), running: true });
      
      await appCore.checkServerHealth();
      
      expect(appCore.getServerStatus().running).toBe(false);
      expect(appCore.getServerStatus().pid).toBe(null);
    });
  });

  describe('UI Updates', () => {
    it('should update UI when server is running', async () => {
      appCore.setServerStatus({
        running: true,
        port: 3001,
        pid: 12345,
        healthUrl: null,
        external: false
      });
      appCore.setLocalIp('192.168.1.100');
      
      await appCore.updateUI();
      
      expect(appCore.getElements().statusDot.classList.add).toHaveBeenCalledWith('running');
      expect(appCore.getElements().statusText.textContent).toBe('Running');
      expect(appCore.getElements().serverInfo.style.display).toBe('block');
      expect(appCore.getElements().serverUrl.textContent).toBe('http://192.168.1.100:3001');
      expect(appCore.getElements().serverPid.textContent).toBe(12345);
      expect(appCore.getElements().startBtn.disabled).toBe(true);
      expect(appCore.getElements().stopBtn.disabled).toBe(false);
    });

    it('should show external notice for external servers', async () => {
      appCore.setServerStatus({
        running: true,
        port: 3001,
        pid: null,
        healthUrl: null,
        external: true
      });
      
      await appCore.updateUI();
      
      expect(appCore.getElements().statusText.textContent).toBe('Running (External)');
      expect(appCore.getElements().serverPid.textContent).toBe('External Process');
      expect(appCore.getElements().externalNotice.style.display).toBe('block');
    });

    it('should update UI when server is not running', async () => {
      appCore.setServerStatus({ ...appCore.getServerStatus(), running: false });
      
      await appCore.updateUI();
      
      expect(appCore.getElements().statusDot.classList.remove).toHaveBeenCalledWith('running');
      expect(appCore.getElements().statusText.textContent).toBe('Not Running');
      expect(appCore.getElements().serverInfo.style.display).toBe('none');
      expect(appCore.getElements().startBtn.disabled).toBe(false);
      expect(appCore.getElements().stopBtn.disabled).toBe(true);
    });
  });

  describe('Config Path Selection', () => {
    it('should open directory dialog and update path', async () => {
      const { open } = await import('@tauri-apps/plugin-dialog');
      open.mockResolvedValueOnce('/new/custom/path');
      
      await appCore.selectConfigPath();
      
      expect(open).toHaveBeenCalledWith({
        directory: true,
        multiple: false
      });
      expect(appCore.getConfigPath()).toBe('/new/custom/path');
      expect(appCore.getElements().configPathInput.value).toBe('/new/custom/path');
    });

    it('should handle dialog cancellation', async () => {
      const { open } = await import('@tauri-apps/plugin-dialog');
      open.mockResolvedValueOnce(null);
      const originalPath = appCore.getConfigPath();
      
      await appCore.selectConfigPath();
      
      expect(appCore.getConfigPath()).toBe(originalPath);
    });
  });

  describe('QR Code Generation', () => {
    it('should generate QR code with correct URL', async () => {
      const QRCode = (await import('qrcode')).default;
      appCore.setLocalIp('192.168.1.100');
      appCore.setServerStatus({ ...appCore.getServerStatus(), port: 3001 });
      
      await appCore.generateQRCode();
      
      expect(QRCode.toCanvas).toHaveBeenCalledWith(
        appCore.getElements().qrCanvas,
        'http://192.168.1.100:3001?tls=0',
        expect.objectContaining({
          width: 200,
          margin: 2
        })
      );
      expect(appCore.getElements().connectionString.textContent).toBe('http://192.168.1.100:3001?tls=0');
    });

    it('should include auth token in QR code if configured', async () => {
      const QRCode = (await import('qrcode')).default;
      localStorage.setItem('claude-companion-auth-token', 'test-token-123');
      appCore.setLocalIp('192.168.1.100');
      appCore.setServerStatus({ ...appCore.getServerStatus(), port: 3001 });
      
      await appCore.generateQRCode();
      
      expect(QRCode.toCanvas).toHaveBeenCalledWith(
        appCore.getElements().qrCanvas,
        'http://192.168.1.100:3001?token=test-token-123&tls=0',
        expect.any(Object)
      );
    });
  });

  describe('Initialization', () => {
    it('should initialize app correctly', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      
      // Mock DOM elements
      global.document.getElementById = vi.fn((id) => {
        const elements = {
          'config-path': { value: '', addEventListener: vi.fn() },
          'browse-btn': { addEventListener: vi.fn(), disabled: false },
          'port': { value: '3001', addEventListener: vi.fn() },
          'status-dot': { classList: { add: vi.fn(), remove: vi.fn() } },
          'status-text': { textContent: '' },
          'server-info': { style: { display: 'none' } },
          'server-url': { textContent: '' },
          'server-pid': { textContent: '' },
          'start-btn': { 
            addEventListener: vi.fn(), 
            disabled: false,
            classList: { add: vi.fn(), remove: vi.fn() }
          },
          'stop-btn': { 
            addEventListener: vi.fn(), 
            disabled: true,
            title: ''
          },
          'qr-section': { style: { display: 'none' } },
          'qr-code': { innerHTML: '' },
          'connection-string': { textContent: '' },
          'external-notice': { style: { display: 'none' } }
        };
        return elements[id] || null;
      });
      
      await appCore.init();
      
      expect(invoke).toHaveBeenCalledWith('get_local_ip');
      expect(invoke).toHaveBeenCalledWith('get_server_status');
      expect(invoke).toHaveBeenCalledWith('detect_running_server', { port: 3001 });
      expect(appCore.getElements().browseBtn.addEventListener).toHaveBeenCalledWith('click', expect.any(Function));
      expect(appCore.getElements().startBtn.addEventListener).toHaveBeenCalledWith('click', expect.any(Function));
      expect(appCore.getElements().stopBtn.addEventListener).toHaveBeenCalledWith('click', expect.any(Function));
      expect(appCore.getElements().portInput.addEventListener).toHaveBeenCalledWith('change', appCore.saveConfig);
      expect(global.setInterval).toHaveBeenCalledWith(appCore.checkServerHealth, 2000);
    });

    it('should detect externally running server on init', async () => {
      const { invoke } = await import('@tauri-apps/api/core');
      invoke.mockImplementation(async (cmd) => {
        if (cmd === 'detect_running_server') {
          return {
            running: true,
            port: 3001,
            pid: null,
            health_url: 'http://localhost:3001/health',
            external: true
          };
        }
        if (cmd === 'get_local_ip') return '192.168.1.100';
        if (cmd === 'get_server_status') return { running: false };
      });
      
      global.document.getElementById = vi.fn((id) => {
        const elements = {
          'config-path': { value: '', addEventListener: vi.fn() },
          'browse-btn': { addEventListener: vi.fn(), disabled: false },
          'port': { value: '3001', addEventListener: vi.fn() },
          'status-dot': { classList: { add: vi.fn(), remove: vi.fn() } },
          'status-text': { textContent: '' },
          'server-info': { style: { display: 'none' } },
          'server-url': { textContent: '' },
          'server-pid': { textContent: '' },
          'start-btn': { 
            addEventListener: vi.fn(), 
            disabled: false,
            classList: { add: vi.fn(), remove: vi.fn() }
          },
          'stop-btn': { 
            addEventListener: vi.fn(), 
            disabled: true,
            title: ''
          },
          'qr-section': { style: { display: 'none' } },
          'qr-code': { innerHTML: '' },
          'connection-string': { textContent: '' },
          'external-notice': { style: { display: 'none' } }
        };
        return elements[id] || null;
      });
      
      await appCore.init();
      
      expect(appCore.getServerStatus().running).toBe(true);
      expect(appCore.getServerStatus().external).toBe(true);
    });
  });
});