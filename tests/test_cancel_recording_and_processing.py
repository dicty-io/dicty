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
        """Test that cancel_active_processing cancels the registered task."""
        async def run_test():
            async def dummy_processing():
                await asyncio.sleep(10)

            task = asyncio.create_task(dummy_processing())
            register_processing_task(task)

            # Ensure task is registered
            self.assertFalse(task.done())

            # Cancel processing
            cancel_active_processing()
            self.assertTrue(task.cancelling() or task.cancelled())

            # Catch the CancelledError
            try:
                await task
            except asyncio.CancelledError:
                pass

            # Unregister task
            unregister_processing_task(task)
            self.assertTrue(task.cancelled())

        asyncio.run(run_test())

    def test_cancel_transcription_subprocess(self):
        """Test transcriber.cancel_active_transcription terminates running process."""
        mock_proc = MagicMock()
        mock_proc.poll.return_value = None

        transcriber._current_process = mock_proc
        transcriber.cancel_active_transcription()

        self.assertTrue(transcriber._is_cancelled)
        mock_proc.terminate.assert_called_once()
        transcriber._current_process = None


if __name__ == "__main__":
    unittest.main()
