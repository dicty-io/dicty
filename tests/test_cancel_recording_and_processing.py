import _bootstrap  # noqa: F401
import os
import sys
import unittest
import asyncio
from unittest.mock import MagicMock, patch

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi.testclient import TestClient
from dicty_engine import app
from services.state import (
    register_processing_task,
    unregister_processing_task,
    cancel_active_processing,
    transcriber,
    recorder,
)


class TestCancelRecordingAndProcessing(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.client = TestClient(app)

    def test_cancel_recording_endpoint(self):
        """Test POST /recording/cancel when recorder is idle."""
        with patch.object(recorder, "is_recording", False):
            resp = self.client.post("/recording/cancel")
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertEqual(data.get("status"), "cancelled")

    def test_cancel_recording_when_recording(self):
        """Test POST /recording/cancel when recording is active."""
        with patch.object(recorder, "is_recording", True), \
             patch.object(recorder, "stop") as mock_stop:
            resp = self.client.post("/recording/cancel")
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertEqual(data.get("status"), "cancelled")
            mock_stop.assert_called_once()

    def test_cancel_processing_task(self):
        """Test that cancel_active_processing cancels all registered tasks."""
        async def run_test():
            async def dummy_processing():
                await asyncio.sleep(10)

            task1 = asyncio.create_task(dummy_processing())
            task2 = asyncio.create_task(dummy_processing())
            register_processing_task(task1)
            register_processing_task(task2)

            # Ensure both tasks are registered
            self.assertFalse(task1.done())
            self.assertFalse(task2.done())

            # Unregistering task1 should NOT unregister task2
            unregister_processing_task(task1)

            # Cancel processing
            cancel_active_processing()
            self.assertTrue(task2.cancelling() or task2.cancelled())
            self.assertFalse(task1.cancelling() or task1.cancelled())

            # Clean up task1 as well
            task1.cancel()

            # Catch the CancelledError
            for t in (task1, task2):
                try:
                    await t
                except asyncio.CancelledError:
                    pass

            unregister_processing_task(task2)
            self.assertTrue(task2.cancelled())

        asyncio.run(run_test())

    def test_cancel_transcription_subprocess(self):
        """Test transcriber.cancel_active_transcription terminates running process."""
        mock_proc = MagicMock()
        mock_proc.poll.return_value = None

        transcriber._current_process = mock_proc
        transcriber.cancel_active_transcription()

        mock_proc.terminate.assert_called_once()
        transcriber._current_process = None

    def test_stop_recording_audio_file_path_validation(self):
        """Test that audio_file_path safely validates paths and rejects path traversal."""
        import tempfile

        # 1. Path traversal attempts should be safely rejected with 400
        resp = self.client.post("/recording/stop", data={"audio_file_path": "../../etc/passwd"})
        self.assertEqual(resp.status_code, 400)

        # 2. Legitimate audio file in temp directory is accepted
        with tempfile.NamedTemporaryFile(suffix=".wav", prefix="dicty_mic_test_", delete=False) as tf:
            tf.write(b"RIFF" + b"\x00" * 300)
            tf_path = tf.name

        try:
            with patch("routers.recording.pipeline.process_transcription") as mock_pipeline:
                mock_pipeline.return_value = {"status": "ok", "text": "test"}
                resp = self.client.post("/recording/stop", data={"audio_file_path": tf_path})
                self.assertEqual(resp.status_code, 200)
        finally:
            if os.path.exists(tf_path):
                os.remove(tf_path)

        # 3. Symlink pointing to audio file should be rejected
        symlink_path = os.path.join(tempfile.gettempdir(), "dicty_mic_test_symlink.wav")
        if os.path.islink(symlink_path) or os.path.exists(symlink_path):
            os.remove(symlink_path)
        with tempfile.NamedTemporaryFile(suffix=".wav", prefix="dicty_mic_real_", delete=False) as real_tf:
            real_tf.write(b"RIFF" + b"\x00" * 300)
            real_tf_path = real_tf.name
        try:
            os.symlink(real_tf_path, symlink_path)
            resp = self.client.post("/recording/stop", data={"audio_file_path": symlink_path})
            self.assertEqual(resp.status_code, 400)
        finally:
            if os.path.islink(symlink_path) or os.path.exists(symlink_path):
                os.remove(symlink_path)
            if os.path.exists(real_tf_path):
                os.remove(real_tf_path)


if __name__ == "__main__":
    unittest.main()
