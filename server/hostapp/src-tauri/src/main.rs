#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::State;

use claude_companion_hostapp::{
    check_server_health_impl, detect_running_server_impl, get_local_ip as get_local_ip_impl,
    get_server_status_impl, start_server_impl, stop_server_impl, AppState, ServerStatus,
};

#[tauri::command]
fn get_local_ip() -> Result<String, String> {
    get_local_ip_impl()
}

#[tauri::command]
async fn start_server(state: State<'_, AppState>, port: u16) -> Result<ServerStatus, String> {
    start_server_impl(&state, port).await
}

#[tauri::command]
async fn stop_server(
    state: State<'_, AppState>,
    force_external: Option<bool>,
) -> Result<(), String> {
    stop_server_impl(&state, force_external).await
}

#[tauri::command]
async fn check_server_health(port: u16) -> Result<bool, String> {
    check_server_health_impl(port).await
}

#[tauri::command]
fn get_server_status(state: State<'_, AppState>) -> ServerStatus {
    get_server_status_impl(&state)
}

#[tauri::command]
async fn detect_running_server(
    state: State<'_, AppState>,
    port: u16,
) -> Result<ServerStatus, String> {
    detect_running_server_impl(&state, port).await
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_shell::init())
        .manage(AppState::new())
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
