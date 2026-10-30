import _bootstrap  # noqa: F401
import unittest
import os
import sys
import numpy as np
import soundfile as sf
import tempfile
import asyncio
from unittest.mock import patch, MagicMock, AsyncMock
from fastapi.testclient import TestClient

from audio_recorder import AudioRecorder
import dicty_engine
from dicty_engine import app
from services.audio import mix_audio
from services.paths import SYSTEM_AUDIO_PATH, AUDIO_PATH

class TestWasapiLoopbackRecording(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.temp_dir = tempfile.mkdtemp()
        self.test_mic_wav = os.path.join(self.temp_dir, "test_mic.wav")
        self.test_sys_wav = os.path.join(self.temp_dir, "test_sys.wav")
        self.test_out_wav = os.path.join(self.temp_dir, "test_mixed.wav")

        sr = 16000
        # Generate 1 sec sine tone for mic (440Hz)
        t = np.linspace(0, 1.0, sr, endpoint=False)
        mic_data = (0.2 * np.sin(2 * np.pi * 440 * t) * 32767).astype(np.int16)
        sf.write(self.test_mic_wav, mic_data, sr, subtype='PCM_16')

        # Generate 1 sec sine tone for system/Zoom (880Hz)
        sys_data = (0.3 * np.sin(2 * np.pi * 880 * t) * 32767).astype(np.int16)
        sf.write(self.test_sys_wav, sys_data, sr, subtype='PCM_16')

    def tearDown(self):
        for path in [self.test_mic_wav, self.test_sys_wav, self.test_out_wav]:
            if os.path.exists(path):
                try: os.remove(path)
                except: pass
        if os.path.exists(self.temp_dir):
            try: os.rmdir(self.temp_dir)
            except: pass

    def test_recorder_mode_configuration(self):
        recorder = AudioRecorder()
        with patch.object(recorder, '_udp_worker'), \
             patch('sounddevice.InputStream'), \
             patch('threading.Thread'):
            
            # Meeting mode on Windows should enable loopback capture
            with patch('sys.platform', 'win32'):
                recorder.start(mode="meeting")
                self.assertTrue(recorder.capture_loopback)
                recorder.is_recording = False

            # Dictation mode should NOT enable loopback capture
            with patch('sys.platform', 'win32'):
                recorder.start(mode="dictation")
                self.assertFalse(recorder.capture_loopback)
                recorder.is_recording = False

            # Librarian mode should NOT enable loopback capture (microphone only)
            with patch('sys.platform', 'win32'):
                recorder.start(mode="librarian")
                self.assertFalse(recorder.capture_loopback)
                recorder.is_recording = False

    def test_loopback_audio_save_on_stop(self):
        recorder = AudioRecorder()
        recorder.is_recording = True
        recorder.capture_loopback = True
        
        # Simulate captured loopback chunks from speaker (e.g. Zoom voices)
        sr = 16000
        chunk1 = np.ones((1600, 1), dtype=np.float32) * 0.1
        chunk2 = np.ones((1600, 1), dtype=np.float32) * 0.2
        recorder.loopback_chunks = [chunk1, chunk2]
        
        # Simulate mic chunks
        recorder.full_audio_history = [chunk1, chunk2]
        
        out_mic = os.path.join(self.temp_dir, "out_mic.wav")
        out_sys = os.path.join(self.temp_dir, "out_sys.wav")
        
        try:
            success = recorder.stop(out_mic, loopback_output_path=out_sys, use_vad_streaming=False)
            self.assertTrue(success)
            self.assertTrue(os.path.exists(out_sys))
            self.assertGreater(os.path.getsize(out_sys), 100)
            
            # Verify loopback data saved properly
            data, rate = sf.read(out_sys)
            self.assertEqual(rate, 16000)
            self.assertGreater(len(data), 3200) # Includes padding
        finally:
            if os.path.exists(out_mic): os.remove(out_mic)
            if os.path.exists(out_sys): os.remove(out_sys)

    def test_mix_audio_combines_system_and_mic(self):
        mix_audio(self.test_sys_wav, self.test_mic_wav, self.test_out_wav)
        self.assertTrue(os.path.exists(self.test_out_wav))
        self.assertGreater(os.path.getsize(self.test_out_wav), 100)

        data, rate = sf.read(self.test_out_wav)
        self.assertEqual(rate, 16000)
        self.assertEqual(len(data), 16000)
        # Check that mixed audio has non-zero amplitude
        self.assertGreater(np.max(np.abs(data)), 0.1)

    def test_stop_recording_meeting_mode_mixes_system_audio(self):
        # Place test system loopback and mic audio at engine paths
        shutil = __import__('shutil')
        shutil.copy2(self.test_sys_wav, SYSTEM_AUDIO_PATH)
        shutil.copy2(self.test_mic_wav, AUDIO_PATH)

        dicty_engine.recorder.is_recording = True
        dicty_engine.recorder.recording_mode = "meeting"

        with patch("services.pipeline.process_transcription", new_callable=AsyncMock) as mock_process:
            mock_process.return_value = {"text": "Speaker 1: Browser Zoom voice heard", "status": "ok"}
            
            # Stop meeting recording
            response = self.client.post("/recording/stop", data={"mode": "meeting"})
            self.assertEqual(response.status_code, 200)

            # Check that process_transcription was called with mixed audio
            self.assertTrue(mock_process.called)
            called_audio_path = mock_process.call_args[0][0]
            called_mode = mock_process.call_args[0][1]
            self.assertEqual(called_mode, "meeting")
            # In meeting mode with default separation ('you_others'), system audio is primary audio_path,
            # mic is mic_audio_path, and mixed audio is passed via mixed_audio_path kwarg
            self.assertEqual(called_audio_path, SYSTEM_AUDIO_PATH)
            self.assertEqual(mock_process.call_args[1].get("mic_audio_path"), AUDIO_PATH)
            self.assertIn("mixed_", mock_process.call_args[1].get("mixed_audio_path", ""))

    def test_stop_recording_meeting_mode_speaker_separation_off_mixes_system_audio(self):
        shutil = __import__('shutil')
        shutil.copy2(self.test_sys_wav, SYSTEM_AUDIO_PATH)
        shutil.copy2(self.test_mic_wav, AUDIO_PATH)

        dicty_engine.recorder.is_recording = True
        dicty_engine.recorder.recording_mode = "meeting"

        with patch("services.pipeline.process_transcription", new_callable=AsyncMock) as mock_process:
            mock_process.return_value = {"text": "Speaker 1: Browser Zoom voice heard", "status": "ok"}
            
            # Stop meeting recording with separation turned off
            response = self.client.post("/recording/stop", data={"mode": "meeting", "speaker_separation": "off"})
            self.assertEqual(response.status_code, 200)

            self.assertTrue(mock_process.called)
            called_audio_path = mock_process.call_args[0][0]
            called_mode = mock_process.call_args[0][1]
            self.assertEqual(called_mode, "meeting")
            # When speaker separation is off, target_audio is the mixed audio file
            self.assertIn("mixed_", called_audio_path)

    def test_selective_meeting_mode_uses_system_audio_only(self):
        shutil = __import__('shutil')
        shutil.copy2(self.test_sys_wav, SYSTEM_AUDIO_PATH)
        shutil.copy2(self.test_mic_wav, AUDIO_PATH)

        dicty_engine.recorder.is_recording = True
        dicty_engine.recorder.recording_mode = "meeting"

        with patch("services.pipeline.process_transcription", new_callable=AsyncMock) as mock_process:
            mock_process.return_value = {"text": "Speaker 2: Clean browser Zoom voice without mic", "status": "ok"}
            
            # Stop meeting recording with mic muted
            response = self.client.post("/recording/stop", data={"mode": "meeting", "mute_microphone": "true"})
            self.assertEqual(response.status_code, 200)

            self.assertTrue(mock_process.called)
            called_audio_path = mock_process.call_args[0][0]
            # When mic is muted, it should use SYSTEM_AUDIO_PATH directly without mic mixing
            self.assertEqual(called_audio_path, SYSTEM_AUDIO_PATH)

if __name__ == "__main__":
    unittest.main()
