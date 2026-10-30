"""End-to-end snippet behavior through process_transcription (STT and LLM mocked)."""
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

import snippet_service

LINKEDIN_URL = "https://www.linkedin.com/in/john-doe/"


class SnippetPipelineTests(unittest.TestCase):
    def setUp(self):
        import dicty_engine
        self.engine = dicty_engine

        fd, self.store_path = tempfile.mkstemp(suffix=".json")
        os.close(fd)
        os.remove(self.store_path)
        self.store = snippet_service.SnippetsManager(self.store_path)
        self.store.add("my LinkedIn", LINKEDIN_URL)

        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
            with wave.open(f.name, "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(16000)
                w.writeframes(b"\x00" * 32000)
            self.wav = f.name

    def tearDown(self):
        for p in (self.wav, self.store_path):
            if os.path.exists(p):
                os.remove(p)

    def _run(self, spoken, self_correct=None):
        async def mock_transcribe(path, *args, **kwargs):
            return spoken

        correction = unittest.mock.AsyncMock(side_effect=self_correct) if self_correct else unittest.mock.AsyncMock()
        with unittest.mock.patch("services.pipeline.snippets_manager", self.store), \
             unittest.mock.patch("dicty_engine.TranscribeService.transcribe", side_effect=mock_transcribe), \
             unittest.mock.patch("services.pipeline.apply_self_correction", correction), \
             unittest.mock.patch("dicty_engine.dictation_metrics.record", return_value="test"):
            res = asyncio.run(self.engine.process_transcription(
                audio_path=self.wav,
                mode="dictation",
                dictation_format_style="raw",
                enable_self_correction=self_correct is not None,
                is_incognito=True,
            ))
        return res, correction

    def test_whole_utterance_returns_snippet_and_skips_llm(self):
        res, correction = self._run("My LinkedIn.", self_correct=lambda text, **kw: text)
        self.assertEqual(res["status"], "success")
        self.assertEqual(res["text"], LINKEDIN_URL)
        correction.assert_not_called()  # no LLM latency for a pure snippet

    def test_inline_cue_survives_self_correction(self):
        # LLM cleans up the sentence but keeps the placeholder (as instructed)
        def llm(text, **kw):
            return text.replace("uh, ", "")
        res, correction = self._run("Here is uh, insert my LinkedIn for you", self_correct=llm)
        correction.assert_called_once()
        sent_to_llm = correction.call_args.args[0]
        self.assertNotIn(LINKEDIN_URL, sent_to_llm)  # content never reaches the LLM
        self.assertEqual(res["text"], f"Here is {LINKEDIN_URL} for you")

    def test_llm_dropping_placeholder_falls_back_to_pre_llm_text(self):
        res, _ = self._run("Here is insert my LinkedIn for you", self_correct=lambda text, **kw: "Here it is for you")
        self.assertEqual(res["text"], f"Here is {LINKEDIN_URL} for you")

    def test_normal_dictation_untouched(self):
        res, _ = self._run("My LinkedIn profile needs an update soon.")
        self.assertEqual(res["text"], "My LinkedIn profile needs an update soon.")


if __name__ == "__main__":
    unittest.main()
