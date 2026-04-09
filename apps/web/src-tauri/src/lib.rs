use serde::Serialize;
use std::sync::Mutex;

/// Check if the Next.js backend is reachable.
#[tauri::command]
async fn check_server_health() -> Result<bool, String> {
    let url = "http://localhost:3000/api/health/claude";
    let client = reqwest::Client::new();
    match client.get(url).send().await {
        Ok(resp) => Ok(resp.status().is_success()),
        Err(_) => Ok(false),
    }
}

/// Get the platform name for conditional UI.
#[tauri::command]
fn get_platform() -> &'static str {
    if cfg!(target_os = "macos") {
        "macos"
    } else if cfg!(target_os = "windows") {
        "windows"
    } else {
        "linux"
    }
}

#[derive(Serialize)]
struct AudioFileResult {
    path: String,
    name: String,
    size: u64,
}

/// Open a native file dialog to select an audio file for transcription.
#[tauri::command]
async fn pick_audio_file(app: tauri::AppHandle) -> Result<Option<AudioFileResult>, String> {
    use tauri_plugin_dialog::DialogExt;

    let file = app
        .dialog()
        .file()
        .add_filter("Audio Files", &["wav", "mp3", "m4a", "ogg", "flac", "webm", "mp4"])
        .blocking_pick_file();

    match file {
        Some(file_path) => {
            let path_buf = file_path
                .into_path()
                .map_err(|e| format!("Invalid file path: {}", e))?;
            let path_str = path_buf.to_string_lossy().to_string();
            let metadata = std::fs::metadata(&path_buf)
                .map_err(|e| format!("Failed to read file: {}", e))?;
            let name = path_buf
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_default();
            Ok(Some(AudioFileResult {
                path: path_str,
                name,
                size: metadata.len(),
            }))
        }
        None => Ok(None),
    }
}

/// Manages the Next.js sidecar server process.
struct ServerProcess(Mutex<Option<std::process::Child>>);

#[tauri::command]
fn start_server(state: tauri::State<'_, ServerProcess>) -> Result<String, String> {
    let mut guard = state.0.lock().unwrap();
    if guard.is_some() {
        return Ok("Server already running".into());
    }

    // In production, run the bundled standalone server
    let exe_dir = std::env::current_exe()
        .map_err(|e| e.to_string())?
        .parent()
        .unwrap()
        .to_path_buf();
    let server_dir = exe_dir.join("sidecar");

    if !server_dir.exists() {
        return Err("Sidecar directory not found — running in dev mode?".into());
    }

    let child = std::process::Command::new("node")
        .arg("server.js")
        .current_dir(&server_dir)
        .env("PORT", "3000")
        .env("HOSTNAME", "localhost")
        .spawn()
        .map_err(|e| format!("Failed to start server: {}", e))?;

    *guard = Some(child);
    Ok("Server started on port 3000".into())
}

#[tauri::command]
fn stop_server(state: tauri::State<'_, ServerProcess>) -> Result<(), String> {
    let mut guard = state.0.lock().unwrap();
    if let Some(mut child) = guard.take() {
        child.kill().map_err(|e| format!("Failed to stop server: {}", e))?;
    }
    Ok(())
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .manage(ServerProcess(Mutex::new(None)))
        .invoke_handler(tauri::generate_handler![
            check_server_health,
            get_platform,
            pick_audio_file,
            start_server,
            stop_server,
        ])
        .setup(|app| {
            if cfg!(debug_assertions) {
                app.handle().plugin(
                    tauri_plugin_log::Builder::default()
                        .level(log::LevelFilter::Info)
                        .build(),
                )?;
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
