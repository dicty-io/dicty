use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter, Listener, Manager};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut, ShortcutState};

use crate::engine_http;

use std::collections::HashMap;
use std::sync::Mutex;

pub static PROFILES: &[(&str, &str, &str, &str)] = &[
    (
        "prof_1",
        "General Dictation",
        "dictation",
        "punctuation_fast",
    ),
    ("prof_2", "Code & Architecture", "dictation", "custom"),
    ("prof_3", "Architecture Librarian", "librarian", "note"),
    ("prof_4", "Meeting Assistant", "meeting", "note"),
    (
        "prof_focused_meeting",
        "Focused App Meeting",
        "focused_meeting",
        "note",
    ),
    ("prof_5", "Book & Prose", "dictation", "book"),
];

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct ProfileSyncItem {
    pub id: String,
    pub name: String,
    pub mode_type: String,
    pub format_style: String,
    pub whisper_model: String,
    #[serde(default)]
    pub custom_prompt: Option<String>,
    #[serde(default)]
    pub tags: Vec<String>,
    #[serde(default)]
    pub target_apps: Vec<String>,
}

static REGISTERED_PROFILES: Mutex<Option<Vec<ProfileSyncItem>>> = Mutex::new(None);

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct RunningAppInfo {
    pub process_name: String,
    pub window_title: String,
    pub pid: u32,
}

pub static RECORDING_OVERRIDE_MODE: Mutex<Option<String>> = Mutex::new(None);
pub static MANUAL_OVERRIDE_ACTIVE: AtomicBool = AtomicBool::new(false);
pub static OVERRIDE_SCOPE: Mutex<String> = Mutex::new(String::new());

#[tauri::command]
pub fn set_recording_mode_override(mode_id: Option<String>) -> Result<(), String> {
    let mut guard = RECORDING_OVERRIDE_MODE.lock().unwrap();
    *guard = mode_id;
    Ok(())
}

#[tauri::command]
pub fn set_manual_override_active(active: bool) -> Result<(), String> {
    MANUAL_OVERRIDE_ACTIVE.store(active, Ordering::SeqCst);
    Ok(())
}

#[tauri::command]
pub fn set_override_scope(scope: String) -> Result<(), String> {
    let mut guard = OVERRIDE_SCOPE.lock().unwrap();
    *guard = scope;
    Ok(())
}

static PROFILE_MODELS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

pub fn get_profile_model(profile_id: &str) -> String {
    let mut guard = PROFILE_MODELS.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        m.insert("prof_1".to_string(), "base.en".to_string());
        m.insert("prof_2".to_string(), "base.en".to_string());
        m.insert("prof_3".to_string(), "small.en".to_string());
        m.insert("prof_4".to_string(), "large-v3-turbo".to_string());
        m.insert(
            "prof_focused_meeting".to_string(),
            "large-v3-turbo".to_string(),
        );
        m.insert("prof_5".to_string(), "small.en".to_string());
        *guard = Some(m);
    }
    guard
        .as_ref()
        .and_then(|m| m.get(profile_id).cloned())
        .unwrap_or_else(|| "base.en".to_string())
}

pub fn set_profile_model_internal(profile_id: String, model_id: String) {
    let mut guard = PROFILE_MODELS.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        m.insert("prof_1".to_string(), "base.en".to_string());
        m.insert("prof_2".to_string(), "base.en".to_string());
        m.insert("prof_3".to_string(), "small.en".to_string());
        m.insert("prof_4".to_string(), "large-v3-turbo".to_string());
        m.insert(
            "prof_focused_meeting".to_string(),
            "large-v3-turbo".to_string(),
        );
        m.insert("prof_5".to_string(), "small.en".to_string());
        *guard = Some(m);
    }
    if let Some(ref mut m) = *guard {
        m.insert(profile_id, model_id);
    }
}

static PROFILE_FORMAT_STYLES: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

pub fn get_profile_format_style(profile_id: &str) -> String {
    let mut guard = PROFILE_FORMAT_STYLES.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        for (id, _, _, style) in PROFILES {
            m.insert(id.to_string(), style.to_string());
        }
        *guard = Some(m);
    }
    guard
        .as_ref()
        .and_then(|m| m.get(profile_id).cloned())
        .unwrap_or_else(|| "raw".to_string())
}

pub fn set_profile_format_style_internal(profile_id: String, format_style: String) {
    let mut guard = PROFILE_FORMAT_STYLES.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        for (id, _, _, style) in PROFILES {
            m.insert(id.to_string(), style.to_string());
        }
        *guard = Some(m);
    }
    if let Some(ref mut m) = *guard {
        m.insert(profile_id, format_style);
    }
}

static PROFILE_CUSTOM_PROMPTS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

pub fn get_profile_custom_prompt(profile_id: &str) -> String {
    let mut guard = PROFILE_CUSTOM_PROMPTS.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        m.insert("prof_2".to_string(), "Format with clean developer syntax, preserving camelCase, snake_case, and markdown backticks.".to_string());
        *guard = Some(m);
    }
    guard
        .as_ref()
        .and_then(|m| m.get(profile_id).cloned())
        .unwrap_or_default()
}

pub fn set_profile_custom_prompt_internal(profile_id: String, prompt: String) {
    let mut guard = PROFILE_CUSTOM_PROMPTS.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        m.insert("prof_2".to_string(), "Format with clean developer syntax, preserving camelCase, snake_case, and markdown backticks.".to_string());
        *guard = Some(m);
    }
    if let Some(ref mut m) = *guard {
        m.insert(profile_id, prompt);
    }
}

static PROFILE_TAGS: Mutex<Option<HashMap<String, Vec<String>>>> = Mutex::new(None);

pub fn get_profile_tags(profile_id: &str) -> Vec<String> {
    let mut guard = PROFILE_TAGS.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        m.insert(
            "prof_1".to_string(),
            vec!["general".into(), "typing".into()],
        );
        m.insert(
            "prof_2".to_string(),
            vec!["dev".into(), "coding".into(), "syntax".into()],
        );
        m.insert(
            "prof_3".to_string(),
            vec!["architecture".into(), "adr".into(), "obsidian".into()],
        );
        m.insert(
            "prof_4".to_string(),
            vec!["meetings".into(), "summary".into()],
        );
        m.insert(
            "prof_focused_meeting".to_string(),
            vec!["meeting".into(), "app".into(), "focused".into()],
        );
        m.insert("prof_5".to_string(), vec!["writing".into(), "prose".into()]);
        *guard = Some(m);
    }
    guard
        .as_ref()
        .and_then(|m| m.get(profile_id).cloned())
        .unwrap_or_default()
}

pub fn set_profile_tags_internal(profile_id: String, tags: Vec<String>) {
    let mut guard = PROFILE_TAGS.lock().unwrap();
    if guard.is_none() {
        let mut m = HashMap::new();
        m.insert(
            "prof_1".to_string(),
            vec!["general".into(), "typing".into()],
        );
        m.insert(
            "prof_2".to_string(),
            vec!["dev".into(), "coding".into(), "syntax".into()],
        );
        m.insert(
            "prof_3".to_string(),
            vec!["architecture".into(), "adr".into(), "obsidian".into()],
        );
        m.insert(
            "prof_4".to_string(),
            vec!["meetings".into(), "summary".into()],
        );
        m.insert(
            "prof_focused_meeting".to_string(),
            vec!["meeting".into(), "app".into(), "focused".into()],
        );
        m.insert("prof_5".to_string(), vec!["writing".into(), "prose".into()]);
        *guard = Some(m);
    }
    if let Some(ref mut m) = *guard {
        m.insert(profile_id, tags);
    }
}

