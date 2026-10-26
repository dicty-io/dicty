#[cfg(target_os = "windows")]
use std::path::{Path, PathBuf};
use std::process::Child;
#[cfg(target_os = "windows")]
use std::process::Command;
use std::sync::Mutex;
use std::time::Duration;

use tauri::{AppHandle, Emitter, Manager};

use crate::{engine_auth, engine_http};

pub struct EngineState {
    pub process: Mutex<Option<Child>>,
    pub port: u16,
}

impl Default for EngineState {
    fn default() -> Self {
        Self {
            process: Mutex::new(None),
            port: engine_http::port(),
        }
    }
}

fn emit_engine_error(app: &AppHandle, message: &str) {
    eprintln!("[!] {}", message);
    let _ = app.emit(
        "engine-auth-failed",
        serde_json::json!({ "error": message }),
    );
}

fn is_port_listening(port: u16) -> bool {
    for _ in 0..10 {
        if std::net::TcpStream::connect_timeout(
            &std::net::SocketAddr::from(([127, 0, 0, 1], port)),
            Duration::from_millis(100),
        )
        .is_ok()
        {
            return true;
        }
    }
    false
}

fn verify_existing_engine(app: &AppHandle) -> bool {
    let health_client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_millis(700))
        .build()
        .unwrap_or_default();
    let health_url = engine_http::url("/health");

    let mut healthy = false;
    for _ in 0..10 {
        if let Ok(response) = health_client.get(&health_url).send() {
            if response.status().is_success() {
                healthy = true;
                break;
            }
        }
        std::thread::sleep(Duration::from_millis(100));
    }

    if !healthy {
        emit_engine_error(
            app,
            "Another program is using Dicty's engine port. Close it and restart Dicty.",
        );
        return false;
    }

    let mut token = None;
    for _ in 0..10 {
        token = engine_auth::adopt_running_token();
        if token.is_some() {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }

    let Some(token) = token else {
        emit_engine_error(
            app,
            "Dicty's engine is running but its session token could not be read. Restart the engine.",
        );
        return false;
    };

    let auth_client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(2))
        .build()
        .unwrap_or_default();
    let models_url = engine_http::url("/models");

    match auth_client
        .get(&models_url)
        .header(engine_auth::HEADER_NAME, token)
        .send()
    {
        Ok(response) if response.status().is_success() => {
            println!("[*] Adopted the running Dicty engine with its session token.");
            true
        }
        Ok(response) => {
            emit_engine_error(
                app,
                &format!(
                    "Another program is using Dicty's engine port (HTTP {}). Close it and restart Dicty.",
                    response.status()
                ),
            );
            false
        }
        Err(error) => {
            emit_engine_error(
                app,
                &format!(
                    "Could not verify Dicty's running engine: {}. Restart the engine.",
                    error
                ),
            );
            false
        }
    }
}

#[cfg(target_os = "windows")]
fn configure_engine_command(command: &mut Command) {
    command
        .env("DICTY_SESSION_TOKEN", engine_auth::launch_token())
        .env("DICTY_DATA_DIR", engine_auth::data_dir());
}

