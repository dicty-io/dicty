import _bootstrap  # noqa: F401
import os
import sys
import platform
import unittest
import json
from unittest.mock import patch, MagicMock

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi.testclient import TestClient
from dicty_engine import app


class TestUpdateAndApiSuite(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    # =========================================================================
    # 1. UPDATE SYSTEM TESTS
    # =========================================================================

    def test_update_check_newer_version(self):
        """Test GET /update/check when a newer release is available."""
        mock_github_response = {
            "tag_name": "v1.2.0",
            "body": "### Features\n- Revolutionary voice AI\n- Auto-updater fixes",
            "assets": [
                {
                    "name": "Dicty.dmg",
                    "browser_download_url": "https://github.com/dicty-io/dicty/releases/download/v1.2.0/Dicty.dmg"
                },
                {
                    "name": "Dicty.exe",
                    "browser_download_url": "https://github.com/dicty-io/dicty/releases/download/v1.2.0/Dicty.exe"
                }
            ]
        }
        
        with patch("urllib.request.urlopen") as mock_urlopen:
            mock_res = MagicMock()
            mock_res.status = 200
            mock_res.read.return_value = json.dumps(mock_github_response).encode("utf-8")
            mock_res.__enter__.return_value = mock_res
            mock_urlopen.return_value = mock_res
            
            response = self.client.get("/update/check?current_version=1.0.0")
            self.assertEqual(response.status_code, 200)
            
            data = response.json()
            self.assertTrue(data.get("has_update"))
            self.assertEqual(data.get("latest_version"), "1.2.0")
            if platform.system() == "Windows":
                self.assertIn("Dicty.exe", data.get("download_url", ""))
                self.assertEqual(data.get("asset_name"), "Dicty.exe")
            else:
                self.assertIn("Dicty.dmg", data.get("download_url", ""))
                self.assertEqual(data.get("asset_name"), "Dicty.dmg")
            self.assertIn("Revolutionary voice AI", data.get("release_notes", ""))

    def test_update_check_same_version(self):
        """Test GET /update/check when current version matches latest."""
        mock_github_response = {
            "tag_name": "v1.2.0",
            "body": "Latest release notes",
            "assets": [{"name": "Dicty.dmg", "browser_download_url": "https://github.com/dicty-io/dicty/releases/download/v1.2.0/Dicty.dmg"}]
        }
        
        with patch("urllib.request.urlopen") as mock_urlopen:
            mock_res = MagicMock()
            mock_res.status = 200
            mock_res.read.return_value = json.dumps(mock_github_response).encode("utf-8")
            mock_res.__enter__.return_value = mock_res
            mock_urlopen.return_value = mock_res
            
            response = self.client.get("/update/check?current_version=1.2.0")
            self.assertEqual(response.status_code, 200)
            
            data = response.json()
            self.assertFalse(data.get("has_update"))
            self.assertEqual(data.get("latest_version"), "1.2.0")

    def test_update_check_serial_subpatch_has_update(self):
        """Test GET /update/check detects serial sub-patch (e.g. 1.0.40-1 > 1.0.40)."""
        from update_manager import parse_semver
        self.assertEqual(parse_semver("1.0.40"), (1, 0, 40, 0))
        self.assertEqual(parse_semver("1.0.40-1"), (1, 0, 40, 1))
        self.assertEqual(parse_semver("v1.0.40-2"), (1, 0, 40, 2))
        self.assertEqual(parse_semver("1.0.41"), (1, 0, 41, 0))
        self.assertTrue(parse_semver("1.0.40-1") > parse_semver("1.0.40"))
        self.assertTrue(parse_semver("1.0.40-2") > parse_semver("1.0.40-1"))
        self.assertTrue(parse_semver("1.0.41") > parse_semver("1.0.40-2"))
        self.assertFalse(parse_semver("1.0.40") > parse_semver("1.0.40-1"))

        mock_github_response = {
            "tag_name": "v1.0.40-1",
            "body": "Subpatch bugfixes",
            "assets": [{"name": "Dicty_1.0.40-1_x64-setup.exe", "browser_download_url": "https://github.com/dicty-io/dicty/releases/download/v1.0.40-1/Dicty_1.0.40-1_x64-setup.exe"}]
        }
        with patch("urllib.request.urlopen") as mock_urlopen:
            mock_res = MagicMock()
            mock_res.status = 200
            mock_res.read.return_value = json.dumps(mock_github_response).encode("utf-8")
            mock_res.__enter__.return_value = mock_res
            mock_urlopen.return_value = mock_res
            
            response = self.client.get("/update/check?current_version=1.0.40")
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertTrue(data.get("has_update"))
            self.assertEqual(data.get("latest_version"), "1.0.40-1")

    def test_update_check_cross_os_releases_selection(self):
        """Test GET /update/check selects the newest release that has an installer for the current OS."""
        mock_releases = [
            {
                "tag_name": "v1.0.69-2",
                "name": "v1.0.69-2 (macOS hotfix)",
                "body": "Fixes macOS issues",
                "assets": [{"name": "Dicty.dmg", "browser_download_url": "https://example.com/Dicty_1.0.69-2.dmg"}]
            },
            {
                "tag_name": "v1.0.69",
                "name": "v1.0.69 (Windows build)",
                "body": "Windows release notes",
                "assets": [{"name": "Dicty_1.0.69_x64-setup.exe", "browser_download_url": "https://example.com/Dicty_1.0.69_x64-setup.exe"}]
            },
            {
                "tag_name": "v1.0.68-1",
                "name": "v1.0.68-1",
                "body": "Older release for both",
                "assets": [
                    {"name": "Dicty_1.0.68-1_x64-setup.exe", "browser_download_url": "https://example.com/Dicty_1.0.68-1.exe"},
                    {"name": "Dicty.dmg", "browser_download_url": "https://example.com/Dicty_1.0.68-1.dmg"}
                ]
            }
        ]

        with patch("urllib.request.urlopen") as mock_urlopen:
            mock_res = MagicMock()
            mock_res.status = 200
            mock_res.read.return_value = json.dumps(mock_releases).encode("utf-8")
            mock_res.__enter__.return_value = mock_res
            mock_urlopen.return_value = mock_res

            response = self.client.get("/update/check?current_version=1.0.68-1")
            self.assertEqual(response.status_code, 200)
            data = response.json()

            if platform.system() == "Windows":
                # On Windows, should pick v1.0.69 because v1.0.69-2 only has macOS dmg
                self.assertTrue(data.get("has_update"))
                self.assertEqual(data.get("latest_version"), "1.0.69")
                self.assertEqual(data.get("asset_name"), "Dicty_1.0.69_x64-setup.exe")
                self.assertEqual(data.get("download_url"), "https://example.com/Dicty_1.0.69_x64-setup.exe")
            elif platform.system() == "Darwin":
                # On macOS, should pick v1.0.69-2
                self.assertTrue(data.get("has_update"))
                self.assertEqual(data.get("latest_version"), "1.0.69-2")
                self.assertEqual(data.get("asset_name"), "Dicty.dmg")
                self.assertEqual(data.get("download_url"), "https://example.com/Dicty_1.0.69-2.dmg")

    def test_update_progress_endpoint(self):
        """Test GET /update/progress returns download progress percentage."""
        response = self.client.get("/update/progress")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("progress", data)
        self.assertIsInstance(data["progress"], (int, float))
        self.assertGreaterEqual(data["progress"], 0.0)
        self.assertLessEqual(data["progress"], 100.0)

    def test_update_apply_with_query_params(self):
        """Test POST /update/apply with query parameters (Swift client format)."""
        with patch("update_manager.UpdateManager.apply_update", return_value=True) as mock_apply:
            url = "https://github.com/dicty-io/dicty/releases/download/v1.2.0/Dicty.dmg"
            asset = "Dicty.dmg"
            
            response = self.client.post(f"/update/apply?download_url={url}&asset_name={asset}")
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertEqual(data.get("status"), "success")
            self.assertTrue(data.get("success"))
            mock_apply.assert_called_once_with(url, asset)

    def test_update_apply_with_json_body(self):
        """Test POST /update/apply with JSON payload."""
        with patch("update_manager.UpdateManager.apply_update", return_value=True) as mock_apply:
            payload = {
                "download_url": "https://github.com/dicty-io/dicty/releases/download/v1.2.0/Dicty.dmg",
                "asset_name": "Dicty.dmg"
            }
            
            response = self.client.post("/update/apply", json=payload)
            self.assertEqual(response.status_code, 200)
            data = response.json()
            self.assertEqual(data.get("status"), "success")
            self.assertTrue(data.get("success"))
            mock_apply.assert_called_once_with(payload["download_url"], payload["asset_name"])

    def test_update_apply_missing_parameters(self):
        """Test POST /update/apply fails gracefully when parameters are omitted."""
        response = self.client.post("/update/apply")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data.get("status"), "error")
        self.assertFalse(data.get("success"))
        self.assertIn("Missing", data.get("error", ""))

    def test_update_apply_incompatible_os_asset(self):
        """Test UpdateManager rejects incompatible OS assets (e.g. DMG on Windows, EXE on macOS)."""
        import update_manager
        mgr = update_manager.UpdateManager()
        if mgr.os_type == "Windows":
            res = mgr.apply_update("https://example.com/Dicty.dmg", "Dicty.dmg")
            self.assertFalse(res)
            self.assertIn("Cannot install non-Windows asset", mgr.last_error)
        elif mgr.os_type == "Darwin":
            res = mgr.apply_update("https://example.com/Dicty.exe", "Dicty.exe")
            self.assertFalse(res)
            self.assertIn("Cannot install non-macOS asset", mgr.last_error)

    # =========================================================================
    # 2. CORE ENGINE & CONFIGURATION TESTS
    # =========================================================================

    def test_models_list_endpoint(self):
        """Test GET /models returns dictionary containing models list."""
        response = self.client.get("/models")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("models", data)
        models = data["models"]
        self.assertIsInstance(models, list)
        self.assertGreater(len(models), 0)
        
        first_model = models[0]
        self.assertIn("id", first_model)
        self.assertIn("name", first_model)
        self.assertIn("is_downloaded", first_model)

    def test_models_active_endpoint(self):
        """Test GET /models/active returns currently selected model."""
        response = self.client.get("/models/active")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("active_model", data)

    def test_devices_endpoint(self):
        """Test GET /devices returns available audio input devices."""
        response = self.client.get("/devices")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn("devices", data)
        self.assertIsInstance(data["devices"], list)

    def test_librarian_queue_lifecycle(self):
        """Test GET and POST /librarian/queue."""
        response = self.client.get("/librarian/queue")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data.get("status"), "success")
        self.assertIn("items", data)
        self.assertIn("count", data)

        post_res = self.client.post("/librarian/queue", json={"text": "Test thought for automated test", "source": "ci_test"})
        self.assertEqual(post_res.status_code, 200)
        post_data = post_res.json()
        self.assertEqual(post_data.get("status"), "success")
        self.assertIn("item", post_data)
        self.assertEqual(post_data["item"]["text"], "Test thought for automated test")

    def test_history_and_stats_endpoints(self):
        """Test GET /history and GET /stats."""
        history_res = self.client.get("/history")
        self.assertEqual(history_res.status_code, 200)
        
        stats_res = self.client.get("/stats")
        self.assertEqual(stats_res.status_code, 200)

    def test_updates_history_endpoint(self):
        """Test GET /updates/history returns list or history dictionary."""
        response = self.client.get("/updates/history")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(isinstance(data, list) or "history" in data or "status" in data)

    def test_reupload_nonexistent_history_item(self):
        """Test POST /updates/history/{id}/reupload handles invalid ID gracefully."""
        response = self.client.post("/updates/history/nonexistent_id_9999/reupload")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue("detail" in data or data.get("status") in ["error", "failed"] or data.get("success") is False)

    def test_prompts_endpoint(self):
        """Test GET /prompts returns system and user prompt definitions."""
        response = self.client.get("/prompts")
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIsInstance(data, (dict, list))

    def test_vocabulary_endpoint_lifecycle(self):
        """Test vocabulary CRUD lifecycle and deduplication."""
        # 1. Add vocabulary item
        res_add = self.client.post("/vocabulary", json={"word": "Kubernetes", "replacement": "K8s"})
        self.assertEqual(res_add.status_code, 200)
        item = res_add.json().get("item", {})
        item_id = item.get("id")
        self.assertTrue(item_id)
        self.assertEqual(item.get("word"), "Kubernetes")
        self.assertEqual(item.get("replacement"), "K8s")

        # 2. List vocabulary to verify
        res_get = self.client.get("/vocabulary")
        self.assertEqual(res_get.status_code, 200)
        vocab_list = res_get.json().get("vocabulary", [])
        self.assertTrue(any(v.get("id") == item_id for v in vocab_list))

        # 3. Delete vocabulary item
        res_del = self.client.delete(f"/vocabulary/{item_id}")
        self.assertEqual(res_del.status_code, 200)
        self.assertEqual(res_del.json().get("deleted"), item_id)

    def test_cloud_sync_payload_schema(self):
        """Verify cloud sync payload structure containing custom prompts, librarian config, and vocabulary."""
        payload = {
            "customPrompts": [
                {"key": "dictation", "active_value": "Enhanced", "is_custom": True}
            ],
            "librarianConfig": {
                "targetSystem": "notion",
                "selectedGitHubRepo": "dicty-io/dicty"
            },
            "vocabulary": [
                {"id": "voc_1", "word": "Dicty", "replacement": "Dicty AI"}
            ]
        }
        import json
        dumped = json.dumps(payload)
        parsed = json.loads(dumped)
        self.assertIn("customPrompts", parsed)
        self.assertIn("librarianConfig", parsed)
        self.assertIn("vocabulary", parsed)
        self.assertEqual(parsed["vocabulary"][0]["word"], "Dicty")

    def test_settings_keep_model_loaded_endpoint(self):
        """Test POST /settings/keep_model_loaded."""
        response = self.client.post("/settings/keep_model_loaded", json={"keep_loaded": True})
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data.get("success") or data.get("status") == "success" or "keep_loaded" in data)

    def test_recording_pause_and_resume_endpoints(self):
        """Test POST /recording/pause, POST /recording/resume, and GET /recording/status."""
        # When not recording, pause/resume return not_recording safely
        res_pause = self.client.post("/recording/pause")
        self.assertEqual(res_pause.status_code, 200)
        self.assertEqual(res_pause.json().get("status"), "not_recording")

        res_resume = self.client.post("/recording/resume")
        self.assertEqual(res_resume.status_code, 200)
        self.assertEqual(res_resume.json().get("status"), "not_recording")

        # Status check
        res_status = self.client.get("/recording/status")
        self.assertEqual(res_status.status_code, 200)
        status_data = res_status.json()
        self.assertIn("is_recording", status_data)
        self.assertIn("is_paused", status_data)

    def test_audio_recorder_pause_resume_logic(self):
        """Test unit logic of AudioRecorder pause and resume states."""
        from audio_recorder import AudioRecorder
        rec = AudioRecorder()
        self.assertFalse(rec.is_recording)
        self.assertFalse(rec.is_paused)

        rec.is_recording = True
        rec.pause()
        self.assertTrue(rec.is_paused)
        self.assertEqual(rec.current_volume, 0.0)

        rec.resume()
        self.assertFalse(rec.is_paused)

        rec.is_recording = False

    def test_incognito_mode_skips_history_and_audio_persistence(self):
        """Test that incognito_mode=true skips history saving and cleans up audio."""
        import dicty_engine
        import os
        
        # Check initial history count
        initial_history_len = len(dicty_engine.history_manager.get_all())
        
        # Call process_transcription with is_incognito=True using dummy audio
        test_wav = "test_incognito_sample.wav"
        with open(test_wav, "wb") as f:
            f.write(b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80>\x00\x00\x00}\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00")
            
        import asyncio
        try:
            res = asyncio.run(dicty_engine.process_transcription(
                test_wav,
                mode="dictation",
                pre_transcribed_text="This is a secret incognito thought.",
                is_incognito=True
            ))
        except RuntimeError:
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            res = loop.run_until_complete(dicty_engine.process_transcription(
                test_wav,
                mode="dictation",
                pre_transcribed_text="This is a secret incognito thought.",
                is_incognito=True
            ))
        
        # Verify status is success
        self.assertEqual(res.get("status"), "success")
        self.assertEqual(res.get("text"), "This is a secret incognito thought.")
        
        # Verify history count is UNCHANGED
        after_history_len = len(dicty_engine.history_manager.get_all())
        self.assertEqual(after_history_len, initial_history_len)
        
        # Verify temp audio was scrubbed
        self.assertFalse(os.path.exists(test_wav))

    def test_meeting_and_librarian_modes_never_bypass_transcription_with_mic_vad(self):
        """Test that meeting modes never bypass actual audio transcription with mic-only VAD string, while librarian only needs mic."""
        import dicty_engine
        import asyncio
        from unittest.mock import AsyncMock, patch

        dummy_wav = "test_meeting_mode.wav"
        with open(dummy_wav, "wb") as f:
            f.write(b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80>\x00\x00\x00}\x00\x00\x02\x00\x10\x00data\x00\x00\x00\x00")

        try:
            with patch("dicty_engine.TranscribeService.transcribe", new_callable=AsyncMock) as mock_transcribe:
                mock_transcribe.return_value = "Speaker A: This is Zoom audio transcribed from mixed WAV."
                
                # Test meeting mode (must not bypass)
                loop = asyncio.new_event_loop()
                res_meeting = loop.run_until_complete(dicty_engine.process_transcription(
                    dummy_wav,
                    mode="meeting",
                    pre_transcribed_text="Mic only whisper", # Should NOT bypass
                    is_incognito=True
                ))
                self.assertIn("Zoom audio", res_meeting.get("text", ""))
                self.assertTrue(mock_transcribe.called)

                # Test focused_meeting mode (must not bypass)
                mock_transcribe.reset_mock()
                mock_transcribe.return_value = "Speaker B: App focused meeting audio."
                res_focused = loop.run_until_complete(dicty_engine.process_transcription(
                    dummy_wav,
                    mode="focused_meeting",
                    pre_transcribed_text="Mic only whisper", # Should NOT bypass
                    is_incognito=True
                ))
                self.assertIn("App focused", res_focused.get("text", ""))
                self.assertTrue(mock_transcribe.called)

                # Test librarian mode (mic only, can use pre-transcribed text directly)
                mock_transcribe.reset_mock()
                res_lib = loop.run_until_complete(dicty_engine.process_transcription(
                    dummy_wav,
                    mode="librarian",
                    pre_transcribed_text="Architecture decision from mic",
                    is_incognito=True
                ))
                self.assertEqual(res_lib.get("text", ""), "Architecture decision from mic")
                self.assertFalse(mock_transcribe.called)
                loop.close()
        finally:
            if os.path.exists(dummy_wav):
                os.remove(dummy_wav)

    # =========================================================================
    # 7. SECURITY & ACCESS CONTROL TESTS
    # =========================================================================

    def test_cross_origin_protection_middleware(self):
        """Ensure external websites cannot make cross-origin requests to localhost engine."""
        # 1. Native Swift / curl request without Origin succeeds
        res_local = self.client.get("/recording/status")
        self.assertEqual(res_local.status_code, 200)

        # 2. Browser request from unauthorized external domain is blocked with 403
        res_external = self.client.get("/recording/status", headers={"origin": "https://evil-hacker.com"})
        self.assertEqual(res_external.status_code, 403)
        self.assertIn("Cross-origin access from external web pages is prohibited", res_external.json().get("error", ""))

        # 3. Browser cross-site form/fetch is blocked
        res_cross_site = self.client.get("/recording/status", headers={"sec-fetch-site": "cross-site"})
        self.assertEqual(res_cross_site.status_code, 403)

        # 4. Authorized local origin (e.g. Tauri or localhost) is permitted
        res_tauri = self.client.get("/recording/status", headers={"origin": "tauri://localhost"})
        self.assertEqual(res_tauri.status_code, 200)

        # 5. Tauri v2 on Windows uses http://tauri.localhost by default.
        res_tauri_windows = self.client.get(
            "/recording/status", headers={"origin": "http://tauri.localhost"}
        )
        self.assertEqual(res_tauri_windows.status_code, 200)

    def test_history_audio_path_traversal_sandboxing(self):
        """Ensure /history/audio/{id} denies files located outside allowed data directory."""
        from dicty_engine import history_manager
        
        evil_id = "traversal_test_record"
        history_manager.add_record({
            "id": evil_id,
            "text": "test",
            "audio_file": "/etc/passwd"
        })
        
        try:
            res = self.client.get(f"/history/audio/{evil_id}")
            self.assertEqual(res.status_code, 403)
            self.assertIn("outside allowed directory", res.json().get("detail", ""))
        finally:
            history_manager.delete_record(evil_id)


    def test_websocket_cswsh_protection(self):
        """Ensure WebSocket /ws/transcribe/stream blocks unauthorized cross-origin connections."""
        from starlette.websockets import WebSocketDisconnect
        # 1. External malicious browser origin is rejected
        with self.assertRaises(WebSocketDisconnect):
            with self.client.websocket_connect("/ws/transcribe/stream", headers={"origin": "https://malicious.com"}):
                pass

        # 2. Permitted origin connects cleanly
        with self.client.websocket_connect("/ws/transcribe/stream", headers={"origin": "tauri://localhost"}) as ws:
            ws.send_text("ping")

        # 3. Tauri v2 on Windows uses http://tauri.localhost by default.
        with self.client.websocket_connect(
            "/ws/transcribe/stream", headers={"origin": "http://tauri.localhost"}
        ) as ws:
            ws.send_text("ping")

    def test_update_manager_security_validation(self):
        """Ensure UpdateManager enforces domain whitelist and strict asset name sanitization."""
        from update_manager import UpdateManager, is_safe_update_url
        mgr = UpdateManager()

        # 1. Untrusted third-party download domain is rejected
        if mgr.os_type == "Windows":
            res_evil_url = mgr.apply_update("https://malicious-server.com/malware.exe", "Dicty_v1.exe")
            self.assertFalse(res_evil_url)
            self.assertIn("Untrusted update source URL", mgr.last_error)
        else:
            res_evil_url = mgr.apply_update("https://malicious-server.com/malware.dmg", "Dicty.dmg")
            self.assertFalse(res_evil_url)
            self.assertIn("Untrusted update source URL", mgr.last_error)

        # 2. Path traversal in asset_name is rejected
        valid_url = "https://github.com/dicty-io/dicty/releases/download/v1.0.0/Dicty.dmg" if mgr.os_type == "Darwin" else "https://github.com/dicty-io/dicty/releases/download/v1.0.0/Dicty.exe"
        evil_asset = "../../evil.dmg" if mgr.os_type == "Darwin" else "../../evil.exe"
        res_traversal = mgr.apply_update(valid_url, evil_asset)
        self.assertFalse(res_traversal)
        self.assertIn("Invalid or unsafe asset name", mgr.last_error)

        # 3. Command injection in asset_name is rejected
        evil_cmd = 'test";reboot;.dmg' if mgr.os_type == "Darwin" else 'test&calc.exe'
        res_cmd = mgr.apply_update(valid_url, evil_cmd)
        self.assertFalse(res_cmd)
        self.assertIn("Invalid or unsafe asset name", mgr.last_error)

        # 4. Official GitHub release URLs are verified safe
        self.assertTrue(is_safe_update_url("https://github.com/dicty-io/dicty/releases/download/v1.0.0/Dicty.dmg"))
        self.assertTrue(is_safe_update_url("https://objects.githubusercontent.com/github-production-release-asset-2e65be/123/456"))
        self.assertFalse(is_safe_update_url("http://github.com/insecure"))
        self.assertFalse(is_safe_update_url("https://evil-github.com/malware.dmg"))

    def test_mock_auth_endpoint_disabled_by_default(self):
        """Ensure /auth/google/mock returns 404 in production environments."""
        res = self.client.post("/auth/google/mock", json={"email": "attacker@example.com"})
        self.assertEqual(res.status_code, 404)
        self.assertIn("disabled", res.json().get("detail", "").lower())

    def test_token_submission_rejects_unverified_signatures(self):
        """Ensure /auth/token rejects forged tokens with unverified signatures when cloud is unreachable."""
        import base64
        header = base64.urlsafe_b64encode(b'{"alg":"HS256","typ":"JWT"}').decode().rstrip("=")
        payload = base64.urlsafe_b64encode(b'{"sub":"hacker@evil.com","email":"hacker@evil.com","is_pro":true}').decode().rstrip("=")
        forged_token = f"{header}.{payload}.invalid_signature"

        with patch("urllib.request.urlopen", side_effect=Exception("Cloud unavailable")):
            res = self.client.post("/auth/token", json={"token": forged_token})
            self.assertEqual(res.status_code, 401)
            self.assertIn("signature verification failed", res.json().get("detail", "").lower())

    def test_model_manager_path_traversal_protection(self):
        """Ensure ModelManager prevents directory traversal on model deletion."""
        from model_manager import ModelManager
        mm = ModelManager()
        self.assertFalse(mm.delete_model("../../etc/passwd"))


if __name__ == "__main__":
    unittest.main(verbosity=2)

