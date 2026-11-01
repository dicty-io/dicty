use std::fs;
use std::path::Path;

fn main() {
    // Ensure the resources directory declared in tauri.conf.json has at least one
    // file so tauri-build does not fail when checking/building without PyInstaller.
    let engine_dir = Path::new("resources/dicty_engine");
    if !engine_dir.exists() {
        let _ = fs::create_dir_all(engine_dir);
    }
    let is_empty = fs::read_dir(engine_dir)
        .map(|mut entries| entries.next().is_none())
        .unwrap_or(true);
    if is_empty {
        let _ = fs::write(
            engine_dir.join(".placeholder"),
            "Placeholder for Tauri resources glob matching during compilation.\n",
        );
    }

    tauri_build::build();
}
