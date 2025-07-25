// Import Tauri API
const { invoke } = window.__TAURI__.core;
const { open } = window.__TAURI__.dialog || {}; // Dialog might be through plugin
const { appDataDir } = window.__TAURI__.path;

// Import QR code library
import QRCode from 'qrcode';

// State
let serverStatus = {
    running: false,
    port: 3001,
    pid: null,
    healthUrl: null,
    external: false
};

let localIp = '';
let configPath = '';

// DOM Elements
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

// Initialize
async function init() {
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
    browseBtn.addEventListener('click', selectConfigPath);
    startBtn.addEventListener('click', startServer);
    stopBtn.addEventListener('click', stopServer);
    portInput.addEventListener('change', saveConfig);
    
    // Start health check polling
    setInterval(checkServerHealth, 2000);
}

// Config Management
async function loadConfig() {
    try {
        const savedConfig = localStorage.getItem('claude-companion-config');
        if (savedConfig) {
            const config = JSON.parse(savedConfig);
            configPath = config.configPath || await getDefaultPath();
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
        configPath: configPath,
        port: parseInt(portInput.value)
    };
    localStorage.setItem('claude-companion-config', JSON.stringify(config));
}

async function getDefaultPath() {
    try {
        const dataDir = await appDataDir();
        return dataDir + '/claude-companion';
    } catch {
        return '~/claude-companion-data';
    }
}

async function selectConfigPath() {
    try {
        const selected = await open({
            directory: true,
            multiple: false,
            defaultPath: configPath,
        });
        
        if (selected) {
            configPath = selected;
            configPathInput.value = configPath;
            await saveConfig();
        }
    } catch (error) {
        console.error('Failed to select path:', error);
    }
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
        alert('Failed to start server: ' + error);
    } finally {
        startBtn.disabled = false;
        startBtn.classList.remove('loading');
    }
}

async function stopServer() {
    stopBtn.disabled = true;
    
    try {
        await invoke('stop_server');
        serverStatus.running = false;
        serverStatus.pid = null;
        await updateUI();
    } catch (error) {
        console.error('Failed to stop server:', error);
        alert('Failed to stop server: ' + error);
    } finally {
        stopBtn.disabled = false;
    }
}

async function checkServerHealth() {
    if (!serverStatus.running) return;
    
    try {
        const isHealthy = await invoke('check_server_health', { 
            port: serverStatus.port 
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
            stopBtn.disabled = true;
            stopBtn.title = 'Cannot stop externally managed server';
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
                dark: '#0E1116',  // Dark-Slate Terminal bg color
                light: '#FFFFFF'
            }
        });
    } catch (error) {
        console.error('Failed to generate QR code:', error);
    }
}

// Initialize when DOM is ready
document.addEventListener('DOMContentLoaded', init);