#[derive(Clone, Default)]
pub struct LlmConfig {
    pub provider: String,
    pub model: String,
    pub api_key: String,
    pub base_url: String,
}

static LLM_CONFIG: Mutex<Option<LlmConfig>> = Mutex::new(None);

pub fn get_llm_config() -> LlmConfig {
    let guard = LLM_CONFIG.lock().unwrap();
    guard.clone().unwrap_or_default()
}

pub fn set_llm_config_internal(provider: String, model: String, api_key: String, base_url: String) {
    let mut guard = LLM_CONFIG.lock().unwrap();
    *guard = Some(LlmConfig {
        provider,
        model,
        api_key,
        base_url,
    });
}

static CURRENT_PROFILE_INDEX: AtomicUsize = AtomicUsize::new(0);
static LAST_MODE_TRIGGER_MS: AtomicU64 = AtomicU64::new(0);

static IS_RECORDING_LOCAL: AtomicBool = AtomicBool::new(false);
static IS_PAUSED_LOCAL: AtomicBool = AtomicBool::new(false);
static IS_FLOW_BUSY: AtomicBool = AtomicBool::new(false);
static LAST_TRIGGER_MS: AtomicU64 = AtomicU64::new(0);
static LAST_PAUSE_TRIGGER_MS: AtomicU64 = AtomicU64::new(0);

struct BusyGuard;
impl Drop for BusyGuard {
    fn drop(&mut self) {
        IS_FLOW_BUSY.store(false, Ordering::SeqCst);
    }
}

/// Executes mode switching flow: cycles through active profiles, switches engine model, and notifies the UI
pub async fn switch_mode_flow(app: &AppHandle) {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let prev_ms = LAST_MODE_TRIGGER_MS.load(Ordering::SeqCst);
    if now_ms.saturating_sub(prev_ms) < 300 {
        println!("[*] [HOTKEY] Debounced rapid mode switch trigger (<300ms)");
        return;
    }
    LAST_MODE_TRIGGER_MS.store(now_ms, Ordering::SeqCst);

    let total_len = {
        let reg_guard = REGISTERED_PROFILES.lock().unwrap();
        reg_guard
            .as_ref()
            .map(|l| l.len())
            .unwrap_or(PROFILES.len())
    };
    if total_len == 0 {
        return;
    }
    let old_idx = CURRENT_PROFILE_INDEX.load(Ordering::SeqCst);
    let new_idx = (old_idx + 1) % total_len;
    CURRENT_PROFILE_INDEX.store(new_idx, Ordering::SeqCst);
    MANUAL_OVERRIDE_ACTIVE.store(true, Ordering::SeqCst);

    let (id, name, mode) = {
        let reg_guard = REGISTERED_PROFILES.lock().unwrap();
        if let Some(ref list) = *reg_guard {
            if let Some(p) = list.get(new_idx) {
                (p.id.clone(), p.name.clone(), p.mode_type.clone())
            } else {
                let p = &PROFILES[new_idx % PROFILES.len()];
                (p.0.to_string(), p.1.to_string(), p.2.to_string())
            }
        } else {
            let p = &PROFILES[new_idx % PROFILES.len()];
            (p.0.to_string(), p.1.to_string(), p.2.to_string())
        }
    };
    let format_style = get_profile_format_style(&id);
    let whisper_model = get_profile_model(&id);
    println!("\n╔═══════════════════════════════════════════════════════════════════════╗");
    println!(
        "║ 🔄  ACTIVE MODE SWITCHED: {:<43} ║",
        format!("{} ({})", name, id)
    );
    println!(
        "║     Mode: {:<15} Format Style: {:<25} ║",
        mode, format_style
    );
    println!("║     Assigned Model: {:<50} ║", whisper_model);
    println!("╚═══════════════════════════════════════════════════════════════════════╝\n");

    // Asynchronously switch active model on the Python engine
    let model_to_switch = whisper_model.clone();
    tauri::async_runtime::spawn(async move {
        let client = engine_http::client(Duration::from_secs(5));
        let switch_url = engine_http::url(&format!("/models/active/{}", model_to_switch));
        let _ = engine_http::send(client.post(&switch_url)).await;
    });

    // Play subtle audio cue for mode change
    crate::sound::play_mode_switch_sound();

    let payload = serde_json::json!({
        "profile_id": id,
        "profile_name": name,
        "mode": mode,
        "format_style": format_style,
        "whisper_model": whisper_model,
        "index": new_idx,
        "total": total_len
    });
    let _ = app.emit("dicty:mode-changed", payload);
}

/// Triggered when the user activates the Mode Switch shortcut (e.g. Alt + Shift + M):
/// Opens the floating Mode Switcher HUD window so user can navigate modes with Up/Down arrows or mouse.
/// If already open, advances selection to the next mode.
pub async fn trigger_mode_switch_shortcut(app: &AppHandle) {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let prev_ms = LAST_MODE_TRIGGER_MS.load(Ordering::SeqCst);
    if now_ms.saturating_sub(prev_ms) < 200 {
        println!("[*] [HOTKEY] Debounced rapid mode switch trigger (<200ms)");
        return;
    }
    LAST_MODE_TRIGGER_MS.store(now_ms, Ordering::SeqCst);

    if let Some(win) = app.get_webview_window("mode_switcher") {
        let is_vis = win.is_visible().unwrap_or(false);
        if is_vis {
            println!("[*] [HOTKEY] Mode switcher already visible: advancing selection");
            let _ = app.emit("dicty:mode-switcher-next", ());
        } else {
            println!("[*] [HOTKEY] Opening Mode switcher HUD window");
            let _ = win.center();
            let _ = win.show();
            let _ = win.set_always_on_top(true);
            let _ = win.set_focus();
            let _ = app.emit("dicty:mode-switcher-opened", ());
        }
    } else {
        println!("[*] [HOTKEY] mode_switcher window not found, falling back to direct cycle");
        switch_mode_flow(app).await;
    }
}

