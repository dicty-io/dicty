"""Tests for local engine session token authentication (engine_auth).

Validates:
- HTTP 401 on missing or wrong token when enforcement is on (default).
- HTTP 200 when valid X-Dicty-Token is supplied.
- HTTP 403 on invalid Host header (DNS rebinding protection).
- GET /health and CORS OPTIONS preflights are exempt from auth.
- WebSocket connections without token close with code 4401; connect with token.
- Token file engine.token written with 0600 permissions, atomically rewritten.
- Internal self-calls (e.g. /recording/internal/partial) succeed using auth_headers().
- Clean shutdown removes token file.
"""

import _bootstrap  # noqa: F401
import json
import os
import stat
import sys
import unittest
from unittest.mock import patch
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

import dicty_paths
import engine_auth
from dicty_engine import app


class TestEngineAuth(unittest.TestCase):
    def setUp(self):
        # Save env vars to restore after each test
        self._orig_allow_no_token = os.environ.get("DICTY_ALLOW_NO_TOKEN")
        self._orig_session = os.environ.get("DICTY_SESSION_TOKEN")
        os.environ.pop("DICTY_ALLOW_NO_TOKEN", None)
        self.valid_token = engine_auth.get_token()

    def tearDown(self):
        if self._orig_allow_no_token is not None:
            os.environ["DICTY_ALLOW_NO_TOKEN"] = self._orig_allow_no_token
        else:
            os.environ.pop("DICTY_ALLOW_NO_TOKEN", None)

        if self._orig_session is not None:
            os.environ["DICTY_SESSION_TOKEN"] = self._orig_session
        else:
            os.environ.pop("DICTY_SESSION_TOKEN", None)

    def test_missing_token_returns_401(self):
        """Requests without X-Dicty-Token must return HTTP 401 when enforcement is active."""
        unauth_client = TestClient(app, headers={"_dicty_no_auth": True})
        response = unauth_client.get("/models")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"error": "unauthorized"})

    def test_wrong_token_returns_401(self):
        """Requests with an invalid token must return HTTP 401."""
        client = TestClient(app, headers={"X-Dicty-Token": "completely-invalid-bogus-token"})
        response = client.get("/models")
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"error": "unauthorized"})

    def test_valid_token_returns_200(self):
        """Requests with the correct X-Dicty-Token succeed."""
        client = TestClient(app, headers={"X-Dicty-Token": self.valid_token})
        response = client.get("/models")
        self.assertEqual(response.status_code, 200)

    def test_wrong_host_header_returns_403(self):
        """Requests with an untrusted Host header (e.g. from DNS rebinding) return HTTP 403."""
        client = TestClient(app, headers={"X-Dicty-Token": self.valid_token})
        # Override Host header
        response = client.get("/models", headers={"Host": "evil-attacker.com"})
        self.assertEqual(response.status_code, 403)
        self.assertEqual(response.json().get("error"), "forbidden")

    def test_allowed_hosts(self):
        """Standard localhost and 127.0.0.1 with port are allowed."""
        client = TestClient(app, headers={"X-Dicty-Token": self.valid_token})
        for host in ["127.0.0.1:8075", "localhost:8075", "127.0.0.1", "localhost"]:
            resp = client.get("/models", headers={"Host": host})
            self.assertEqual(resp.status_code, 200, f"Host {host} should be accepted")

    def test_health_endpoint_is_exempt(self):
        """GET /health must work without a token and even with an arbitrary Host header."""
        unauth_client = TestClient(app, headers={"_dicty_no_auth": True})
        response = unauth_client.get("/health", headers={"Host": "evil.com"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"ok": True})

    def test_options_preflight_is_exempt(self):
        """CORS OPTIONS preflight requests must not require authentication."""
        unauth_client = TestClient(app, headers={"_dicty_no_auth": True})
        response = unauth_client.options("/models", headers={"Origin": "http://localhost:1420", "Access-Control-Request-Method": "GET"})
        self.assertIn(response.status_code, (200, 204))

    def test_websocket_auth(self):
        """WebSocket connection requires X-Dicty-Token; closes with 4401 if missing or invalid."""
        unauth_client = TestClient(app, headers={"_dicty_no_auth": True})
        with self.assertRaises(WebSocketDisconnect) as ctx:
            with unauth_client.websocket_connect("/ws/transcribe/stream"):
                pass
        self.assertEqual(ctx.exception.code, 4401)

        # Valid token connects via the normal header and does not select a subprotocol.
        auth_client = TestClient(app, headers={"X-Dicty-Token": self.valid_token})
        with auth_client.websocket_connect("/ws/transcribe/stream") as ws:
            self.assertIsNone(ws.accepted_subprotocol)
            ws.send_json({"type": "ping"})

    def test_websocket_subprotocol_auth(self):
        """WebSocket can authenticate with `dicty.v1, <token>` and must echo the subprotocol."""
        client = TestClient(app, headers={"_dicty_no_auth": True})
        with client.websocket_connect(
            "/ws/transcribe/stream",
            subprotocols=["dicty.v1", self.valid_token],
        ) as ws:
            self.assertEqual(ws.accepted_subprotocol, "dicty.v1")
            ws.send_json({"type": "ping"})

    def test_websocket_wrong_subprotocol_token_returns_4401(self):
        client = TestClient(app, headers={"_dicty_no_auth": True})
        with self.assertRaises(WebSocketDisconnect) as ctx:
            with client.websocket_connect(
                "/ws/transcribe/stream",
                subprotocols=["dicty.v1", "wrong-token"],
            ):
                pass
        self.assertEqual(ctx.exception.code, 4401)

    def test_http_ignores_subprotocol_token(self):
        """HTTP requests must only accept the header, never the WS subprotocol token."""
        client = TestClient(app, headers={"_dicty_no_auth": True})
        response = client.get(
            "/models",
            headers={"Sec-WebSocket-Protocol": f"dicty.v1, {self.valid_token}"},
        )
        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json(), {"error": "unauthorized"})

    def test_token_file_mode_and_content(self):
        """Token file has mode 0600, valid JSON, and regenerates when requested."""
        token_path = os.path.join(dicty_paths.get_user_data_dir(), "engine.token")
        self.assertTrue(os.path.isfile(token_path), f"Token file must exist at {token_path}")

        # Check file permissions (owner read/write only)
        st_mode = stat.S_IMODE(os.stat(token_path).st_mode)
        self.assertEqual(st_mode, 0o600, f"Token file mode should be 0600, got {oct(st_mode)}")

        # Check JSON payload
        with open(token_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(data["token"], self.valid_token)
        self.assertEqual(data["pid"], os.getpid())
        self.assertEqual(data["port"], 8075)

    def test_init_token_without_env_var(self):
        """When DICTY_SESSION_TOKEN is not in env, engine generates random 32-byte urlsafe token."""
        os.environ.pop("DICTY_SESSION_TOKEN", None)
        new_token = engine_auth.init_token()
        self.assertGreaterEqual(len(new_token), 32)
        self.assertTrue(engine_auth.check(new_token))

        token_path = os.path.join(dicty_paths.get_user_data_dir(), "engine.token")
        with open(token_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        self.assertEqual(data["token"], new_token)

    def test_token_required_by_default(self):
        """Token authentication is enforced when no override is set."""
        self.assertTrue(engine_auth.is_token_required())

    def test_dev_override_disables_enforcement(self):
        """DICTY_ALLOW_NO_TOKEN=1 disables auth only in source/dev runs."""
        os.environ["DICTY_ALLOW_NO_TOKEN"] = "1"
        self.assertFalse(engine_auth.is_token_required())
        unauth_client = TestClient(app, headers={"_dicty_no_auth": True})
        response = unauth_client.get("/models")
        self.assertEqual(response.status_code, 200)

    def test_dev_override_is_ignored_in_packaged_build(self):
        """A bundled engine must never honor DICTY_ALLOW_NO_TOKEN."""
        os.environ["DICTY_ALLOW_NO_TOKEN"] = "1"
        with patch.object(sys, "frozen", True, create=True):
            self.assertTrue(engine_auth.is_token_required())

    def test_internal_partial_self_call_with_auth_headers(self):
        """The internal /recording/internal/partial endpoint accepts auth_headers()."""
        client = TestClient(app, headers=engine_auth.auth_headers())
        response = client.post("/recording/internal/partial", json={"text": "hello test"})
        self.assertEqual(response.status_code, 200)

    def test_cleanup_token_on_shutdown(self):
        """cleanup_token() deletes file if PID matches, does not delete if PID differs."""
        token_path = os.path.join(dicty_paths.get_user_data_dir(), "engine.token")
        engine_auth.init_token("cleanup-test-token")
        self.assertTrue(os.path.isfile(token_path))

        # Change PID in file to simulate another process owning it
        with open(token_path, "w", encoding="utf-8") as f:
            json.dump({"token": "other", "pid": 99999999, "port": 8075}, f)

        engine_auth.cleanup_token()
        self.assertTrue(os.path.isfile(token_path), "Should not remove token file owned by another PID")

        # Restore matching PID and verify cleanup removes it
        with open(token_path, "w", encoding="utf-8") as f:
            json.dump({"token": "cleanup-test-token", "pid": os.getpid(), "port": 8075}, f)

        engine_auth.cleanup_token()
        self.assertFalse(os.path.isfile(token_path), "Must remove token file owned by our PID")

        # Re-initialize for remaining tests
        engine_auth.init_token(self.valid_token)


if __name__ == "__main__":
    unittest.main()
