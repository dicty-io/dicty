use std::sync::atomic::AtomicBool;
#[cfg(target_os = "windows")]
use std::sync::atomic::Ordering;

static WAS_MEDIA_PAUSED_BY_DICTY: AtomicBool = AtomicBool::new(false);

#[cfg(target_os = "windows")]
mod win_media {
    use windows::Media::Control::{
        GlobalSystemMediaTransportControlsSessionManager,
        GlobalSystemMediaTransportControlsSessionPlaybackStatus,
    };
    use windows::Win32::UI::Input::KeyboardAndMouse::{
        SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP,
        VK_MEDIA_PLAY_PAUSE,
    };

    /// Sends a synthetic Win32 Media Play/Pause key event
    pub fn send_media_play_pause_key() {
        unsafe {
            let inputs = [
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VK_MEDIA_PLAY_PAUSE,
                            wScan: 0,
                            dwFlags: windows::Win32::UI::Input::KeyboardAndMouse::KEYBD_EVENT_FLAGS(0),
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
                INPUT {
                    r#type: INPUT_KEYBOARD,
                    Anonymous: INPUT_0 {
                        ki: KEYBDINPUT {
                            wVk: VK_MEDIA_PLAY_PAUSE,
                            wScan: 0,
                            dwFlags: KEYEVENTF_KEYUP,
                            time: 0,
                            dwExtraInfo: 0,
                        },
                    },
                },
            ];

            SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        }
    }

    /// Checks if any GSMTC media session (Spotify, Chrome, Edge, YouTube, etc.) is actively playing
    pub async fn is_any_media_playing() -> bool {
        let async_op = match GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
            Ok(op) => op,
            Err(_) => return false,
        };

        let manager = match async_op.get() {
            Ok(m) => m,
            Err(_) => return false,
        };

        // Check current active session
        if let Ok(session) = manager.GetCurrentSession() {
            if let Ok(info) = session.GetPlaybackInfo() {
                if let Ok(status) = info.PlaybackStatus() {
                    if status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing {
                        return true;
                    }
                }
            }
        }

        // Check all active media sessions
        if let Ok(sessions) = manager.GetSessions() {
            for session in sessions {
                if let Ok(info) = session.GetPlaybackInfo() {
                    if let Ok(status) = info.PlaybackStatus() {
                        if status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing {
                            return true;
                        }
                    }
                }
            }
        }

        false
    }

    /// Pauses any currently playing media sessions across Windows
    pub async fn pause_background_media() -> bool {
        let async_op = match GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
            Ok(op) => op,
            Err(e) => {
                eprintln!("[*] [MEDIA] GSMTC RequestAsync error: {:?}. Using fallback key.", e);
                send_media_play_pause_key();
                return true;
            }
        };

        let manager = match async_op.get() {
            Ok(m) => m,
            Err(e) => {
                eprintln!("[*] [MEDIA] GSMTC get manager error: {:?}. Using fallback key.", e);
                send_media_play_pause_key();
                return true;
            }
        };

        let mut paused_any = false;

        // Try pausing through sessions
        if let Ok(sessions) = manager.GetSessions() {
            for session in sessions {
                if let Ok(info) = session.GetPlaybackInfo() {
                    if let Ok(status) = info.PlaybackStatus() {
                        if status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing {
                            let source = session.SourceAppUserModelId().unwrap_or_default();
                            println!("[*] [MEDIA] Pausing active media playback in: {}", source);
                            if let Ok(pause_op) = session.TryPauseAsync() {
                                if let Ok(success) = pause_op.get() {
                                    if success {
                                        paused_any = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // If no session explicitly matched or current session was playing, try current session
        if !paused_any {
            if let Ok(current_session) = manager.GetCurrentSession() {
                if let Ok(info) = current_session.GetPlaybackInfo() {
                    if let Ok(status) = info.PlaybackStatus() {
                        if status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing {
                            let source = current_session.SourceAppUserModelId().unwrap_or_default();
                            println!("[*] [MEDIA] Pausing current media session: {}", source);
                            if let Ok(pause_op) = current_session.TryPauseAsync() {
                                if let Ok(success) = pause_op.get() {
                                    if success {
                                        paused_any = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fallback: If media seemed to be playing or if GSMTC didn't catch browser tabs,
        // send media play/pause key if requested
        if !paused_any {
            println!("[*] [MEDIA] No GSMTC playing session detected. Broadcasting fallback media pause.");
            send_media_play_pause_key();
            paused_any = true;
        }

        paused_any
    }

    /// Resumes previously paused media sessions
    pub async fn resume_background_media() {
        let async_op = match GlobalSystemMediaTransportControlsSessionManager::RequestAsync() {
            Ok(op) => op,
            Err(e) => {
                eprintln!("[*] [MEDIA] GSMTC RequestAsync error on resume: {:?}. Using fallback key.", e);
                send_media_play_pause_key();
                return;
            }
        };

        let manager = match async_op.get() {
            Ok(m) => m,
            Err(e) => {
                eprintln!("[*] [MEDIA] GSMTC get manager error on resume: {:?}. Using fallback key.", e);
                send_media_play_pause_key();
                return;
            }
        };

        let mut resumed_any = false;

        if let Ok(sessions) = manager.GetSessions() {
            for session in sessions {
                if let Ok(info) = session.GetPlaybackInfo() {
                    if let Ok(status) = info.PlaybackStatus() {
                        // Resume paused sessions that have controls
                        if status == GlobalSystemMediaTransportControlsSessionPlaybackStatus::Paused {
                            let source = session.SourceAppUserModelId().unwrap_or_default();
                            println!("[*] [MEDIA] Resuming media playback in: {}", source);
                            if let Ok(play_op) = session.TryPlayAsync() {
                                if let Ok(success) = play_op.get() {
                                    if success {
                                        resumed_any = true;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if !resumed_any {
            if let Ok(current_session) = manager.GetCurrentSession() {
                if let Ok(play_op) = current_session.TryPlayAsync() {
                    if let Ok(success) = play_op.get() {
                        if success {
                            resumed_any = true;
                        }
                    }
                }
            }
        }

        if !resumed_any {
            println!("[*] [MEDIA] Fallback: Broadcasting media play/pause key to resume playback.");
            send_media_play_pause_key();
        }
    }
}

/// Call when voice recording starts
pub async fn pause_media_if_playing() {
    #[cfg(target_os = "windows")]
    {
        // Check if audio is currently playing before pausing
        let is_playing = win_media::is_any_media_playing().await;
        println!("[*] [MEDIA] Detected active media playing: {}", is_playing);
        
        if is_playing {
            WAS_MEDIA_PAUSED_BY_DICTY.store(true, Ordering::SeqCst);
            win_media::pause_background_media().await;
        } else {
            WAS_MEDIA_PAUSED_BY_DICTY.store(false, Ordering::SeqCst);
        }
    }
}

/// Call when voice recording stops
pub async fn resume_media_if_needed() {
    #[cfg(target_os = "windows")]
    {
        if WAS_MEDIA_PAUSED_BY_DICTY.swap(false, Ordering::SeqCst) {
            println!("[*] [MEDIA] Resuming background media that was paused by Dicty...");
            win_media::resume_background_media().await;
        } else {
            println!("[*] [MEDIA] No media was paused by Dicty during this recording. Skipping resume.");
        }
    }
}
