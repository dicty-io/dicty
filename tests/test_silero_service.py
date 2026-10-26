import _bootstrap  # noqa: F401
import unittest
import os
import wave
import io
from silero_service import SileroService, SILERO_VOICES_CONFIG, SILERO_LANG_CONFIG

class TestSileroService(unittest.TestCase):
    def setUp(self):
        self.service = SileroService()

    def test_silero_catalog(self):
        voices = self.service.get_catalog_voices()
        self.assertTrue(len(voices) >= 10, f"Expected at least 10 voices, got {len(voices)}")
        ru_voices = [v for v in voices if v["lang"] == "ru"]
        de_voices = [v for v in voices if v["lang"] == "de"]
        self.assertTrue(len(ru_voices) >= 5, "Expected Russian voices in catalog")
        self.assertTrue(len(de_voices) >= 5, "Expected German voices in catalog")

    def test_silero_russian_synthesis(self):
        if not self.service.is_voice_installed("silero:ru_xenia"):
            self.skipTest("Silero ru model not downloaded, skipping audio synthesis test.")
        text = "Привет! Это проверка синтеза речи от Dicty через модель Silero."
        wav_bytes = self.service.synthesize(text=text, voice="silero:ru_xenia")
        self.assertTrue(len(wav_bytes) > 10000, "WAV bytes should be non-empty")
        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 1)
            self.assertEqual(wf.getsampwidth(), 2)
            self.assertEqual(wf.getframerate(), 48000)

    def test_silero_german_synthesis(self):
        if not self.service.is_voice_installed("silero:de_karlsson"):
            self.skipTest("Silero de model not downloaded, skipping audio synthesis test.")
        text = "Hallo! Das ist ein Test der Sprachsynthese mit Dicty über das Silero-Modell."
        wav_bytes = self.service.synthesize(text=text, voice="silero:de_karlsson")
        self.assertTrue(len(wav_bytes) > 10000, "WAV bytes should be non-empty")
        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 1)
            self.assertEqual(wf.getsampwidth(), 2)
            self.assertEqual(wf.getframerate(), 48000)

    def test_russian_text_normalization(self):
        from silero_service import normalize_text_for_silero
        raw = "В 1927 году в зоопарке было около 60 гектаров. Dicty работает на 100%!"
        norm = normalize_text_for_silero(raw, "ru")
        self.assertIn("тысяча девятьсот двадцать седьмом году", norm)
        self.assertIn("шестидесяти гектаров", norm)
        self.assertIn("Дикти", norm)
        self.assertIn("сто процентов", norm)

    def test_silero_user_sentence_synthesis(self):
        if not self.service.is_voice_installed("silero:ru_xenia"):
            self.skipTest("Silero ru model not downloaded, skipping audio synthesis test.")
        text = "Например, в Ростове-на-Дону работает знаменитый городской зоопарк, чья история началась в 1927 году. До него легко добраться из любой точки города. Сегодня Ростовский зоопарк — один из крупнейших зоопарков России и Европы. Его территория — около 60 гектаров."
        wav_bytes = self.service.synthesize(text=text, voice="silero:ru_xenia")
        self.assertTrue(len(wav_bytes) > 50000, "WAV bytes should be non-empty for full paragraph")
        with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
            self.assertEqual(wf.getnchannels(), 1)
            self.assertEqual(wf.getsampwidth(), 2)
            self.assertEqual(wf.getframerate(), 48000)
            duration = wf.getnframes() / float(wf.getframerate())
            # Paragraph with numbers normalized is ~16-17s
            self.assertGreater(duration, 14.0, f"Expected duration > 14s, got {duration:.2f}s")

if __name__ == "__main__":
    unittest.main()
