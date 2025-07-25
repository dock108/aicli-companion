// Core application logic separated for testing
import { invoke } from '@tauri-apps/api/core';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import { appDataDir } from '@tauri-apps/api/path';
import QRCode from 'qrcode';

// State
const state = {
  serverStatus: {
    running: false,
    port: 3001,
    pid: null,
    healthUrl: null,
    external: false,
  },
  localIp: '',
  configPath: '',
  elements: {},
};

// Export getters and setters for testing
export const getState = () => state;
export const setState = (updates) => Object.assign(state, updates);
export const getServerStatus = () => state.serverStatus;
export const setServerStatus = (status) => {
  state.serverStatus = status;
};
export const getLocalIp = () => state.localIp;
export const setLocalIp = (ip) => {
  state.localIp = ip;
};
export const getConfigPath = () => state.configPath;
export const setConfigPath = (path) => {
  state.configPath = path;
};
export const getElements = () => state.elements;
export const setElements = (els) => {
  state.elements = els;
};

// Config Management
export async function loadConfig() {
  try {
    const savedConfig = localStorage.getItem('claude-companion-config');
    if (savedConfig) {
      const config = JSON.parse(savedConfig);
      setConfigPath(config.configPath || (await getDefaultPath()));
      state.serverStatus.port = config.port || 3001;
    } else {
      setConfigPath(await getDefaultPath());
    }

    if (state.elements.configPathInput) state.elements.configPathInput.value = state.configPath;
    if (state.elements.portInput) state.elements.portInput.value = state.serverStatus.port;
  } catch (error) {
    console.error('Failed to load config:', error);
  }
}

export async function saveConfig() {
  const config = {
    configPath: state.configPath,
    port: parseInt(state.elements.portInput.value),
  };
  localStorage.setItem('claude-companion-config', JSON.stringify(config));
}

export async function getDefaultPath() {
  try {
    const dataDir = await appDataDir();
    return `${dataDir}/claude-companion`;
  } catch {
    return '~/claude-companion-data';
  }
}

export async function selectConfigPath() {
  console.log('🔥 === selectConfigPath() CALLED ===');

  if (!openDialog) {
    console.error('❌ openDialog function is not available!');
    return;
  }

  try {
    const dialogOptions = {
      directory: true,
      multiple: false,
    };

    if (state.configPath && state.configPath !== '~/claude-companion-data') {
      dialogOptions.defaultPath = state.configPath;
    }

    const selected = await openDialog(dialogOptions);

    if (selected) {
      console.log('✅ User selected path:', selected);
      setConfigPath(selected);
      state.elements.configPathInput.value = state.configPath;
      await saveConfig();
    } else {
      console.log('❌ User cancelled dialog or no selection made');
    }
  } catch (error) {
    console.error('💥 Failed to select path:', error);
  }
}

// Server Management
export async function startServer() {
  console.log('🚀 startServer() called');
  console.log('Current state:', state);
  console.log('Port input value:', state.elements.portInput?.value);
  
  state.elements.startBtn.disabled = true;
  state.elements.startBtn.classList.add('loading');

  const port = parseInt(state.elements.portInput.value);
  console.log('Starting server on port:', port);

  try {
    console.log('Invoking start_server...');
    const status = await invoke('start_server', { port });
    console.log('Server started, status:', status);
    setServerStatus(status);
    await updateUI();

    // Wait a bit for server to fully start
    setTimeout(async () => {
      await checkServerHealth();
      if (state.serverStatus.running) {
        await generateQRCode();
      }
    }, 2000);
  } catch (error) {
    console.error('Failed to start server:', error);
    alert(`Failed to start server: ${error}`);
  } finally {
    state.elements.startBtn.disabled = false;
    state.elements.startBtn.classList.remove('loading');
  }
}

export async function stopServer() {
  state.elements.stopBtn.disabled = true;

  try {
    await invoke('stop_server', { force_external: false });
    state.serverStatus.running = false;
    state.serverStatus.pid = null;
    state.serverStatus.external = false;
    await updateUI();
  } catch (error) {
    console.error('Failed to stop server:', error);

    if (error.toString().includes('not started by this app')) {
      const confirmed = confirm(
        `This server was not started by the desktop app.\n\n` +
          `Do you want to force stop it anyway?\n\n` +
          `Warning: This will kill any process listening on port ${state.serverStatus.port}`
      );

      if (confirmed) {
        try {
          await invoke('stop_server', { force_external: true });
          state.serverStatus.running = false;
          state.serverStatus.pid = null;
          state.serverStatus.external = false;
          await updateUI();
        } catch (forceError) {
          console.error('Failed to force stop server:', forceError);
          alert(`Failed to stop server: ${forceError}`);
        }
      }
    } else {
      alert(`Failed to stop server: ${error}`);
    }
  } finally {
    state.elements.stopBtn.disabled = false;
  }
}

export async function checkServerHealth() {
  if (!state.serverStatus.running) return;

  try {
    const isHealthy = await invoke('check_server_health', {
      port: state.serverStatus.port,
    });

    if (!isHealthy && state.serverStatus.running) {
      state.serverStatus.running = false;
      state.serverStatus.pid = null;
      state.serverStatus.external = false;
      await updateUI();
    } else if (isHealthy && state.serverStatus.running && state.serverStatus.external) {
      const status = await invoke('detect_running_server', { port: state.serverStatus.port });
      if (status.external !== state.serverStatus.external) {
        setServerStatus(status);
        await updateUI();
      }
    }
  } catch (error) {
    console.error('Health check failed:', error);
  }
}

