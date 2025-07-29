// Core application logic separated for testing
import { invoke } from '@tauri-apps/api/core';
import { open as openDialog, ask, message } from '@tauri-apps/plugin-dialog';
import { desktopDir } from '@tauri-apps/api/path';
import { listen } from '@tauri-apps/api/event';
import QRCode from 'qrcode';

// Debounce utility function
function debounce(func, wait) {
  let timeout;
  return function executedFunction(...args) {
    const later = () => {
      clearTimeout(timeout);
      func(...args);
    };
    clearTimeout(timeout);
    timeout = setTimeout(later, wait);
  };
}

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
  aicliStatus: null,
  aicliLogs: [],
  aicliLogsUnlisten: null,
  // Performance optimization state
  lastRenderedLogIndex: 0,
  lastRenderedAICLILogIndex: 0,
  renderPending: false,
  aicliRenderPending: false,
  // Session persistence state
  activeSessions: new Map(),
  sessionHistory: [],
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
    const savedConfig = localStorage.getItem('aicli-companion-config');
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
    const authToken = localStorage.getItem('aicli-companion-auth-token');
    if (authToken && state.elements.authTokenInput) {
      state.elements.authTokenInput.value = authToken;
    }

    // Load session history
    loadSessionHistory();
  } catch (error) {
    console.error('Failed to load config:', error);
  }
}

// Session persistence functions
export function loadSessionHistory() {
  try {
    const savedSessions = localStorage.getItem('aicli-companion-sessions');
    if (savedSessions) {
      const sessions = JSON.parse(savedSessions);
      state.sessionHistory = sessions;

      // Restore active sessions map
      sessions.forEach((session) => {
        if (session.status === 'active') {
          state.activeSessions.set(session.sessionId, session);
        }
      });
    }
  } catch (error) {
    console.error('Failed to load session history:', error);
  }
}

export function saveSessionHistory() {
  try {
    const sessions = Array.from(state.activeSessions.values());
    // Also include recent inactive sessions from history
    const recentInactive = state.sessionHistory.filter((s) => s.status !== 'active').slice(0, 20); // Keep last 20 inactive sessions

    const allSessions = [...sessions, ...recentInactive];
    localStorage.setItem('aicli-companion-sessions', JSON.stringify(allSessions));
  } catch (error) {
    console.error('Failed to save session history:', error);
  }
}

export function addSession(sessionInfo) {
  const session = {
    ...sessionInfo,
    createdAt: new Date().toISOString(),
    lastActivity: new Date().toISOString(),
  };

  state.activeSessions.set(session.sessionId, session);
  saveSessionHistory();
  updateSessionUI();
}

export function updateSession(sessionId, updates) {
  const session = state.activeSessions.get(sessionId);
  if (session) {
    Object.assign(session, updates, {
      lastActivity: new Date().toISOString(),
    });
    saveSessionHistory();
    updateSessionUI();
  }
}

export function removeSession(sessionId) {
  const session = state.activeSessions.get(sessionId);
  if (session) {
    session.status = 'stopped';
    session.stoppedAt = new Date().toISOString();
    state.activeSessions.delete(sessionId);
    state.sessionHistory.unshift(session); // Add to history
    saveSessionHistory();
    updateSessionUI();
  }
}

function updateSessionUI() {
  // Update session count in UI
  const activeCount = state.activeSessions.size;

  // Update session count
  if (state.elements.sessionCount) {
    state.elements.sessionCount.textContent = activeCount;
  }

  // Update session list
  if (state.elements.activeSessionsList) {
    if (activeCount === 0) {
      state.elements.activeSessionsList.innerHTML =
        '<div class="log-empty-state">No active sessions</div>';
    } else {
      const fragment = document.createDocumentFragment();
      state.activeSessions.forEach((session) => {
        const sessionEl = document.createElement('div');
        sessionEl.className = 'session-item';

        const timeSinceStart = getTimeSince(session.createdAt);
        const timeSinceActivity = getTimeSince(session.lastActivity);

        sessionEl.innerHTML = `
          <div class="session-header">
            <span class="session-id">${session.sessionId}</span>
            <span class="session-status active">Active</span>
          </div>
          <div class="session-details">
            <div><strong>Project:</strong> ${session.projectName || 'Unknown'}</div>
            <div><strong>Started:</strong> ${timeSinceStart} ago</div>
            <div><strong>Last Activity:</strong> ${timeSinceActivity} ago</div>
          </div>
        `;
        fragment.appendChild(sessionEl);
      });
      state.elements.activeSessionsList.innerHTML = '';
      state.elements.activeSessionsList.appendChild(fragment);
    }
  }

  // Show/hide session section based on server status
  if (state.elements.sessionSection) {
    state.elements.sessionSection.style.display = state.serverStatus.running ? 'block' : 'none';
  }
}

