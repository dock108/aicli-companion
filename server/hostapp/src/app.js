console.log('🚀 App.js starting to load...');

// Import Tauri API
let invoke, openDialog, appDataDir, QRCode;

async function loadModules() {
  try {
    console.log('📦 Importing Tauri APIs...');
    const coreModule = await import('@tauri-apps/api/core');
    invoke = coreModule.invoke;
    console.log('✅ Core API imported:', !!invoke);

    const dialogModule = await import('@tauri-apps/plugin-dialog');
    openDialog = dialogModule.open;
    console.log('✅ Dialog API imported:', !!openDialog);

    const pathModule = await import('@tauri-apps/api/path');
    appDataDir = pathModule.appDataDir;
    console.log('✅ Path API imported:', !!appDataDir);

    // Import QR code library
    console.log('📦 Importing QRCode...');
    const qrModule = await import('qrcode');
    QRCode = qrModule.default;
    console.log('✅ QRCode imported:', !!QRCode);
  } catch (error) {
    console.error('❌ Failed to import modules:', error);
  }
}

// State
let serverStatus = {
  running: false,
  port: 3001,
  pid: null,
  healthUrl: null,
  external: false,
};

let localIp = '';
let configPath = '';

// DOM Elements
console.log('🔍 Finding DOM elements...');
const configPathInput = document.getElementById('config-path');
const browseBtn = document.getElementById('browse-btn');
const portInput = document.getElementById('port');
const statusDot = document.getElementById('status-dot');
const statusText = document.getElementById('status-text');
const serverInfo = document.getElementById('server-info');
const serverUrl = document.getElementById('server-url');
const serverPid = document.getElementById('server-pid');
const startBtn = document.getElementById('start-btn');
const stopBtn = document.getElementById('stop-btn');
const qrSection = document.getElementById('qr-section');
const qrCanvas = document.getElementById('qr-code');
const connectionString = document.getElementById('connection-string');
const externalNotice = document.getElementById('external-notice');

console.log('📋 DOM elements found:');
console.log('  configPathInput:', !!configPathInput);
console.log('  browseBtn:', !!browseBtn);
console.log('  startBtn:', !!startBtn);
console.log('  stopBtn:', !!stopBtn);

// Initialize
async function init() {
  console.log('🚀 Starting init()...');

  // Load modules first
  await loadModules();
  console.log('📦 Modules loaded, continuing with init...');

  // Load saved config
  await loadConfig();

  // Get local IP
  try {
    localIp = await invoke('get_local_ip');
  } catch (error) {
    console.error('Failed to get local IP:', error);
  }

  // Check initial server status
  await updateServerStatus();

  // Check if server is already running
  const port = parseInt(portInput.value);
  try {
    const status = await invoke('detect_running_server', { port });
    serverStatus = status;
    await updateUI();

    if (serverStatus.running && serverStatus.external) {
      console.log('Detected externally managed server on port', port);
    }
  } catch (error) {
    console.error('Failed to detect running server:', error);
  }

  // Set up event listeners
  console.log('🎯 Setting up event listeners...');

  if (browseBtn) {
    console.log('📁 Adding browse button event listener...');
    browseBtn.addEventListener('click', (event) => {
      console.log('🖱️ Browse button CLICKED!', event);
      selectConfigPath();
    });
    console.log('✅ Browse button event listener added');
  } else {
    console.error('❌ Browse button not found!');
  }

  if (startBtn) {
    startBtn.addEventListener('click', startServer);
    console.log('✅ Start button event listener added');
  }

  if (stopBtn) {
    stopBtn.addEventListener('click', stopServer);
    console.log('✅ Stop button event listener added');
  }

  if (portInput) {
    portInput.addEventListener('change', saveConfig);
    console.log('✅ Port input event listener added');
  }

  // Start health check polling
  setInterval(checkServerHealth, 2000);
}

// Config Management
async function loadConfig() {
  try {
    const savedConfig = localStorage.getItem('claude-companion-config');
    if (savedConfig) {
      const config = JSON.parse(savedConfig);
      configPath = config.configPath || (await getDefaultPath());
      serverStatus.port = config.port || 3001;
    } else {
      configPath = await getDefaultPath();
    }

    configPathInput.value = configPath;
    portInput.value = serverStatus.port;
  } catch (error) {
    console.error('Failed to load config:', error);
  }
}

async function saveConfig() {
  const config = {
    configPath,
    port: parseInt(portInput.value),
  };
  localStorage.setItem('claude-companion-config', JSON.stringify(config));
}

async function getDefaultPath() {
  try {
    const dataDir = await appDataDir();
    return `${dataDir}/claude-companion`;
  } catch {
    return '~/claude-companion-data';
  }
}

async function selectConfigPath() {
  console.log('🔥 === selectConfigPath() CALLED ===');
  console.log('📁 Browse button clicked, attempting to open dialog...');
  console.log('📍 Current configPath:', configPath);
  console.log('🔧 openDialog function available:', !!openDialog);
  console.log('🔧 openDialog type:', typeof openDialog);

  if (!openDialog) {
    console.error('❌ openDialog function is not available!');
    console.error('🚫 Dialog API not available. Check console for import errors.');
    return;
  }

  try {
    // Try with minimal options first, then fall back to defaultPath
    const dialogOptions = {
      directory: true,
      multiple: false,
    };

    // Only add defaultPath if it's a valid path
    if (configPath && configPath !== '~/claude-companion-data') {
      dialogOptions.defaultPath = configPath;
      console.log('📂 Using defaultPath:', configPath);
    } else {
      console.log('📂 No defaultPath set, using home directory');
    }

    console.log('📋 Calling openDialog() with options:', dialogOptions);
    console.log('⏳ Awaiting dialog result...');

    const selected = await openDialog(dialogOptions);

    console.log('📬 Dialog returned:', selected);
    console.log('📬 Dialog result type:', typeof selected);

    if (selected) {
      console.log('✅ User selected path:', selected);
      configPath = selected;
      configPathInput.value = configPath;
      await saveConfig();
      console.log('💾 Config path updated to:', configPath);
    } else {
      console.log('❌ User cancelled dialog or no selection made');
    }
  } catch (error) {
    console.error('💥 Failed to select path:', error);
    console.error('💥 Error type:', typeof error);
    console.error('💥 Error message:', error.message);
    console.error('💥 Error stack:', error.stack);
    console.error('🚫 Failed to open file dialog:', error);
  }

  console.log('🏁 === selectConfigPath() FINISHED ===');
}