export async function updateServerStatus() {
  try {
    setServerStatus(await invoke('get_server_status'));
    await updateUI();
  } catch (error) {
    console.error('Failed to get server status:', error);
  }
}

// UI Updates
export async function updateUI() {
  if (state.serverStatus.running) {
    state.elements.statusDot.classList.add('running');

    if (state.serverStatus.external) {
      state.elements.statusText.textContent = 'Running (External)';
      state.elements.serverPid.textContent = 'External Process';
      state.elements.stopBtn.disabled = false;
      state.elements.stopBtn.title = 'Stop external server (requires confirmation)';
      state.elements.externalNotice.style.display = 'block';
    } else {
      state.elements.statusText.textContent = 'Running';
      state.elements.serverPid.textContent = state.serverStatus.pid || '-';
      state.elements.stopBtn.disabled = false;
      state.elements.stopBtn.title = '';
      state.elements.externalNotice.style.display = 'none';
    }

    state.elements.serverInfo.style.display = 'block';
    state.elements.serverUrl.textContent = `http://${state.localIp}:${state.serverStatus.port}`;
    state.elements.startBtn.disabled = true;
    state.elements.qrSection.style.display = 'block';

    if (state.elements.qrSection.style.display === 'block' && !state.elements.qrCanvas.innerHTML) {
      await generateQRCode();
    }
  } else {
    state.elements.statusDot.classList.remove('running');
    state.elements.statusText.textContent = 'Not Running';
    state.elements.serverInfo.style.display = 'none';
    state.elements.startBtn.disabled = false;
    state.elements.stopBtn.disabled = true;
    state.elements.stopBtn.title = '';
    state.elements.qrSection.style.display = 'none';
    state.elements.externalNotice.style.display = 'none';
  }
}

// QR Code Generation
export async function generateQRCode() {
  const url = `http://${state.localIp}:${state.serverStatus.port}`;
  const params = new URLSearchParams();

  const authToken = localStorage.getItem('claude-companion-auth-token');
  if (authToken) {
    params.append('token', authToken);
  }

  params.append('tls', '0');

  const fullUrl = params.toString() ? `${url}?${params}` : url;
  state.elements.connectionString.textContent = fullUrl;

  try {
    await QRCode.toCanvas(state.elements.qrCanvas, fullUrl, {
      width: 200,
      margin: 2,
      color: {
        dark: '#0E1116',
        light: '#FFFFFF',
      },
    });
  } catch (error) {
    console.error('Failed to generate QR code:', error);
  }
}

// Initialize
export async function init() {
  console.log('🚀 Starting init()...');
  console.log('Document ready state:', document.readyState);
  console.log('Window location:', window.location.href);

  // Get DOM elements
  console.log('Getting DOM elements...');
  setElements({
    configPathInput: document.getElementById('config-path'),
    browseBtn: document.getElementById('browse-btn'),
    portInput: document.getElementById('port'),
    statusDot: document.getElementById('status-dot'),
    statusText: document.getElementById('status-text'),
    serverInfo: document.getElementById('server-info'),
    serverUrl: document.getElementById('server-url'),
    serverPid: document.getElementById('server-pid'),
    startBtn: document.getElementById('start-btn'),
    stopBtn: document.getElementById('stop-btn'),
    qrSection: document.getElementById('qr-section'),
    qrCanvas: document.getElementById('qr-code'),
    connectionString: document.getElementById('connection-string'),
    externalNotice: document.getElementById('external-notice'),
  });

  console.log('DOM elements found:', {
    configPathInput: !!state.elements.configPathInput,
    browseBtn: !!state.elements.browseBtn,
    portInput: !!state.elements.portInput,
    startBtn: !!state.elements.startBtn,
    stopBtn: !!state.elements.stopBtn,
  });

  // Load saved config
  await loadConfig();

  // Get local IP
  try {
    setLocalIp(await invoke('get_local_ip'));
  } catch (error) {
    console.error('Failed to get local IP:', error);
  }

  // Check initial server status
  await updateServerStatus();

  // Check if server is already running
  const port = parseInt(state.elements.portInput.value);
  try {
    const status = await invoke('detect_running_server', { port });
    setServerStatus(status);
    await updateUI();

    if (state.serverStatus.running && state.serverStatus.external) {
      console.log('Detected externally managed server on port', port);
    }
  } catch (error) {
    console.error('Failed to detect running server:', error);
  }

  // Set up event listeners
  console.log('Setting up event listeners...');
  
  if (state.elements.browseBtn) {
    console.log('✅ Adding click listener to browseBtn');
    state.elements.browseBtn.addEventListener('click', () => {
      console.log('Browse button clicked!');
      selectConfigPath();
    });
  } else {
    console.log('❌ browseBtn not found');
  }

  if (state.elements.startBtn) {
    console.log('✅ Adding click listener to startBtn');
    state.elements.startBtn.addEventListener('click', () => {
      console.log('Start button clicked!');
      startServer();
    });
  } else {
    console.log('❌ startBtn not found');
  }

  if (state.elements.stopBtn) {
    console.log('✅ Adding click listener to stopBtn');
    state.elements.stopBtn.addEventListener('click', () => {
      console.log('Stop button clicked!');
      stopServer();
    });
  } else {
    console.log('❌ stopBtn not found');
  }

  if (state.elements.portInput) {
    state.elements.portInput.addEventListener('change', saveConfig);
  }

  // Start health check polling
  setInterval(checkServerHealth, 2000);
}
