use std::sync::OnceLock;
use std::time::Duration;

use tauri::{AppHandle, Emitter};

use crate::engine_auth;

pub const HOST: &str = "127.0.0.1";
pub const PORT: u16 = 8075;

static APP_HANDLE: OnceLock<AppHandle> = OnceLock::new();

pub fn init(app: AppHandle) {
    let _ = APP_HANDLE.set(app);
}

pub fn port() -> u16 {
    PORT
}

pub fn base_url() -> String {
    format!("http://{}:{}", HOST, PORT)
}

pub fn url(path: &str) -> String {
    if path.starts_with('/') {
        format!("{}{}", base_url(), path)
    } else {
        format!("{}/{}", base_url(), path)
    }
}

pub fn client(timeout: Duration) -> reqwest::Client {
    reqwest::Client::builder()
        .timeout(timeout)
        .build()
        .unwrap_or_default()
}

pub async fn send(builder: reqwest::RequestBuilder) -> Result<reqwest::Response, String> {
    if !engine_auth::is_trusted() {
        return Err(
            "Dicty's engine connection is not trusted. Restart Dicty to reconnect.".to_string(),
        );
    }

    for attempt in 0..2 {
        let token = engine_auth::current_token().ok_or_else(|| {
            "Dicty's engine token is unavailable. Restart Dicty to reconnect.".to_string()
        })?;
        let request = builder
            .try_clone()
            .ok_or_else(|| "Could not prepare the engine request for retry.".to_string())?;
        let response = request
            .header(engine_auth::HEADER_NAME, token)
            .send()
            .await
            .map_err(|error| format!("Could not reach the Dicty engine: {}", error))?;

        if response.status() != reqwest::StatusCode::UNAUTHORIZED {
            return Ok(response);
        }

        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        let is_token_rejection = serde_json::from_str::<serde_json::Value>(&body)
            .ok()
            .and_then(|payload| {
                payload
                    .get("error")
                    .and_then(|error| error.as_str())
                    .map(|error| error == "unauthorized")
            })
            .unwrap_or(false);

        if is_token_rejection && attempt == 0 {
            engine_auth::reload_from_disk();
            continue;
        }

        if is_token_rejection {
            let message = "Dicty's engine rejected this session. Restart the engine to reconnect."
                .to_string();
            notify_auth_failed(&message);
            return Err(message);
        }

        return Err(format!("Dicty's engine returned HTTP {}: {}", status, body));
    }

    Err("Dicty's engine rejected this session. Restart the engine to reconnect.".to_string())
}

pub fn notify_auth_failed(message: &str) {
    if let Some(app) = APP_HANDLE.get() {
        let _ = app.emit(
            "engine-auth-failed",
            serde_json::json!({ "error": message }),
        );
    }
}