// Helper function to get relative time
function getTimeSince(dateString) {
  const date = new Date(dateString);
  const now = new Date();
  const seconds = Math.floor((now - date) / 1000);

  if (seconds < 60) return `${seconds} seconds`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} minute${minutes > 1 ? 's' : ''}`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} hour${hours > 1 ? 's' : ''}`;
  const days = Math.floor(hours / 24);
  return `${days} day${days > 1 ? 's' : ''}`;
}

export async function saveConfig() {
  const config = {
    configPath: state.configPath,
    port: parseInt(state.elements.portInput.value),
  };
  localStorage.setItem('aicli-companion-config', JSON.stringify(config));
}

export async function getDefaultPath() {
  try {
    const desktop = await desktopDir();
    return desktop;
  } catch {
    return '~/Desktop';
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

    if (state.configPath && state.configPath !== '~/aicli-companion-data') {
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
  const token = Array.from(array, (byte) => byte.toString(16).padStart(2, '0')).join('');

  // Save to localStorage
  localStorage.setItem('aicli-companion-auth-token', token);

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
    const authToken = localStorage.getItem('aicli-companion-auth-token');
    const configPath = state.configPath;

    const status = await invoke('start_server', {
      port,
      authToken,
      configPath,
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
    await message(`Failed to start server: ${error}`, {
      title: 'Error',
      kind: 'error',
    });
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
      const confirmed = await ask(
        `This server was not started by the desktop app.\n\n` +
          `Do you want to force stop it anyway?\n\n` +
          `Warning: This will kill any process listening on port ${state.serverStatus.port}`,
        {
          title: 'Confirm Force Stop',
          kind: 'warning',
        }
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
          await message(`Failed to stop server: ${forceError}`, {
            title: 'Error',
            kind: 'error',
          });
        }
      }
    } else {
      await message(`Failed to stop server: ${error}`, {
        title: 'Error',
        kind: 'error',
      });
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

    // Update session UI
    updateSessionUI();
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

  const authToken = localStorage.getItem('aicli-companion-auth-token');
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
    state.lastRenderedLogIndex = 0; // Reset render index
    renderLogs(true); // Full render when loading
  } catch (error) {
    console.error('Failed to load logs:', error);
  }
}

export async function clearLogs() {
  try {
    await invoke('clear_logs');
    state.logs = [];
    state.lastRenderedLogIndex = 0; // Reset render index
    renderLogs(true); // Full render after clearing
  } catch (error) {
    console.error('Failed to clear logs:', error);
  }
}

export function renderLogs(fullRender = false) {
  const logsDisplay = state.elements.logsDisplay;
  if (!logsDisplay) return;

  // Prevent multiple renders in same frame
  if (state.renderPending) return;
  state.renderPending = true;

  requestAnimationFrame(() => {
    state.renderPending = false;

    // Get filter values
    const searchTerm = state.elements.logSearch?.value.toLowerCase() || '';
    const levelFilter = state.elements.logLevelFilter?.value || 'all';

    // Check if filters changed (requires full render)
    const filtersChanged = searchTerm || levelFilter !== 'all';

    if (fullRender || filtersChanged) {
      // Full render for filtered view
      const filteredLogs = state.logs.filter((log) => {
        const matchesSearch = !searchTerm || log.message.toLowerCase().includes(searchTerm);
        const matchesLevel = levelFilter === 'all' || log.level === levelFilter;
        return matchesSearch && matchesLevel;
      });

      logsDisplay.innerHTML = '';
      state.lastRenderedLogIndex = 0;

      if (filteredLogs.length === 0) {
        logsDisplay.innerHTML =
          '<div class="log-empty-state">No logs match the current filters.</div>';
        return;
      }

      // Use DocumentFragment for better performance
      const fragment = document.createDocumentFragment();
      filteredLogs.forEach((log) => {
        fragment.appendChild(createLogEntry(log));
      });
      logsDisplay.appendChild(fragment);
      state.lastRenderedLogIndex = state.logs.length;
    } else {
      // Incremental render - only append new logs
      if (state.lastRenderedLogIndex < state.logs.length) {
        const fragment = document.createDocumentFragment();
        for (let i = state.lastRenderedLogIndex; i < state.logs.length; i++) {
          fragment.appendChild(createLogEntry(state.logs[i]));
        }
        logsDisplay.appendChild(fragment);
        state.lastRenderedLogIndex = state.logs.length;
      }
    }

    // Auto-scroll if enabled
    if (state.elements.autoScroll?.checked) {
      logsDisplay.scrollTop = logsDisplay.scrollHeight;
    }
  });
}

// Helper function to create log entry element
function createLogEntry(log) {
  const logEntry = document.createElement('div');
  logEntry.className = 'log-entry';

  const timestamp = document.createElement('span');
  timestamp.className = 'log-timestamp';
  timestamp.textContent = log.timestamp;

  const level = document.createElement('span');
  level.className = `log-level ${log.level}`;
  level.textContent = log.level;

  const messageElement = document.createElement('span');
  messageElement.className = 'log-message';
  messageElement.textContent = log.message;

  logEntry.appendChild(timestamp);
  logEntry.appendChild(level);
  logEntry.appendChild(messageElement);

  return logEntry;
}

// Tab Navigation
export function switchTab(tabName) {
  // Prevent switching to hidden AICLI tab
  if (tabName === 'aicli') {
    console.log('AICLI tab is currently hidden');
    return;
  }

  // Update tab buttons
  document.querySelectorAll('.tab-button').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.tab === tabName);
  });

  // Update tab panels
  document.querySelectorAll('.tab-panel').forEach((panel) => {
    panel.classList.toggle('active', panel.id === `${tabName}-tab`);
  });

  state.currentTab = tabName;

  // Load logs when switching to logs tab
  if (tabName === 'logs') {
    loadLogs();
  }
  // AICLI tab functionality preserved but hidden
  // else if (tabName === 'aicli') {
  //   loadAICLIStatus();
  // }
}

