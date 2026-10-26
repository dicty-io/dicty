use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, OnceLock};

use base64::Engine as _;
use serde_json::Value;

pub const TOKEN_FILENAME: &str = "engine.token";
pub const HEADER_NAME: &str = "X-Dicty-Token";

static LAUNCH_TOKEN: OnceLock<String> = OnceLock::new();
static CACHED_TOKEN: Mutex<Option<String>> = Mutex::new(None);
static TRUSTED: AtomicBool = AtomicBool::new(true);

pub fn data_dir() -> PathBuf {
    if let Some(override_dir) = std::env::var_os("DICTY_DATA_DIR") {
        let path = PathBuf::from(override_dir);
        let _ = std::fs::create_dir_all(&path);
        return path;
    }

    let home = std::env::var_os("USERPROFILE")
        .or_else(|| std::env::var_os("HOME"))
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("."));

    #[cfg(target_os = "macos")]
    let path = home
        .join("Library")
        .join("Application Support")
        .join("Dicty");
    #[cfg(not(target_os = "macos"))]
    let path = home.join(".dicty");

    let _ = std::fs::create_dir_all(&path);
    path
}

pub fn token_file_path() -> PathBuf {
    data_dir().join(TOKEN_FILENAME)
}

pub fn read_token_file() -> Option<String> {
    let raw = std::fs::read_to_string(token_file_path()).ok()?;
    let payload: Value = serde_json::from_str(&raw).ok()?;
    let token = payload.get("token")?.as_str()?.trim();
    if token.is_empty() {
        None
    } else {
        Some(token.to_string())
    }
}

pub fn launch_token() -> String {
    LAUNCH_TOKEN
        .get_or_init(|| {
            let environment_token = std::env::var("DICTY_SESSION_TOKEN")
                .ok()
                .map(|token| token.trim().to_string())
                .filter(|token| !token.is_empty());
            let token = environment_token.unwrap_or_else(generate_token);

            let mut cached = CACHED_TOKEN.lock().unwrap();
            if cached.is_none() {
                *cached = Some(token.clone());
            }
            token
        })
        .clone()
}

pub fn current_token() -> Option<String> {
    {
        let cached = CACHED_TOKEN.lock().unwrap();
        if let Some(token) = cached.as_ref() {
            return Some(token.clone());
        }
    }

    if let Some(token) = read_token_file() {
        set_cached_token(token.clone());
        return Some(token);
    }

    Some(launch_token())
}

pub fn set_cached_token(token: String) {
    let mut cached = CACHED_TOKEN.lock().unwrap();
    *cached = Some(token);
}

pub fn adopt_running_token() -> Option<String> {
    let token = read_token_file()?;
    set_cached_token(token.clone());
    Some(token)
}

pub fn reload_from_disk() -> Option<String> {
    let token = read_token_file()?;
    set_cached_token(token.clone());
    Some(token)
}

pub fn set_trusted(trusted: bool) {
    TRUSTED.store(trusted, Ordering::SeqCst);
}

pub fn is_trusted() -> bool {
    TRUSTED.load(Ordering::SeqCst)
}

fn generate_token() -> String {
    let mut bytes = [0u8; 32];
    getrandom::getrandom(&mut bytes).expect("failed to generate secure engine token");
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}
