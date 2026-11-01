use std::env;
use std::fs;
use std::path::Path;

fn main() {
    let engine_dir = Path::new("resources/dicty_engine");
    let profile = env::var("PROFILE").unwrap_or_default();

    if profile == "release" {
        // In release builds, ensure the real engine executable is present.
        // Never allow packaging a release with an empty directory or stub placeholder.
        let engine_exe = engine_dir.join("dicty_engine.exe");
        let engine_unix = engine_dir.join("dicty_engine");
        if !engine_exe.exists() && !engine_unix.exists() {
            panic!(
                "Release build failed: expected dicty_engine executable in {:?}. \
                 Run backend packaging (e.g. scripts/windows/build_win.bat) before building a release.",
                engine_dir
            );
        }
    } else {
        // In dev / debug / cargo check mode, provide a placeholder if the engine hasn't been built yet.
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
    }

    tauri_build::build();
}
