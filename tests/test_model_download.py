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
        """Set up isolated temporary directories for models and settings."""
        self.tmp_data = tempfile.mkdtemp()
        self.patch_data = patch("services.model_manager.DATA_DIR", self.tmp_data)
        self.patch_models = patch("services.model_manager.MODELS_DIR", os.path.join(self.tmp_data, "models"))
        self.patch_settings = patch("services.model_manager.SETTINGS_FILE", os.path.join(self.tmp_data, "settings.json"))
        self.patch_data.start()
        self.patch_models.start()
        self.patch_settings.start()
        self.mm = ModelManager()

    def tearDown(self):
        """Clean up temporary test directory and stop environment patches."""
        self.patch_settings.stop()
        self.patch_models.stop()
        self.patch_data.stop()
        import shutil
        shutil.rmtree(self.tmp_data, ignore_errors=True)

    def test_prequantized_url_small_en(self):
        """Verify prequantized URL mapping selects q5_1 for small.en."""
        url, quality = self.mm._prequantized_url(
            "small.en",
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin",
            "q5_0"
        )
        self.assertEqual(quality, "q5_1")
        self.assertIn("ggml-small.en-q5_1.bin", url)

    def test_prequantized_url_non_quantized(self):
        """Verify non-quantized f16 quality retains base Hugging Face URL."""
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
                 patch.dict("sys.modules", {"faster_whisper": None}), \
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
                 patch.dict("sys.modules", {"faster_whisper": None}), \
                 patch("httpx.stream", side_effect=httpx.ConnectError("Network unreachable")):

                self.mm._download_worker(model_data, "q5_0", None, on_complete)

            self.assertEqual(self.mm.download_progress.get("small.en"), -1.0)
            self.assertNotIn("small.en", self.mm.downloading)
            self.assertTrue(completed and not completed[0])

    def test_download_worker_fallback_on_404(self):
        """Verify _download_worker falls back to base URL when pre-quantized URL returns 404."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            model_data = {
                "id": "tiny",
                "name": "Nano",
                "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                "size": "31 MB",
                "is_cloud": False
            }

            fake_chunks = [b"C" * 600_000, b"D" * 600_000]
            mock_success = MagicMock()
            mock_success.headers = {"content-length": "1200000"}
            mock_success.iter_bytes.return_value = fake_chunks
            mock_success.raise_for_status = MagicMock()

            req = httpx.Request("GET", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny-q5_1.bin")
            resp_404 = httpx.Response(404, request=req)

            stream_call_count = 0
            def mock_stream_side_effect(method, url, **kwargs):
                nonlocal stream_call_count
                stream_call_count += 1
                if "q5_1" in str(url):
                    mock_err = MagicMock()
                    mock_err.__enter__.side_effect = httpx.HTTPStatusError("Not Found", request=req, response=resp_404)
                    return mock_err
                mock_ok = MagicMock()
                mock_ok.__enter__.return_value = mock_success
                return mock_ok

            completed = []
            def on_complete(m_id, success):
                completed.append(success)

            with patch("services.model_manager.MODELS_DIR", tmp_dir), \
                 patch.object(self.mm, "MODELS_DIR", tmp_dir), \
                 patch("sys.platform", "darwin"), \
                 patch("platform.system", return_value="Darwin"), \
                 patch("httpx.stream", side_effect=mock_stream_side_effect), \
                 patch("subprocess.run", side_effect=OSError("quantization unavailable")), \
                 patch.object(self.mm, "set_model_quality") as mock_set_quality:

                self.mm._download_worker(model_data, "q5_0", None, on_complete)

            self.assertEqual(stream_call_count, 2)
            mock_set_quality.assert_called_once_with("tiny", "f16")
            dest_file = os.path.join(tmp_dir, "ggml-tiny.bin")
            self.assertTrue(os.path.exists(dest_file))
            self.assertEqual(self.mm.download_progress.get("tiny"), 100.0)
            self.assertTrue(completed and completed[0])

    def test_download_worker_missing_content_length(self):
        """Verify _download_worker handles chunked downloads without content-length header."""
        with tempfile.TemporaryDirectory() as tmp_dir:
            model_data = {
                "id": "tiny",
                "name": "Nano",
                "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin",
                "size": "Cloud",
                "is_cloud": False
            }

            fake_chunks = [b"X" * 600_000, b"Y" * 600_000]
            mock_response = MagicMock()
            mock_response.headers = {}  # missing content-length
            mock_response.iter_bytes.return_value = fake_chunks
            mock_response.raise_for_status = MagicMock()

            reports = []
            def on_progress(m_id, pct):
                reports.append(pct)

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
                self.mm._download_worker(model_data, "f16", on_progress, on_complete)

            dest_file = os.path.join(tmp_dir, "ggml-tiny.bin")
            self.assertTrue(os.path.exists(dest_file))
            self.assertEqual(self.mm.download_progress.get("tiny"), 100.0)
            self.assertTrue(len(reports) > 0)
            self.assertTrue(all(r < 100.0 for r in reports))
            self.assertEqual(reports, sorted(reports))
            self.assertTrue(completed and completed[0])

    def test_atomic_set_model_quality(self):
        """Verify set_model_quality writes atomically and updates quality dictionary."""
        self.mm.set_model_quality("tiny", "q5_1")
        self.assertEqual(self.mm.get_model_quality("tiny"), "q5_1")


if __name__ == "__main__":
    unittest.main()
