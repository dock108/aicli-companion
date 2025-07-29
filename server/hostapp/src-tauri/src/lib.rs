#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::env;
use std::io::{BufRead, BufReader};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::thread;
use tauri::{AppHandle, Emitter};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerStatus {
    pub running: bool,
    pub port: u16,
    pub pid: Option<u32>,
    pub health_url: String,
    pub external: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogEntry {
    pub timestamp: String,
    pub level: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LogsState {
    pub entries: Vec<LogEntry>,
    pub max_entries: usize,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct NetworkInfo {
    pub ip: String,
    pub port: u16,
}

pub struct AppState {
    pub server_process: Mutex<Option<std::process::Child>>,
    pub server_status: Mutex<ServerStatus>,
    pub logs: Arc<Mutex<LogsState>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            server_process: Mutex::new(None),
            server_status: Mutex::new(ServerStatus {
                running: false,
                port: 3001,
                pid: None,
                health_url: "http://localhost:3001/health".to_string(),
                external: false,
            }),
            logs: Arc::new(Mutex::new(LogsState {
                entries: Vec::new(),
                max_entries: 5000, // Reduced from 10000 for better performance
            })),
        }
    }
}

impl Default for AppState {
    fn default() -> Self {
        Self::new()
    }
}

pub fn get_local_ip() -> Result<String, String> {
    match local_ip_address::local_ip() {
        Ok(ip) => Ok(ip.to_string()),
        Err(e) => Err(format!("Failed to get local IP: {e}")),
    }
}

// Helper function to add log entry
fn add_log_entry(logs: &Arc<Mutex<LogsState>>, level: &str, message: String, app_handle: Option<&AppHandle>) {
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S%.3f").to_string();
    let entry = LogEntry {
        timestamp,
        level: level.to_string(),
        message,
    };

    let mut logs_guard = logs.lock().unwrap();
    logs_guard.entries.push(entry.clone());
    
    // Keep only the last max_entries
    let len = logs_guard.entries.len();
    let max = logs_guard.max_entries;
    if len > max {
        logs_guard.entries.drain(0..len - max);
    }
    drop(logs_guard);
    
    // Emit log event if app handle is provided
    if let Some(handle) = app_handle {
        let _ = handle.emit("log-entry", entry);
    }
}

// Get all logs
pub fn get_logs_impl(state: &AppState) -> Vec<LogEntry> {
    state.logs.lock().unwrap().entries.clone()
}

// Clear logs
pub fn clear_logs_impl(state: &AppState) {
    state.logs.lock().unwrap().entries.clear();
}

// Helper function to find process ID by port
pub fn find_process_by_port(port: u16) -> Option<u32> {
    #[cfg(target_os = "macos")]
    {
        let output = Command::new("lsof")
            .args(["-ti", &format!(":{port}")])
            .output()
            .ok()?;

        if output.status.success() {
            let pid_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
            pid_str.parse::<u32>().ok()
        } else {
            None
        }
    }

    #[cfg(target_os = "linux")]
    {
        let output = Command::new("lsof")
            .args(["-ti", &format!(":{port}")])
            .output()
            .ok()?;

        if output.status.success() {
            let pid_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
            pid_str.parse::<u32>().ok()
        } else {
            None
        }
    }

    #[cfg(target_os = "windows")]
    {
        // On Windows, use netstat to find the process
        let output = Command::new("netstat")
            .args(["-ano", "-p", "TCP"])
            .output()
            .ok()?;

        if output.status.success() {
            let output_str = String::from_utf8_lossy(&output.stdout);
            for line in output_str.lines() {
                if line.contains(&format!(":{port}")) && line.contains("LISTENING") {
                    let parts: Vec<&str> = line.split_whitespace().collect();
                    if let Some(pid_str) = parts.last() {
                        return pid_str.parse::<u32>().ok();
                    }
                }
            }
        }
        None
    }
}

pub async fn start_server_impl(
    state: &AppState, 
    port: u16,
    auth_token: Option<String>,
    config_path: Option<String>,
    app_handle: Option<&AppHandle>
) -> Result<ServerStatus, String> {
    // First check if server is already running on this port
    let health_check = check_server_health_impl(port).await?;

    if health_check {
        // Server is already running externally
        let mut status_guard = state.server_status.lock().unwrap();
        *status_guard = ServerStatus {
            running: true,
            port,
            pid: None,
            health_url: format!("http://localhost:{port}/health"),
            external: true,
        };
        return Ok(status_guard.clone());
    }

    let mut process_guard = state.server_process.lock().unwrap();

    // Check if we already have a process
    if process_guard.is_some() {
        return Err("Server process is already managed".to_string());
    }

    // Get server directory - different approach for dev vs prod
    let server_dir = if cfg!(debug_assertions) {
        // Development: Find the server directory relative to the desktop project
        let current_dir =
            env::current_dir().map_err(|e| format!("Failed to get current directory: {e}"))?;

        // Try to find the server directory by going up from current working directory
        let mut search_dir = current_dir.as_path();
        loop {
            let potential_server = search_dir.join("server");
            if potential_server.join("src").join("index.js").exists() {
                break potential_server;
            }

            let parent_server = search_dir.join("../server");
            if parent_server.join("src").join("index.js").exists() {
                break parent_server
                    .canonicalize()
                    .map_err(|e| format!("Failed to canonicalize path: {e}"))?;
            }

            match search_dir.parent() {
                Some(parent) => search_dir = parent,
                None => return Err("Could not find server directory with src/index.js".to_string()),
            }
        }
    } else {
        // Production: server should be in the same directory as the executable
        let current_exe =
            env::current_exe().map_err(|e| format!("Failed to get current exe: {e}"))?;

        let exe_dir = current_exe.parent().ok_or("Failed to get exe directory")?;

        exe_dir.join("server")
    };

    // Start the server
    let mut cmd = Command::new("node");
    cmd.arg("src/index.js")
        .current_dir(server_dir)
        .env("PORT", port.to_string())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    
    // Add auth token if provided
    if let Some(token) = auth_token {
        cmd.env("AUTH_TOKEN", token);
    }
    
    // Add config path if provided
    if let Some(path) = config_path {
        cmd.env("CONFIG_PATH", path);
    }

    match cmd.spawn() {
        Ok(mut child) => {
            let pid = child.id();
            
            // Set up log capturing for stdout
            if let Some(stdout) = child.stdout.take() {
                let logs_clone = Arc::clone(&state.logs);
                let app_handle_clone = app_handle.cloned();
                thread::spawn(move || {
                    let reader = BufReader::new(stdout);
                    for line in reader.lines() {
                        if let Ok(line) = line {
                            // Determine log level based on content
                            let level = if line.contains("ERROR") || line.contains("error") {
                                "error"
                            } else if line.contains("WARN") || line.contains("warning") {
                                "warning"
                            } else {
                                "info"
                            };
                            add_log_entry(&logs_clone, level, line, app_handle_clone.as_ref());
                        }
                    }
                });
            }
            
            // Set up log capturing for stderr
            if let Some(stderr) = child.stderr.take() {
                let logs_clone = Arc::clone(&state.logs);
                let app_handle_clone = app_handle.cloned();
                thread::spawn(move || {
                    let reader = BufReader::new(stderr);
                    for line in reader.lines() {
                        if let Ok(line) = line {
                            add_log_entry(&logs_clone, "error", line, app_handle_clone.as_ref());
                        }
                    }
                });
            }
            
            *process_guard = Some(child);

            // Update status
            let mut status_guard = state.server_status.lock().unwrap();
            *status_guard = ServerStatus {
                running: true,
                port,
                pid: Some(pid),
                health_url: format!("http://localhost:{port}/health"),
                external: false,
            };
            
            // Add start log entry
            add_log_entry(&state.logs, "info", format!("Server started on port {} (PID: {})", port, pid), app_handle);

            Ok(status_guard.clone())
        }
        Err(e) => {
            let error_msg = format!("Failed to start server: {e}");
            add_log_entry(&state.logs, "error", error_msg.clone(), app_handle);
            Err(error_msg)
        }
    }
}

pub async fn stop_server_impl(
    state: &AppState,
    force_external: Option<bool>,
    app_handle: Option<&AppHandle>
) -> Result<(), String> {
    let status_guard = state.server_status.lock().unwrap();
    let is_external = status_guard.external;
    let port = status_guard.port;
    drop(status_guard); // Release the lock

    // If it's an external server and force_external is not true, return error
    if is_external && !force_external.unwrap_or(false) {
        return Err(
            "Server was not started by this app. Use force_external=true to stop it anyway."
                .to_string(),
        );
    }

    let mut process_guard = state.server_process.lock().unwrap();

    // If we have a managed process, kill it
    if let Some(mut child) = process_guard.take() {
        match child.kill() {
            Ok(_) => {
                let mut status_guard = state.server_status.lock().unwrap();
                status_guard.running = false;
                status_guard.pid = None;
                status_guard.external = false;
                add_log_entry(&state.logs, "info", "Server stopped successfully".to_string(), app_handle);
                return Ok(());
            }
            Err(e) => return Err(format!("Failed to stop managed server: {e}")),
        }
    }

    // If it's an external server and force_external is true, find and kill the process
    if is_external && force_external.unwrap_or(false) {
        if let Some(pid) = find_process_by_port(port) {
            #[cfg(unix)]
            {
                let output = Command::new("kill")
                    .arg("-9")
                    .arg(pid.to_string())
                    .output()
                    .map_err(|e| format!("Failed to execute kill command: {e}"))?;

                if output.status.success() {
                    let mut status_guard = state.server_status.lock().unwrap();
                    status_guard.running = false;
                    status_guard.pid = None;
                    status_guard.external = false;
                    add_log_entry(&state.logs, "info", format!("External server on port {} stopped successfully", port), app_handle);
                    return Ok(());
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    let error_msg = format!("Failed to kill process {pid}: {stderr}");
                    add_log_entry(&state.logs, "error", error_msg.clone(), app_handle);
                    return Err(error_msg);
                }
            }

            #[cfg(windows)]
            {
                let output = Command::new("taskkill")
                    .args(["/F", "/PID", &pid.to_string()])
                    .output()
                    .map_err(|e| format!("Failed to execute taskkill command: {e}"))?;

                if output.status.success() {
                    let mut status_guard = state.server_status.lock().unwrap();
                    status_guard.running = false;
                    status_guard.pid = None;
                    status_guard.external = false;
                    add_log_entry(&state.logs, "info", format!("External server on port {} stopped successfully", port), app_handle);
                    return Ok(());
                } else {
                    let stderr = String::from_utf8_lossy(&output.stderr);
                    let error_msg = format!("Failed to kill process {pid}: {stderr}");
                    add_log_entry(&state.logs, "error", error_msg.clone(), app_handle);
                    return Err(error_msg);
                }
            }
        } else {
            return Err(format!("Could not find process listening on port {port}"));
        }
    }

    Err("Server is not running".to_string())
}

pub async fn check_server_health_impl(port: u16) -> Result<bool, String> {
    let url = format!("http://localhost:{port}/health");

    match reqwest::get(&url).await {
        Ok(response) => Ok(response.status().is_success()),
        Err(_) => Ok(false),
    }
}

pub fn get_server_status_impl(state: &AppState) -> ServerStatus {
    state.server_status.lock().unwrap().clone()
}

pub async fn detect_running_server_impl(
    state: &AppState,
    port: u16,
) -> Result<ServerStatus, String> {
    let is_running = check_server_health_impl(port).await?;

    let mut status_guard = state.server_status.lock().unwrap();

    if is_running {
        // Check if we have a managed process
        let process_guard = state.server_process.lock().unwrap();
        let is_external = process_guard.is_none();

        *status_guard = ServerStatus {
            running: true,
            port,
            pid: None,
            health_url: format!("http://localhost:{port}/health"),
            external: is_external,
        };
    } else {
        status_guard.running = false;
        status_guard.external = false;
        status_guard.pid = None;
    }

    Ok(status_guard.clone())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_local_ip() {
        let result = get_local_ip();
        assert!(result.is_ok());
        let ip = result.unwrap();
        assert!(!ip.is_empty());
        // Check if it's a valid IP format
        assert!(ip.contains('.') || ip.contains(':'));
    }

    #[test]
    fn test_app_state_creation() {
        let state = AppState::new();
        let status = state.server_status.lock().unwrap();
        assert_eq!(status.running, false);
        assert_eq!(status.port, 3001);
        assert_eq!(status.pid, None);
        assert_eq!(status.external, false);
    }

    #[test]
    fn test_server_status_serialization() {
        let status = ServerStatus {
            running: true,
            port: 3001,
            pid: Some(12345),
            health_url: "http://localhost:3001/health".to_string(),
            external: false,
        };

        let json = serde_json::to_string(&status).unwrap();
        assert!(json.contains("\"running\":true"));
        assert!(json.contains("\"port\":3001"));
        assert!(json.contains("\"pid\":12345"));
        assert!(json.contains("\"external\":false"));

        let deserialized: ServerStatus = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.running, status.running);
        assert_eq!(deserialized.port, status.port);
        assert_eq!(deserialized.pid, status.pid);
        assert_eq!(deserialized.external, status.external);
    }

    #[tokio::test]
    async fn test_check_server_health_impl() {
        // Test with a port that's unlikely to be running
        let result = check_server_health_impl(65432).await;
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), false);
    }

    #[test]
    fn test_get_server_status_impl() {
        let state = AppState::new();
        let status = get_server_status_impl(&state);
        assert_eq!(status.running, false);
        assert_eq!(status.port, 3001);
        assert_eq!(status.pid, None);
        assert_eq!(status.external, false);
    }

    #[tokio::test]
    async fn test_detect_running_server_not_running() {
        let state = AppState::new();
        let result = detect_running_server_impl(&state, 65432).await;
        assert!(result.is_ok());
        let status = result.unwrap();
        assert_eq!(status.running, false);
        assert_eq!(status.external, false);
        assert_eq!(status.pid, None);
    }

    #[test]
    fn test_find_process_by_port() {
        // Test with a port that's unlikely to be in use
        let result = find_process_by_port(65432);
        assert_eq!(result, None);
    }

    #[tokio::test]
    async fn test_stop_server_not_started() {
        let state = AppState::new();
        let result = stop_server_impl(&state, None).await;
        assert!(result.is_err());
        assert_eq!(result.unwrap_err(), "Server is not running");
    }

    #[tokio::test]
    async fn test_stop_external_server_without_force() {
        let state = AppState::new();
        {
            let mut status = state.server_status.lock().unwrap();
            status.external = true;
            status.running = true;
        }

        let result = stop_server_impl(&state, Some(false)).await;
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("not started by this app"));
    }

    #[test]
    fn test_network_info_serialization() {
        let info = NetworkInfo {
            ip: "192.168.1.100".to_string(),
            port: 3001,
        };

        let json = serde_json::to_string(&info).unwrap();
        assert!(json.contains("\"ip\":\"192.168.1.100\""));
        assert!(json.contains("\"port\":3001"));

        let deserialized: NetworkInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.ip, info.ip);
        assert_eq!(deserialized.port, info.port);
    }
}
