#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use tauri::State;
use serde::{Deserialize, Serialize};
use std::io::Read;

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ServerStatus {
    running: bool,
    port: u16,
    pid: Option<u32>,
    health_url: String,
    external: bool, // true if server wasn't started by this app
}

#[derive(Debug, Serialize, Deserialize)]
struct NetworkInfo {
    ip: String,
    port: u16,
}

struct AppState {
    server_process: Mutex<Option<std::process::Child>>,
    server_status: Mutex<ServerStatus>,
}

#[tauri::command]
fn get_local_ip() -> Result<String, String> {
    match local_ip_address::local_ip() {
        Ok(ip) => Ok(ip.to_string()),
        Err(e) => Err(format!("Failed to get local IP: {}", e)),
    }
}

// Helper function to find process ID by port
fn find_process_by_port(port: u16) -> Option<u32> {
    #[cfg(target_os = "macos")]
    {
        let output = Command::new("lsof")
            .args(&["-ti", &format!(":{}", port)])
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
            .args(&["-ti", &format!(":{}", port)])
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
            .args(&["-ano", "-p", "TCP"])
            .output()
            .ok()?;
        
        if output.status.success() {
            let output_str = String::from_utf8_lossy(&output.stdout);
            for line in output_str.lines() {
                if line.contains(&format!(":{}", port)) && line.contains("LISTENING") {
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

#[tauri::command]
async fn start_server(state: State<'_, AppState>, port: u16) -> Result<ServerStatus, String> {
    // First check if server is already running on this port
    let health_check = check_server_health(port).await?;
    
    if health_check {
        // Server is already running externally
        let mut status_guard = state.server_status.lock().unwrap();
        *status_guard = ServerStatus {
            running: true,
            port,
            pid: None,
            health_url: format!("http://localhost:{}/health", port),
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
        let current_dir = env::current_dir()
            .map_err(|e| format!("Failed to get current directory: {}", e))?;
        
        // Try to find the server directory by going up from current working directory
        let mut search_dir = current_dir.as_path();
        loop {
            let potential_server = search_dir.join("server");
            if potential_server.join("src").join("index.js").exists() {
                break potential_server;
            }
            
            let parent_server = search_dir.join("../server");
            if parent_server.join("src").join("index.js").exists() {
                break parent_server.canonicalize()
                    .map_err(|e| format!("Failed to canonicalize path: {}", e))?;
            }
            
            match search_dir.parent() {
                Some(parent) => search_dir = parent,
                None => return Err("Could not find server directory with src/index.js".to_string()),
            }
        }
    } else {
        // Production: server should be in the same directory as the executable
        let current_exe = env::current_exe()
            .map_err(|e| format!("Failed to get current exe: {}", e))?;
        
        let exe_dir = current_exe.parent()
            .ok_or("Failed to get exe directory")?;
            
        exe_dir.join("server")
    };
    
    // Start the server
    let mut cmd = Command::new("node");
    cmd.arg("src/index.js")
        .current_dir(server_dir)
        .env("PORT", port.to_string())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    
    match cmd.spawn() {
        Ok(child) => {
            let pid = child.id();
            *process_guard = Some(child);
            
            // Update status
            let mut status_guard = state.server_status.lock().unwrap();
            *status_guard = ServerStatus {
                running: true,
                port,
                pid: Some(pid),
                health_url: format!("http://localhost:{}/health", port),
                external: false,
            };
            
            Ok(status_guard.clone())
        }
        Err(e) => Err(format!("Failed to start server: {}", e)),
    }
}

#[tauri::command]
async fn stop_server(state: State<'_, AppState>, force_external: Option<bool>) -> Result<(), String> {
    let status_guard = state.server_status.lock().unwrap();
    let is_external = status_guard.external;
    let port = status_guard.port;
    drop(status_guard); // Release the lock
    
    // If it's an external server and force_external is not true, return error
    if is_external && !force_external.unwrap_or(false) {
        return Err("Server was not started by this app. Use force_external=true to stop it anyway.".to_string());
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
                return Ok(());
            }
            Err(e) => return Err(format!("Failed to stop managed server: {}", e)),
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
                    .map_err(|e| format!("Failed to execute kill command: {}", e))?;
                
                if output.status.success() {
                    let mut status_guard = state.server_status.lock().unwrap();
                    status_guard.running = false;
                    status_guard.pid = None;
                    status_guard.external = false;
                    return Ok(());
                } else {
                    return Err(format!("Failed to kill process {}: {}", pid, String::from_utf8_lossy(&output.stderr)));
                }
            }
            
            #[cfg(windows)]
            {
                let output = Command::new("taskkill")
                    .args(&["/F", "/PID", &pid.to_string()])
                    .output()
                    .map_err(|e| format!("Failed to execute taskkill command: {}", e))?;
                
                if output.status.success() {
                    let mut status_guard = state.server_status.lock().unwrap();
                    status_guard.running = false;
                    status_guard.pid = None;
                    status_guard.external = false;
                    return Ok(());
                } else {
                    return Err(format!("Failed to kill process {}: {}", pid, String::from_utf8_lossy(&output.stderr)));
                }
            }
        } else {
            return Err(format!("Could not find process listening on port {}", port));
        }
    }
    
    Err("Server is not running".to_string())
}

#[tauri::command]
async fn check_server_health(port: u16) -> Result<bool, String> {
    let url = format!("http://localhost:{}/health", port);
    
    match reqwest::get(&url).await {
        Ok(response) => Ok(response.status().is_success()),
        Err(_) => Ok(false),
    }
}

#[tauri::command]
fn get_server_status(state: State<'_, AppState>) -> ServerStatus {
    state.server_status.lock().unwrap().clone()
}

#[tauri::command]
async fn detect_running_server(state: State<'_, AppState>, port: u16) -> Result<ServerStatus, String> {
    let is_running = check_server_health(port).await?;
    
    let mut status_guard = state.server_status.lock().unwrap();
    
    if is_running {
        // Check if we have a managed process
        let process_guard = state.server_process.lock().unwrap();
        let is_external = process_guard.is_none();
        
        *status_guard = ServerStatus {
            running: true,
            port,
            pid: None,
            health_url: format!("http://localhost:{}/health", port),
            external: is_external,
        };
    } else {
        status_guard.running = false;
        status_guard.external = false;
        status_guard.pid = None;
    }
    
    Ok(status_guard.clone())
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .manage(AppState {
            server_process: Mutex::new(None),
            server_status: Mutex::new(ServerStatus {
                running: false,
                port: 3001,
                pid: None,
                health_url: "http://localhost:3001/health".to_string(),
                external: false,
            }),
        })
        .invoke_handler(tauri::generate_handler![
            get_local_ip,
            start_server,
            stop_server,
            check_server_health,
            get_server_status,
            detect_running_server
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}