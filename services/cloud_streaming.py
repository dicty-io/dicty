"""
Cloud transcription while the user is still speaking.

Two strategies, chosen per model:

1. DeepgramLiveSession: true streaming. Raw PCM goes over a WebSocket to Deepgram's live API
   as it is captured; Deepgram returns finalized phrases on pauses. On stop we send `Finalize`
   and only the last fraction of a second remains to be processed.

2. SegmentedBatchSession: for providers that only accept whole files (OpenRouter and therefore
   Dicty Cloud, Groq, ElevenLabs batch, OpenAI whisper-1). Audio is cut ONLY at natural pauses
   and each finished phrase is transcribed in the background while the user keeps talking.
   Cutting at real pauses (not on a timer) keeps accuracy close to whole-file transcription.

Both are best-effort: `finalize()` returns None on any problem and the caller falls back to the
normal whole-file batch request on the saved WAV, so the worst case is today's latency, never lost text.

Threading: `feed()` is called from the recorder's audio worker thread and must never block it.
Network work runs on the engine's asyncio loop (passed in at creation).
"""
import asyncio
import io
import json
import threading
import time
import wave
from typing import List, Optional

import numpy as np

import transcribe_service as ts
from transcript_join import join_transcript_parts

TARGET_SR = 16000


def _to_pcm16(chunk: np.ndarray) -> bytes:
    a = np.asarray(chunk, dtype=np.float32).reshape(-1)
    return (np.clip(a, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()


def _resample_to_16k(audio: np.ndarray, sr: int) -> np.ndarray:
    if sr == TARGET_SR or len(audio) == 0:
        return audio
    try:
        import scipy.signal
        from math import gcd
        g = gcd(TARGET_SR, int(sr))
        return scipy.signal.resample_poly(audio, TARGET_SR // g, int(sr) // g).astype(np.float32)
    except Exception:
        x_old = np.linspace(0, 1, len(audio))
        x_new = np.linspace(0, 1, int(len(audio) * TARGET_SR / sr))
        return np.interp(x_new, x_old, audio).astype(np.float32)


def _wav_bytes(audio_16k: np.ndarray) -> bytes:
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(TARGET_SR)
        w.writeframes(_to_pcm16(audio_16k))
    return buf.getvalue()


def _ws_connect(url: str, headers: dict):
    """websockets >= 13 uses `additional_headers`; older versions use `extra_headers`."""
    import inspect
    import websockets
    kw = dict(open_timeout=5, ping_interval=10, max_size=None)
    params = inspect.signature(websockets.connect.__init__).parameters
    if "additional_headers" in params:
        return websockets.connect(url, additional_headers=headers, **kw)
    return websockets.connect(url, extra_headers=headers, **kw)


class StreamSession:
    """Interface used by the recorder (feed) and the engine (finalize/abort)."""
    label = "stream"

    def feed(self, chunk: np.ndarray) -> None: ...
    async def finalize(self, timeout: float) -> Optional[str]: ...
    def abort(self) -> None: ...


# ---------------------------------------------------------------------------
# 1. Deepgram live (true streaming)
# ---------------------------------------------------------------------------
class DeepgramLiveSession(StreamSession):
    def __init__(self, loop: asyncio.AbstractEventLoop, model: str, sample_rate: int,
                 language: str = "auto", keyterms: Optional[List[str]] = None,
                 relay_base_url: Optional[str] = None, relay_token: Optional[str] = None):
        """relay_base_url/relay_token: stream through the Dicty Cloud worker (server-side Deepgram key,
        billed to the Dicty account) instead of connecting to Deepgram with the user's own key."""
        self.relay_base_url = relay_base_url
        self.relay_token = relay_token
        self.loop = loop
        self.model = model
        self.sample_rate = int(sample_rate)
        self.language = language
        self.keyterms = [k for k in (keyterms or []) if k][:50]
        self.label = f"Dicty Cloud live ({model})" if relay_base_url else f"Deepgram live ({model})"
        self._queue: "asyncio.Queue[Optional[bytes]]" = asyncio.Queue()
        self._finals: List[str] = []
        self._failed = False
        self.auth_failed = False
        self._finalized = asyncio.Event()
        self._closed = False
        self._last_audio = time.monotonic()
        self._task = asyncio.run_coroutine_threadsafe(self._run(), loop)

    def feed(self, chunk: np.ndarray) -> None:
        if self._closed or self._failed:
            return
        data = _to_pcm16(chunk)
        try:
            self.loop.call_soon_threadsafe(self._queue.put_nowait, data)
        except RuntimeError:
            self._failed = True

    def _url(self, host: str) -> str:
        from urllib.parse import urlencode
        params = [("model", self.model), ("encoding", "linear16"), ("sample_rate", str(self.sample_rate)),
                  ("channels", "1"), ("smart_format", "true"), ("punctuate", "true"),
                  ("interim_results", "false"), ("endpointing", "300")]
        if self.language and self.language != "auto":
            params.append(("language", self.language))
        elif self.model.startswith("nova-3"):
            params.append(("language", "multi"))
        for k in self.keyterms:
            params.append(("keyterm", k))
        if self.relay_base_url:
            base = self.relay_base_url.rstrip("/").replace("https://", "wss://").replace("http://", "ws://")
            return f"{base}/v1/listen?{urlencode(params)}"
        return f"wss://{host}/v1/listen?{urlencode(params)}"

    async def _run(self):
        import websockets
        try:
            if self.relay_base_url:
                host, headers = "", {"Authorization": f"Bearer {self.relay_token}"}
            else:
                host = await asyncio.to_thread(ts._deepgram_host)
                headers = {"Authorization": f"Token {ts.get_stt_key('deepgram')}"}
            async with _ws_connect(self._url(host), headers) as ws:
                receiver = asyncio.create_task(self._receive(ws))
                while True:
                    try:
                        item = await asyncio.wait_for(self._queue.get(), timeout=4.0)
                    except asyncio.TimeoutError:
                        # Paused / muted: keep the socket open (Deepgram closes after ~10s without data)
                        await ws.send(json.dumps({"type": "KeepAlive"}))
                        continue
                    if item is None:
                        break
                    await ws.send(item)
                await ws.send(json.dumps({"type": "Finalize"}))
                try:
                    await asyncio.wait_for(self._finalized.wait(), timeout=3.0)
                finally:
                    try:
                        await ws.send(json.dumps({"type": "CloseStream"}))
                    except Exception:
                        pass
                    receiver.cancel()
        except Exception as e:
            if not self._closed:
                print(f"[!] Deepgram live stream failed: {e}")
            status = getattr(getattr(e, 'response', None), 'status_code', None) or getattr(e, 'status_code', None)
            if status in (401, 403) or "401" in str(e) or "Unauthorized" in str(e) or "INVALID_AUTH" in str(e):
                self.auth_failed = True
                hint = "Dicty Cloud token / login" if self.relay_base_url else "DEEPGRAM_API_KEY in Dicty Settings"
                print(f"[!] [CLOUD AUTH ERROR] Authentication failed ({status or 401}). Please check your {hint}.")
            self._failed = True
            self._finalized.set()

    async def _receive(self, ws):
        try:
            async for raw in ws:
                if isinstance(raw, bytes):
                    continue
                msg = json.loads(raw)
                if msg.get("type") != "Results":
                    continue
                alt = (msg.get("channel", {}).get("alternatives") or [{}])[0]
                text = (alt.get("transcript") or "").strip()
                if msg.get("is_final") and text:
                    self._finals.append(text)
                if msg.get("from_finalize"):
                    self._finalized.set()
        except Exception:
            pass
        finally:
            self._finalized.set()

    async def finalize(self, timeout: float = 2.0) -> Optional[str]:
        self._queue.put_nowait(None)
        try:
            await asyncio.wait_for(self._finalized.wait(), timeout=timeout)
        except asyncio.TimeoutError:
            print("[!] Deepgram live finalize timed out")
            self._failed = True
        self._closed = True
        if self._failed:
            return None
        return join_transcript_parts(self._finals, separate_responses=True)

    def abort(self) -> None:
        self._closed = True
        try:
            self.loop.call_soon_threadsafe(self._queue.put_nowait, None)
        except RuntimeError:
            pass


# ---------------------------------------------------------------------------
# 2. Pause-segmented batch (OpenRouter / Dicty Cloud / Groq / ElevenLabs / OpenAI)
# ---------------------------------------------------------------------------
class SegmentedBatchSession(StreamSession):
    MIN_SEGMENT_S = 3.0        # don't cut tiny fragments (hurts accuracy, costs requests)
    MAX_SEGMENT_S = 25.0       # stay under per-request limits; cut at the quietest recent point
    PAUSE_S = 0.6              # a real pause between phrases
    FRAME_S = 0.03

    def __init__(self, loop: asyncio.AbstractEventLoop, model: str, sample_rate: int, *,
                 provider: str, language: str = "auto", prompt: str = ""):
        self.loop = loop
        self.model = model
        self.sample_rate = int(sample_rate)
        self.provider = provider
        self.language = language
        self.prompt = prompt
        self.label = f"Segmented cloud ({model})"
        self._buf: List[np.ndarray] = []
        self._buf_len = 0
        self._silent_run = 0
        self._noise_floor = 0.003
        self._futures: List["asyncio.Future"] = []
        self._lock = threading.Lock()
        self._closed = False
        self.segments_sent = 0

    # -- called from the audio worker thread; cheap, never blocks --
    def feed(self, chunk: np.ndarray) -> None:
        if self._closed:
            return
        a = np.asarray(chunk, dtype=np.float32).reshape(-1)
        with self._lock:
            self._buf.append(a)
            self._buf_len += len(a)
            rms = float(np.sqrt(np.mean(a * a))) if len(a) else 0.0
            if rms < self._noise_floor * 1.5 + 0.002:
                self._silent_run += len(a)
                self._noise_floor = 0.95 * self._noise_floor + 0.05 * rms
            else:
                self._silent_run = 0
            seg_s = self._buf_len / self.sample_rate
            pause_s = self._silent_run / self.sample_rate
            if (seg_s >= self.MIN_SEGMENT_S and pause_s >= self.PAUSE_S) or seg_s >= self.MAX_SEGMENT_S:
                audio = np.concatenate(self._buf)
                self._buf, self._buf_len, self._silent_run = [], 0, 0
            else:
                return
        self._submit(audio)

    def _submit(self, audio_native: np.ndarray) -> None:
        idx = self.segments_sent
        self.segments_sent += 1
        fut = asyncio.run_coroutine_threadsafe(self._transcribe(audio_native, idx), self.loop)
        self._futures.append(fut)

    async def _transcribe(self, audio_native: np.ndarray, idx: int) -> str:
        audio = _resample_to_16k(audio_native, self.sample_rate)
        # Skip pure-silence segments (would only invite hallucinations)
        if len(audio) == 0 or float(np.sqrt(np.mean(audio * audio))) < 0.004:
            return ""
        audio = np.concatenate([audio, np.zeros(int(0.2 * TARGET_SR), dtype=np.float32)])
        import tempfile, os
        fd, path = tempfile.mkstemp(suffix=".wav", prefix=f"dicty_seg{idx}_")
        try:
            with os.fdopen(fd, "wb") as f:
                f.write(await asyncio.to_thread(_wav_bytes, audio))
            svc = ts.TranscribeService()
            t0 = time.perf_counter()
            text = await svc.transcribe_remote(path, self.model, self.prompt, self.language,
                                               openrouter_key=ts.get_stt_key("openrouter"),
                                               provider=self.provider)
            print(f"[*] Segment {idx} ({len(audio)/TARGET_SR:.1f}s) transcribed in {(time.perf_counter()-t0)*1000:.0f} ms")
            return (text or "").strip()
        finally:
            try:
                os.remove(path)
            except Exception:
                pass

    async def finalize(self, timeout: float = 15.0) -> Optional[str]:
        self._closed = True
        with self._lock:
            tail = np.concatenate(self._buf) if self._buf else None
            self._buf, self._buf_len = [], 0
        if tail is not None and len(tail) > int(0.2 * self.sample_rate):
            self._submit(tail)
        if not self._futures:
            return None
        try:
            results = await asyncio.wait_for(
                asyncio.gather(*[asyncio.wrap_future(f) for f in self._futures]), timeout=timeout)
        except Exception as e:
            print(f"[!] Segmented transcription failed ({e}); falling back to whole-file request")
            return None
        return join_transcript_parts(results, separate_responses=True)

    def abort(self) -> None:
        self._closed = True
        for f in self._futures:
            f.cancel()


def dicty_cloud_url() -> str:
    import os
    return os.getenv("DICTY_CLOUD_URL", "https://dicty-backend.dicty-backend.workers.dev")


def dicty_cloud_token() -> Optional[str]:
    try:
        import auth
        session = auth.SecureAuthManager.get_session()
        return (session or {}).get("jwt_token") or None
    except Exception:
        return None


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------
def create_session(loop: asyncio.AbstractEventLoop, model_id: str, sample_rate: int, *,
                   route_provider: str, language: str, vocab_words: List[str]) -> Optional[StreamSession]:
    """Returns a session for cloud models, or None (local models, or no usable credentials)."""
    if model_id.startswith("deepgram/"):
        model = model_id.split("/", 1)[1]
        if ts.get_stt_key("deepgram"):
            # User's own key: straight to Deepgram (nearest region)
            return DeepgramLiveSession(loop, model, sample_rate, language=language, keyterms=vocab_words)
        token = dicty_cloud_token() if route_provider == "dicty_cloud" else None
        if token:
            # Dicty Cloud: live relay through the Dicty worker (server-side key, billed to the account)
            return DeepgramLiveSession(loop, model, sample_rate, language=language, keyterms=vocab_words,
                                       relay_base_url=dicty_cloud_url(), relay_token=token)
    if "/" not in model_id:
        return None  # local whisper.cpp model
    own = ts.direct_provider_for_model(model_id)
    has_route = ((own and ts.get_stt_key(own))
                 or (route_provider == "dicty_cloud" and dicty_cloud_token())
                 or ts.get_stt_key("openrouter"))
    if not has_route:
        return None
    prompt = ", ".join(vocab_words[:25]) if vocab_words else ""
    return SegmentedBatchSession(loop, model_id, sample_rate, provider=route_provider,
                                 language=language, prompt=prompt)
