import _bootstrap  # noqa: F401
import asyncio
import os
import sys
import unittest

import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

import cloud_streaming as cs
import transcribe_service as ts

SR = 48000


def tone(seconds, amp=0.2):
    t = np.arange(int(seconds * SR)) / SR
    return (amp * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def silence(seconds):
    return np.zeros(int(seconds * SR), dtype=np.float32)


class SegmentedSessionTests(unittest.TestCase):
    def setUp(self):
        self.calls = []
        calls = self.calls

        async def fake_remote(svc, path, model, prompt="", language="auto", **kw):
            import soundfile as sf
            data, sr = sf.read(path)
            calls.append(round(len(data) / sr, 1))
            return f"seg{len(calls)}"

        self._orig = ts.TranscribeService.transcribe_remote
        ts.TranscribeService.transcribe_remote = fake_remote

    def tearDown(self):
        ts.TranscribeService.transcribe_remote = self._orig

    def _run(self, pieces, chunk_s=0.1):
        async def main():
            loop = asyncio.get_running_loop()
            s = cs.SegmentedBatchSession(loop, "nvidia/parakeet-tdt-0.6b-v3", SR, provider="openrouter")
            audio = np.concatenate(pieces)
            step = int(chunk_s * SR)

            def pump():
                for i in range(0, len(audio), step):
                    s.feed(audio[i:i + step])
            await asyncio.to_thread(pump)
            return s, await s.finalize(timeout=5)
        return asyncio.run(main())

    def test_cuts_only_at_pauses_and_keeps_order(self):
        s, text = self._run([tone(4), silence(0.8), tone(5), silence(0.8), tone(2)])
        self.assertEqual(s.segments_sent, 3)
        self.assertEqual(text, "seg1 seg2 seg3")

    def test_short_pause_inside_phrase_does_not_cut(self):
        # 0.3s breath pause < PAUSE_S: must stay one segment
        s, _ = self._run([tone(2), silence(0.3), tone(2)])
        self.assertEqual(s.segments_sent, 1)

    def test_no_cut_before_min_segment_length(self):
        s, _ = self._run([tone(1.5), silence(1.0), tone(1.5)])
        self.assertEqual(s.segments_sent, 1)

    def test_hard_cap_splits_long_monologue(self):
        s, _ = self._run([tone(cs.SegmentedBatchSession.MAX_SEGMENT_S + 5)])
        self.assertEqual(s.segments_sent, 2)

    def test_silent_segments_are_not_sent(self):
        s, text = self._run([silence(5)])
        self.assertEqual(self.calls, [])
        self.assertEqual(text, "")

    def test_failure_returns_none_for_batch_fallback(self):
        async def boom(*a, **k):
            raise RuntimeError("network down")
        ts.TranscribeService.transcribe_remote = boom
        _, text = self._run([tone(4), silence(0.8), tone(2)])
        self.assertIsNone(text)


class PostprocessTests(unittest.TestCase):
    def test_vocabulary_and_tag_cleanup(self):
        out = ts.postprocess_transcript("[BLANK_AUDIO] ask chat gpt", [{"word": "chat gpt", "replacement": "ChatGPT"}])
        self.assertEqual(out, "ask ChatGPT")


if __name__ == "__main__":
    unittest.main()
