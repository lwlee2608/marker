// Prevents an extra console window on Windows in release.
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    if std::env::args().skip(1).any(|a| a == "--version" || a == "-V") {
        println!("marker {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    marker_lib::run();
}