/// Executes the full native dictation flow:
/// 1. Toggles recording on the local FastAPI backend
/// 2. Remembers the active user foreground window (Notepad, Word, Browser, etc.)
/// 3. Pauses background music / media playback across Windows (GSMTC + Win32)
/// 4. Shows the floating HUD recording overlay window without stealing typing focus
/// 5. On stop: puts text into OS clipboard, restores target window focus, injects Ctrl+V,
///    resumes background media if Dicty paused it, and hides the overlay window
/// 6. Prints full terminal latency breakdown for debugging
pub async fn toggle_recording_flow(app: &AppHandle) {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let prev_ms = LAST_TRIGGER_MS.load(Ordering::SeqCst);
    if now_ms.saturating_sub(prev_ms) < 350 {
        println!("[*] [HOTKEY] Debounced rapid duplicate trigger (<350ms)");
        return;
    }
    LAST_TRIGGER_MS.store(now_ms, Ordering::SeqCst);

    if IS_FLOW_BUSY
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        println!("[*] [HOTKEY] Trigger dropped: dictation engine operation in progress");
        return;
    }
    let _guard = BusyGuard;

    // 1. Probe current engine state using a fast client (2.5s timeout)
    let fast_client = engine_http::client(Duration::from_millis(2500));

    let status_url = engine_http::url("/recording/status");
    let is_rec = match engine_http::send(fast_client.get(&status_url)).await {
        Ok(resp) => {
            if let Ok(json) = resp.json::<serde_json::Value>().await {
                json.get("is_recording")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false)
            } else {
                IS_RECORDING_LOCAL.load(Ordering::SeqCst)
            }
        }
        Err(e) => {
            if !IS_RECORDING_LOCAL.load(Ordering::SeqCst) {
                eprintln!(
                    "[!] [DICTATION TRIGGER] Cannot start recording: Backend engine offline: {}",
                    e
                );
                let _ = app.emit(
                    "dicty:backend-error",
                    serde_json::json!({
                        "error": "Dicty backend engine is offline or unreachable. Please make sure the Python engine is running."
                    }),
                );
                return;
            }
            IS_RECORDING_LOCAL.load(Ordering::SeqCst)
        }
    };

    let (profile_id, profile_name, active_mode) = {
        let reg_guard = REGISTERED_PROFILES.lock().unwrap();
        if let Some(ref list) = *reg_guard {
            if !list.is_empty() {
                let idx = CURRENT_PROFILE_INDEX.load(Ordering::SeqCst) % list.len();
                let item = &list[idx];
                (item.id.clone(), item.name.clone(), item.mode_type.clone())
            } else {
                let idx = CURRENT_PROFILE_INDEX.load(Ordering::SeqCst) % PROFILES.len();
                let (id, name, mode, _) = PROFILES[idx];
                (id.to_string(), name.to_string(), mode.to_string())
            }
        } else {
            let idx = CURRENT_PROFILE_INDEX.load(Ordering::SeqCst) % PROFILES.len();
            let (id, name, mode, _) = PROFILES[idx];
            (id.to_string(), name.to_string(), mode.to_string())
        }
    };
    let active_format_style = get_profile_format_style(&profile_id);
    let active_custom_prompt = get_profile_custom_prompt(&profile_id);
    let active_tags = get_profile_tags(&profile_id).join(",");

    if !is_rec {
        // --- START RECORDING ---
        let target_app = crate::paste::capture_foreground_window();

        // Auto-pause background music/media asynchronously in background so audio start is instantaneous.
        // Note: System audio modes (meeting, focused_meeting) must never pause media,
        // because they record active meetings (Zoom, Google Meet, browser, etc.)!
        let is_system_audio_mode = active_mode == "meeting" || active_mode == "focused_meeting";
        if !is_system_audio_mode {
            tauri::async_runtime::spawn(async {
                crate::media::pause_media_if_playing().await;
            });
        }

        let mut start_params = vec![format!("mode={}", active_mode)];
        if let Some(ref app_info) = target_app {
            start_params.push(format!("app_id={}", app_info.app_id));
        }
        if let Some(ref override_mode) = *RECORDING_OVERRIDE_MODE.lock().unwrap() {
            start_params.push(format!("mode_override={}", override_mode));
        }
        if MANUAL_OVERRIDE_ACTIVE.load(Ordering::SeqCst) {
            start_params.push("manual_override_active=true".to_string());
        }
        let start_url = engine_http::url(&format!("/recording/start?{}", start_params.join("&")));
        match engine_http::send(fast_client.post(&start_url)).await {
            Ok(resp) => {
                if resp.status().is_success() {
                    IS_RECORDING_LOCAL.store(true, Ordering::SeqCst);
                    IS_PAUSED_LOCAL.store(false, Ordering::SeqCst);
                    println!("\n[*] [DICTATION TRIGGER] >>> RECORDING STARTED (Target Window Captured, Mode: {} [{}]) <<<", profile_name, active_mode);

                    // Play native audio cue for recording start immediately
                    crate::sound::play_recording_sound(true);

                    let _ = app.emit(
                        "dicty:recording-state-changed",
                        serde_json::json!({
                            "is_recording": true,
                            "is_paused": false,
                            "mode": active_mode,
                            "profile_id": profile_id,
                            "profile_name": profile_name,
                            "app_id": target_app.as_ref().map(|a| a.app_id.clone()),
                            "app_name": target_app.as_ref().map(|a| a.app_name.clone()),
                        }),
                    );

                    // Show floating HUD recording overlay without stealing foreground typing focus
                    if let Some(overlay) = app.get_webview_window("overlay") {
                        if let Ok(url) = overlay.url() {
                            let url_str = url.as_str();
                            if url_str.contains("chromewebdata") || url_str.contains("error") {
                                if let Some(main_win) = app.get_webview_window("main") {
                                    if let Ok(main_url) = main_win.url() {
                                        let mut target = main_url.clone();
                                        target.set_query(Some("window=overlay"));
                                        let _ = overlay.navigate(target);
                                    }
                                }
                            }
                        }
                        let _ = overlay.show();
                        let _ = overlay.set_always_on_top(true);
                        crate::paste::restore_foreground_window();
                    }
                } else {
                    let status = resp.status();
                    let err_body = resp.text().await.unwrap_or_default();
                    let detail = serde_json::from_str::<serde_json::Value>(&err_body)
                        .ok()
                        .and_then(|v| {
                            v.get("detail")
                                .and_then(|d| d.as_str().map(|s| s.to_string()))
                        })
                        .unwrap_or_else(|| err_body);
                    eprintln!(
                        "[!] [DICTATION TRIGGER] Recording blocked (HTTP {}): {}",
                        status, detail
                    );
                    IS_RECORDING_LOCAL.store(false, Ordering::SeqCst);
                    crate::sound::play_recording_sound(false);
                    let _ = app.emit(
                        "dicty:backend-error",
                        serde_json::json!({
                            "error": detail
                        }),
                    );
                }
            }
            Err(e) => {
                eprintln!("[!] [DICTATION TRIGGER] Failed to reach backend: {:?}", e);
                IS_RECORDING_LOCAL.store(false, Ordering::SeqCst);
                let _ = app.emit(
                    "dicty:backend-error",
                    serde_json::json!({
                        "error": format!("Dicty engine connection failed: {}", e)
                    }),
                );
            }
        }
    } else {
        // --- STOP RECORDING & INFER ---
        // Immediately mark local state as stopped so subsequent triggers won't race
        IS_RECORDING_LOCAL.store(false, Ordering::SeqCst);
        IS_PAUSED_LOCAL.store(false, Ordering::SeqCst);

        // Play native audio cue for recording stop immediately
        crate::sound::play_recording_sound(false);

        let _ = app.emit(
            "dicty:recording-state-changed",
            serde_json::json!({
                "is_recording": false,
                "is_paused": false,
                "status": "processing",
                "mode": active_mode,
                "profile_id": profile_id
            }),
        );

        // Resume background media asynchronously in background if not in meeting mode
        let is_system_audio_mode = active_mode == "meeting" || active_mode == "focused_meeting";
        if !is_system_audio_mode {
            tauri::async_runtime::spawn(async {
                crate::media::resume_media_if_needed().await;
            });
        }

        println!("\n[*] [DICTATION TRIGGER] >>> RECORDING STOPPED. Processing transcription (Mode: {}, Style: {})... <<<", active_mode, active_format_style);
        let t_stop_0 = Instant::now();
        let stop_url = engine_http::url("/recording/stop");

        // Dedicated client with 60-second timeout for Whisper AI transcription inference
        let infer_client = engine_http::client(Duration::from_secs(60));

        let mut form_params = vec![
            ("mode".to_string(), active_mode.to_string()),
            (
                "dictation_format_style".to_string(),
                active_format_style.clone(),
            ),
        ];
        if !active_custom_prompt.is_empty() {
            form_params.push(("custom_prompt".to_string(), active_custom_prompt));
        }
        if !active_tags.is_empty() {
            form_params.push(("tags".to_string(), active_tags));
        }
        let llm_cfg = get_llm_config();
        if !llm_cfg.provider.is_empty() {
            form_params.push(("llm_provider".to_string(), llm_cfg.provider));
        }
        if !llm_cfg.model.is_empty() {
            form_params.push(("llm_model".to_string(), llm_cfg.model));
        }
        if !llm_cfg.api_key.is_empty() {
            form_params.push(("llm_api_key".to_string(), llm_cfg.api_key));
        }
        if !llm_cfg.base_url.is_empty() {
            form_params.push(("llm_base_url".to_string(), llm_cfg.base_url));
        }

        if let Some(ref app_info) = *crate::paste::CURRENT_TARGET_APP.lock().unwrap() {
            form_params.push(("app_id".to_string(), app_info.app_id.clone()));
            form_params.push(("target_app_name".to_string(), app_info.app_name.clone()));
            form_params.push(("target_app_bundle_id".to_string(), app_info.app_id.clone()));
        }
        if let Some(ref override_mode) = *RECORDING_OVERRIDE_MODE.lock().unwrap() {
            form_params.push(("mode_override".to_string(), override_mode.clone()));
        }
        if MANUAL_OVERRIDE_ACTIVE.load(Ordering::SeqCst) {
            form_params.push(("manual_override_active".to_string(), "true".to_string()));
        }

        let res = engine_http::send(infer_client.post(&stop_url).form(&form_params)).await;
        let t_backend_ms = t_stop_0.elapsed().as_millis();

        match res {
            Ok(resp) => {
                let status_code = resp.status();
                if !status_code.is_success() {
                    let err_body = resp
                        .text()
                        .await
                        .unwrap_or_else(|_| status_code.to_string());
                    eprintln!(
                        "[!] [DICTATION TRIGGER] Stop request failed with HTTP {}: {}",
                        status_code, err_body
                    );
                    let _ = app.emit(
                        "dicty:recording-state-changed",
                        serde_json::json!({
                            "is_recording": false,
                            "is_paused": false,
                            "text": "",
                            "error": format!("Backend error (HTTP {}): {}", status_code, err_body)
                        }),
                    );
                    if let Some(overlay) = app.get_webview_window("overlay") {
                        let _ = overlay.hide();
                    }
                    return;
                }

                if let Ok(json) = resp.json::<serde_json::Value>().await {
                    let text = json
                        .get("text")
                        .and_then(|t| t.as_str())
                        .unwrap_or("")
                        .to_string();
                    if !text.is_empty() {
                        let t_paste_0 = Instant::now();
                        let paste_res = crate::paste::copy_and_paste(text.clone()).await;
                        let t_paste_ms = t_paste_0.elapsed().as_millis();
                        let t_total_ms = t_stop_0.elapsed().as_millis();

                        if let Err(ref pe) = paste_res {
                            eprintln!("[!] [DICTATION TRIGGER] Paste error: {}", pe);
                        }

                        println!("╔═══════════════════════════════════════════════════════════════════════╗");
                        println!("║ ⏱️   CLIENT PASTE LATENCY BREAKDOWN                                    ║");
                        println!("╠═══════════════════════════════════════════════════════════════════════╣");
                        println!("║  Engine STT + Network Latency:    {:>6} ms                         ║", t_backend_ms);
                        println!("║  Clipboard Write & Win32 Paste:   {:>6} ms                         ║", t_paste_ms);
                        println!("║  Total Client End-to-End Latency: {:>6} ms                         ║", t_total_ms);
                        println!("╠═══════════════════════════════════════════════════════════════════════╣");
                        let preview = if text.chars().count() > 50 {
                            format!("{}...", text.chars().take(47).collect::<String>())
                        } else {
                            text.clone()
                        };
                        println!("║  Pasted: {:<58} ║", preview);
                        println!("╚═══════════════════════════════════════════════════════════════════════╝\n");

                        let _ = app.emit(
                            "dicty:recording-state-changed",
                            serde_json::json!({
                                "is_recording": false,
                                "is_paused": false,
                                "text": text,
                                "timings": {
                                    "backend_ms": t_backend_ms,
                                    "paste_ms": t_paste_ms,
                                    "client_total_ms": t_total_ms
                                }
                            }),
                        );

                        if let Some(res_mode) = json.get("resolved_mode").and_then(|v| v.as_str()) {
                            let reason = json.get("mode_reason").and_then(|v| v.as_str()).unwrap_or("default");
                            let _ = app.emit(
                                "dicty:resolved-mode-changed",
                                serde_json::json!({
                                    "resolved_mode": res_mode,
                                    "mode_reason": reason
                                }),
                            );
                        }
                        if let Some(sug) = json.get("suggestion") {
                            let _ = app.emit("dicty:app-rule-suggestion", sug.clone());
                        }

                        *RECORDING_OVERRIDE_MODE.lock().unwrap() = None;
                        let scope = OVERRIDE_SCOPE.lock().unwrap().clone();
                        if scope.is_empty() || scope == "recording" {
                            MANUAL_OVERRIDE_ACTIVE.store(false, Ordering::SeqCst);
                        }
                    } else {
                        let msg = json
                            .get("message")
                            .and_then(|m| m.as_str())
                            .unwrap_or("Empty or ignored audio");
                        println!("[*] [DICTATION TRIGGER] Finished with no text: {}", msg);
                        let _ = app.emit(
                            "dicty:recording-state-changed",
                            serde_json::json!({
                                "is_recording": false,
                                "is_paused": false,
                                "text": "",
                                "message": msg
                            }),
                        );
                    }
                } else {
                    eprintln!("[!] [DICTATION TRIGGER] Failed to parse JSON response from /recording/stop");
                    let _ = app.emit(
                        "dicty:recording-state-changed",
                        serde_json::json!({
                            "is_recording": false,
                            "is_paused": false,
                            "text": "",
                            "error": "Failed to parse JSON response from backend engine"
                        }),
                    );
                }

                // Hide floating HUD recording overlay once transcription & paste are done
                if let Some(overlay) = app.get_webview_window("overlay") {
                    let _ = overlay.hide();
                }
            }
            Err(e) => {
                eprintln!("[!] [DICTATION TRIGGER] Stop request failed: {:?}", e);
                let _ = app.emit(
                    "dicty:recording-state-changed",
                    serde_json::json!({
                        "is_recording": false,
                        "is_paused": false,
                        "text": "",
                        "error": e.to_string()
                    }),
                );
                if let Some(overlay) = app.get_webview_window("overlay") {
                    let _ = overlay.hide();
                }
            }
        }
    }
}

