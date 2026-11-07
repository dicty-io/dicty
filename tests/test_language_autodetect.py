import _bootstrap  # noqa: F401
import unittest
from unittest.mock import AsyncMock, patch, MagicMock
import os
import wave
from transcribe_service import TranscribeService, resolve_faster_whisper_model_name
from services.whisper_server import get_whisper_server_cmd
from services.pipeline import process_transcription


class TestLanguageAutoDetect(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.dummy_wav = "test_autodetect_dummy.wav"
        with wave.open(self.dummy_wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(16000)
            w.writeframes(b"\x00" * 32000)

    def tearDown(self):
        if os.path.exists(self.dummy_wav):
            os.remove(self.dummy_wav)

    def test_faster_whisper_model_resolution_autodetect(self):
        """When language is 'auto', resolve_faster_whisper_model_name must NEVER return English-only .en models."""
        # For 'base':
        self.assertEqual(resolve_faster_whisper_model_name("base", language="auto"), "base")
        self.assertEqual(resolve_faster_whisper_model_name("base", language="en"), "base.en")
        self.assertEqual(resolve_faster_whisper_model_name("base", language="ru"), "base")

        # For cloud models like deepgram/nova-3:
        self.assertNotIn(".en", resolve_faster_whisper_model_name("deepgram/nova-3", language="auto"))
        self.assertNotIn(".en", resolve_faster_whisper_model_name("deepgram/nova-3", language="ru"))

    def test_whisper_server_cmd_skipped_for_cloud_models(self):
        """Whisper server must not start with an English model when active model is a cloud model."""
        with patch("model_manager.ModelManager.get_active_model", return_value="deepgram/nova-3"):
            cmd = get_whisper_server_cmd()
            self.assertIsNone(cmd, "whisper-server should return None for cloud models like deepgram/nova-3")

    async def test_auto_detect_skips_english_vocabulary_prompt(self):
        """When language is 'auto' and vocab has only English/Latin words, prompt_str must be omitted to avoid English biasing."""
        ts = TranscribeService()
        english_vocab = [
            {"word": "FastAPI", "replacement": "FastAPI"},
            {"word": "Kubernetes", "replacement": "Kubernetes"},
        ]

        with patch.object(ts, "transcribe_remote", new_callable=AsyncMock) as mock_remote:
            mock_remote.return_value = "Привет мир"
            with patch("model_manager.ModelManager.get_active_model", return_value="deepgram/nova-3"):
                await ts.transcribe(
                    audio_path=self.dummy_wav,
                    vocab_data=english_vocab,
                    language="auto",
                    model_name="deepgram/nova-3",
                    provider="dicty_cloud"
                )

                self.assertTrue(mock_remote.called)
                call_args, call_kwargs = mock_remote.call_args
                # prompt_str is the 3rd positional argument or keyword argument
                prompt_arg = call_args[2] if len(call_args) > 2 else call_kwargs.get("prompt_str", "")
                self.assertEqual(prompt_arg, "", "English vocabulary prompt must be empty when language='auto'")

    async def test_specified_language_retains_vocabulary_prompt(self):
        """When language is 'en', English vocabulary prompt should be included."""
        ts = TranscribeService()
        english_vocab = [
            {"word": "FastAPI", "replacement": "FastAPI"},
            {"word": "Kubernetes", "replacement": "Kubernetes"},
        ]

        with patch.object(ts, "transcribe_remote", new_callable=AsyncMock) as mock_remote:
            mock_remote.return_value = "Hello world"
            with patch("model_manager.ModelManager.get_active_model", return_value="deepgram/nova-3"):
                await ts.transcribe(
                    audio_path=self.dummy_wav,
                    vocab_data=english_vocab,
                    language="en",
                    model_name="deepgram/nova-3",
                    provider="dicty_cloud"
                )

                self.assertTrue(mock_remote.called)
                call_args, call_kwargs = mock_remote.call_args
                prompt_arg = call_args[2] if len(call_args) > 2 else call_kwargs.get("prompt_str", "")
                self.assertIn("FastAPI", prompt_arg)

    async def test_deepgram_batch_detect_language_param(self):
        """Direct Deepgram calls should pass detect_language=true when language='auto'."""
        ts = TranscribeService()
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {
            "results": {
                "channels": [{"alternatives": [{"transcript": "Привет мир"}]}]
            }
        }

        with patch("httpx.AsyncClient.post", new_callable=AsyncMock) as mock_post:
            mock_post.return_value = mock_resp
            with patch.dict(os.environ, {"DEEPGRAM_API_KEY": "dg-test-key"}):
                res = await ts.transcribe_remote(
                    audio_path=self.dummy_wav,
                    model_name="deepgram/nova-3",
                    language="auto"
                )
                self.assertEqual(res, "Привет мир")
                call_args, _ = mock_post.call_args
                url = call_args[0]
                self.assertIn("detect_language=true", url)

    async def test_cloud_model_ignores_local_vad_pretranscribed_text(self):
        """In pipeline, if active model is cloud, pre_transcribed_text from local VAD stream must NOT be used."""
        with patch("transcribe_service.TranscribeService.transcribe", new_callable=AsyncMock) as mock_transcribe:
            mock_transcribe.return_value = "Привет, это распознавание через облако."
            with patch("services.pipeline.apply_self_correction", new_callable=AsyncMock) as mock_corr:
                mock_corr.side_effect = lambda text, **kw: text

                result = await process_transcription(
                    audio_path=self.dummy_wav,
                    mode="dictation",
                    dictation_format_style="raw",
                    model_id="deepgram/nova-3",
                    pre_transcribed_text="English hallucination from local base.en VAD stream",
                    pre_transcribed_provider=None,  # None means local VAD stream
                    language="auto",
                    is_incognito=True
                )

                self.assertTrue(mock_transcribe.called, "transcribe() should be called instead of using local VAD text")
                self.assertEqual(result.get("text"), "Привет, это распознавание через облако.")


if __name__ == "__main__":
    unittest.main()
