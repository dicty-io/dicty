"""
tests/test_model_download.py
============================
Tests for model downloading, progress reporting, pre-quantized URLs,
and atomic file writing (.part -> final destination).
"""
import _bootstrap  # noqa: F401
import os
import tempfile
import unittest
from unittest.mock import MagicMock, patch
import httpx

from services.model_manager import ModelManager


class TestModelDownload(unittest.TestCase):
    def setUp(self):
        self.tmp_data = tempfile.mkdtemp()
        self.patch_data = patch("services.model_manager.DATA_DIR", self.tmp_data)
        self.patch_models = patch("services.model_manager.MODELS_DIR", os.path.join(self.tmp_data, "models"))
        self.patch_settings = patch("services.model_manager.SETTINGS_FILE", os.path.join(self.tmp_data, "settings.json"))
        self.patch_data.start()
        self.patch_models.start()
        self.patch_settings.start()
        self.mm = ModelManager()

    def tearDown(self):
        self.patch_settings.stop()
        self.patch_models.stop()
        self.patch_data.stop()
        import shutil
        shutil.rmtree(self.tmp_data, ignore_errors=True)

    def test_prequantized_url_small_en(self):
        url, quality = self.mm._prequantized_url(
            "small.en",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
            "q5_0"
        )
        self.assertEqual(quality, "q5_1")
        self.assertIn("ggml-small.en-q5_1.bin", url)

    def test_prequantized_url_non_quantized(self):
        url, quality = self.mm._prequantized_url(
            "small.en",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
            "f16"
        )
        self.assertIsNone(quality)
        self.assertEqual(url, "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin")

    def test_download_worker_atomic_file_creation(self):
        """Verify _download_worker streams chunks into .part and renames to final dest_path."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            model_data = {
                "id": "small.en",
                "name": "Fast",
                "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
                "is_cloud": False
            }

            fake_chunks = [b"A" * 600_000, b"B" * 600_000]
            total_size = sum(len(c) for c in fake_chunks)

            mock_response = MagicMock()
            mock_response.headers = {"content-length": str(total_size)}
            mock_response.iter_bytes.return_value = fake_chunks
            mock_response.raise_for_status = MagicMock()

            progress_reports = []
            def on_progress(m_id, pct):
                progress_reports.append(pct)

            completed = []
            def on_complete(m_id, success):
                completed.append(success)

            with patch("services.model_manager.MODELS_DIR", tmp_dir), \
                 patch.object(self.mm, "MODELS_DIR", tmp_dir), \
                 patch("sys.platform", "darwin"), \
                 patch("platform.system", return_value="Darwin"), \
                 patch("httpx.stream") as mock_stream, \
                 patch.object(self.mm, "set_model_quality"):

                mock_stream.return_value.__enter__.return_value = mock_response

                self.mm._download_worker(model_data, "q5_0", on_progress, on_complete)

            # Check that final destination file exists with the full content
            dest_file = os.path.join(tmp_dir, "ggml-small.en.bin")
            self.assertTrue(os.path.exists(dest_file))
            with open(dest_file, "rb") as f:
                self.assertEqual(f.read(), b"A" * 600_000 + b"B" * 600_000)

            # Check that .part file was removed/renamed
            self.assertFalse(os.path.exists(dest_file + ".part"))

            # Check that progress reached 100.0%
            self.assertEqual(self.mm.download_progress.get("small.en"), 100.0)
            self.assertTrue(completed and completed[0])

    def test_download_worker_error_handling(self):
        """Verify _download_worker handles network errors gracefully without crashing."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            model_data = {
                "id": "small.en",
                "name": "Fast",
                "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
                "is_cloud": False
            }

            completed = []
            def on_complete(m_id, success):
                completed.append(success)

            with patch("services.model_manager.MODELS_DIR", tmp_dir), \
                 patch.object(self.mm, "MODELS_DIR", tmp_dir), \
                 patch("sys.platform", "darwin"), \
                 patch("platform.system", return_value="Darwin"), \
                 patch("httpx.stream", side_effect=httpx.ConnectError("Network unreachable")):

                self.mm._download_worker(model_data, "q5_0", None, on_complete)

            self.assertEqual(self.mm.download_progress.get("small.en"), -1.0)
            self.assertNotIn("small.en", self.mm.downloading)
            self.assertTrue(completed and not completed[0])


if __name__ == "__main__":
    unittest.main()