/// Executes native toggle pause/resume flow:
pub async fn toggle_pause_flow(app: &AppHandle) {
    let now_ms = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis() as u64;
    let prev_ms = LAST_PAUSE_TRIGGER_MS.load(Ordering::SeqCst);
    if now_ms.saturating_sub(prev_ms) < 300 {
        println!("[*] [PAUSE TRIGGER] Debounced rapid duplicate trigger (<300ms)");
        return;
    }
    LAST_PAUSE_TRIGGER_MS.store(now_ms, Ordering::SeqCst);

    let client = engine_http::client(Duration::from_secs(5));

    let toggle_url = engine_http::url("/recording/toggle_pause");
    match engine_http::send(client.post(&toggle_url)).await {
        Ok(resp) => {
            if let Ok(json) = resp.json::<serde_json::Value>().await {
                let is_rec = json
                    .get("is_recording")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);
                let is_paused = json
                    .get("is_paused")
                    .and_then(|v| v.as_bool())
                    .unwrap_or(false);

                if !is_rec {
                    println!("[*] [PAUSE TRIGGER] Ignored - Dicty is not currently recording.");
                    return;
                }

                IS_RECORDING_LOCAL.store(true, Ordering::SeqCst);
                IS_PAUSED_LOCAL.store(is_paused, Ordering::SeqCst);

                println!(
                    "\n[*] [DICTATION TRIGGER] >>> RECORDING {} <<<",
                    if is_paused { "PAUSED" } else { "RESUMED" }
                );

                let _ = app.emit(
                    "dicty:recording-state-changed",
                    serde_json::json!({
                        "is_recording": true,
                        "is_paused": is_paused
                    }),
                );
            }
        }
        Err(e) => {
            eprintln!("[!] [PAUSE TRIGGER] Failed to reach backend: {:?}", e);
        }
    }
}