/// Spawns the local dicty_engine process if it's not already running
pub fn ensure_engine_running(app: &AppHandle, state: &EngineState) {
    let mut proc_guard = state.process.lock().unwrap();
    if let Some(child) = proc_guard.as_mut() {
        match child.try_wait() {
            Ok(None) => return, // Child is still actively running
            _ => {
                // Process has exited or failed, reset state so it can be respawned
                *proc_guard = None;
            }
        }
    }

    engine_auth::launch_token();

    if is_port_listening(state.port) {
        if verify_existing_engine(app) {
            println!(
                "[*] Dicty backend engine is already listening on port {}, skipping local process spawn.",
                state.port
            );
            engine_auth::set_trusted(true);
            return;
        }

        engine_auth::set_trusted(false);
        return;
    }

    engine_auth::set_trusted(true);

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x08000000;

        // In debug / development mode, prioritize the active Python source code in the workspace
        #[cfg(debug_assertions)]
        {
            let dev_python_candidates = [
                PathBuf::from("../../.venv/Scripts/python.exe"),
                PathBuf::from("../.venv/Scripts/python.exe"),
                PathBuf::from(".venv/Scripts/python.exe"),
            ];
            for py in &dev_python_candidates {
                if py.exists() {
                    let ws_dir = py
                        .parent()
                        .and_then(|p| p.parent())
                        .unwrap_or(Path::new("."));
                    let engine_script = ws_dir.join("dicty_engine.py");
                    if engine_script.exists() {
                        println!(
                            "[*] [DEV] Launching active Python backend engine: {:?} {:?}",
                            py, engine_script
                        );
                        let mut command = Command::new(py);
                        command
                            .arg("dicty_engine.py")
                            .current_dir(ws_dir)
                            .creation_flags(CREATE_NO_WINDOW);
                        configure_engine_command(&mut command);
                        match command.spawn() {
                            Ok(child) => {
                                *proc_guard = Some(child);
                                return;
                            }
                            Err(err) => {
                                eprintln!("[!] [DEV] Failed to spawn python backend: {}", err)
                            }
                        }
                    }
                }
            }
        }

        let exe_candidates = [
            // 1. Packaged inside resources/ (Tauri standard layout in release bundles)
            #[cfg(not(debug_assertions))]
            std::env::current_exe().ok().and_then(|p| {
                p.parent().map(|d| {
                    d.join("resources")
                        .join("dicty_engine")
                        .join("dicty_engine.exe")
                })
            }),
            // 2. Packaged next to Dicty.exe (e.g. C:\Program Files\Dicty\dicty_engine\dicty_engine.exe)
            std::env::current_exe().ok().and_then(|p| {
                p.parent()
                    .map(|d| d.join("dicty_engine").join("dicty_engine.exe"))
            }),
            // 3. Bundled NSIS relative layout (_up_/_up_/dist/dicty_engine/dicty_engine.exe)
            std::env::current_exe().ok().and_then(|p| {
                p.parent().map(|d| {
                    d.join("_up_")
                        .join("_up_")
                        .join("dist")
                        .join("dicty_engine")
                        .join("dicty_engine.exe")
                })
            }),
            // 4. In same directory as executable
            std::env::current_exe()
                .ok()
                .and_then(|p| p.parent().map(|d| d.join("dicty_engine.exe"))),
            // 5. Local build directory (e.g. dist/dicty_engine/dicty_engine.exe)
            Some(PathBuf::from("dist/dicty_engine/dicty_engine.exe")),
            Some(PathBuf::from("../dist/dicty_engine/dicty_engine.exe")),
            Some(PathBuf::from("../../dist/dicty_engine/dicty_engine.exe")),
            Some(PathBuf::from("dicty_engine/dicty_engine.exe")),
        ];

        for candidate in exe_candidates.into_iter().flatten() {
            if candidate.exists() {
                println!("[*] Launching embedded dicty_engine at {:?}", candidate);
                let working_dir = candidate.parent().unwrap_or(Path::new("."));
                let mut command = Command::new(&candidate);
                command
                    .current_dir(working_dir)
                    .creation_flags(CREATE_NO_WINDOW);
                configure_engine_command(&mut command);
                match command.spawn() {
                    Ok(child) => {
                        *proc_guard = Some(child);
                        return;
                    }
                    Err(err) => eprintln!(
                        "[!] Failed to spawn dicty_engine at {:?}: {}",
                        candidate, err
                    ),
                }
            }
        }

        emit_engine_error(
            app,
            "Could not start Dicty's local engine. Reinstall Dicty or restart the app.",
        );
    }

    #[cfg(not(target_os = "windows"))]
    {
        emit_engine_error(
            app,
            "Dicty's local engine is not available on this platform.",
        );
    }
}

pub fn stop_engine(state: &EngineState) {
    let mut proc_guard = state.process.lock().unwrap();
    if let Some(mut child) = proc_guard.take() {
        let _ = child.kill();
    }
    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        const CREATE_NO_WINDOW: u32 = 0x08000000;
        let _ = std::process::Command::new("taskkill")
            .args(["/F", "/IM", "dicty_engine.exe", "/T"])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
    }
}

#[tauri::command]
pub async fn ensure_engine(app: AppHandle) -> Result<(), String> {
    tauri::async_runtime::spawn_blocking(move || {
        let state = app.state::<EngineState>();
        ensure_engine_running(&app, &state);
    })
    .await
    .map_err(|error| format!("Failed to start Dicty's engine: {}", error))
}
