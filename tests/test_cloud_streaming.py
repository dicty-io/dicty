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


class DeepgramLiveStreamingTests(unittest.TestCase):
    def test_ssl_context_uses_certifi(self):
        ctx = cs._get_ssl_context()
        self.assertIsNotNone(ctx)

    def test_ws_connect_includes_ssl_for_wss(self):
        from unittest.mock import patch
        with patch("websockets.connect") as mock_connect:
            mock_connect.return_value = "mock_ws"
            _ = cs._ws_connect("wss://example.com/v1/listen", {"Authorization": "Bearer test"})
            mock_connect.assert_called_once()
            _, kwargs = mock_connect.call_args
            self.assertIn("ssl", kwargs)
            self.assertIsNotNone(kwargs["ssl"])

    def test_create_session_with_cloud_token(self):
        from unittest.mock import patch
        loop = asyncio.new_event_loop()
        try:
            with patch("cloud_streaming.dicty_cloud_token", return_value="fake_jwt_token"), \
                 patch("transcribe_service.get_stt_key", return_value=None):
                sess = cs.create_session(
                    loop, "deepgram/nova-3", 16000,
                    route_provider="dicty_cloud", language="auto", vocab_words=[]
                )
                self.assertIsNotNone(sess)
                self.assertIsInstance(sess, cs.DeepgramLiveSession)
                self.assertEqual(sess.relay_token, "fake_jwt_token")
                self.assertIsNotNone(sess.relay_base_url)
        finally:
            loop.close()

    def test_reconnects_on_mid_stream_drop_and_replays_unfinalized(self):
        import json
        from unittest.mock import patch

        sent_per_conn = []

        class FakeWS:
            def __init__(self, conn_idx):
                self.conn_idx = conn_idx
                self.sent = []
                sent_per_conn.append(self.sent)
                self._incoming = asyncio.Queue()
                self._closed = False

            async def __aenter__(self):
                return self

            async def __aexit__(self, *args):
                self._closed = True

            async def send(self, data):
                self.sent.append(data)
                if self.conn_idx == 0 and isinstance(data, bytes) and len(self.sent) == 2:
                    # First chunk was finalized; drop on second chunk
                    raise ConnectionError("no close frame received or sent")
                if isinstance(data, str):
                    msg = json.loads(data)
                    if msg.get("type") == "Finalize":
                        await self._incoming.put(json.dumps({
                            "type": "Results",
                            "is_final": True,
                            "from_finalize": True,
                            "start": 0.0,
                            "duration": 1.0,
                            "channel": {"alternatives": [{"transcript": "world"}]},
                        }))

            def __aiter__(self):
                return self

            async def __anext__(self):
                if self.conn_idx == 0 and not hasattr(self, "_emitted_first"):
                    self._emitted_first = True
                    return json.dumps({
                        "type": "Results",
                        "is_final": True,
                        "from_finalize": False,
                        "start": 0.0,
                        "duration": 1.0,
                        "channel": {"alternatives": [{"transcript": "Hello"}]},
                    })
                item = await self._incoming.get()
                if item is None:
                    raise StopAsyncIteration
                return item

        conn_count = 0

        def fake_connect(*args, **kwargs):
            nonlocal conn_count
            ws = FakeWS(conn_count)
            conn_count += 1
            return ws

        async def main():
            loop = asyncio.get_running_loop()
            with patch("cloud_streaming._ws_connect", side_effect=fake_connect):
                sess = cs.DeepgramLiveSession(
                    loop, "nova-3", 16000,
                    relay_base_url="https://example.workers.dev", relay_token="tok"
                )
                # 1.0s chunk (32000 bytes at 16kHz PCM16) -> finalized on conn 0
                sess.feed(np.zeros(16000, dtype=np.float32))
                await asyncio.sleep(0.05)
                # 0.5s chunk -> triggers drop on conn 0, must be replayed on conn 1
                sess.feed(np.ones(8000, dtype=np.float32) * 0.1)
                await asyncio.sleep(0.15)
                res = await sess.finalize(timeout=2.0)
                return sess, res

        sess, res = asyncio.run(main())
        self.assertFalse(sess._failed)
        self.assertEqual(conn_count, 2)
        self.assertEqual(res, "Hello world")
        # Conn 1 should replay only the 0.5s (16000 bytes) unfinalized chunk, not the 1.0s (32000 bytes) chunk
        replayed_bytes = [x for x in sent_per_conn[1] if isinstance(x, bytes)]
        self.assertEqual(len(replayed_bytes), 1)
        self.assertEqual(len(replayed_bytes[0]), 16000)

    def test_auth_failure_does_not_reconnect(self):
        from unittest.mock import patch
        calls = 0

        class AuthFailWS:
            async def __aenter__(self):
                nonlocal calls
                calls += 1
                raise RuntimeError("HTTP 401 Unauthorized")

            async def __aexit__(self, *args):
                pass

        async def main():
            loop = asyncio.get_running_loop()
            with patch("cloud_streaming._ws_connect", side_effect=lambda *a, **k: AuthFailWS()):
                sess = cs.DeepgramLiveSession(
                    loop, "nova-3", 16000,
                    relay_base_url="https://example.workers.dev", relay_token="bad"
                )
                await asyncio.sleep(0.05)
                res = await sess.finalize(timeout=1.0)
                return sess, res

        sess, res = asyncio.run(main())
        self.assertEqual(calls, 1)
        self.assertTrue(sess.auth_failed)
        self.assertTrue(sess._failed)
        self.assertIsNone(res)


if __name__ == "__main__":
    unittest.main()
