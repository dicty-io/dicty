import _bootstrap  # noqa: F401
import unittest
import os
import wave
import io
from tts_service import tts_service, VOICE_CATALOG

class TestTTSService(unittest.TestCase):
    def test_status_structure(self):
        status = tts_service.get_status()
        self.assertIn("installed", status)
        self.assertIn("engine", status)
        self.assertEqual(status["engine"], "kokoro_onnx")
        self.assertIn("voices", status)
        self.assertIsInstance(status["voices"], list)
        self.assertGreaterEqual(len(status["voices"]), 5)

    def test_voice_catalog_entries(self):
        for v in VOICE_CATALOG:
            self.assertIn("id", v)
            self.assertIn("name", v)
            self.assertIn("gender", v)
            self.assertIn("accent", v)
            self.assertIn("description", v)

    def test_synthesis_if_installed(self):
        if not tts_service.is_installed():
            self.skipTest("Kokoro model not downloaded, skipping audio synthesis test.")

        audio_bytes = tts_service.synthesize("Test phrase for Dicty TTS.", voice="af_heart", speed=1.0)
        self.assertIsInstance(audio_bytes, bytes)
        self.assertGreater(len(audio_bytes), 1000)

        # Validate that audio_bytes is a valid 24kHz WAV
        buffer = io.BytesIO(audio_bytes)
        with wave.open(buffer, "rb") as wav:
            self.assertEqual(wav.getnchannels(), 1)
            self.assertEqual(wav.getsampwidth(), 2) # 16-bit
            self.assertEqual(wav.getframerate(), 24000)
            self.assertGreater(wav.getnframes(), 0)

    def test_voice_blending_synthesis(self):
        if not tts_service.is_installed():
            self.skipTest("Kokoro model not downloaded, skipping audio synthesis test.")

        audio_bytes = tts_service.synthesize(
            text="Blended neural voice test.",
            voice="af_heart",
            blend_voice="bm_george",
            blend_ratio=0.35,
            speed=1.0
        )
        self.assertIsInstance(audio_bytes, bytes)
        self.assertGreater(len(audio_bytes), 1000)

        buffer = io.BytesIO(audio_bytes)
        with wave.open(buffer, "rb") as wav:
            self.assertEqual(wav.getnchannels(), 1)
            self.assertEqual(wav.getframerate(), 24000)
            self.assertGreater(wav.getnframes(), 0)

    def test_expressiveness_and_pacing(self):
        if not tts_service.is_installed():
            self.skipTest("Kokoro model not downloaded, skipping audio synthesis test.")

        audio_bytes = tts_service.synthesize(
            text="Testing expressiveness, with a comma; and a period.",
            voice="af_heart",
            expressiveness=0.25,
            sentence_pause=0.35,
            clause_pause=0.12,
            continuous=True
        )
        self.assertIsInstance(audio_bytes, bytes)
        self.assertGreater(len(audio_bytes), 1000)

        buffer = io.BytesIO(audio_bytes)
        with wave.open(buffer, "rb") as wav:
            self.assertEqual(wav.getnchannels(), 1)
            self.assertEqual(wav.getframerate(), 24000)

    def test_empty_text_validation(self):
        with self.assertRaises(ValueError):
            tts_service.synthesize("", voice="af_heart")

    def test_speak_endpoint_save_record(self):
        if not tts_service.is_installed():
            self.skipTest("Kokoro model not downloaded, skipping audio synthesis test.")

        from fastapi.testclient import TestClient
        from dicty_engine import app, history_manager

        client = TestClient(app)
        resp = client.post("/tts/speak", json={
            "text": "Testing history persistence for text to voice.",
            "voice": "af_heart",
            "save_record": True
        })
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.headers.get("content-type"), "audio/wav")
        record_id = resp.headers.get("x-record-id")
        self.assertIsNotNone(record_id)

        # Verify entry in history_manager
        records = history_manager.get_all()
        saved = next((r for r in records if r["id"] == record_id), None)
        self.assertIsNotNone(saved)
        self.assertEqual(saved["mode"], "tts")
        self.assertEqual(saved["voice"], "af_heart")
        self.assertIn("TTS", saved.get("tags", []))
        self.assertTrue(os.path.exists(saved["audio_file"]))

        # Cleanup test record
        history_manager.delete_record(record_id)

if __name__ == "__main__":
    unittest.main()
