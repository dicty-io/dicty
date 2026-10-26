use arboard::Clipboard;

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct TargetAppInfo {
    pub app_id: String,
    pub app_name: String,
    pub exe_path: String,
}

pub static CURRENT_TARGET_APP: std::sync::Mutex<Option<TargetAppInfo>> = std::sync::Mutex::new(None);

#[cfg(target_os = "windows")]
pub static TARGET_HWND: std::sync::atomic::AtomicIsize = std::sync::atomic::AtomicIsize::new(0);

pub fn capture_foreground_window() -> Option<TargetAppInfo> {
    #[cfg(target_os = "windows")]
    unsafe {
        let hwnd = windows::Win32::UI::WindowsAndMessaging::GetForegroundWindow();
        TARGET_HWND.store(hwnd.0 as isize, std::sync::atomic::Ordering::SeqCst);

        let mut app_info: Option<TargetAppInfo> = None;
        let mut pid = 0u32;
        windows::Win32::UI::WindowsAndMessaging::GetWindowThreadProcessId(hwnd, Some(&mut pid));

        if pid > 0 {
            if let Ok(hproc) = windows::Win32::System::Threading::OpenProcess(
                windows::Win32::System::Threading::PROCESS_QUERY_LIMITED_INFORMATION,
                false,
                pid,
            ) {
                let mut pbuf = vec![0u16; 512];
                let mut size = 512u32;
                if windows::Win32::System::Threading::QueryFullProcessImageNameW(
                    hproc,
                    windows::Win32::System::Threading::PROCESS_NAME_FORMAT(0),
                    windows::core::PWSTR(pbuf.as_mut_ptr()),
                    &mut size,
                )
                .is_ok()
                    && size > 0
                {
                    let full_path = String::from_utf16_lossy(&pbuf[..size as usize]);
                    let raw_exe = std::path::Path::new(&full_path)
                        .file_name()
                        .and_then(|f| f.to_str())
                        .unwrap_or("")
                        .to_string();
                    let app_id = raw_exe.to_lowercase();

                    let mut display_name = std::path::Path::new(&raw_exe)
                        .file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or(&raw_exe)
                        .to_string();
                    if let Some(c) = display_name.chars().next() {
                        display_name = format!("{}{}", c.to_uppercase(), &display_name[c.len_utf8()..]);
                    }

                    let len = windows::Win32::UI::WindowsAndMessaging::GetWindowTextLengthW(hwnd);
                    if len > 0 {
                        let mut wbuf = vec![0u16; (len + 1) as usize];
                        let rlen = windows::Win32::UI::WindowsAndMessaging::GetWindowTextW(hwnd, &mut wbuf);
                        if rlen > 0 {
                            let title = String::from_utf16_lossy(&wbuf[..rlen as usize]).trim().to_string();
                            if !title.is_empty() && title.contains(" - ") {
                                if let Some(suffix) = title.split(" - ").last() {
                                    let s = suffix.trim();
                                    if !s.is_empty() && s.len() < 30 {
                                        display_name = s.to_string();
                                    }
                                }
                            }
                        }
                    }

                    if !app_id.is_empty() && app_id != "dicty-client-tauri.exe" && app_id != "dicty_engine.exe" {
                        app_info = Some(TargetAppInfo {
                            app_id,
                            app_name: display_name,
                            exe_path: full_path,
                        });
                    }
                }
                let _ = windows::Win32::Foundation::CloseHandle(hproc);
            }
        }

        let mut guard = CURRENT_TARGET_APP.lock().unwrap();
        *guard = app_info.clone();
        app_info
    }
    #[cfg(not(target_os = "windows"))]
    {
        let guard = CURRENT_TARGET_APP.lock().unwrap();
        guard.clone()
    }
}

#[tauri::command]
pub fn get_foreground_app() -> Result<Option<TargetAppInfo>, String> {
    let guard = CURRENT_TARGET_APP.lock().unwrap();
    Ok(guard.clone())
}

#[tauri::command]
pub fn set_foreground_app_override(app_id: String, app_name: String) -> Result<(), String> {
    let mut guard = CURRENT_TARGET_APP.lock().unwrap();
    *guard = Some(TargetAppInfo {
        app_id: app_id.to_lowercase(),
        app_name,
        exe_path: String::new(),
    });
    Ok(())
}

pub fn restore_foreground_window() {
    #[cfg(target_os = "windows")]
    {
        let raw = TARGET_HWND.load(std::sync::atomic::Ordering::SeqCst);
        if raw != 0 {
            unsafe {
                let hwnd = windows::Win32::Foundation::HWND(raw as *mut std::ffi::c_void);
                let _ = windows::Win32::UI::WindowsAndMessaging::SetForegroundWindow(hwnd);
            }
        }
    }
}

/// Copies the given text to the OS clipboard with retries in case clipboard is locked by another process
#[tauri::command]
pub async fn copy_to_clipboard(text: String) -> Result<(), String> {
    for attempt in 0..5 {
        match Clipboard::new().and_then(|mut cb| cb.set_text(text.clone())) {
            Ok(_) => return Ok(()),
            Err(e) => {
                if attempt == 4 {
                    eprintln!("[!] [CLIPBOARD] Failed to write to clipboard after 5 attempts: {:?}", e);
                    return Err(format!("Failed to write to clipboard: {}", e));
                }
                tokio::time::sleep(tokio::time::Duration::from_millis(25)).await;
            }
        }
    }
    Ok(())
}

/// Copies the text to the OS clipboard and then simulates Ctrl+V paste into the active application
#[tauri::command]
pub async fn copy_and_paste(text: String) -> Result<(), String> {
    // 1. Put text into clipboard with retries
    copy_to_clipboard(text).await?;

    // 2. Perform synthetic keystroke paste into active window
    simulate_paste().await
}

/// Simulates synthetic keystrokes to paste text into the active target application.
/// On Windows, this translates to Win32 SendInput (Ctrl + V).
#[tauri::command]
pub async fn simulate_paste() -> Result<(), String> {
    #[cfg(target_os = "windows")]
    {
        use windows::Win32::UI::Input::KeyboardAndMouse::{
            SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
            VIRTUAL_KEY, VK_CONTROL,
        };

        restore_foreground_window();

        // Sleep briefly to let the target application regain key focus
        tokio::time::sleep(tokio::time::Duration::from_millis(150)).await;

        unsafe {
            let vk_v = VIRTUAL_KEY(0x56); // 'V' key

            let inputs = [
                // 1. Ctrl down
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VK_CONTROL,
                            wScan: 0,
                            dwFlags: windows::Win32::UI::Input::KeyboardAndMouse::KEYBD_EVENT_FLAGS(0),
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                // 2. V down
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: vk_v,
                            wScan: 0,
                            dwFlags: windows::Win32::UI::Input::KeyboardAndMouse::KEYBD_EVENT_FLAGS(0),
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                // 3. V up
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: vk_v,
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                // 4. Ctrl up
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VK_CONTROL,
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
            ];

            let sent = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
            if sent != 4 {
                return Err("Failed to post all keystrokes to target window".into());
            }
        }
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn test_clipboard_operations() {
        let test_str = "Dicty Clipboard Test String";
        let res = copy_to_clipboard(test_str.to_string()).await;
        println!("copy_to_clipboard result: {:?}", res);
        assert!(res.is_ok(), "Clipboard failed: {:?}", res);
    }
}
