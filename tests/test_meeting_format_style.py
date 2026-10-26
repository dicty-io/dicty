import _bootstrap  # noqa: F401
import os
import sys
import unittest
from unittest.mock import patch, AsyncMock, MagicMock

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from dicty_engine import process_transcription, history_manager


class TestMeetingFormatStyle(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.created_record_ids = []

    def tearDown(self):
        for rid in self.created_record_ids:
            try:
                history_manager.delete_record(rid)
            except Exception:
                pass

    @patch("transcribe_service.TranscribeService.transcribe", new_callable=AsyncMock)
    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    async def test_meeting_mode_with_structured_note_generates_summary(self, mock_http_post, mock_transcribe):
        raw_transcript = "Lily, regarding development metrics at MRA, we haven't had updates in four days."
        mock_transcribe.return_value = raw_transcript

        mock_note = "## Meeting Outline\n- Postgres replication lag mitigation\n- Action items: create dedicated host"
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.raise_for_status = MagicMock()
        mock_resp.json.return_value = {
            "choices": [
                {"message": {"content": mock_note}}
            ]
        }
        mock_http_post.return_value = mock_resp

        result = await process_transcription(
            audio_path="test_audio.wav",
            mode="meeting",
            dictation_format_style="note",
            llm_provider="openai",
            llm_model="gpt-4o-mini",
            llm_api_key="sk-test-mock-key"
        )

        mock_transcribe.assert_called_once()
        mock_http_post.assert_called_once()
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["raw_text"], raw_transcript)
        self.assertEqual(result["summary"], mock_note)

        # Check that it was persisted properly in history
        history_records = history_manager.get_all()
        matching = [r for r in history_records if r.get("raw_text") == raw_transcript or r.get("text") == raw_transcript]
        self.assertTrue(len(matching) > 0)
        record = matching[0]
        self.created_record_ids.append(record["id"])

        self.assertEqual(record.get("summary"), mock_note)
        self.assertEqual(record.get("text"), raw_transcript)

    @patch("transcribe_service.TranscribeService.transcribe", new_callable=AsyncMock)
    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    async def test_meeting_mode_with_raw_formatting_skips_llm(self, mock_http_post, mock_transcribe):
        raw_transcript = "Plain meeting discussion without formatting."
        mock_transcribe.return_value = raw_transcript

        result = await process_transcription(
            audio_path="test_audio.wav",
            mode="meeting",
            dictation_format_style="raw"
        )

        mock_transcribe.assert_called_once()
        mock_http_post.assert_not_called()
        self.assertEqual(result["status"], "success")
        self.assertEqual(result["raw_text"], raw_transcript)
        self.assertIsNone(result.get("summary"))

        history_records = history_manager.get_all()
        matching = [r for r in history_records if r.get("text") == raw_transcript]
        self.assertTrue(len(matching) > 0)
        record = matching[0]
        self.created_record_ids.append(record["id"])
        self.assertIsNone(record.get("summary"))


if __name__ == "__main__":
    unittest.main()
