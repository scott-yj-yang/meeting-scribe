use serde::Serialize;
use tauri::Manager;

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
        Some(path) => {
            let path_str = path.to_string_lossy().to_string();
            let metadata = std::fs::metadata(&path_str)
                .map_err(|e| format!("Failed to read file: {}", e))?;
            let name = std::path::Path::new(&path_str)
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

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            check_server_health,
            get_platform,
            pick_audio_file,
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
