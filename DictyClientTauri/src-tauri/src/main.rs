#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod engine;
mod engine_auth;
mod engine_http;
mod git;
mod hotkey;
mod media;
mod paste;
mod sound;
mod tray;

use engine::{ensure_engine_running, EngineState};
use tauri::Manager;

#[tauri::command]
fn open_models_folder() -> Result<(), String> {
    let user_profile = std::env::var("USERPROFILE")
        .or_else(|_| std::env::var("HOME"))
        .unwrap_or_else(|_| ".".to_string());
    let models_path = std::path::Path::new(&user_profile)
        .join(".dicty")
        .join("models");
    let _ = std::fs::create_dir_all(&models_path);
    let path_str = models_path.to_string_lossy().to_string();

    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("explorer")
            .arg(&path_str)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&path_str)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&path_str)
            .spawn()
            .map_err(|e| e.to_string())?;
    }

    Ok(())
}

#[tauri::command]
fn open_external_url(url: String) -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        std::process::Command::new("cmd")
            .args(["/c", "start", "", &url])
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "macos")]
    {
        std::process::Command::new("open")
            .arg(&url)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    #[cfg(target_os = "linux")]
    {
        std::process::Command::new("xdg-open")
            .arg(&url)
            .spawn()
            .map_err(|e| e.to_string())?;
    }
    Ok(())
}

#[tauri::command]
fn get_app_version(app: tauri::AppHandle) -> String {
    app.package_info().version.to_string()
}

#[tauri::command]
fn pick_app_executable() -> Result<Option<String>, String> {
    #[cfg(target_os = "windows")]
    {
        let script = r#"
        Add-Type -AssemblyName System.Windows.Forms
        $f = New-Object System.Windows.Forms.OpenFileDialog
        $f.Filter = "Executable files (*.exe)|*.exe|All files (*.*)|*.*"
        $f.Title = "Select Application Executable"
        if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            Write-Output $f.FileName
        }
        "#;
        let output = std::process::Command::new("powershell")
            .args(["-NoProfile", "-NonInteractive", "-Command", script])
            .output()
            .map_err(|e| e.to_string())?;
        if output.status.success() {
            let res = String::from_utf8_lossy(&output.stdout).trim().to_string();
            if !res.is_empty() {
                return Ok(Some(res));
            }
        }
        Ok(None)
    }
    #[cfg(not(target_os = "windows"))]
    {
        Ok(None)
    }
}

#[tauri::command]
fn engine_token(window: tauri::WebviewWindow) -> Result<String, String> {
    if !matches!(window.label(), "main" | "overlay" | "mode_switcher") {
        return Err("The engine token is not available to this window.".to_string());
    }
    if !engine_auth::is_trusted() {
        return Err(
            "Dicty's engine connection is not trusted. Restart Dicty to reconnect.".to_string(),
        );
    }
    engine_auth::reload_from_disk()
        .or_else(engine_auth::current_token)
        .ok_or_else(|| "Dicty's engine token is not available yet. Try again.".to_string())
}

fn extract_oauth_token(url: &str) -> Option<String> {
    let clean_url = url.trim().trim_matches('"').trim_matches('\'');
    if !clean_url.starts_with("dicty://") {
        return None;
    }
    if let Some(pos) = clean_url.find("token=") {
        let token_part = &clean_url[pos + 6..];
        let token = token_part.split('&').next().unwrap_or(token_part);
        let cleaned = token
            .trim()
            .trim_matches('"')
            .trim_matches('\'')
            .trim_end_matches('/');
        if !cleaned.is_empty() {
            return Some(cleaned.to_string());
        }
    }
    None
}

#[cfg(target_os = "windows")]
fn register_windows_protocol() {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x08000000;

    if let Ok(exe_path) = std::env::current_exe() {
        let exe_str = exe_path.to_string_lossy();
        let cmd = format!("\"{}\" \"%1\"", exe_str);

        let _ = std::process::Command::new("reg")
            .args([
                "add",
                "HKCU\\Software\\Classes\\dicty",
                "/ve",
                "/d",
                "URL:Dicty Protocol",
                "/f",
            ])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
        let _ = std::process::Command::new("reg")
            .args([
                "add",
                "HKCU\\Software\\Classes\\dicty",
                "/v",
                "URL Protocol",
                "/d",
                "",
                "/f",
            ])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
        let _ = std::process::Command::new("reg")
            .args([
                "add",
                "HKCU\\Software\\Classes\\dicty\\shell\\open\\command",
                "/ve",
                "/d",
                &cmd,
                "/f",
            ])
            .creation_flags(CREATE_NO_WINDOW)
            .status();
    }
}

