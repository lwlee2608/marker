use std::path::{Path, PathBuf};
use std::time::Duration;

use notify_debouncer_full::notify::{RecommendedWatcher, RecursiveMode, Watcher};
use notify_debouncer_full::{new_debouncer, DebounceEventResult, Debouncer, FileIdMap};
use tauri::{AppHandle, Emitter};

use crate::markdown;

pub type FileWatcher = Debouncer<RecommendedWatcher, FileIdMap>;

/// Watch the file's parent directory (NonRecursive) and re-render on any
/// debounced event touching the target. Watching the directory survives the
/// temp-write + rename dance editors use for atomic saves.
pub fn watch(app: &AppHandle, path: &Path) -> Result<FileWatcher, String> {
    let target: PathBuf = path.to_path_buf();
    let watch_dir: PathBuf = target
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| target.clone());

    let app = app.clone();
    let target_cb = target.clone();

    let mut debouncer = new_debouncer(
        Duration::from_millis(200),
        None,
        move |result: DebounceEventResult| {
            let Ok(events) = result else { return };
            let touched = events
                .iter()
                .any(|e| e.paths.iter().any(|p| same_file(p, &target_cb)));
            if !touched {
                return;
            }
            match markdown::render_path(&target_cb) {
                Ok(payload) => {
                    let _ = app.emit("file-changed", payload);
                }
                Err(e) => eprintln!("re-render failed: {e}"),
            }
        },
    )
    .map_err(|e| e.to_string())?;

    debouncer
        .watcher()
        .watch(&watch_dir, RecursiveMode::NonRecursive)
        .map_err(|e| e.to_string())?;
    debouncer
        .cache()
        .add_root(&watch_dir, RecursiveMode::NonRecursive);

    Ok(debouncer)
}

fn same_file(a: &Path, b: &Path) -> bool {
    if a == b {
        return true;
    }
    match (a.canonicalize(), b.canonicalize()) {
        (Ok(x), Ok(y)) => x == y,
        _ => a.file_name() == b.file_name(),
    }
}
