use std::path::PathBuf;
use std::sync::atomic::Ordering;

use tauri::{AppHandle, Manager};
use tauri_plugin_dialog::DialogExt;

use crate::markdown::{self, DocPayload};
use crate::watcher;
use crate::AppState;

#[tauri::command]
pub fn get_initial_file(state: tauri::State<AppState>) -> Option<String> {
    state.frontend_ready.store(true, Ordering::SeqCst);
    state.initial_file.lock().unwrap().take()
}

#[tauri::command]
pub fn get_highlight_css() -> String {
    markdown::highlight_css()
}

#[tauri::command]
pub fn open_file_dialog(app: AppHandle) -> Result<Option<DocPayload>, String> {
    let file = app
        .dialog()
        .file()
        .add_filter("Markdown", &["md", "markdown"])
        .blocking_pick_file();

    match file {
        Some(fp) => {
            let path = fp.into_path().map_err(|e| e.to_string())?;
            Ok(Some(load_path(&app, path)?))
        }
        None => Ok(None),
    }
}

#[tauri::command]
pub fn load_file(app: AppHandle, path: String) -> Result<DocPayload, String> {
    load_path(&app, PathBuf::from(path))
}

/// Single funnel: render → swap the active watcher to this path → return payload.
pub fn load_path(app: &AppHandle, path: PathBuf) -> Result<DocPayload, String> {
    let path = std::fs::canonicalize(&path).unwrap_or(path);
    let payload = markdown::render_path(&path)?;

    let state = app.state::<AppState>();
    *state.current_path.lock().unwrap() = Some(path.clone());

    match watcher::watch(app, &path) {
        Ok(debouncer) => *state.watcher.lock().unwrap() = Some(debouncer),
        Err(e) => eprintln!("watch failed: {e}"),
    }

    Ok(payload)
}