fn main() {
    std::panic::set_hook(Box::new(|info| {
        let payload = if let Some(s) = info.payload().downcast_ref::<&str>() {
            s.to_string()
        } else if let Some(s) = info.payload().downcast_ref::<String>() {
            s.clone()
        } else {
            format!("{:?}", info.payload())
        };
        let location = info
            .location()
            .map(|l| format!("{}:{}:{}", l.file(), l.line(), l.column()))
            .unwrap_or_default();
        let msg = format!(
            "CRASH: {}\nLocation: {}\nFull: {:?}",
            payload, location, info
        );
        eprintln!("{}", msg);
        let _ = std::fs::write("dicty_crash.log", &msg);
    }));

    let engine_state = EngineState::default();

    tauri::Builder::default()
        .plugin(tauri_plugin_global_shortcut::Builder::new().build())
        .plugin(tauri_plugin_single_instance::init(|app, args, _cwd| {
            if let Some(main_window) = app.get_webview_window("main") {
                let _ = main_window.show();
                let _ = main_window.unminimize();
                let _ = main_window.set_focus();
            }

            use tauri::Emitter;
            for arg in &args {
                if let Some(token) = extract_oauth_token(arg) {
                    println!(
                        "[*] Received OAuth token via deep-link: {}...",
                        &token[..token.len().min(15)]
                    );
                    let _ = app.emit("oauth-token", token);
                    break;
                }
            }
        }))
        .manage(engine_state)
        .setup(|app| {
            let handle = app.handle();

            #[cfg(target_os = "windows")]
            register_windows_protocol();

            // Check if application was launched directly with a deep-link arg
            use tauri::Emitter;
            for arg in std::env::args() {
                if let Some(token) = extract_oauth_token(&arg) {
                    println!(
                        "[*] Application launched with deep-link token: {}...",
                        &token[..token.len().min(15)]
                    );
                    let app_handle = app.handle().clone();
                    tauri::async_runtime::spawn(async move {
                        tokio::time::sleep(tokio::time::Duration::from_millis(1000)).await;
                        let _ = app_handle.emit("oauth-token", token);
                    });
                    break;
                }
            }

            // 1. Initialize system tray
            if let Err(e) = tray::setup_tray(handle) {
                eprintln!("[!] Failed to setup tray icon: {}", e);
            }

            // 2. Initialize global keyboard shortcuts
            if let Err(e) = hotkey::setup_global_shortcuts(handle) {
                eprintln!("[!] Failed to setup global shortcuts: {}", e);
            }

            // 3. Ensure local Python backend engine is running
            engine_http::init(handle.clone());
            let state = app.state::<EngineState>();
            ensure_engine_running(handle, &state);

            // 4. Ensure main window is visible and intercept close request to hide to tray
            if let Some(main_window) = app.get_webview_window("main") {
                let _ = main_window.show();
                let _ = main_window.unminimize();
                let _ = main_window.set_focus();

                let main_window_clone = main_window.clone();
                main_window.on_window_event(move |event| {
                    if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                        api.prevent_close();
                        let _ = main_window_clone.hide();
                    }
                });
            }

            let handle_clone = handle.clone();
            tauri::async_runtime::spawn(async move {
                tokio::time::sleep(tokio::time::Duration::from_millis(1500)).await;
                if let Some(main_win) = handle_clone.get_webview_window("main") {
                    if let Ok(main_url) = main_win.url() {
                        for label in &["overlay", "mode_switcher"] {
                            if let Some(sub_win) = handle_clone.get_webview_window(label) {
                                if let Ok(sub_url) = sub_win.url() {
                                    let s = sub_url.as_str();
                                    if s.contains("chromewebdata") || s.contains("error") {
                                        let mut target = main_url.clone();
                                        target.set_query(Some(&format!("window={}", label)));
                                        let _ = sub_win.navigate(target);
                                    }
                                }
                            }
                        }
                    }
                }
            });

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            paste::simulate_paste,
            paste::copy_to_clipboard,
            paste::copy_and_paste,
            hotkey::toggle_dictation,
            hotkey::toggle_pause,
            hotkey::cancel_dictation,
            hotkey::set_overlay_mode,
            hotkey::start_drag_overlay,
            hotkey::move_overlay_by,
            hotkey::switch_mode,
            hotkey::toggle_mode_switcher,
            hotkey::show_mode_switcher,
            hotkey::hide_mode_switcher,
            hotkey::set_active_mode,
            hotkey::sync_profiles,
            hotkey::get_running_applications,
            hotkey::set_profile_model,
            hotkey::set_profile_format_style,
            hotkey::set_profile_custom_prompt,
            hotkey::set_profile_tags,
            hotkey::set_llm_config,
            hotkey::register_custom_hotkeys,
            hotkey::pause_global_shortcuts,
            hotkey::resume_global_shortcuts,
            sound::play_system_sound,
            sound::get_available_system_sounds,
            sound::save_sound_config,
            sound::load_sound_config,
            sound::play_dictation_sound,
            git::git_fetch_repositories,
            git::git_fetch_branches,
            git::git_fetch_context,
            git::check_github_hosts_status,
            git::repair_windows_hosts,
            git::git_test_connection,
            git::get_env_git_tokens,
            open_models_folder,
            engine::ensure_engine,
            engine_token,
            open_external_url,
            get_app_version,
            pick_app_executable,
            paste::get_foreground_app,
            paste::set_foreground_app_override,
            hotkey::set_recording_mode_override,
            hotkey::set_manual_override_active,
            hotkey::set_override_scope
        ])
        .build(tauri::generate_context!())
        .expect("failed to build app")
        .run(|app_handle, event| match event {
            tauri::RunEvent::ExitRequested { code, api, .. } => {
                if code.is_none() {
                    api.prevent_exit();
                }
            }
            tauri::RunEvent::Exit => {
                let state = app_handle.state::<engine::EngineState>();
                engine::stop_engine(&state);
            }
            _ => {}
        });
}