// AICLI CLI Management
export async function loadAICLIStatus() {
  if (!state.serverStatus.running) {
    updateAICLIStatusUI({
      aicli: { installed: false, version: null, path: null, available: false },
      sessions: { active: 0, max: 0, details: [] },
    });
    return;
  }

  try {
    const response = await fetch(`http://localhost:${state.serverStatus.port}/api/aicli/status`);
    if (response.ok) {
      const status = await response.json();
      state.aicliStatus = status;
      updateAICLIStatusUI(status);
    }
  } catch (error) {
    console.error('Failed to load AICLI status:', error);
  }
}

export async function testAICLI() {
  if (!state.serverStatus.running) {
    alert('Server must be running to test AICLI CLI');
    return;
  }

  const testBtn = state.elements.testAICLIBtn;
  testBtn.disabled = true;
  testBtn.textContent = 'Testing...';

  try {
    const response = await fetch(`http://localhost:${state.serverStatus.port}/api/aicli/test`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt: 'Hello! Please respond with a brief greeting.' }),
    });

    const result = await response.json();

    if (result.success) {
      alert('AICLI CLI test successful! Check the AICLI logs for the response.');
      addAICLILog(
        'test',
        `Test successful: ${JSON.stringify(result.response).substring(0, 200)}...`
      );
    } else {
      alert(`AICLI CLI test failed: ${result.message}`);
      addAICLILog('error', `Test failed: ${result.message}`);
    }
  } catch (error) {
    alert(`Failed to test AICLI CLI: ${error.message}`);
    addAICLILog('error', `Test error: ${error.message}`);
  } finally {
    testBtn.disabled = false;
    testBtn.textContent = 'Test AICLI CLI';
  }
}