/// Executes native cancel recording flow:
pub async fn cancel_recording_flow(app: &AppHandle) {
    IS_RECORDING_LOCAL.store(false, Ordering::SeqCst);
    IS_PAUSED_LOCAL.store(false, Ordering::SeqCst);

    let client = engine_http::client(Duration::from_secs(5));

    let cancel_url = engine_http::url("/recording/cancel");
    let _ = engine_http::send(client.post(&cancel_url)).await;

    // Resume background media if Dicty paused it
    crate::media::resume_media_if_needed().await;

    // Hide overlay
    if let Some(overlay) = app.get_webview_window("overlay") {
        let _ = overlay.hide();
    }

    println!("\n[*] [DICTATION TRIGGER] >>> RECORDING CANCELLED <<<");
    let _ = app.emit(
        "dicty:recording-state-changed",
        serde_json::json!({
            "is_recording": false,
            "is_paused": false,
            "status": "cancelled"
        }),
    );
}

/// Tauri command to trigger toggle record from frontend or scripts
#[tauri::command]
pub async fn toggle_dictation(app: AppHandle) -> Result<(), String> {
    toggle_recording_flow(&app).await;
    Ok(())
}

/// Tauri command to trigger pause/resume from frontend or scripts
#[tauri::command]
pub async fn toggle_pause(app: AppHandle) -> Result<(), String> {
    toggle_pause_flow(&app).await;
    Ok(())
}

/// Tauri command to cancel recording without pasting
#[tauri::command]
pub async fn cancel_dictation(app: AppHandle) -> Result<(), String> {
    cancel_recording_flow(&app).await;
    Ok(())
}

/// Tauri command to resize the overlay window between mini pill and expanded modes
#[tauri::command]
pub async fn set_overlay_mode(app: AppHandle, mini: bool) -> Result<(), String> {
    if let Some(overlay) = app.get_webview_window("overlay") {
        if mini {
            let _ = overlay.set_size(tauri::LogicalSize::new(180.0, 48.0));
        } else {
            let _ = overlay.set_size(tauri::LogicalSize::new(430.0, 136.0));
        }
    }
    Ok(())
}

/// Tauri command to shift overlay window position by (dx, dy) pixels
#[tauri::command]
pub fn move_overlay_by(app: AppHandle, dx: i32, dy: i32) -> Result<(), String> {
    if let Some(overlay) = app.get_webview_window("overlay") {
        if let Ok(pos) = overlay.outer_position() {
            let _ = overlay.set_position(tauri::PhysicalPosition::new(pos.x + dx, pos.y + dy));
        }
    }
    Ok(())
}

/// Tauri command to initiate native OS window dragging on Windows
#[tauri::command]
pub fn start_drag_overlay(app: AppHandle) -> Result<(), String> {
    if let Some(overlay) = app.get_webview_window("overlay") {
        let _ = overlay.start_dragging();
    }
    Ok(())
}

static LISTENERS_INITIALIZED: AtomicBool = AtomicBool::new(false);

/// Registers default global hotkeys for dictation recording and pause
pub fn setup_global_shortcuts(app: &AppHandle) -> Result<(), Box<dyn std::error::Error>> {
    // 1. Internal event listeners (from tray menu, frontend, etc.) - only initialize once
    if !LISTENERS_INITIALIZED.swap(true, Ordering::SeqCst) {
        let app_handle_for_rec = app.clone();
        app.listen("dicty:toggle-recording", move |_| {
            let h = app_handle_for_rec.clone();
            tauri::async_runtime::spawn(async move {
                toggle_recording_flow(&h).await;
            });
        });

        let app_handle_for_pause = app.clone();
        app.listen("dicty:toggle-pause", move |_| {
            let h = app_handle_for_pause.clone();
            tauri::async_runtime::spawn(async move {
                toggle_pause_flow(&h).await;
            });
        });

        let app_handle_for_cancel = app.clone();
        app.listen("dicty:cancel-recording", move |_| {
            let h = app_handle_for_cancel.clone();
            tauri::async_runtime::spawn(async move {
                cancel_recording_flow(&h).await;
            });
        });

        let app_handle_for_mode = app.clone();
        app.listen("dicty:switch-mode", move |_| {
            let h = app_handle_for_mode.clone();
            tauri::async_runtime::spawn(async move {
                trigger_mode_switch_shortcut(&h).await;
            });
        });
    }

    // 2. Global hotkeys for Record Toggle (Start / Stop)
    let record_shortcuts = ["ctrl+space", "f8", "ctrl+shift+space", "alt+shift+space"];
    for s in &record_shortcuts {
        if let Ok(shortcut) = s.parse::<Shortcut>() {
            let _ = app.global_shortcut().unregister(shortcut);
            let app_handle = app.clone();
            let name = s.to_string();
            match app
                .global_shortcut()
                .on_shortcut(shortcut, move |_app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        println!("[*] Global shortcut triggered (Record): '{}'", name);
                        let h = app_handle.clone();
                        tauri::async_runtime::spawn(async move {
                            toggle_recording_flow(&h).await;
                        });
                    }
                }) {
                Ok(_) => println!("[+] Successfully registered record shortcut: {}", s),
                Err(e) => eprintln!("[-] Record shortcut '{}' error: {:?}", s, e),
            }
        }
    }

    // 3. Global hotkeys for Pause Toggle (Pause / Resume)
    let pause_shortcuts = [
        "alt+p",
        "ctrl+shift+p",
        "f7",
        "ctrl+alt+p",
        "pause",
        "shift+f7",
        "ctrl+f7",
    ];
    for s in &pause_shortcuts {
        if let Ok(shortcut) = s.parse::<Shortcut>() {
            let _ = app.global_shortcut().unregister(shortcut);
            let app_handle = app.clone();
            let name = s.to_string();
            match app
                .global_shortcut()
                .on_shortcut(shortcut, move |_app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        println!("[*] Global shortcut triggered (Pause): '{}'", name);
                        let h = app_handle.clone();
                        tauri::async_runtime::spawn(async move {
                            toggle_pause_flow(&h).await;
                        });
                    }
                }) {
                Ok(_) => println!("[+] Successfully registered pause shortcut: {}", s),
                Err(e) => eprintln!("[-] Pause shortcut '{}' error: {:?}", s, e),
            }
        }
    }

    // 4. Global hotkeys for Mode Switch (Cycle active profile)
    let mode_shortcuts = ["alt+shift+m", "ctrl+shift+m", "ctrl+alt+m"];
    for s in &mode_shortcuts {
        if let Ok(shortcut) = s.parse::<Shortcut>() {
            let _ = app.global_shortcut().unregister(shortcut);
            let app_handle = app.clone();
            let name = s.to_string();
            match app
                .global_shortcut()
                .on_shortcut(shortcut, move |_app, _shortcut, event| {
                    if event.state() == ShortcutState::Pressed {
                        println!("[*] Global shortcut triggered (Switch Mode): '{}'", name);
                        let h = app_handle.clone();
                        tauri::async_runtime::spawn(async move {
                            trigger_mode_switch_shortcut(&h).await;
                        });
                    }
                }) {
                Ok(_) => println!("[+] Successfully registered mode switch shortcut: {}", s),
                Err(e) => eprintln!("[-] Mode switch shortcut '{}' error: {:?}", s, e),
            }
        }
    }

    Ok(())
}

