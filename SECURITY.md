# Security

## Local engine authentication

Dicty's local engine binds to loopback (`127.0.0.1:8075`) and requires a
per-session token. The token protects against malicious websites, DNS rebinding,
and unauthorized local processes.

- HTTP clients send `X-Dicty-Token: <token>`.
- Browser/WebView WebSocket clients send the subprotocol list
  `dicty.v1, <token>`; the engine echoes `dicty.v1` on accept.
- `GET /health` and CORS `OPTIONS` preflights are exempt.
- A rejected HTTP request returns exactly `401 {"error": "unauthorized"}`.
- A rejected WebSocket upgrade closes with `4401` (bad token) or `4403` (bad
  Host/Origin).
- The token is never accepted from a query parameter and is never logged.

### Token file

The engine writes `<data dir>/engine.token` atomically with owner-only
permissions (`0600` on Unix):

```json
{
  "token": "<random token>",
  "pid": 12345,
  "port": 8075
}
```

Data directories:

- macOS: `~/Library/Application Support/Dicty`
- Windows: `%USERPROFILE%\.dicty`
- Linux: `~/.dicty`
- Override: `DICTY_DATA_DIR`

The file is removed on clean engine shutdown when its `pid` matches the engine
process. Clients read it to adopt an already-running engine.

### Host and Origin checks

The engine validates the `Host` header against loopback names and validates
`Origin`/`Sec-Fetch-Site` for WebSocket upgrades. Tauri v2 on Windows uses
`http://tauri.localhost` by default; that origin is explicitly allowed.

### Development override

Token authentication is enforced by default, including packaged builds.
`DICTY_ALLOW_NO_TOKEN=1` disables enforcement **only when running from Python
source**. It is ignored in frozen/PyInstaller builds.

## Calling the engine by hand

Use the helper so the current token is read from the data directory and sent
correctly:

```bash
./scripts/engine_curl.sh /health
./scripts/engine_curl.sh /models
./scripts/engine_curl.sh -X POST /recording/start
```

The helper works on macOS, Linux, and Windows Git Bash/msys.

## Reporting

Report security issues privately to the maintainers rather than opening a
public issue with exploit details.
