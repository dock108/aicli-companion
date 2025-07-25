#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::env;
use std::process::{Command, Stdio};
use std::sync::Mutex;
use tauri::State;
use serde::{Deserialize, Serialize};

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
    
    // Get current executable directory and navigate to server
    let current_exe = env::current_exe()
        .map_err(|e| format!("Failed to get current exe: {}", e))?;
    
    let exe_dir = current_exe.parent()
        .ok_or("Failed to get exe directory")?;
    
    // In dev mode, we need to go up more directories
    // In production, the structure will be different
    let server_dir = if cfg!(debug_assertions) {
        // Development: exe is in target/debug, so go up to find server
        exe_dir
            .parent() // target
            .and_then(|p| p.parent()) // desktop
            .and_then(|p| p.parent()) // server
            .ok_or("Failed to find server directory in dev")?
    } else {
        // Production: adjust path as needed
        exe_dir
            .parent()
            .and_then(|p| p.parent())
            .ok_or("Failed to find server directory in prod")?
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
async fn stop_server(state: State<'_, AppState>) -> Result<(), String> {
    let status_guard = state.server_status.lock().unwrap();
    
    if status_guard.external {
        drop(status_guard); // Release the lock
        return Err("Cannot stop externally managed server".to_string());
    }
    drop(status_guard); // Release the lock
    
    let mut process_guard = state.server_process.lock().unwrap();
    
    if let Some(mut child) = process_guard.take() {
        match child.kill() {
            Ok(_) => {
                let mut status_guard = state.server_status.lock().unwrap();
                status_guard.running = false;
                status_guard.pid = None;
                status_guard.external = false;
                Ok(())
            }
            Err(e) => Err(format!("Failed to stop server: {}", e)),
        }
    } else {
        Err("Server is not running".to_string())
    }
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