/// Tauri command to cycle to the next active mode
#[tauri::command]
pub async fn switch_mode(app: AppHandle) -> Result<serde_json::Value, String> {
    trigger_mode_switch_shortcut(&app).await;
    get_active_mode()
}

/// Tauri command to toggle the floating mode switcher HUD window
#[tauri::command]
pub fn toggle_mode_switcher(app: AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("mode_switcher") {
        let is_vis = win.is_visible().unwrap_or(false);
        if is_vis {
            let _ = win.hide();
            let _ = app.emit("dicty:mode-switcher-closed", ());
        } else {
            let _ = win.center();
            let _ = win.show();
            let _ = win.set_always_on_top(true);
            let _ = win.set_focus();
            let _ = app.emit("dicty:mode-switcher-opened", ());
        }
        Ok(())
    } else {
        Err("mode_switcher window not found".to_string())
    }
}

/// Tauri command to show the floating mode switcher HUD window
#[tauri::command]
pub fn show_mode_switcher(app: AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("mode_switcher") {
        let _ = win.center();
        let _ = win.show();
        let _ = win.set_always_on_top(true);
        let _ = win.set_focus();
        let _ = app.emit("dicty:mode-switcher-opened", ());
        Ok(())
    } else {
        Err("mode_switcher window not found".to_string())
    }
}

/// Tauri command to hide the floating mode switcher HUD window
#[tauri::command]
pub fn hide_mode_switcher(app: AppHandle) -> Result<(), String> {
    if let Some(win) = app.get_webview_window("mode_switcher") {
        let _ = win.hide();
        let _ = app.emit("dicty:mode-switcher-closed", ());
        Ok(())
    } else {
        Err("mode_switcher window not found".to_string())
    }
}

/// Tauri command to sync all active profiles from frontend
#[tauri::command]
pub fn sync_profiles(profiles: Vec<ProfileSyncItem>) -> Result<(), String> {
    for p in &profiles {
        if !p.whisper_model.is_empty() {
            set_profile_model_internal(p.id.clone(), p.whisper_model.clone());
        }
        if !p.format_style.is_empty() {
            set_profile_format_style_internal(p.id.clone(), p.format_style.clone());
        }
        if let Some(ref prompt) = p.custom_prompt {
            set_profile_custom_prompt_internal(p.id.clone(), prompt.clone());
        }
        set_profile_tags_internal(p.id.clone(), p.tags.clone());
    }
    let mut guard = REGISTERED_PROFILES.lock().unwrap();
    *guard = Some(profiles);
    Ok(())
}

/// Tauri command to enumerate running applications on Windows
#[tauri::command]
pub fn get_running_applications() -> Result<Vec<RunningAppInfo>, String> {
    #[cfg(windows)]
    {
        use windows::Win32::Foundation::{BOOL, HWND, LPARAM};
        use windows::Win32::UI::WindowsAndMessaging::{
            EnumWindows, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId,
            IsWindowVisible,
        };

        extern "system" {
            fn OpenInputDesktop(dwflags: u32, finherit: BOOL, dwdesiredaccess: u32) -> HWND;
            fn EnumDesktopWindows(
                hdesktop: HWND,
                lpenumfunc: Option<unsafe extern "system" fn(HWND, LPARAM) -> BOOL>,
                lparam: LPARAM,
            ) -> BOOL;
            fn CloseDesktop(hdesktop: HWND) -> BOOL;
        }

        struct EnumContext {
            apps: Vec<RunningAppInfo>,
            seen_processes: std::collections::HashSet<String>,
        }

        unsafe extern "system" fn enum_window_callback(hwnd: HWND, lparam: LPARAM) -> BOOL {
            let ctx = &mut *(lparam.0 as *mut EnumContext);
            if IsWindowVisible(hwnd).as_bool() {
                let length = GetWindowTextLengthW(hwnd);
                if length > 0 {
                    let mut buf = vec![0u16; (length + 1) as usize];
                    let read_len = GetWindowTextW(hwnd, &mut buf);
                    if read_len > 0 {
                        let title = String::from_utf16_lossy(&buf[..read_len as usize])
                            .trim()
                            .to_string();
                        let title_lower = title.to_lowercase();
                        let is_dicty_window = title == "Dicty"
                            || title == "Dicty Recording Overlay"
                            || title == "Dicty Mode Switcher"
                            || title_lower.contains("com.dicty.desktop");

                        if !title.is_empty()
                            && title != "Program Manager"
                            && title != "Settings"
                            && title != "Windows Input Experience"
                            && !is_dicty_window
                        {
                            let mut pid = 0u32;
                            GetWindowThreadProcessId(hwnd, Some(&mut pid));

                            let mut proc_name = String::new();
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
                                    ).is_ok() && size > 0 {
                                        let full_path = String::from_utf16_lossy(&pbuf[..size as usize]);
                                        proc_name = std::path::Path::new(&full_path)
                                            .file_name()
                                            .and_then(|f| f.to_str())
                                            .unwrap_or("")
                                            .to_lowercase();
                                    }
                                    let _ = windows::Win32::Foundation::CloseHandle(hproc);
                                }
                            }

                            // Exclude Dicty itself and UWP wrapper host if child app is already captured
                            let is_dicty_proc = proc_name == "dicty-client-tauri.exe"
                                || proc_name == "dicty_engine.exe";
                            let is_wrapper = proc_name == "applicationframehost.exe";

                            if !proc_name.is_empty()
                                && !is_dicty_proc
                                && !is_wrapper
                                && !ctx.seen_processes.contains(&proc_name)
                            {
                                ctx.seen_processes.insert(proc_name.clone());
                                ctx.apps.push(RunningAppInfo {
                                    process_name: proc_name,
                                    window_title: title,
                                    pid,
                                });
                            }
                        }
                    }
                }
            }
            BOOL(1)
        }

        let mut ctx = EnumContext {
            apps: Vec::new(),
            seen_processes: std::collections::HashSet::new(),
        };

        unsafe {
            // DESKTOP_READOBJECTS = 0x0001
            let desk = OpenInputDesktop(0, BOOL(0), 0x0001);
            if !desk.is_invalid() {
                let _ = EnumDesktopWindows(
                    desk,
                    Some(enum_window_callback),
                    LPARAM(&mut ctx as *mut _ as isize),
                );
                let _ = CloseDesktop(desk);
            }
            if ctx.apps.is_empty() {
                let _ = EnumWindows(
                    Some(enum_window_callback),
                    LPARAM(&mut ctx as *mut _ as isize),
                );
            }
        }

        Ok(ctx.apps)
    }
    #[cfg(not(windows))]
    {
        Ok(Vec::new())
    }
}

