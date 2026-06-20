mod commands;
mod markdown;
mod watcher;

use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;

#[cfg(desktop)]
use tauri::Manager;
use tauri::{Emitter, State};

#[derive(Default)]
pub struct AppState {
    pub current_path: Mutex<Option<PathBuf>>,
    pub watcher: Mutex<Option<watcher::FileWatcher>>,
    pub initial_file: Mutex<Option<String>>,
    pub frontend_ready: AtomicBool,
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let mut builder = tauri::Builder::default();

    #[cfg(desktop)]
    {
        builder = builder.plugin(tauri_plugin_single_instance::init(|app, argv, cwd| {
            if let Some(path) = first_md_arg(&argv) {
                let abs = resolve_arg(&path, std::path::Path::new(&cwd));
                if let Ok(payload) = commands::load_path(app, abs) {
                    let _ = app.emit("file-opened", payload);
                }
            }
            if let Some(window) = app.get_webview_window("main") {
                let _ = window.set_focus();
            }
        }));
    }

    builder
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .plugin(tauri_plugin_cli::init())
        .plugin(tauri_plugin_opener::init())
        .manage(AppState::default())
        .invoke_handler(tauri::generate_handler![
            commands::open_file_dialog,
            commands::load_file,
            commands::get_initial_file,
            commands::get_highlight_css,
        ])
        .setup(|app| {
            #[cfg(desktop)]
            capture_cli_arg(app);
            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|_app, _event| {
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Opened { urls } = _event {
                handle_opened(_app, urls);
            }
        });
}

// CLI args may be relative paths. Resolve them against the caller's working
// directory up front — when launched from an AppImage the process CWD is the
// mountpoint, not the user's shell dir, so a bare "README.md" would not be found.
#[cfg(desktop)]
fn resolve_arg(path: &str, base: &std::path::Path) -> PathBuf {
    let p = PathBuf::from(path);
    if p.is_absolute() {
        p
    } else {
        base.join(p)
    }
}

#[cfg(desktop)]
fn first_md_arg(argv: &[String]) -> Option<String> {
    argv.iter()
        .skip(1)
        .find(|a| {
            let lower = a.to_lowercase();
            lower.ends_with(".md") || lower.ends_with(".markdown")
        })
        .cloned()
}

#[cfg(desktop)]
fn capture_cli_arg(app: &tauri::App) {
    use tauri_plugin_cli::CliExt;
    let Ok(matches) = app.cli().matches() else {
        return;
    };
    if let Some(arg) = matches.args.get("source") {
        if let Some(s) = arg.value.as_str() {
            if !s.is_empty() {
                let base = std::env::current_dir().unwrap_or_default();
                let abs = resolve_arg(s, &base);
                let state: State<AppState> = app.state();
                *state.initial_file.lock().unwrap() = Some(abs.to_string_lossy().into_owned());
            }
        }
    }
}

#[cfg(target_os = "macos")]
fn handle_opened(app: &tauri::AppHandle, urls: Vec<tauri::Url>) {
    for url in urls {
        let Ok(path) = url.to_file_path() else {
            continue;
        };
        let state = app.state::<AppState>();
        if state.frontend_ready.load(Ordering::SeqCst) {
            if let Ok(payload) = commands::load_path(app, path) {
                let _ = app.emit("file-opened", payload);
            }
        } else {
            *state.initial_file.lock().unwrap() = Some(path.to_string_lossy().to_string());
        }
    }
}
