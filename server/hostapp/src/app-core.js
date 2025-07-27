// Core application logic separated for testing
import { invoke } from '@tauri-apps/api/core';
import { open as openDialog } from '@tauri-apps/plugin-dialog';
import { appDataDir } from '@tauri-apps/api/path';
import { listen } from '@tauri-apps/api/event';
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
  logs: [],
  logsUnlisten: null,
  currentTab: 'server',
  claudeStatus: null,
  claudeLogs: [],
  claudeLogsUnlisten: null,
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
    
    // Load auth token
    const authToken = localStorage.getItem('claude-companion-auth-token');
    if (authToken && state.elements.authTokenInput) {
      state.elements.authTokenInput.value = authToken;
    }
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

// Token generation
export function generateAuthToken() {
  console.log('🔐 Generating auth token...');
  // Generate a secure random token
  const array = new Uint8Array(32);
  window.crypto.getRandomValues(array);
  const token = Array.from(array, byte => byte.toString(16).padStart(2, '0')).join('');
  
  // Save to localStorage
  localStorage.setItem('claude-companion-auth-token', token);
  
  // Update UI
  if (state.elements.authTokenInput) {
    state.elements.authTokenInput.value = token;
  }
  
  // Regenerate QR code if server is running
  if (state.serverStatus.running) {
    generateQRCode();
  }
  
  return token;
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
    
    // Get auth token and config path for server
    const authToken = localStorage.getItem('claude-companion-auth-token');
    const configPath = state.configPath;
    
    const status = await invoke('start_server', { 
      port,
      authToken,
      configPath 
    });
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

// Logs Management
export async function loadLogs() {
  try {
    const logs = await invoke('get_logs');
    state.logs = logs;
    renderLogs();
  } catch (error) {
    console.error('Failed to load logs:', error);
  }
}

export async function clearLogs() {
  try {
    await invoke('clear_logs');
    state.logs = [];
    renderLogs();
  } catch (error) {
    console.error('Failed to clear logs:', error);
  }
}

export function renderLogs() {
  const logsDisplay = state.elements.logsDisplay;
  if (!logsDisplay) return;

  // Get filter values
  const searchTerm = state.elements.logSearch?.value.toLowerCase() || '';
  const levelFilter = state.elements.logLevelFilter?.value || 'all';

  // Filter logs
  const filteredLogs = state.logs.filter(log => {
    const matchesSearch = !searchTerm || log.message.toLowerCase().includes(searchTerm);
    const matchesLevel = levelFilter === 'all' || log.level === levelFilter;
    return matchesSearch && matchesLevel;
  });

  // Clear existing logs
  logsDisplay.innerHTML = '';

  if (filteredLogs.length === 0) {
    logsDisplay.innerHTML = '<div class="log-empty-state">No logs match the current filters.</div>';
    return;
  }

  // Render each log entry
  filteredLogs.forEach(log => {
    const logEntry = document.createElement('div');
    logEntry.className = 'log-entry';
    
    const timestamp = document.createElement('span');
    timestamp.className = 'log-timestamp';
    timestamp.textContent = log.timestamp;
    
    const level = document.createElement('span');
    level.className = `log-level ${log.level}`;
    level.textContent = log.level;
    
    const message = document.createElement('span');
    message.className = 'log-message';
    message.textContent = log.message;
    
    logEntry.appendChild(timestamp);
    logEntry.appendChild(level);
    logEntry.appendChild(message);
    
    logsDisplay.appendChild(logEntry);
  });

  // Auto-scroll if enabled
  if (state.elements.autoScroll?.checked) {
    logsDisplay.scrollTop = logsDisplay.scrollHeight;
  }
}

// Tab Navigation
export function switchTab(tabName) {
  // Update tab buttons
  document.querySelectorAll('.tab-button').forEach(btn => {
    btn.classList.toggle('active', btn.dataset.tab === tabName);
  });

  // Update tab panels
  document.querySelectorAll('.tab-panel').forEach(panel => {
    panel.classList.toggle('active', panel.id === `${tabName}-tab`);
  });

  state.currentTab = tabName;

  // Load logs when switching to logs tab
  if (tabName === 'logs') {
    loadLogs();
  } else if (tabName === 'claude') {
    loadClaudeStatus();
  }
}

// Claude CLI Management
export async function loadClaudeStatus() {
  if (!state.serverStatus.running) {
    updateClaudeStatusUI({
      claude: { installed: false, version: null, path: null, available: false },
      sessions: { active: 0, max: 0, details: [] }
    });
    return;
  }

  try {
    const response = await fetch(`http://localhost:${state.serverStatus.port}/api/claude/status`);
    if (response.ok) {
      const status = await response.json();
      state.claudeStatus = status;
      updateClaudeStatusUI(status);
    }
  } catch (error) {
    console.error('Failed to load Claude status:', error);
  }
}

export async function testClaude() {
  if (!state.serverStatus.running) {
    alert('Server must be running to test Claude CLI');
    return;
  }

  const testBtn = state.elements.testClaudeBtn;
  testBtn.disabled = true;
  testBtn.textContent = 'Testing...';

  try {
    const response = await fetch(`http://localhost:${state.serverStatus.port}/api/claude/test`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: 'Hello! Please respond with a brief greeting.' })
    });

    const result = await response.json();
    
    if (result.success) {
      alert('Claude CLI test successful! Check the Claude logs for the response.');
      addClaudeLog('test', `Test successful: ${JSON.stringify(result.response).substring(0, 200)}...`);
    } else {
      alert(`Claude CLI test failed: ${result.message}`);
      addClaudeLog('error', `Test failed: ${result.message}`);
    }
  } catch (error) {
    alert(`Failed to test Claude CLI: ${error.message}`);
    addClaudeLog('error', `Test error: ${error.message}`);
  } finally {
    testBtn.disabled = false;
    testBtn.textContent = 'Test Claude CLI';
  }
}