function updateAICLIStatusUI(status) {
  if (!status) return;

  // Update AICLI installation status
  const installedEl = state.elements.aicliInstalled;
  const versionEl = state.elements.aicliVersion;
  const pathEl = state.elements.aicliPath;
  const availableEl = state.elements.aicliAvailable;

  if (installedEl) {
    installedEl.textContent = status.aicli.installed ? 'Installed' : 'Not Installed';
    installedEl.className = status.aicli.installed ? 'status-value success' : 'status-value error';
  }

  if (versionEl) {
    versionEl.textContent = status.aicli.version || '-';
  }

  if (pathEl) {
    pathEl.textContent = status.aicli.path || '-';
  }

  if (availableEl) {
    availableEl.textContent = status.aicli.available ? 'Yes' : 'No';
    availableEl.className = status.aicli.available ? 'status-value success' : 'status-value error';
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
      sessionsList.innerHTML = '<div class="log-empty-state">No active AICLI CLI sessions</div>';
    } else {
      status.sessions.details.forEach((session) => {
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

function addAICLILog(type, content) {
  const log = {
    type,
    content,
    timestamp: new Date().toISOString(),
  };

  state.aicliLogs.push(log);
  if (state.aicliLogs.length > 500) {
    state.aicliLogs = state.aicliLogs.slice(-500); // Reduced for better performance
  }

  renderAICLILogs();
}

export function renderAICLILogs(fullRender = false) {
  const logsDisplay = state.elements.aicliLogsDisplay;
  if (!logsDisplay) return;

  // Prevent multiple renders in same frame
  if (state.aicliRenderPending) return;
  state.aicliRenderPending = true;

  requestAnimationFrame(() => {
    state.aicliRenderPending = false;

    const filterValue = state.elements.aicliLogFilter?.value || 'all';
    const filtersChanged = filterValue !== 'all';

    if (fullRender || filtersChanged) {
      // Full render for filtered view
      const filteredLogs = state.aicliLogs.filter((log) => {
        if (filterValue === 'all') return true;
        return log.type === filterValue;
      });

      logsDisplay.innerHTML = '';
      state.lastRenderedAICLILogIndex = 0;

      if (filteredLogs.length === 0) {
        logsDisplay.innerHTML =
          '<div class="log-empty-state">No AICLI CLI logs match the filter.</div>';
        return;
      }

      // Use DocumentFragment for better performance
      const fragment = document.createDocumentFragment();
      filteredLogs.forEach((log) => {
        fragment.appendChild(createAICLILogEntry(log));
      });
      logsDisplay.appendChild(fragment);
      state.lastRenderedAICLILogIndex = state.aicliLogs.length;
    } else {
      // Incremental render - only append new logs
      if (state.lastRenderedAICLILogIndex < state.aicliLogs.length) {
        const fragment = document.createDocumentFragment();
        for (let i = state.lastRenderedAICLILogIndex; i < state.aicliLogs.length; i++) {
          fragment.appendChild(createAICLILogEntry(state.aicliLogs[i]));
        }
        logsDisplay.appendChild(fragment);
        state.lastRenderedAICLILogIndex = state.aicliLogs.length;
      }
    }

    if (state.elements.aicliAutoScroll?.checked) {
      logsDisplay.scrollTop = logsDisplay.scrollHeight;
    }
  });
}

// Helper function to create AICLI log entry element
function createAICLILogEntry(log) {
  const logEntry = document.createElement('div');
  logEntry.className = 'aicli-log-entry';

  const logType = document.createElement('span');
  logType.className = `aicli-log-type ${log.type}`;
  logType.textContent = log.type;

  const logContent = document.createElement('span');
  logContent.className = 'aicli-log-content';
  logContent.textContent = log.content;

  logEntry.appendChild(logType);
  logEntry.appendChild(logContent);

  return logEntry;
}

export function clearAICLILogs() {
  state.aicliLogs = [];
  state.lastRenderedAICLILogIndex = 0; // Reset render index
  renderAICLILogs(true); // Full render after clearing
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
    // Session elements
    sessionSection: document.getElementById('session-section'),
    sessionCount: document.getElementById('session-count'),
    activeSessionsList: document.getElementById('active-sessions-list'),
    // AICLI elements
    aicliInstalled: document.getElementById('aicli-installed'),
    aicliVersion: document.getElementById('aicli-version'),
    aicliPath: document.getElementById('aicli-path'),
    aicliAvailable: document.getElementById('aicli-available'),
    refreshAICLIBtn: document.getElementById('refresh-aicli-btn'),
    testAICLIBtn: document.getElementById('test-aicli-btn'),
    activeSessionsCount: document.getElementById('active-sessions-count'),
    maxSessions: document.getElementById('max-sessions'),
    sessionsList: document.getElementById('sessions-list'),
    aicliLogsDisplay: document.getElementById('aicli-logs-display'),
    aicliLogFilter: document.getElementById('aicli-log-filter'),
    clearAICLILogsBtn: document.getElementById('clear-aicli-logs-btn'),
    aicliAutoScroll: document.getElementById('aicli-auto-scroll'),
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
  document.querySelectorAll('.tab-button').forEach((btn) => {
    btn.addEventListener('click', () => {
      switchTab(btn.dataset.tab);
    });
  });

  // Logs event listeners
  if (state.elements.logSearch) {
    const debouncedSearch = debounce(() => renderLogs(true), 300);
    state.elements.logSearch.addEventListener('input', debouncedSearch);
  }

  if (state.elements.logLevelFilter) {
    state.elements.logLevelFilter.addEventListener('change', () => renderLogs(true));
  }

  if (state.elements.clearLogsBtn) {
    state.elements.clearLogsBtn.addEventListener('click', clearLogs);
  }

  // AICLI event listeners
  if (state.elements.refreshAICLIBtn) {
    state.elements.refreshAICLIBtn.addEventListener('click', loadAICLIStatus);
  }

  if (state.elements.testAICLIBtn) {
    state.elements.testAICLIBtn.addEventListener('click', testAICLI);
  }

  if (state.elements.aicliLogFilter) {
    state.elements.aicliLogFilter.addEventListener('change', () => renderAICLILogs(true));
  }

  if (state.elements.clearAICLILogsBtn) {
    state.elements.clearAICLILogsBtn.addEventListener('click', clearAICLILogs);
  }

  // Listen for real-time log updates
  state.logsUnlisten = await listen('log-entry', (event) => {
    const log = event.payload;
    state.logs.push(log);
    // Keep only last 5000 logs in UI (matching backend limit)
    if (state.logs.length > 5000) {
      state.logs = state.logs.slice(-5000);
    }
    renderLogs();

    // Parse AICLI-specific logs
    if (log.message) {
      if (log.message.includes('[CLAUDE_PROCESS_START]')) {
        addAICLILog('start', log.message.replace('[CLAUDE_PROCESS_START]', '').trim());

        // Extract session info from start message
        const sessionMatch = log.message.match(/Session ID: (project_[^\s]+)/);
        const projectMatch = log.message.match(/Project: ([^\s]+)/);
        if (sessionMatch && projectMatch) {
          addSession({
            sessionId: sessionMatch[1],
            projectName: projectMatch[1],
            status: 'active',
            type: 'aicli-cli',
          });
        }
      } else if (log.message.includes('[CLAUDE_STDOUT]')) {
        addAICLILog('stdout', log.message.replace('[CLAUDE_STDOUT]', '').trim());
      } else if (log.message.includes('[CLAUDE_STDERR]')) {
        addAICLILog('stderr', log.message.replace('[CLAUDE_STDERR]', '').trim());
      } else if (log.message.includes('[CLAUDE_PROCESS_EXIT]')) {
        addAICLILog('exit', log.message.replace('[CLAUDE_PROCESS_EXIT]', '').trim());

        // Extract session ID and mark as stopped
        const sessionMatch = log.message.match(/Session (project_[^\s]+)/);
        if (sessionMatch) {
          removeSession(sessionMatch[1]);
        }
      } else if (log.message.includes('[CLAUDE_PROCESS_ERROR]')) {
        addAICLILog('error', log.message.replace('[CLAUDE_PROCESS_ERROR]', '').trim());
      } else if (log.message.includes('[CLAUDE_COMMAND]')) {
        addAICLILog('command', log.message.replace('[CLAUDE_COMMAND]', '').trim());

        // Update session activity
        const sessionMatch = log.message.match(/Session (project_[^\s]+)/);
        if (sessionMatch) {
          updateSession(sessionMatch[1], { lastCommand: new Date().toISOString() });
        }
      }
    }
  });

  // Start health check polling
  setInterval(checkServerHealth, 10000); // Reduced from 2s to 10s for cleaner logs
}
