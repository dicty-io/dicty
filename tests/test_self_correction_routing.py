"""Self-correction routing: local rules vs cloud model, per mode ai_location."""
import _bootstrap  # noqa: F401
import asyncio
import os
import sys
import tempfile
import unittest
import unittest.mock
import wave

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


class SelfCorrectionRoutingTests(unittest.TestCase):
    def setUp(self):
        import dicty_engine
        self.engine = dicty_engine
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            with wave.open(f.name, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(b"\x00" * 32000)
            self.wav = f.name

    def tearDown(self):
        if os.path.exists(self.wav):
            os.remove(self.wav)

    def _run(self, spoken, *, correction_location, cloud_reply=None):
        async def mock_transcribe(path, *args, **kwargs):
            return spoken

        correction = unittest.mock.AsyncMock(return_value=cloud_reply or spoken)
        with unittest.mock.patch("dicty_engine.TranscribeService.transcribe", side_effect=mock_transcribe), \
             unittest.mock.patch("dicty_engine.apply_self_correction", correction), \
             unittest.mock.patch("dicty_engine.dictation_metrics.record", return_value="test"):
            res = asyncio.run(self.engine.process_transcription(
                audio_path=self.wav,
                mode="dictation",
                dictation_format_style="raw",
                enable_self_correction=True,
                correction_location=correction_location,
                is_incognito=True,
            ))
        return res, correction

    def test_local_uses_rules_and_never_calls_the_cloud(self):
        res, correction = self._run("um so I think the the plan works", correction_location="local")
        self.assertEqual(res["correction_path"], "local_rules")
        correction.assert_not_called()
        self.assertNotIn("um", res["text"])
        self.assertNotIn("the the", res["text"])

    def test_capabilities_vocabulary_is_accepted(self):
        # /capabilities reports "local_rules"; the engine must accept it.
        res, correction = self._run("um the the plan", correction_location="local_rules")
        self.assertEqual(res["correction_path"], "local_rules")
        correction.assert_not_called()

    def test_cloud_when_better_runs_rules_then_the_model(self):
        res, correction = self._run(
            "Send it Tuesday actually no send it Wednesday",
            correction_location="cloud_when_better",
            cloud_reply="Send it Wednesday",
        )
        correction.assert_called_once()
        self.assertEqual(res["correction_path"], "cloud")
        self.assertEqual(res["text"], "Send it Wednesday")

    def test_cloud_falls_back_to_rules_when_the_model_fails(self):
        async def boom(*args, **kwargs):
            return None

        async def mock_transcribe(path, *args, **kwargs):
            return "um the the report"

        with unittest.mock.patch("dicty_engine.TranscribeService.transcribe", side_effect=mock_transcribe), \
             unittest.mock.patch("dicty_engine.apply_self_correction", side_effect=boom), \
             unittest.mock.patch("dicty_engine.dictation_metrics.record", return_value="test"):
            res = asyncio.run(self.engine.process_transcription(
                audio_path=self.wav,
                mode="dictation",
                dictation_format_style="raw",
                enable_self_correction=True,
                correction_location="cloud_when_better",
                is_incognito=True,
            ))
        self.assertEqual(res["correction_path"], "local_rules")
        self.assertNotIn("the the", res["text"])

    def test_default_location_keeps_the_old_cloud_behaviour(self):
        res, correction = self._run("no filler here at all", correction_location=None)
        correction.assert_called_once()
        self.assertIn(res["correction_path"], ("none", "cloud"))

    def test_correction_off_does_nothing(self):
        async def mock_transcribe(path, *args, **kwargs):
            return "um the the report"

        correction = unittest.mock.AsyncMock()
        with unittest.mock.patch("dicty_engine.TranscribeService.transcribe", side_effect=mock_transcribe), \
             unittest.mock.patch("dicty_engine.apply_self_correction", correction), \
             unittest.mock.patch("dicty_engine.dictation_metrics.record", return_value="test"):
            res = asyncio.run(self.engine.process_transcription(
                audio_path=self.wav,
                mode="dictation",
                dictation_format_style="raw",
                enable_self_correction=False,
                correction_location="local",
                is_incognito=True,
            ))
        correction.assert_not_called()
        self.assertEqual(res["correction_path"], "none")


if __name__ == "__main__":
    unittest.main(verbosity=2)