function updateClaudeStatusUI(status) {
  if (!status) return;

  // Update Claude installation status
  const installedEl = state.elements.claudeInstalled;
  const versionEl = state.elements.claudeVersion;
  const pathEl = state.elements.claudePath;
  const availableEl = state.elements.claudeAvailable;

  if (installedEl) {
    installedEl.textContent = status.claude.installed ? 'Installed' : 'Not Installed';
    installedEl.className = status.claude.installed ? 'status-value success' : 'status-value error';
  }

  if (versionEl) {
    versionEl.textContent = status.claude.version || '-';
  }

  if (pathEl) {
    pathEl.textContent = status.claude.path || '-';
  }

  if (availableEl) {
    availableEl.textContent = status.claude.available ? 'Yes' : 'No';
    availableEl.className = status.claude.available ? 'status-value success' : 'status-value error';
  }

  // Update session info
  if (state.elements.activeSessionsCount) {
    state.elements.activeSessionsCount.textContent = status.sessions.active;
  }

  if (state.elements.maxSessions) {
    state.elements.maxSessions.textContent = status.sessions.max;
  }

  // Update sessions list
  const sessionsList = state.elements.sessionsList;
  if (sessionsList) {
    sessionsList.innerHTML = '';
    
    if (status.sessions.details.length === 0) {
      sessionsList.innerHTML = '<div class="log-empty-state">No active Claude CLI sessions</div>';
    } else {
      status.sessions.details.forEach(session => {
        const sessionEl = document.createElement('div');
        sessionEl.className = 'session-item';
        sessionEl.innerHTML = `
          <div class="session-header">
            <span class="session-id">${session.sessionId}</span>
            <span class="session-pid">PID: ${session.pid || 'N/A'}</span>
          </div>
          <div class="session-details">
            <div>Working Directory: ${session.workingDirectory}</div>
            <div>Created: ${new Date(session.createdAt).toLocaleTimeString()}</div>
            <div>Last Activity: ${new Date(session.lastActivity).toLocaleTimeString()}</div>
          </div>
        `;
        sessionsList.appendChild(sessionEl);
      });
    }
  }
}

function addClaudeLog(type, content) {
  const log = {
    type,
    content,
    timestamp: new Date().toISOString()
  };
  
  state.claudeLogs.push(log);
  if (state.claudeLogs.length > 1000) {
    state.claudeLogs = state.claudeLogs.slice(-1000);
  }
  
  renderClaudeLogs();
}

export function renderClaudeLogs() {
  const logsDisplay = state.elements.claudeLogsDisplay;
  if (!logsDisplay) return;

  const filterValue = state.elements.claudeLogFilter?.value || 'all';
  
  const filteredLogs = state.claudeLogs.filter(log => {
    if (filterValue === 'all') return true;
    return log.type === filterValue;
  });

  logsDisplay.innerHTML = '';

  if (filteredLogs.length === 0) {
    logsDisplay.innerHTML = '<div class="log-empty-state">No Claude CLI logs match the filter.</div>';
    return;
  }

  filteredLogs.forEach(log => {
    const logEntry = document.createElement('div');
    logEntry.className = 'claude-log-entry';
    
    const logType = document.createElement('span');
    logType.className = `claude-log-type ${log.type}`;
    logType.textContent = log.type;
    
    const logContent = document.createElement('span');
    logContent.className = 'claude-log-content';
    logContent.textContent = log.content;
    
    logEntry.appendChild(logType);
    logEntry.appendChild(logContent);
    
    logsDisplay.appendChild(logEntry);
  });

  if (state.elements.claudeAutoScroll?.checked) {
    logsDisplay.scrollTop = logsDisplay.scrollHeight;
  }
}

