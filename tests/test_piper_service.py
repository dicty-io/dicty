import _bootstrap  # noqa: F401
import unittest
import wave
import io
import os
from piper_service import PiperService, PIPER_VOICES_CONFIG
from tts_service import TTSService

class TestPiperService(unittest.TestCase):
    def setUp(self):
        self.service = PiperService()
        self.tts = TTSService()

    def test_piper_catalog(self):
        voices = self.service.get_supported_voices()
        self.assertGreaterEqual(len(voices), 4)
        langs = {v["lang"] for v in voices}
        self.assertIn("de", langs)
        self.assertIn("ru", langs)
        for v in voices:
            self.assertEqual(v["engine"], "piper")
            self.assertIn("name", v)
            self.assertIn("installed", v)

    def test_piper_german_synthesis(self):
        voice_id = "piper:de_DE-thorsten-medium"
        # Download if not present
        if not self.service.is_voice_installed(voice_id):
            print(f"Downloading {voice_id} for test...")
            ok = self.service.download_voice(voice_id)
            self.assertTrue(ok)
        self.assertTrue(self.service.is_voice_installed(voice_id))

        german_text = "Hallo, wie geht es dir? Dicty unterstützt jetzt Deutsch."
        wav_bytes = self.service.synthesize(german_text, voice_id=voice_id, speed=1.0)
        self.assertIsInstance(wav_bytes, bytes)
        self.assertGreater(len(wav_bytes), 44)

        # Validate WAV structure
        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 1)
            self.assertEqual(wf.getsampwidth(), 2)
            duration = wf.getnframes() / float(wf.getframerate())
            self.assertGreater(duration, 0.5)

    def test_piper_russian_synthesis(self):
        voice_id = "piper:ru_RU-dmitri-medium"
        # Download if not present
        if not self.service.is_voice_installed(voice_id):
            print(f"Downloading {voice_id} for test...")
            ok = self.service.download_voice(voice_id)
            self.assertTrue(ok)
        self.assertTrue(self.service.is_voice_installed(voice_id))

        russian_text = "Привет, мир! Теперь Dicty отлично синтезирует русскую речь."
        wav_bytes = self.service.synthesize(russian_text, voice_id=voice_id, speed=1.1)
        self.assertIsInstance(wav_bytes, bytes)
        self.assertGreater(len(wav_bytes), 44)

        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 1)
            self.assertEqual(wf.getsampwidth(), 2)
            duration = wf.getnframes() / float(wf.getframerate())
            self.assertGreater(duration, 0.5)

    def test_tts_service_piper_dispatch(self):
        voice_id = "piper:de_DE-thorsten-medium"
        wav_bytes = self.tts.synthesize(
            text="Guten Tag!",
            voice=voice_id,
            speed=1.0,
        )
        self.assertIsInstance(wav_bytes, bytes)
        self.assertGreater(len(wav_bytes), 44)

if __name__ == "__main__":
    unittest.main()