// Server Management
async function startServer() {
  startBtn.disabled = true;
  startBtn.classList.add('loading');

  const port = parseInt(portInput.value);

  try {
    const status = await invoke('start_server', { port });
    serverStatus = status;
    await updateUI();

    // Wait a bit for server to fully start
    setTimeout(async () => {
      await checkServerHealth();
      if (serverStatus.running) {
        generateQRCode();
      }
    }, 2000);
  } catch (error) {
    console.error('Failed to start server:', error);
    alert(`Failed to start server: ${error}`);
  } finally {
    startBtn.disabled = false;
    startBtn.classList.remove('loading');
  }
}

async function stopServer() {
  stopBtn.disabled = true;

  try {
    // First try to stop normally
    await invoke('stop_server', { force_external: false });
    serverStatus.running = false;
    serverStatus.pid = null;
    serverStatus.external = false;
    await updateUI();
  } catch (error) {
    console.error('Failed to stop server:', error);

    // If it's an external server, ask for confirmation
    if (error.toString().includes('not started by this app')) {
      const confirmed = confirm(
        `This server was not started by the desktop app.\n\n` +
          `Do you want to force stop it anyway?\n\n` +
          `Warning: This will kill any process listening on port ${serverStatus.port}`
      );

      if (confirmed) {
        try {
          await invoke('stop_server', { force_external: true });
          serverStatus.running = false;
          serverStatus.pid = null;
          serverStatus.external = false;
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
    stopBtn.disabled = false;
  }
}

async function checkServerHealth() {
  if (!serverStatus.running) return;

  try {
    const isHealthy = await invoke('check_server_health', {
      port: serverStatus.port,
    });

    if (!isHealthy && serverStatus.running) {
      // Server died
      serverStatus.running = false;
      serverStatus.pid = null;
      serverStatus.external = false;
      await updateUI();
    } else if (isHealthy && serverStatus.running) {
      // For external servers, periodically check if still external
      if (serverStatus.external) {
        const status = await invoke('detect_running_server', { port: serverStatus.port });
        if (status.external !== serverStatus.external) {
          serverStatus = status;
          await updateUI();
        }
      }
    }
  } catch (error) {
    console.error('Health check failed:', error);
  }
}

async function updateServerStatus() {
  try {
    serverStatus = await invoke('get_server_status');
    await updateUI();
  } catch (error) {
    console.error('Failed to get server status:', error);
  }
}

// UI Updates
async function updateUI() {
  if (serverStatus.running) {
    statusDot.classList.add('running');

    if (serverStatus.external) {
      statusText.textContent = 'Running (External)';
      serverPid.textContent = 'External Process';
      stopBtn.disabled = false; // Allow stopping external servers
      stopBtn.title = 'Stop external server (requires confirmation)';
      externalNotice.style.display = 'block';
    } else {
      statusText.textContent = 'Running';
      serverPid.textContent = serverStatus.pid || '-';
      stopBtn.disabled = false;
      stopBtn.title = '';
      externalNotice.style.display = 'none';
    }

    serverInfo.style.display = 'block';
    serverUrl.textContent = `http://${localIp}:${serverStatus.port}`;
    startBtn.disabled = true;
    qrSection.style.display = 'block';

    // Generate QR code if not already done
    if (qrSection.style.display === 'block' && !qrCanvas.innerHTML) {
      generateQRCode();
    }
  } else {
    statusDot.classList.remove('running');
    statusText.textContent = 'Not Running';
    serverInfo.style.display = 'none';
    startBtn.disabled = false;
    stopBtn.disabled = true;
    stopBtn.title = '';
    qrSection.style.display = 'none';
    externalNotice.style.display = 'none';
  }
}

// QR Code Generation
async function generateQRCode() {
  const url = `http://${localIp}:${serverStatus.port}`;
  const params = new URLSearchParams();

  // Add auth token if configured
  const authToken = localStorage.getItem('claude-companion-auth-token');
  if (authToken) {
    params.append('token', authToken);
  }

  // Add TLS flag (default false for local network)
  params.append('tls', '0');

  const fullUrl = params.toString() ? `${url}?${params}` : url;
  connectionString.textContent = fullUrl;

  // Generate QR code
  try {
    await QRCode.toCanvas(qrCanvas, fullUrl, {
      width: 200,
      margin: 2,
      color: {
        dark: '#0E1116', // Dark-Slate Terminal bg color
        light: '#FFFFFF',
      },
    });
  } catch (error) {
    console.error('Failed to generate QR code:', error);
  }
}

// Initialize when DOM is ready
console.log('🎯 Setting up DOMContentLoaded listener...');
document.addEventListener('DOMContentLoaded', () => {
  console.log('✅ DOM Content Loaded - starting init()');
  init();
});