export function clearClaudeLogs() {
  state.claudeLogs = [];
  renderClaudeLogs();
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
    authTokenInput: document.getElementById('auth-token'),
    generateTokenBtn: document.getElementById('generate-token-btn'),
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
    // Logs elements
    logsDisplay: document.getElementById('logs-display'),
    logSearch: document.getElementById('log-search'),
    logLevelFilter: document.getElementById('log-level-filter'),
    clearLogsBtn: document.getElementById('clear-logs-btn'),
    autoScroll: document.getElementById('auto-scroll'),
    // Claude elements
    claudeInstalled: document.getElementById('claude-installed'),
    claudeVersion: document.getElementById('claude-version'),
    claudePath: document.getElementById('claude-path'),
    claudeAvailable: document.getElementById('claude-available'),
    refreshClaudeBtn: document.getElementById('refresh-claude-btn'),
    testClaudeBtn: document.getElementById('test-claude-btn'),
    activeSessionsCount: document.getElementById('active-sessions-count'),
    maxSessions: document.getElementById('max-sessions'),
    sessionsList: document.getElementById('sessions-list'),
    claudeLogsDisplay: document.getElementById('claude-logs-display'),
    claudeLogFilter: document.getElementById('claude-log-filter'),
    clearClaudeLogsBtn: document.getElementById('clear-claude-logs-btn'),
    claudeAutoScroll: document.getElementById('claude-auto-scroll'),
  });

  console.log('DOM elements found:', {
    configPathInput: !!state.elements.configPathInput,
    browseBtn: !!state.elements.browseBtn,
    portInput: !!state.elements.portInput,
    authTokenInput: !!state.elements.authTokenInput,
    generateTokenBtn: !!state.elements.generateTokenBtn,
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

  if (state.elements.generateTokenBtn) {
    console.log('✅ Adding click listener to generateTokenBtn');
    state.elements.generateTokenBtn.addEventListener('click', () => {
      console.log('Generate token button clicked!');
      generateAuthToken();
    });
  } else {
    console.log('❌ generateTokenBtn not found');
  }

  // Tab navigation listeners
  document.querySelectorAll('.tab-button').forEach(btn => {
    btn.addEventListener('click', () => {
      switchTab(btn.dataset.tab);
    });
  });

  // Logs event listeners
  if (state.elements.logSearch) {
    state.elements.logSearch.addEventListener('input', renderLogs);
  }

  if (state.elements.logLevelFilter) {
    state.elements.logLevelFilter.addEventListener('change', renderLogs);
  }

  if (state.elements.clearLogsBtn) {
    state.elements.clearLogsBtn.addEventListener('click', clearLogs);
  }

  // Claude event listeners
  if (state.elements.refreshClaudeBtn) {
    state.elements.refreshClaudeBtn.addEventListener('click', loadClaudeStatus);
  }

  if (state.elements.testClaudeBtn) {
    state.elements.testClaudeBtn.addEventListener('click', testClaude);
  }

  if (state.elements.claudeLogFilter) {
    state.elements.claudeLogFilter.addEventListener('change', renderClaudeLogs);
  }

  if (state.elements.clearClaudeLogsBtn) {
    state.elements.clearClaudeLogsBtn.addEventListener('click', clearClaudeLogs);
  }

  // Listen for real-time log updates
  state.logsUnlisten = await listen('log-entry', (event) => {
    const log = event.payload;
    state.logs.push(log);
    // Keep only last 10000 logs in UI
    if (state.logs.length > 10000) {
      state.logs = state.logs.slice(-10000);
    }
    renderLogs();
    
    // Parse Claude-specific logs
    if (log.message) {
      if (log.message.includes('[CLAUDE_PROCESS_START]')) {
        addClaudeLog('start', log.message.replace('[CLAUDE_PROCESS_START]', '').trim());
      } else if (log.message.includes('[CLAUDE_STDOUT]')) {
        addClaudeLog('stdout', log.message.replace('[CLAUDE_STDOUT]', '').trim());
      } else if (log.message.includes('[CLAUDE_STDERR]')) {
        addClaudeLog('stderr', log.message.replace('[CLAUDE_STDERR]', '').trim());
      } else if (log.message.includes('[CLAUDE_PROCESS_EXIT]')) {
        addClaudeLog('exit', log.message.replace('[CLAUDE_PROCESS_EXIT]', '').trim());
      } else if (log.message.includes('[CLAUDE_PROCESS_ERROR]')) {
        addClaudeLog('error', log.message.replace('[CLAUDE_PROCESS_ERROR]', '').trim());
      } else if (log.message.includes('[CLAUDE_COMMAND]')) {
        addClaudeLog('command', log.message.replace('[CLAUDE_COMMAND]', '').trim());
      }
    }
  });

  // Start health check polling
  setInterval(checkServerHealth, 10000); // Reduced from 2s to 10s for cleaner logs
}
