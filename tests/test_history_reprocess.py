import _bootstrap  # noqa: F401
import os
import sys
import unittest
from unittest.mock import patch, AsyncMock
import uuid

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi.testclient import TestClient
from dicty_engine import app, history_manager


class TestHistoryReprocess(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def setUp(self):
        self.test_id = str(uuid.uuid4())
        self.dummy_record = {
            "id": self.test_id,
            "timestamp": "2026-09-02T12:00:00+00:00",
            "text": "Hey team we need to finish the deployment today by 5 PM.",
            "mode": "dictation",
            "audio_file": f"/tmp/test_audio_{self.test_id}.wav",
            "speaking_wpm": 120,
            "engine_wpm": 450,
            "credits_used": 0
        }
        history_manager.add_record(self.dummy_record)

    def tearDown(self):
        history_manager.delete_record(self.test_id)
        if os.path.exists(self.dummy_record["audio_file"]):
            os.remove(self.dummy_record["audio_file"])

    def test_reprocess_404_for_unknown_id(self):
        resp = self.client.post("/history/reprocess/non-existent-id", json={
            "mode": "dictation",
            "format_style": "raw"
        })
        self.assertEqual(resp.status_code, 404)

    def test_reprocess_fast_reformat_with_custom_prompt(self):
        mock_llm_response = "• Team deployment deadline: 5 PM today."
        with patch("llm_service.LLMService.generate", new_callable=AsyncMock) as mock_gen:
            mock_gen.return_value = mock_llm_response
            resp = self.client.post(f"/history/reprocess/{self.test_id}", json={
                "mode": "meeting",
                "format_style": "custom",
                "custom_prompt": "Convert into concise bullet points",
                "retranscribe_audio": False
            })
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertEqual(data["status"], "success")
            self.assertEqual(data["record"]["text"], mock_llm_response)
            self.assertEqual(data["record"]["mode"], "meeting")
            self.assertIn("reprocessed_at", data["record"])

    def test_reprocess_missing_audio_file_returns_400(self):
        resp = self.client.post(f"/history/reprocess/{self.test_id}", json={
            "mode": "dictation",
            "format_style": "raw",
            "retranscribe_audio": True
        })
        self.assertEqual(resp.status_code, 400)
        self.assertIn("Audio file no longer exists", resp.json()["detail"])

    def test_reprocess_full_retranscribe_with_existing_audio(self):
        # Create dummy audio file
        with open(self.dummy_record["audio_file"], "w") as f:
            f.write("DUMMY AUDIO CONTENT")

        with patch("services.pipeline.process_transcription", new_callable=AsyncMock) as mock_trans:
            mock_trans.return_value = {"status": "success", "text": "New transcription"}
            resp = self.client.post(f"/history/reprocess/{self.test_id}", json={
                "mode": "dictation",
                "format_style": "note",
                "retranscribe_audio": True
            })
            self.assertEqual(resp.status_code, 200)
            self.assertEqual(resp.json()["status"], "success")
            mock_trans.assert_called_once()
            _, kwargs = mock_trans.call_args
            self.assertEqual(kwargs.get("existing_record_id"), self.test_id)


if __name__ == "__main__":
    unittest.main()
