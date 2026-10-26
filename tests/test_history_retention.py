import _bootstrap  # noqa: F401
import os
import sys
import unittest
import json
import tempfile
from datetime import datetime, timedelta, timezone
import uuid
from unittest.mock import patch

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import dicty_engine
from fastapi.testclient import TestClient
from dicty_engine import app, history_manager


class TestHistoryRetentionAndTagging(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        # Create isolated temp files for history and retention settings
        self.temp_history_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        self.temp_history_file.write(b"[]")
        self.temp_history_file.close()

        self.temp_settings_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        self.temp_settings_file.write(json.dumps({
            "retention_period": "forever",
            "scrub_audio_immediately": False
        }).encode("utf-8"))
        self.temp_settings_file.close()

        self.orig_history_file = dicty_engine.HISTORY_FILE
        self.orig_settings_file = dicty_engine.RETENTION_CONFIG_FILE

        dicty_engine.HISTORY_FILE = self.temp_history_file.name
        dicty_engine.RETENTION_CONFIG_FILE = self.temp_settings_file.name

        self.test_id = str(uuid.uuid4())
        self.audio_path = f"/tmp/test_retention_{self.test_id}.wav"
        with open(self.audio_path, "w") as f:
            f.write("dummy audio")
        
        self.dummy_record = {
            "id": self.test_id,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "text": "Discussion on architecture and retention policies.",
            "mode": "dictation",
            "audio_file": self.audio_path,
            "speaking_wpm": 140,
            "engine_wpm": 600,
            "credits_used": 0,
            "title": None,
            "tags": []
        }
        history_manager.add_record(self.dummy_record)

    def tearDown(self):
        dicty_engine.HISTORY_FILE = self.orig_history_file
        dicty_engine.RETENTION_CONFIG_FILE = self.orig_settings_file

        if os.path.exists(self.temp_history_file.name):
            os.remove(self.temp_history_file.name)
        if os.path.exists(self.temp_settings_file.name):
            os.remove(self.temp_settings_file.name)
        if os.path.exists(self.audio_path):
            try:
                os.remove(self.audio_path)
            except Exception:
                pass

    def test_get_and_update_retention_settings(self):
        # GET retention settings
        resp = self.client.get("/history/settings/retention")
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("retention_period", data)
        self.assertIn("scrub_audio_immediately", data)

        # POST retention settings update
        resp2 = self.client.post("/history/settings/retention", json={
            "retention_period": "30d",
            "scrub_audio_immediately": True
        })
        self.assertEqual(resp2.status_code, 200)
        updated = resp2.json()["settings"]
        self.assertEqual(updated["retention_period"], "30d")
        self.assertTrue(updated["scrub_audio_immediately"])

    def test_patch_title_and_tags(self):
        # Update title and tags
        resp = self.client.patch(f"/history/{self.test_id}", json={
            "title": "Architecture Sync",
            "tags": ["Meeting", "#Sprint", " backend "]
        })
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["status"], "success")
        self.assertEqual(data["record"]["title"], "Architecture Sync")
        # Tags should be stripped of # and lowercased
        self.assertEqual(data["record"]["tags"], ["meeting", "sprint", "backend"])

        # Clear title by passing empty string
        resp2 = self.client.patch(f"/history/{self.test_id}", json={
            "title": ""
        })
        self.assertEqual(resp2.status_code, 200)
        self.assertIsNone(resp2.json()["record"]["title"])

    def test_patch_notes(self):
        # Update notes
        resp = self.client.patch(f"/history/{self.test_id}", json={
            "notes": "Discussed Q3 goals with Alice (VP Eng) and Bob (Lead Architect)."
        })
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertEqual(data["status"], "success")
        self.assertEqual(data["record"]["notes"], "Discussed Q3 goals with Alice (VP Eng) and Bob (Lead Architect).")

        # Clear notes with empty string
        resp2 = self.client.patch(f"/history/{self.test_id}", json={
            "notes": "   "
        })
        self.assertEqual(resp2.status_code, 200)
        self.assertIsNone(resp2.json()["record"]["notes"])

    def test_cleanup_retention_prunes_old_records(self):
        # Create an old record from 2 days ago
        old_id = str(uuid.uuid4())
        old_time = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat()
        old_audio = f"/tmp/old_audio_{old_id}.wav"
        with open(old_audio, "w") as f:
            f.write("old audio")
        
        history_manager.add_record({
            "id": old_id,
            "timestamp": old_time,
            "text": "Old note from 2 days ago",
            "mode": "dictation",
            "audio_file": old_audio,
            "speaking_wpm": 100,
            "engine_wpm": 500,
            "credits_used": 0
        })

        # Set retention to 24h
        history_manager.save_retention_settings({
            "retention_period": "24h",
            "scrub_audio_immediately": False
        })

        resp = self.client.post("/history/cleanup")
        self.assertEqual(resp.status_code, 200)
        res = resp.json()["result"]
        self.assertGreaterEqual(res["deleted_records"], 1)

        # Check that old record and old audio are gone from the isolated temp file
        all_ids = [r["id"] for r in history_manager.get_all()]
        self.assertNotIn(old_id, all_ids)
        self.assertFalse(os.path.exists(old_audio))

        # Recent test_id should still exist
        self.assertIn(self.test_id, all_ids)


if __name__ == "__main__":
    unittest.main()
