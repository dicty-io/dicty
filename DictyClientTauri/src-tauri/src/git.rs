use reqwest::header::{ACCEPT, AUTHORIZATION};
use serde::{Deserialize, Serialize};
use std::net::SocketAddr;
use std::time::Duration;

#[derive(Debug, Serialize, Deserialize)]
pub struct GitCommitItem {
    pub id: String,
    pub message: String,
    pub author: String,
    pub date: String,
    pub url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GitPRItem {
    pub id: u64,
    pub title: String,
    pub author: String,
    pub date: String,
    pub url: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct GitContextResponse {
    pub commits: Vec<GitCommitItem>,
    pub prs: Vec<GitPRItem>,
}

fn clean_token(token: &str) -> String {
    let t = token.trim().trim_matches('"').trim_matches('\'').trim();
    if let Some(stripped) = t.strip_prefix("Bearer ") {
        stripped.trim().to_string()
    } else if let Some(stripped) = t.strip_prefix("bearer ") {
        stripped.trim().to_string()
    } else if let Some(stripped) = t.strip_prefix("token ") {
        stripped.trim().to_string()
    } else if let Some(stripped) = t.strip_prefix("Token ") {
        stripped.trim().to_string()
    } else {
        t.to_string()
    }
}

fn github_auth_header(token: &str) -> String {
    let clean = clean_token(token);
    if clean.starts_with("github_pat_") {
        format!("Bearer {}", clean)
    } else {
        format!("token {}", clean)
    }
}

fn build_client(provider: &str) -> reqwest::Client {
    let mut builder = reqwest::Client::builder()
        .user_agent("Dicty/1.0 (Windows NT 10.0; Win64; x64)")
        .timeout(Duration::from_secs(25));

    if provider == "github" {
        // Resolve api.github.com directly to official GitHub IP to bypass rogue hosts entry (e.g. 8.8.4.4)
        if let Ok(addr) = "140.82.121.5:443".parse::<SocketAddr>() {
            builder = builder.resolve("api.github.com", addr);
        }
    }

    builder.build().unwrap_or_default()
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GitTokens {
    pub github_token: Option<String>,
    pub gitlab_token: Option<String>,
    pub bitbucket_token: Option<String>,
}

pub fn find_env_token(provider: &str) -> Option<String> {
    let var_names: &[&str] = match provider {
        "github" => &["GITHUB_TOKEN", "GH_TOKEN"],
        "gitlab" => &["GITLAB_TOKEN", "GL_TOKEN"],
        "bitbucket" => &["BITBUCKET_TOKEN"],
        _ => &[],
    };

    for name in var_names {
        if let Ok(val) = std::env::var(name) {
            let cleaned = clean_token(&val);
            if !cleaned.is_empty() {
                return Some(cleaned);
            }
        }
    }

    use std::path::PathBuf;
    let mut candidates = vec![
        PathBuf::from(".env"),
        PathBuf::from("../.env"),
        PathBuf::from("../../.env"),
    ];

    if let Ok(cur) = std::env::current_dir() {
        candidates.push(cur.join(".env"));
        candidates.push(cur.join("../.env"));
        candidates.push(cur.join("../../.env"));
    }

    for path in &candidates {
        if let Ok(content) = std::fs::read_to_string(path) {
            for line in content.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with('#') || !trimmed.contains('=') {
                    continue;
                }
                if let Some((k, v)) = trimmed.split_once('=') {
                    let key = k.trim();
                    for name in var_names {
                        if key.eq_ignore_ascii_case(name) {
                            let cleaned = clean_token(v);
                            if !cleaned.is_empty() {
                                return Some(cleaned);
                            }
                        }
                    }
                }
            }
        }
    }

    None
}

/// Retrieve detected Git tokens from local .env or system environment
#[tauri::command]
pub fn get_env_git_tokens() -> GitTokens {
    GitTokens {
        github_token: find_env_token("github"),
        gitlab_token: find_env_token("gitlab"),
        bitbucket_token: find_env_token("bitbucket"),
    }
}

/// Fetch user repositories across GitHub, GitLab, and Bitbucket
#[tauri::command]
pub async fn git_fetch_repositories(
    provider: String,
    token: String,
    host: Option<String>,
) -> Result<Vec<String>, String> {
    let mut clean = clean_token(&token);
    if clean.is_empty() {
        if let Some(env_tok) = find_env_token(&provider) {
            clean = env_tok;
        } else {
            return Err(format!("No {} token provided or detected in .env", provider.to_uppercase()));
        }
    }

    let client = build_client(&provider);

    if provider == "github" {
        let auth = github_auth_header(&clean);
        let resp = client
            .get("https://api.github.com/user/repos?per_page=100&sort=updated")
            .header(AUTHORIZATION, &auth)
            .header(ACCEPT, "application/vnd.github.v3+json")
            .send()
            .await
            .map_err(|e| format!("GitHub connection error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            // If 401 and we have a fallback token in .env that differs from current, retry with it
            if status == reqwest::StatusCode::UNAUTHORIZED {
                if let Some(env_tok) = find_env_token("github") {
                    if env_tok != clean {
                        let retry_auth = github_auth_header(&env_tok);
                        if let Ok(retry_resp) = client
                            .get("https://api.github.com/user/repos?per_page=100&sort=updated")
                            .header(AUTHORIZATION, retry_auth)
                            .header(ACCEPT, "application/vnd.github.v3+json")
                            .send()
                            .await
                        {
                            if retry_resp.status().is_success() {
                                if let Ok(json) = retry_resp.json::<Vec<serde_json::Value>>().await {
                                    let repos = json
                                        .into_iter()
                                        .filter_map(|r| r.get("full_name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                                        .collect();
                                    return Ok(repos);
                                }
                            }
                        }
                    }
                }
            }

            let body = resp.text().await.unwrap_or_default();
            let msg = if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body) {
                json.get("message").and_then(|m| m.as_str()).unwrap_or(&body).to_string()
            } else {
                body
            };
            return Err(format!("GitHub ({}): {}", status, msg));
        }

        let json = resp
            .json::<Vec<serde_json::Value>>()
            .await
            .map_err(|e| format!("Failed to parse GitHub repositories: {}", e))?;

        let repos = json
            .into_iter()
            .filter_map(|r| r.get("full_name").and_then(|n| n.as_str()).map(|s| s.to_string()))
            .collect();
        Ok(repos)
    } else if provider == "gitlab" {
        let base_host = host.unwrap_or_else(|| "https://gitlab.com".to_string());
        let clean_host = base_host.trim_end_matches('/');
        let url = format!("{}/api/v4/projects?membership=true&per_page=100&order_by=updated_at", clean_host);

        let resp = client
            .get(&url)
            .header("PRIVATE-TOKEN", clean)
            .send()
            .await
            .map_err(|e| format!("GitLab connection error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("GitLab ({}): {}", status, body));
        }

        let json = resp
            .json::<Vec<serde_json::Value>>()
            .await
            .map_err(|e| format!("Failed to parse GitLab projects: {}", e))?;

        let repos = json
            .into_iter()
            .filter_map(|r| {
                r.get("path_with_namespace")
                    .or_else(|| r.get("name"))
                    .and_then(|n| n.as_str())
                    .map(|s| s.to_string())
            })
            .collect();
        Ok(repos)
    } else if provider == "bitbucket" {
        let url = "https://api.bitbucket.org/2.0/user/permissions/repositories?pagelen=100";
        let mut req = client.get(url).header(ACCEPT, "application/json");
        if clean.contains(':') {
            let encoded = base64_encode(&clean);
            req = req.header(AUTHORIZATION, format!("Basic {}", encoded));
        } else {
            req = req.header(AUTHORIZATION, format!("Bearer {}", clean));
        }

        let resp = req.send().await.map_err(|e| format!("Bitbucket connection error: {}", e))?;
        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            return Err(format!("Bitbucket ({}): {}", status, body));
        }

        let json = resp
            .json::<serde_json::Value>()
            .await
            .map_err(|e| format!("Failed to parse Bitbucket repos: {}", e))?;

        let mut repos = Vec::new();
        if let Some(values) = json.get("values").and_then(|v| v.as_array()) {
            for v in values {
                if let Some(name) = v.pointer("/repository/full_name").and_then(|n| n.as_str()) {
                    repos.push(name.to_string());
                }
            }
        }
        Ok(repos)
    } else {
        Err(format!("Unsupported git provider: {}", provider))
    }
}

/// Fetch branches for a repository
#[tauri::command]
pub async fn git_fetch_branches(
    provider: String,
    token: String,
    repo: String,
    host: Option<String>,
) -> Result<Vec<String>, String> {
    let mut clean = clean_token(&token);
    if clean.is_empty() {
        if let Some(env_tok) = find_env_token(&provider) {
            clean = env_tok;
        } else {
            return Ok(Vec::new());
        }
    }
    if repo.is_empty() {
        return Ok(Vec::new());
    }

    let client = build_client(&provider);

    if provider == "github" {
        let auth = github_auth_header(&clean);
        let url = format!("https://api.github.com/repos/{}/branches?per_page=100", repo);
        let resp = client
            .get(&url)
            .header(AUTHORIZATION, &auth)
            .header(ACCEPT, "application/vnd.github.v3+json")
            .send()
            .await
            .map_err(|e| format!("GitHub branches error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            if status == reqwest::StatusCode::UNAUTHORIZED {
                if let Some(env_tok) = find_env_token("github") {
                    if env_tok != clean {
                        let retry_auth = github_auth_header(&env_tok);
                        if let Ok(retry_resp) = client
                            .get(&url)
                            .header(AUTHORIZATION, retry_auth)
                            .header(ACCEPT, "application/vnd.github.v3+json")
                            .send()
                            .await
                        {
                            if retry_resp.status().is_success() {
                                if let Ok(json) = retry_resp.json::<Vec<serde_json::Value>>().await {
                                    let branches = json
                                        .into_iter()
                                        .filter_map(|b| b.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
                                        .collect();
                                    return Ok(branches);
                                }
                            }
                        }
                    }
                }
            }

            let body = resp.text().await.unwrap_or_default();
            return Err(format!("GitHub branches ({}): {}", status, body));
        }

        let json = resp
            .json::<Vec<serde_json::Value>>()
            .await
            .map_err(|e| format!("Failed to parse branches: {}", e))?;

        let branches = json
            .into_iter()
            .filter_map(|b| b.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
            .collect();
        Ok(branches)
    } else if provider == "gitlab" {
        let base_host = host.unwrap_or_else(|| "https://gitlab.com".to_string());
        let clean_host = base_host.trim_end_matches('/');
        let encoded_repo = urlencoding_encode(&repo);
        let url = format!("{}/api/v4/projects/{}/repository/branches?per_page=100", clean_host, encoded_repo);

        let resp = client
            .get(&url)
            .header("PRIVATE-TOKEN", clean)
            .send()
            .await
            .map_err(|e| format!("GitLab branches error: {}", e))?;

        if !resp.status().is_success() {
            return Err(format!("GitLab branches failed ({})", resp.status()));
        }

        let json = resp
            .json::<Vec<serde_json::Value>>()
            .await
            .map_err(|e| format!("Failed to parse GitLab branches: {}", e))?;

        let branches = json
            .into_iter()
            .filter_map(|b| b.get("name").and_then(|n| n.as_str()).map(|s| s.to_string()))
            .collect();
        Ok(branches)
    } else if provider == "bitbucket" {
        let url = format!("https://api.bitbucket.org/2.0/repositories/{}/refs/branches?pagelen=100", repo);
        let mut req = client.get(&url).header(ACCEPT, "application/json");
        if clean.contains(':') {
            req = req.header(AUTHORIZATION, format!("Basic {}", base64_encode(&clean)));
        } else {
            req = req.header(AUTHORIZATION, format!("Bearer {}", clean));
        }

        let resp = req.send().await.map_err(|e| format!("Bitbucket branches error: {}", e))?;
        if !resp.status().is_success() {
            return Err(format!("Bitbucket branches failed ({})", resp.status()));
        }

        let json = resp
            .json::<serde_json::Value>()
            .await
            .map_err(|e| format!("Failed to parse Bitbucket branches: {}", e))?;

        let mut branches = Vec::new();
        if let Some(values) = json.get("values").and_then(|v| v.as_array()) {
            for v in values {
                if let Some(name) = v.get("name").and_then(|n| n.as_str()) {
                    branches.push(name.to_string());
                }
            }
        }
        Ok(branches)
    } else {
        Err(format!("Unsupported provider: {}", provider))
    }
}

/// Fetch recent commits and open Pull Requests (Active Context)
#[tauri::command]
pub async fn git_fetch_context(
    provider: String,
    token: String,
    repo: String,
    branch: Option<String>,
    limit: Option<usize>,
    host: Option<String>,
) -> Result<GitContextResponse, String> {
    let mut clean = clean_token(&token);
    if clean.is_empty() {
        if let Some(env_tok) = find_env_token(&provider) {
            clean = env_tok;
        } else {
            return Ok(GitContextResponse {
                commits: Vec::new(),
                prs: Vec::new(),
            });
        }
    }
    if repo.is_empty() {
        return Ok(GitContextResponse {
            commits: Vec::new(),
            prs: Vec::new(),
        });
    }

    let client = build_client(&provider);
    let limit = limit.unwrap_or(10);

    if provider == "github" {
        let auth = github_auth_header(&clean);
        let branch_param = branch
            .as_ref()
            .filter(|b| !b.is_empty())
            .map(|b| format!("&sha={}", urlencoding_encode(b)))
            .unwrap_or_default();

        let commits_url = format!(
            "https://api.github.com/repos/{}/commits?per_page={}{}",
            repo, limit, branch_param
        );
        let prs_url = format!("https://api.github.com/repos/{}/pulls?state=open&per_page=15", repo);

        let (mut commits_res, mut prs_res) = tokio::join!(
            client.get(&commits_url).header(AUTHORIZATION, &auth).header(ACCEPT, "application/vnd.github.v3+json").send(),
            client.get(&prs_url).header(AUTHORIZATION, &auth).header(ACCEPT, "application/vnd.github.v3+json").send()
        );

        // If unauthorized and .env has a different token, retry context fetch
        let is_unauthorized = commits_res.as_ref().map(|r| r.status() == reqwest::StatusCode::UNAUTHORIZED).unwrap_or(false)
            || prs_res.as_ref().map(|r| r.status() == reqwest::StatusCode::UNAUTHORIZED).unwrap_or(false);

        if is_unauthorized {
            if let Some(env_tok) = find_env_token("github") {
                if env_tok != clean {
                    let retry_auth = github_auth_header(&env_tok);
                    let (rc, rp) = tokio::join!(
                        client.get(&commits_url).header(AUTHORIZATION, &retry_auth).header(ACCEPT, "application/vnd.github.v3+json").send(),
                        client.get(&prs_url).header(AUTHORIZATION, &retry_auth).header(ACCEPT, "application/vnd.github.v3+json").send()
                    );
                    commits_res = rc;
                    prs_res = rp;
                }
            }
        }

        let mut commits = Vec::new();
        let mut prs = Vec::new();

        if let Ok(resp) = commits_res {
            if resp.status().is_success() {
                if let Ok(data) = resp.json::<Vec<serde_json::Value>>().await {
                    for c in data {
                        let sha = c.get("sha").and_then(|s| s.as_str()).unwrap_or("");
                        let short_sha = if sha.len() >= 7 { &sha[..7] } else { sha };
                        let message = c.pointer("/commit/message")
                            .and_then(|m| m.as_str())
                            .unwrap_or("")
                            .lines()
                            .next()
                            .unwrap_or("");
                        let author = c.pointer("/commit/author/name")
                            .or_else(|| c.pointer("/author/login"))
                            .and_then(|a| a.as_str())
                            .unwrap_or("Unknown");
                        let date = c.pointer("/commit/author/date")
                            .and_then(|d| d.as_str())
                            .unwrap_or("");
                        let html_url = c.get("html_url").and_then(|u| u.as_str()).unwrap_or("");

                        commits.push(GitCommitItem {
                            id: short_sha.to_string(),
                            message: message.to_string(),
                            author: author.to_string(),
                            date: date.to_string(),
                            url: html_url.to_string(),
                        });
                    }
                }
            } else {
                let err_msg = resp.text().await.unwrap_or_default();
                eprintln!("[!] GitHub commits error: {}", err_msg);
            }
        }

        if let Ok(resp) = prs_res {
            if resp.status().is_success() {
                if let Ok(data) = resp.json::<Vec<serde_json::Value>>().await {
                    for p in data {
                        let number = p.get("number").and_then(|n| n.as_u64()).unwrap_or(0);
                        let title = p.get("title").and_then(|t| t.as_str()).unwrap_or("");
                        let author = p.pointer("/user/login").and_then(|u| u.as_str()).unwrap_or("Unknown");
                        let date = p.get("created_at").and_then(|d| d.as_str()).unwrap_or("");
                        let html_url = p.get("html_url").and_then(|u| u.as_str()).unwrap_or("");

                        prs.push(GitPRItem {
                            id: number,
                            title: title.to_string(),
                            author: author.to_string(),
                            date: date.to_string(),
                            url: html_url.to_string(),
                        });
                    }
                }
            }
        }

        Ok(GitContextResponse { commits, prs })
    } else if provider == "gitlab" {
        let base_host = host.unwrap_or_else(|| "https://gitlab.com".to_string());
        let clean_host = base_host.trim_end_matches('/');
        let encoded_repo = urlencoding_encode(&repo);
        let branch_param = branch
            .filter(|b| !b.is_empty())
            .map(|b| format!("&ref_name={}", urlencoding_encode(&b)))
            .unwrap_or_default();

        let commits_url = format!(
            "{}/api/v4/projects/{}/repository/commits?per_page={}{}",
            clean_host, encoded_repo, limit, branch_param
        );
        let prs_url = format!(
            "{}/api/v4/projects/{}/merge_requests?state=opened&per_page=15",
            clean_host, encoded_repo
        );

        let (commits_res, prs_res) = tokio::join!(
            client.get(&commits_url).header("PRIVATE-TOKEN", &clean).send(),
            client.get(&prs_url).header("PRIVATE-TOKEN", &clean).send()
        );

        let mut commits = Vec::new();
        let mut prs = Vec::new();

        if let Ok(resp) = commits_res {
            if resp.status().is_success() {
                if let Ok(data) = resp.json::<Vec<serde_json::Value>>().await {
                    for c in data {
                        let id = c.get("short_id").or_else(|| c.get("id")).and_then(|s| s.as_str()).unwrap_or("");
                        let message = c.get("message").and_then(|m| m.as_str()).unwrap_or("").lines().next().unwrap_or("");
                        let author = c.get("author_name").and_then(|a| a.as_str()).unwrap_or("Unknown");
                        let date = c.get("created_at").and_then(|d| d.as_str()).unwrap_or("");
                        let web_url = c.get("web_url").and_then(|u| u.as_str()).unwrap_or("");

                        commits.push(GitCommitItem {
                            id: id.to_string(),
                            message: message.to_string(),
                            author: author.to_string(),
                            date: date.to_string(),
                            url: web_url.to_string(),
                        });
                    }
                }
            }
        }

        if let Ok(resp) = prs_res {
            if resp.status().is_success() {
                if let Ok(data) = resp.json::<Vec<serde_json::Value>>().await {
                    for p in data {
                        let iid = p.get("iid").and_then(|n| n.as_u64()).unwrap_or(0);
                        let title = p.get("title").and_then(|t| t.as_str()).unwrap_or("");
                        let author = p.pointer("/author/username").and_then(|u| u.as_str()).unwrap_or("Unknown");
                        let date = p.get("created_at").and_then(|d| d.as_str()).unwrap_or("");
                        let web_url = p.get("web_url").and_then(|u| u.as_str()).unwrap_or("");

                        prs.push(GitPRItem {
                            id: iid,
                            title: title.to_string(),
                            author: author.to_string(),
                            date: date.to_string(),
                            url: web_url.to_string(),
                        });
                    }
                }
            }
        }

        Ok(GitContextResponse { commits, prs })
    } else {
        Ok(GitContextResponse { commits: Vec::new(), prs: Vec::new() })
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HostsStatus {
    pub has_rogue_entries: bool,
    pub rogue_entries: Vec<String>,
}

/// Check if Windows hosts file contains rogue entries that poison github.com / api.github.com
#[tauri::command]
pub fn check_github_hosts_status() -> HostsStatus {
    #[cfg(target_os = "windows")]
    {
        use std::path::Path;
        let hosts_path = Path::new("C:\\Windows\\System32\\drivers\\etc\\hosts");
        if hosts_path.exists() {
            if let Ok(content) = std::fs::read_to_string(hosts_path) {
                let rogue: Vec<String> = content
                    .lines()
                    .filter(|line| {
                        let trimmed = line.trim();
                        !trimmed.starts_with('#')
                            && (trimmed.contains("github.com") || trimmed.contains("api.github.com") || trimmed.contains("codeload.github.com"))
                            && (trimmed.starts_with("8.8.4.4") || trimmed.starts_with("127.0.0.1") || trimmed.starts_with("0.0.0.0"))
                    })
                    .map(|s| s.trim().to_string())
                    .collect();

                return HostsStatus {
                    has_rogue_entries: !rogue.is_empty(),
                    rogue_entries: rogue,
                };
            }
        }
    }

    HostsStatus {
        has_rogue_entries: false,
        rogue_entries: Vec::new(),
    }
}

/// Natively repair the Windows hosts file using Windows UAC elevation
#[tauri::command]
pub async fn repair_windows_hosts() -> Result<String, String> {
    #[cfg(target_os = "windows")]
    {
        use std::process::Command;

        let inner_script = r#"$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
$backupPath = "$env:SystemRoot\System32\drivers\etc\hosts.dicty_backup"
if (Test-Path $hostsPath) {
    Copy-Item -Path $hostsPath -Destination $backupPath -Force
    $lines = Get-Content -Path $hostsPath | Where-Object { $_ -notmatch 'github\.com' }
    [System.IO.File]::WriteAllLines($hostsPath, $lines, [System.Text.Encoding]::UTF8)
}"#;

        let inner_b64 = encode_ps_utf16le_base64(inner_script);
        let outer_script = format!(
            "Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-EncodedCommand', '{}')",
            inner_b64
        );
        let outer_b64 = encode_ps_utf16le_base64(&outer_script);

        let output = Command::new("powershell")
            .args(["-NoProfile", "-WindowStyle", "Hidden", "-EncodedCommand", &outer_b64])
            .output()
            .map_err(|e| format!("Failed to launch elevation process: {}", e))?;

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            return Err(format!("UAC elevation cancelled or failed: {}", stderr));
        }

        // Verify if rogue entries were removed
        let recheck = check_github_hosts_status();
        if !recheck.has_rogue_entries {
            Ok("Windows hosts file successfully cleaned! Backup saved to hosts.dicty_backup".to_string())
        } else {
            Err("Hosts file was not modified. Please allow Administrator access when prompted.".to_string())
        }
    }

    #[cfg(not(target_os = "windows"))]
    {
        Ok("Not required on macOS/Linux".to_string())
    }
}

/// Test Git provider authentication connection
#[tauri::command]
pub async fn git_test_connection(
    provider: String,
    token: String,
    host: Option<String>,
) -> Result<String, String> {
    let mut clean = clean_token(&token);
    if clean.is_empty() {
        if let Some(env_tok) = find_env_token(&provider) {
            clean = env_tok;
        } else {
            return Err(format!("No {} token provided or found in .env", provider.to_uppercase()));
        }
    }

    let client = build_client(&provider);

    if provider == "github" {
        let auth = github_auth_header(&clean);
        let resp = client
            .get("https://api.github.com/user")
            .header(AUTHORIZATION, &auth)
            .header(ACCEPT, "application/vnd.github.v3+json")
            .send()
            .await
            .map_err(|e| format!("Connection error: {}", e))?;

        if !resp.status().is_success() {
            let status = resp.status();
            if status == reqwest::StatusCode::UNAUTHORIZED {
                if let Some(env_tok) = find_env_token("github") {
                    if env_tok != clean {
                        let retry_auth = github_auth_header(&env_tok);
                        if let Ok(retry_resp) = client
                            .get("https://api.github.com/user")
                            .header(AUTHORIZATION, retry_auth)
                            .header(ACCEPT, "application/vnd.github.v3+json")
                            .send()
                            .await
                        {
                            if retry_resp.status().is_success() {
                                if let Ok(json) = retry_resp.json::<serde_json::Value>().await {
                                    let login = json.get("login").and_then(|l| l.as_str()).unwrap_or("unknown");
                                    let name = json.get("name").and_then(|n| n.as_str()).unwrap_or(login);
                                    let repos = json.get("public_repos").and_then(|r| r.as_u64()).unwrap_or(0);
                                    return Ok(format!("Connected as {} (@{}) • {} public repos (from .env)", name, login, repos));
                                }
                            }
                        }
                    }
                }
            }

            let body = resp.text().await.unwrap_or_default();
            let msg = if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body) {
                json.get("message").and_then(|m| m.as_str()).unwrap_or(&body).to_string()
            } else {
                body
            };
            return Err(format!("GitHub error ({}): {}", status, msg));
        }

        let json: serde_json::Value = resp.json().await.map_err(|e| format!("Parse error: {}", e))?;
        let login = json.get("login").and_then(|l| l.as_str()).unwrap_or("unknown");
        let name = json.get("name").and_then(|n| n.as_str()).unwrap_or(login);
        let repos = json.get("public_repos").and_then(|r| r.as_u64()).unwrap_or(0);
        Ok(format!("Connected as {} (@{}) • {} public repos", name, login, repos))
    } else if provider == "gitlab" {
        let base_host = host.unwrap_or_else(|| "https://gitlab.com".to_string());
        let clean_host = base_host.trim_end_matches('/');
        let url = format!("{}/api/v4/user", clean_host);

        let resp = client
            .get(&url)
            .header("PRIVATE-TOKEN", &clean)
            .send()
            .await
            .map_err(|e| format!("GitLab connection error: {}", e))?;

        if !resp.status().is_success() {
            return Err(format!("GitLab error: HTTP {}", resp.status()));
        }

        let json: serde_json::Value = resp.json().await.map_err(|e| format!("Parse error: {}", e))?;
        let username = json.get("username").and_then(|u| u.as_str()).unwrap_or("unknown");
        let name = json.get("name").and_then(|n| n.as_str()).unwrap_or(username);
        Ok(format!("Connected as {} (@{})", name, username))
    } else if provider == "bitbucket" {
        let url = "https://api.bitbucket.org/2.0/user";
        let mut req = client.get(url).header(ACCEPT, "application/json");
        if clean.contains(':') {
            let encoded = base64_encode(&clean);
            req = req.header(AUTHORIZATION, format!("Basic {}", encoded));
        } else {
            req = req.header(AUTHORIZATION, format!("Bearer {}", clean));
        }

        let resp = req.send().await.map_err(|e| format!("Bitbucket connection error: {}", e))?;
        if !resp.status().is_success() {
            return Err(format!("Bitbucket error: HTTP {}", resp.status()));
        }

        let json: serde_json::Value = resp.json().await.map_err(|e| format!("Parse error: {}", e))?;
        let display_name = json.get("display_name").and_then(|d| d.as_str()).unwrap_or("unknown");
        Ok(format!("Connected as {}", display_name))
    } else {
        Err(format!("Unsupported provider: {}", provider))
    }
}

pub fn encode_ps_utf16le_base64(script: &str) -> String {
    let utf16: Vec<u8> = script
        .encode_utf16()
        .flat_map(|u| u.to_le_bytes())
        .collect();
    base64_encode_bytes(&utf16)
}

fn base64_encode(input: &str) -> String {
    base64_encode_bytes(input.as_bytes())
}

fn base64_encode_bytes(bytes: &[u8]) -> String {
    const STANDARD: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::with_capacity((bytes.len() + 2) / 3 * 4);
    for chunk in bytes.chunks(3) {
        let b0 = chunk[0];
        let b1 = if chunk.len() > 1 { chunk[1] } else { 0 };
        let b2 = if chunk.len() > 2 { chunk[2] } else { 0 };

        result.push(STANDARD[(b0 >> 2) as usize] as char);
        result.push(STANDARD[(((b0 & 0x03) << 4) | (b1 >> 4)) as usize] as char);
        if chunk.len() > 1 {
            result.push(STANDARD[(((b1 & 0x0F) << 2) | (b2 >> 6)) as usize] as char);
        } else {
            result.push('=');
        }
        if chunk.len() > 2 {
            result.push(STANDARD[(b2 & 0x3F) as usize] as char);
        } else {
            result.push('=');
        }
    }
    result
}

fn urlencoding_encode(input: &str) -> String {
    let mut result = String::new();
    for b in input.bytes() {
        if b.is_ascii_alphanumeric() || b == b'-' || b == b'_' || b == b'.' || b == b'~' {
            result.push(b as char);
        } else {
            result.push_str(&format!("%{:02X}", b));
        }
    }
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_clean_token() {
        assert_eq!(clean_token("  ghp_12345  "), "ghp_12345");
        assert_eq!(clean_token("\"ghp_12345\""), "ghp_12345");
        assert_eq!(clean_token("'ghp_12345'"), "ghp_12345");
        assert_eq!(clean_token("Bearer ghp_12345"), "ghp_12345");
        assert_eq!(clean_token("bearer ghp_12345"), "ghp_12345");
        assert_eq!(clean_token("token ghp_12345"), "ghp_12345");
    }

    #[test]
    fn test_github_auth_header() {
        assert_eq!(github_auth_header("ghp_123"), "token ghp_123");
        assert_eq!(github_auth_header("github_pat_123"), "Bearer github_pat_123");
        assert_eq!(github_auth_header("Bearer github_pat_123"), "Bearer github_pat_123");
    }

    #[test]
    fn test_base64_encode() {
        assert_eq!(base64_encode("user:pass"), "dXNlcjpwYXNz");
    }

    #[test]
    fn test_encode_ps_utf16le_base64() {
        assert_eq!(
            encode_ps_utf16le_base64("Write-Output Hello"),
            "VwByAGkAdABlAC0ATwB1AHQAcAB1AHQAIABIAGUAbABsAG8A"
        );
    }

    #[test]
    fn test_find_env_token() {
        let tok = find_env_token("github");
        assert!(tok.is_some());
        let val = tok.unwrap();
        assert!(val.starts_with("github_pat_"));
    }

    #[test]
    fn test_check_github_hosts_status() {
        let status = check_github_hosts_status();
        // On the current Windows test machine, it should detect the 8.8.4.4 rogue entries
        #[cfg(target_os = "windows")]
        {
            assert!(status.has_rogue_entries);
            assert!(status.rogue_entries.iter().any(|e| e.contains("api.github.com")));
        }
    }
}