/// Tauri command to set the active mode by profile id
#[tauri::command]
pub fn set_active_mode(app: AppHandle, profile_id: String) -> Result<serde_json::Value, String> {
    // 1. Try to find in registered profiles first
    let reg_guard = REGISTERED_PROFILES.lock().unwrap();
    let reg_found = reg_guard.as_ref().and_then(|list| {
        list.iter()
            .enumerate()
            .find(|(_, p)| p.id == profile_id)
            .map(|(i, p)| (i, p.clone(), list.len()))
    });
    drop(reg_guard);

    if let Some((idx, item, total)) = reg_found {
        CURRENT_PROFILE_INDEX.store(idx, Ordering::SeqCst);
        let format_style = get_profile_format_style(&item.id);
        let whisper_model = get_profile_model(&item.id);

        let model_to_switch = whisper_model.clone();
        tauri::async_runtime::spawn(async move {
            let client = engine_http::client(Duration::from_secs(5));
            let switch_url = engine_http::url(&format!("/models/active/{}", model_to_switch));
            let _ = engine_http::send(client.post(&switch_url)).await;
        });

        let payload = serde_json::json!({
            "profile_id": item.id,
            "profile_name": item.name,
            "mode": item.mode_type,
            "format_style": format_style,
            "whisper_model": whisper_model,
            "index": idx,
            "total": total
        });
        let _ = app.emit("dicty:mode-changed", payload.clone());
        println!("[*] [MODE SWITCHER] Active mode set via command: {} ({}) with model '{}' and style '{}'", item.name, item.id, whisper_model, format_style);
        return Ok(payload);
    }

    // 2. Fallback to static PROFILES
    if let Some(idx) = PROFILES.iter().position(|(id, ..)| *id == profile_id) {
        CURRENT_PROFILE_INDEX.store(idx, Ordering::SeqCst);
        let (id, name, mode, _) = PROFILES[idx];
        let format_style = get_profile_format_style(id);
        let whisper_model = get_profile_model(id);

        let model_to_switch = whisper_model.clone();
        tauri::async_runtime::spawn(async move {
            let client = engine_http::client(Duration::from_secs(5));
            let switch_url = engine_http::url(&format!("/models/active/{}", model_to_switch));
            let _ = engine_http::send(client.post(&switch_url)).await;
        });

        let payload = serde_json::json!({
            "profile_id": id,
            "profile_name": name,
            "mode": mode,
            "format_style": format_style,
            "whisper_model": whisper_model,
            "index": idx,
            "total": PROFILES.len()
        });
        let _ = app.emit("dicty:mode-changed", payload.clone());
        println!("[*] [MODE SWITCHER] Active mode set via command: {} ({}) with model '{}' and style '{}'", name, id, whisper_model, format_style);
        return Ok(payload);
    }
    Err(format!("Unknown profile_id: {}", profile_id))
}

/// Tauri command to get the current active mode
#[tauri::command]
pub fn get_active_mode() -> Result<serde_json::Value, String> {
    let reg_guard = REGISTERED_PROFILES.lock().unwrap();
    if let Some(ref list) = *reg_guard {
        if !list.is_empty() {
            let idx = CURRENT_PROFILE_INDEX.load(Ordering::SeqCst) % list.len();
            let item = &list[idx];
            let format_style = get_profile_format_style(&item.id);
            let whisper_model = get_profile_model(&item.id);
            return Ok(serde_json::json!({
                "profile_id": item.id,
                "profile_name": item.name,
                "mode": item.mode_type,
                "format_style": format_style,
                "whisper_model": whisper_model,
                "index": idx,
                "total": list.len()
            }));
        }
    }
    let idx = CURRENT_PROFILE_INDEX.load(Ordering::SeqCst) % PROFILES.len();
    let (id, name, mode, _) = PROFILES[idx];
    let format_style = get_profile_format_style(id);
    let whisper_model = get_profile_model(id);
    Ok(serde_json::json!({
        "profile_id": id,
        "profile_name": name,
        "mode": mode,
        "format_style": format_style,
        "whisper_model": whisper_model,
        "index": idx,
        "total": PROFILES.len()
    }))
}

/// Tauri command to dynamically update a profile's assigned voice model
#[tauri::command]
pub fn set_profile_model(profile_id: String, model_id: String) -> Result<(), String> {
    println!(
        "[*] [MODE PROFILE] Updated profile '{}' to model '{}'",
        profile_id, model_id
    );
    set_profile_model_internal(profile_id, model_id);
    Ok(())
}

/// Tauri command to dynamically update a profile's formatting style
#[tauri::command]
pub fn set_profile_format_style(profile_id: String, format_style: String) -> Result<(), String> {
    println!(
        "[*] [MODE PROFILE] Updated profile '{}' to format style '{}'",
        profile_id, format_style
    );
    set_profile_format_style_internal(profile_id, format_style);
    Ok(())
}

/// Tauri command to dynamically update a profile's custom instruction prompt
#[tauri::command]
pub fn set_profile_custom_prompt(profile_id: String, custom_prompt: String) -> Result<(), String> {
    println!(
        "[*] [MODE PROFILE] Updated profile '{}' custom prompt",
        profile_id
    );
    set_profile_custom_prompt_internal(profile_id, custom_prompt);
    Ok(())
}

/// Tauri command to dynamically update a profile's associated tags
#[tauri::command]
pub fn set_profile_tags(profile_id: String, tags: Vec<String>) -> Result<(), String> {
    println!(
        "[*] [MODE PROFILE] Updated profile '{}' tags: {:?}",
        profile_id, tags
    );
    set_profile_tags_internal(profile_id, tags);
    Ok(())
}

/// Tauri command to dynamically update active LLM configuration
#[tauri::command]
pub fn set_llm_config(
    provider: String,
    model: String,
    api_key: String,
    base_url: String,
) -> Result<(), String> {
    println!(
        "[*] [LLM CONFIG] Updated LLM provider '{}' model '{}'",
        provider, model
    );
    set_llm_config_internal(provider, model, api_key, base_url);
    Ok(())
}

static LAST_CUSTOM_TOGGLE_PRESS_MS: AtomicU64 = AtomicU64::new(0);
static LAST_CUSTOM_PAUSE_PRESS_MS: AtomicU64 = AtomicU64::new(0);
static LAST_CUSTOM_MODE_PRESS_MS: AtomicU64 = AtomicU64::new(0);

static REQUIRE_DOUBLE_TAP_TOGGLE: AtomicBool = AtomicBool::new(false);
static REQUIRE_DOUBLE_TAP_PAUSE: AtomicBool = AtomicBool::new(false);
static REQUIRE_DOUBLE_TAP_MODE: AtomicBool = AtomicBool::new(false);

static REGISTERED_CUSTOM_SHORTCUTS: std::sync::Mutex<Vec<Shortcut>> =
    std::sync::Mutex::new(Vec::new());

/// Tauri command to dynamically register custom user-configured hotkeys
#[tauri::command]
pub async fn register_custom_hotkeys(
    app: AppHandle,
    toggle_key: Option<String>,
    pause_key: Option<String>,
    mode_key: Option<String>,
    double_tap_toggle: Option<bool>,
    double_tap_pause: Option<bool>,
    double_tap_mode: Option<bool>,
) -> Result<(), String> {
    // Unregister any previously registered custom shortcuts first
    let gs = app.global_shortcut();
    if let Ok(mut old_list) = REGISTERED_CUSTOM_SHORTCUTS.lock() {
        for s in old_list.drain(..) {
            let _ = gs.unregister(s);
        }
    }
    if let Some(dt) = double_tap_toggle {
        REQUIRE_DOUBLE_TAP_TOGGLE.store(dt, Ordering::SeqCst);
    }
    if let Some(dt) = double_tap_pause {
        REQUIRE_DOUBLE_TAP_PAUSE.store(dt, Ordering::SeqCst);
    }
    if let Some(dt) = double_tap_mode {
        REQUIRE_DOUBLE_TAP_MODE.store(dt, Ordering::SeqCst);
    }

    if let Some(ref key) = toggle_key {
        if !key.trim().is_empty() {
            let app_h = app.clone();
            let key_str = key.clone();
            let _ = register_single_shortcut(&app, &key_str, move || {
                if REQUIRE_DOUBLE_TAP_TOGGLE.load(Ordering::SeqCst) {
                    let now_ms = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis() as u64;
                    let prev_ms = LAST_CUSTOM_TOGGLE_PRESS_MS.swap(now_ms, Ordering::SeqCst);
                    if now_ms.saturating_sub(prev_ms) > 450 {
                        println!("[*] [HOTKEY] Single tap detected for Toggle Recording (waiting for double tap <= 450ms)");
                        return;
                    }
                }
                let h = app_h.clone();
                tauri::async_runtime::spawn(async move {
                    toggle_recording_flow(&h).await;
                });
            });
        }
    }
    if let Some(ref key) = pause_key {
        if !key.trim().is_empty() {
            let app_h = app.clone();
            let key_str = key.clone();
            let _ = register_single_shortcut(&app, &key_str, move || {
                if REQUIRE_DOUBLE_TAP_PAUSE.load(Ordering::SeqCst) {
                    let now_ms = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis() as u64;
                    let prev_ms = LAST_CUSTOM_PAUSE_PRESS_MS.swap(now_ms, Ordering::SeqCst);
                    if now_ms.saturating_sub(prev_ms) > 450 {
                        println!("[*] [HOTKEY] Single tap detected for Pause Recording (waiting for double tap <= 450ms)");
                        return;
                    }
                }
                let h = app_h.clone();
                tauri::async_runtime::spawn(async move {
                    toggle_pause_flow(&h).await;
                });
            });
        }
    }
    if let Some(ref key) = mode_key {
        if !key.trim().is_empty() {
            let app_h = app.clone();
            let key_str = key.clone();
            let _ = register_single_shortcut(&app, &key_str, move || {
                if REQUIRE_DOUBLE_TAP_MODE.load(Ordering::SeqCst) {
                    let now_ms = SystemTime::now()
                        .duration_since(UNIX_EPOCH)
                        .unwrap_or_default()
                        .as_millis() as u64;
                    let prev_ms = LAST_CUSTOM_MODE_PRESS_MS.swap(now_ms, Ordering::SeqCst);
                    if now_ms.saturating_sub(prev_ms) > 450 {
                        println!("[*] [HOTKEY] Single tap detected for Switch Mode (waiting for double tap <= 450ms)");
                        return;
                    }
                }
                let h = app_h.clone();
                tauri::async_runtime::spawn(async move {
                    trigger_mode_switch_shortcut(&h).await;
                });
            });
        }
    }

    let payload = serde_json::json!({
        "toggle_key": toggle_key,
        "pause_key": pause_key,
        "mode_key": mode_key,
        "double_tap_toggle": double_tap_toggle,
        "double_tap_pause": double_tap_pause,
        "double_tap_mode": double_tap_mode,
    });
    let _ = app.emit("dicty:shortcuts-changed", payload);

    Ok(())
}

/// Temporarily unregisters all global shortcuts while recording in settings
#[tauri::command]
pub fn pause_global_shortcuts(app: AppHandle) -> Result<(), String> {
    let _ = app.global_shortcut().unregister_all();
    println!("[*] [HOTKEY] Global shortcuts paused for recording");
    Ok(())
}

/// Re-registers global shortcuts after recording is finished or cancelled
#[tauri::command]
pub async fn resume_global_shortcuts(
    app: AppHandle,
    toggle_key: Option<String>,
    pause_key: Option<String>,
    mode_key: Option<String>,
    double_tap_toggle: Option<bool>,
    double_tap_pause: Option<bool>,
    double_tap_mode: Option<bool>,
) -> Result<(), String> {
    let _ = register_custom_hotkeys(
        app.clone(),
        toggle_key,
        pause_key,
        mode_key,
        double_tap_toggle,
        double_tap_pause,
        double_tap_mode,
    )
    .await;
    println!("[*] [HOTKEY] Global shortcuts resumed");
    Ok(())
}

pub fn register_single_shortcut<F>(
    app: &AppHandle,
    shortcut_str: &str,
    handler: F,
) -> Result<(), String>
where
    F: Fn() + Send + Sync + 'static,
{
    let norm = shortcut_str
        .to_lowercase()
        .replace(' ', "")
        .replace("win+", "super+")
        .replace("meta+", "super+")
        .replace("cmd+", "super+")
        .replace("command+", "super+");
    let shortcut = norm.parse::<Shortcut>().map_err(|e| {
        eprintln!(
            "[-] [HOTKEY] Failed to parse shortcut '{}' (raw: '{}'): {:?}",
            norm, shortcut_str, e
        );
        format!("Failed to parse '{}': {:?}", norm, e)
    })?;

    let gs = app.global_shortcut();
    let _ = gs.unregister(shortcut);
    let norm_log = norm.clone();
    gs.on_shortcut(shortcut, move |_app, _shortcut, event| {
        if event.state() == ShortcutState::Pressed {
            println!("[*] [HOTKEY] Custom shortcut triggered: '{}'", norm_log);
            handler();
        }
    })
    .map_err(|e| {
        eprintln!(
            "[-] [HOTKEY] Failed to register shortcut '{}': {:?}",
            norm, e
        );
        format!("Failed to register '{}': {:?}", norm, e)
    })?;
    if let Ok(mut list) = REGISTERED_CUSTOM_SHORTCUTS.lock() {
        list.push(shortcut);
    }
    println!(
        "[+] [HOTKEY] Successfully registered custom shortcut: '{}'",
        norm
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_shortcuts_parsing() {
        let shortcuts = [
            "ctrl+space",
            "f8",
            "ctrl+shift+space",
            "alt+shift+space",
            "alt+p",
            "f7",
            "ctrl+alt+p",
            "ctrl+shift+p",
            "shift+f7",
            "ctrl+f7",
            "pause",
            "alt+shift+m",
            "ctrl+shift+m",
            "ctrl+alt+m",
            "super+shift+m",
            "f1",
            "f2",
            "f3",
            "f4",
            "f5",
            "f6",
            "f9",
            "f10",
            "f11",
            "f12",
            "insert",
            "delete",
            "home",
            "end",
            "pageup",
            "pagedown",
            "scrolllock",
            "numlock",
            "capslock",
            "printscreen",
            "tab",
            "enter",
            "backspace",
            "ctrl+m",
            "alt+m",
            "shift+m",
            "super+m",
            "ctrl+alt+1",
            "ctrl+f",
            "alt+space",
            "space",
            "a",
            "m",
            "`",
            "-",
            "=",
            ",",
            ".",
            "/",
            "[",
            "]",
            "\\",
            ";",
            "'",
            "numpad0",
            "numpad1",
            "numpadadd",
            "numpadsubtract",
        ];
        for s in &shortcuts {
            match s.parse::<Shortcut>() {
                Ok(_) => println!("Parsed: {}", s),
                Err(e) => eprintln!("Failed to parse '{}': {:?}", s, e),
            }
        }
    }
}
