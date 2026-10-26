"""
Dicty Text-to-Speech (TTS) Service
===================================
High-fidelity, local neural speech synthesis backed by a unified ONNX Runtime.
Powers Kokoro-82M with instantaneous streaming playback and human-grade cadence.
"""

import os
import io
import sys
import wave
import json
import logging
import threading
import platform
from typing import List, Dict, Any, Optional, Tuple, AsyncGenerator
import numpy as np

logger = logging.getLogger("dicty.tts")

from dicty_paths import get_user_data_dir

# Directory where TTS models are stored locally
TTS_MODELS_DIR = os.path.join(get_user_data_dir(), "models", "tts")
KOKORO_DIR = os.path.join(TTS_MODELS_DIR, "kokoro")

try:
    from piper_service import PIPER_VOICES_CONFIG, PiperService
except Exception as _piper_err:
    logger.warning(f"[-] Piper TTS could not be loaded: {_piper_err}")
    PIPER_VOICES_CONFIG = {}
    PiperService = None

try:
    from silero_service import SILERO_VOICES_CONFIG, SileroService
except Exception as _silero_err:
    logger.warning(f"[-] Silero TTS could not be loaded: {_silero_err}")
    SILERO_VOICES_CONFIG = {}
    SileroService = None

# Default voice catalog with human-friendly descriptions
KOKORO_VOICES = [
    {"id": "af_heart", "name": "Heart", "gender": "female", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Warm, engaging, and expressive (Recommended)"},
    {"id": "af_bella", "name": "Bella", "gender": "female", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Clear, lively, and articulate"},
    {"id": "af_nicole", "name": "Nicole", "gender": "female", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Professional, calm, and polished"},
    {"id": "af_sky", "name": "Sky", "gender": "female", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Soft, natural, and friendly"},
    {"id": "af_sarah", "name": "Sarah", "gender": "female", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Mature, balanced, and confident"},
    {"id": "am_adam", "name": "Adam", "gender": "male", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Deep, confident, and resonant"},
    {"id": "am_michael", "name": "Michael", "gender": "male", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Conversational, natural, and clear"},
    {"id": "am_echo", "name": "Echo", "gender": "male", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Crisp and energetic"},
    {"id": "am_fenrir", "name": "Fenrir", "gender": "male", "accent": "US", "flag": "🇺🇸", "lang": "en", "engine": "kokoro", "description": "Strong, authoritative, and steady"},
    {"id": "bf_emma", "name": "Emma", "gender": "female", "accent": "UK", "flag": "🇬🇧", "lang": "en", "engine": "kokoro", "description": "Refined British narrator"},
    {"id": "bf_isabella", "name": "Isabella", "gender": "female", "accent": "UK", "flag": "🇬🇧", "lang": "en", "engine": "kokoro", "description": "Sophisticated and articulate British"},
    {"id": "bm_george", "name": "George", "gender": "male", "accent": "UK", "flag": "🇬🇧", "lang": "en", "engine": "kokoro", "description": "Warm, classic British timbre"},
    {"id": "bm_lewis", "name": "Lewis", "gender": "male", "accent": "UK", "flag": "🇬🇧", "lang": "en", "engine": "kokoro", "description": "Modern and expressive British narrator"},
]

SILERO_VOICES = [
    {
        "id": meta["id"],
        "name": meta["name"],
        "gender": meta["gender"],
        "accent": meta["accent"],
        "flag": meta.get("flag", "🌐"),
        "lang": meta["lang"],
        "engine": "silero",
        "description": meta["description"],
    }
    for meta in SILERO_VOICES_CONFIG.values()
]
VOICE_CATALOG = KOKORO_VOICES + SILERO_VOICES

class TTSService:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            with cls._lock:
                if not cls._instance:
                    cls._instance = super(TTSService, cls).__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if getattr(self, "_initialized", False):
            return
        self._initialized = True
        self._kokoro = None
        self._model_lock = threading.Lock()
        self._download_lock = threading.Lock()
        self._download_progress = {"status": "idle", "percent": 0.0, "message": ""}
        os.makedirs(KOKORO_DIR, exist_ok=True)

    def get_model_paths(self) -> Tuple[Optional[str], Optional[str]]:
        """Finds downloaded ONNX model weights and voices binary."""
        # Check possible model filenames
        model_names = [
            "kokoro-v1.0.int8.onnx",
            "kokoro-v1.0.fp16.onnx",
            "kokoro-v1.0.onnx",
            "kokoro-v0_19.int8.onnx",
            "kokoro-v0_19.onnx",
        ]
        voice_names = ["voices-v1.0.bin", "voices.bin"]

        model_path = None
        for name in model_names:
            p = os.path.join(KOKORO_DIR, name)
            if os.path.exists(p) and os.path.getsize(p) > 10_000_000:
                model_path = p
                break

        voices_path = None
        for name in voice_names:
            p = os.path.join(KOKORO_DIR, name)
            if os.path.exists(p) and os.path.getsize(p) > 1_000_000:
                voices_path = p
                break

        return model_path, voices_path

    def is_installed(self) -> bool:
        """Returns True if kokoro_onnx is importable and local model weights are present."""
        try:
            import kokoro_onnx
        except ImportError:
            return False
        model_path, voices_path = self.get_model_paths()
        return bool(model_path and voices_path)

    def is_voice_installed(self, voice_id: str) -> bool:
        """Returns True if the specific voice model is installed locally."""
        if voice_id and voice_id.startswith("silero:"):
            try:
                from silero_service import SileroService
                return SileroService().is_voice_installed(voice_id)
            except Exception:
                return False
        if voice_id and voice_id.startswith("piper:"):
            try:
                from piper_service import PiperService
                return PiperService().is_voice_installed(voice_id)
            except Exception:
                return False
        return self.is_installed()

    def get_status(self) -> Dict[str, Any]:
        """Returns TTS engine status and download state."""
        installed = self.is_installed()
        model_path, voices_path = self.get_model_paths()

        silero = None
        try:
            from silero_service import SileroService
            silero = SileroService()
        except Exception:
            pass

        voices = []
        for v in VOICE_CATALOG:
            entry = dict(v)
            if entry.get("engine") == "silero":
                entry["installed"] = silero.is_voice_installed(entry["id"]) if silero else False
            elif entry.get("engine") == "piper":
                try:
                    from piper_service import PiperService
                    entry["installed"] = PiperService().is_voice_installed(entry["id"])
                except Exception:
                    entry["installed"] = False
            else:
                entry["installed"] = installed
            voices.append(entry)

        dl_status = dict(self._download_progress)
        if dl_status.get("status") != "downloading" and silero:
            try:
                silero_dl = silero.get_download_status()
                if silero_dl.get("status") in ("downloading", "failed", "completed"):
                    dl_status = silero_dl
            except Exception:
                pass

        if dl_status.get("status") not in ("downloading", "failed", "completed"):
            try:
                from piper_service import PiperService
                piper_dl = PiperService().get_download_status()
                if piper_dl.get("status") in ("downloading", "failed", "completed"):
                    dl_status = piper_dl
            except Exception:
                pass

        return {
            "installed": installed,
            "engine": "kokoro_onnx",
            "model_path": model_path,
            "voices_path": voices_path,
            "download": dl_status,
            "voices": voices,
        }

    def _get_kokoro(self):
        """Lazy-loads the Kokoro ONNX model instance."""
        if self._kokoro is not None:
            return self._kokoro

        with self._model_lock:
            if self._kokoro is not None:
                return self._kokoro

            model_path, voices_path = self.get_model_paths()
            if not model_path or not voices_path:
                raise FileNotFoundError(
                    f"Kokoro model not found in {KOKORO_DIR}. Please download the model first."
                )

            logger.info("Initializing Kokoro ONNX model from %s...", model_path)
            try:
                import time
                import onnxruntime as rt
                from kokoro_onnx import Kokoro

                opts = rt.SessionOptions()
                num_threads = min(os.cpu_count() or 4, 8)
                opts.intra_op_num_threads = num_threads
                opts.inter_op_num_threads = 2
                opts.graph_optimization_level = rt.GraphOptimizationLevel.ORT_ENABLE_ALL
                opts.execution_mode = rt.ExecutionMode.ORT_SEQUENTIAL

                session = rt.InferenceSession(model_path, sess_options=opts, providers=["CPUExecutionProvider"])
                self._kokoro = Kokoro.from_session(session, voices_path=voices_path)
                logger.info("Kokoro ONNX session initialized with %d threads.", num_threads)
                return self._kokoro
            except Exception as e:
                logger.error("Failed to initialize Kokoro ONNX: %s", e, exc_info=True)
                raise

    def prewarm(self):
        """Pre-warms model in RAM to eliminate cold-start delay."""
        try:
            if self.is_installed() and self._kokoro is None:
                import time
                print("[*] Pre-warming Kokoro TTS model in background...")
                t0 = time.perf_counter()
                kokoro = self._get_kokoro()
                _ = kokoro.create("Dicty ready.", voice="af_heart", speed=1.0)
                dt = time.perf_counter() - t0
                print(f"[+] Kokoro TTS model pre-warmed in {dt:.2f}s.")
        except Exception as e:
            logger.debug("TTS prewarm skipped: %s", e)

    def synthesize(
        self,
        text: str,
        voice: str = "af_heart",
        blend_voice: Optional[str] = None,
        blend_ratio: float = 0.5,
        expressiveness: float = 0.0,
        speed: float = 1.0,
        sentence_pause: float = 0.25,
        clause_pause: float = 0.1,
        continuous: bool = False,
        lang: str = "en-us"
    ) -> bytes:
        """
        Synthesizes text into a high-fidelity 24kHz WAV audio stream with performance metrics,
        custom voice blending, expressiveness variance, and pacing controls.
        """
        import time
        if not text or not text.strip():
            raise ValueError("Input text cannot be empty.")

        if voice and voice.startswith("silero:"):
            try:
                from silero_service import SileroService
                return SileroService().synthesize(
                    text=text,
                    voice=voice,
                    speed=speed or 1.0,
                    sentence_pause=sentence_pause if sentence_pause is not None else 0.25,
                    clause_pause=clause_pause if clause_pause is not None else 0.10,
                    expressiveness=expressiveness if expressiveness is not None else 0.0,
                )
            except Exception as e:
                raise RuntimeError(f"Silero TTS voice synthesis failed: {e}")

        if voice and voice.startswith("piper:"):
            try:
                from piper_service import PiperService
                return PiperService().synthesize(
                    text=text,
                    voice_id=voice,
                    speed=speed or 1.0,
                    expressiveness=expressiveness if expressiveness is not None else 0.0,
                    sentence_pause=sentence_pause if sentence_pause is not None else 0.25,
                    clause_pause=clause_pause if clause_pause is not None else 0.10,
                )
            except Exception as e:
                raise RuntimeError(f"Piper TTS voice synthesis failed: {e}")

        kokoro = self._get_kokoro()
        
        # Kokoro expects language prefixes (e.g. 'en-us', 'en-gb')
        if voice.startswith("b"):
            lang = "en-gb"
        elif voice.startswith("a"):
            lang = "en-us"

        # Resolve voice style embedding or string
        style_input = voice
        voice_desc = voice

        if blend_voice and blend_voice != voice:
            try:
                style_a = kokoro.get_voice_style(voice)
                style_b = kokoro.get_voice_style(blend_voice)
                alpha = max(0.0, min(1.0, float(blend_ratio)))
                style_input = ((1.0 - alpha) * style_a + alpha * style_b).astype(np.float32)
                voice_desc = f"{voice} ({int((1-alpha)*100)}%) + {blend_voice} ({int(alpha*100)}%)"
            except Exception as e:
                logger.warning("Voice blending failed, falling back to primary voice: %s", e)
                style_input = voice

        # Apply expressiveness / style variance
        if expressiveness and expressiveness > 0.0:
            exp_val = max(0.0, min(1.0, float(expressiveness)))
            try:
                if isinstance(style_input, str):
                    style_input = kokoro.get_voice_style(style_input).copy()
                else:
                    style_input = np.copy(style_input)
                
                # Scale phoneme-to-phoneme prosody dynamics (pitch & rhythm excursions)
                mean_frame = style_input.mean(axis=0, keepdims=True)
                delta = style_input - mean_frame
                style_input = mean_frame + delta * (1.0 + exp_val * 1.6)
                
                # Add subtle harmonic variance
                noise = np.random.normal(0, exp_val * 0.02, style_input.shape).astype(np.float32)
                style_input = (style_input + noise).astype(np.float32)
                voice_desc += f" [exp: {int(exp_val*100)}%]"
            except Exception as e:
                logger.warning("Expressiveness perturbation failed: %s", e)

        speed = max(0.5, min(2.5, float(speed)))
        sentence_pause = max(0.05, min(1.5, float(sentence_pause)))
        clause_pause = max(0.02, min(0.8, float(clause_pause)))
        
        words = len(text.strip().split())
        chars = len(text.strip())
        print(f"\n[TTS] Synthesizing {chars} chars ({words} words) with '{voice_desc}' @ {speed:.2g}x (pauses: {sentence_pause:.2f}s / {clause_pause:.2f}s)...")

        t_start = time.perf_counter()
        
        import re
        raw_sentences = [s.strip() for s in re.split(r'(?<=[.!?])\s+', text.strip()) if s.strip()]
        
        if len(raw_sentences) > 1 and sentence_pause > 0.02:
            audio_segments = []
            pause_samples = np.zeros(int(sentence_pause * 24000), dtype=np.float32)
            sample_rate = 24000
            for i, sent in enumerate(raw_sentences):
                seg_samples, sr = kokoro.create(
                    text=sent,
                    voice=style_input,
                    speed=speed,
                    lang=lang,
                    sentence_pause=sentence_pause,
                    clause_pause=clause_pause,
                    continuous=False
                )
                sample_rate = sr
                audio_segments.append(seg_samples)
                if i < len(raw_sentences) - 1:
                    audio_segments.append(pause_samples)
            samples = np.concatenate(audio_segments)
        else:
            samples, sample_rate = kokoro.create(
                text=text.strip(),
                voice=style_input,
                speed=speed,
                lang=lang,
                sentence_pause=sentence_pause,
                clause_pause=clause_pause,
                continuous=False
            )

        t_end = time.perf_counter()
        elapsed_sec = t_end - t_start
        audio_dur_sec = len(samples) / float(sample_rate)
        rtf = elapsed_sec / max(0.001, audio_dur_sec)
        speedup = audio_dur_sec / max(0.001, elapsed_sec)
        wps = words / max(0.001, elapsed_sec)

        # Performance banner output to terminal
        metrics_msg = (
            f"[TTS] Metrics: audio={audio_dur_sec:.2f}s | compute={elapsed_sec:.2f}s | "
            f"speed={speedup:.1f}x real-time (RTF={rtf:.3f}) | throughput={wps:.1f} words/sec"
        )
        print(f"\033[32m[TTS] Complete: \033[0m{metrics_msg}\n")
        logger.info(metrics_msg)

        # Convert float32 [-1.0, 1.0] to int16 PCM
        int16_samples = (np.clip(samples, -1.0, 1.0) * 32767.0).astype(np.int16)

        # Build WAV in memory
        buffer = io.BytesIO()
        with wave.open(buffer, "wb") as wav:
            wav.setnchannels(1)  # Mono
            wav.setsampwidth(2)  # 16-bit
            wav.setframerate(sample_rate)  # 24kHz
            wav.writeframes(int16_samples.tobytes())

        buffer.seek(0)
        return buffer.read()

    async def synthesize_stream(
        self, text: str, voice: str = "af_heart", speed: float = 1.0, lang: str = "en-us"
    ) -> AsyncGenerator[bytes, None]:
        """
        Streams audio chunks in real-time as PCM audio bytes.
        """
        if not text or not text.strip():
            return

        kokoro = self._get_kokoro()
        if voice.startswith("b"):
            lang = "en-gb"
        elif voice.startswith("a"):
            lang = "en-us"

        speed = max(0.5, min(2.5, float(speed)))

        async for chunk, sample_rate in kokoro.create_stream(
            text=text.strip(), voice=voice, speed=speed, lang=lang
        ):
            int16_chunk = (np.clip(chunk, -1.0, 1.0) * 32767.0).astype(np.int16)
            yield int16_chunk.tobytes()

    def start_download_background(self, voice_id: Optional[str] = None):
        """Starts asynchronous download of Kokoro base model or a specific Silero/Piper voice."""
        if voice_id and voice_id.startswith("silero:"):
            try:
                from silero_service import SileroService
                return SileroService().start_download_background(voice_id)
            except Exception as e:
                return {"status": "failed", "message": f"Silero unavailable: {e}"}

        if voice_id and voice_id.startswith("piper:"):
            try:
                from piper_service import PiperService
                piper = PiperService()
                if piper.is_voice_installed(voice_id):
                    return {"status": "completed", "percent": 100.0, "message": "Voice already installed"}
                thread = threading.Thread(target=piper.download_voice, args=(voice_id,), daemon=True)
                thread.start()
                return piper.get_download_status(voice_id)
            except Exception as e:
                return {"status": "failed", "message": f"Piper unavailable: {e}"}

        with self._download_lock:
            if self._download_progress["status"] == "downloading":
                return self._download_progress

            self._download_progress = {
                "status": "downloading",
                "percent": 0.0,
                "message": "Starting download...",
            }

            thread = threading.Thread(target=self._perform_download, daemon=True)
            thread.start()
            return self._download_progress

    def delete_voice(self, voice_id: str) -> bool:
        """Unloads and deletes a voice model to free disk space."""
        if voice_id and voice_id.startswith("silero:"):
            try:
                from silero_service import SileroService
                return SileroService().delete_voice(voice_id)
            except Exception:
                return False
        if voice_id and voice_id.startswith("piper:"):
            try:
                from piper_service import PiperService
                return PiperService().delete_voice(voice_id)
            except Exception:
                return False
        return False

    def _perform_download(self):
        import httpx
        os.makedirs(KOKORO_DIR, exist_ok=True)

        downloads = [
            (
                "voices-v1.0.bin",
                "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/voices-v1.0.bin",
                28_214_398,
            ),
            (
                "kokoro-v1.0.int8.onnx",
                "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.1/kokoro-v1.0.int8.onnx",
                114_119_327,
            ),
        ]

        total_bytes = sum(d[2] for d in downloads)
        downloaded_so_far = 0

        # 15s to establish connection, 60s max silence between chunks
        TIMEOUT = httpx.Timeout(connect=15.0, read=60.0, write=10.0, pool=5.0)
        MAX_RETRIES = 3

        try:
            for filename, url, size in downloads:
                target_path = os.path.join(KOKORO_DIR, filename)
                temp_path = target_path + ".tmp"

                if os.path.exists(target_path) and os.path.getsize(target_path) >= size:
                    downloaded_so_far += size
                    pct = min(99.0, (downloaded_so_far / total_bytes) * 100.0)
                    self._download_progress["percent"] = round(pct, 1)
                    continue

                self._download_progress["message"] = f"Downloading {filename}..."
                last_error = None

                for attempt in range(1, MAX_RETRIES + 1):
                    try:
                        file_downloaded = 0
                        with httpx.stream(
                            "GET", url,
                            follow_redirects=True,
                            timeout=TIMEOUT,
                            headers={"User-Agent": "Dicty-Engine/1.0"},
                        ) as resp:
                            resp.raise_for_status()
                            with open(temp_path, "wb") as out_file:
                                for chunk in resp.iter_bytes(chunk_size=1024 * 512):  # 512 KB
                                    out_file.write(chunk)
                                    file_downloaded += len(chunk)
                                    downloaded_so_far += len(chunk)
                                    pct = min(99.0, (downloaded_so_far / total_bytes) * 100.0)
                                    self._download_progress["percent"] = round(pct, 1)
                        os.replace(temp_path, target_path)
                        last_error = None
                        break  # success — move to next file
                    except Exception as attempt_err:
                        last_error = attempt_err
                        # Roll back partial bytes from the failed attempt
                        downloaded_so_far -= file_downloaded
                        downloaded_so_far = max(0, downloaded_so_far)
                        if os.path.exists(temp_path):
                            try:
                                os.remove(temp_path)
                            except Exception:
                                pass
                        if attempt < MAX_RETRIES:
                            self._download_progress["message"] = (
                                f"Retrying {filename} (attempt {attempt + 1}/{MAX_RETRIES})..."
                            )
                            logger.warning(
                                "Download attempt %d/%d failed for %s: %s",
                                attempt, MAX_RETRIES, filename, attempt_err,
                            )
                        else:
                            raise last_error

            self._download_progress = {
                "status": "completed",
                "percent": 100.0,
                "message": "Download complete. Model is ready to use.",
            }
            logger.info("Kokoro models downloaded successfully.")
        except Exception as e:
            logger.error("Error downloading Kokoro models: %s", e, exc_info=True)
            # Clean up any partial temp files
            for filename, _, _ in downloads:
                tp = os.path.join(KOKORO_DIR, filename + ".tmp")
                if os.path.exists(tp):
                    try:
                        os.remove(tp)
                    except Exception:
                        pass
            self._download_progress = {
                "status": "error",
                "percent": 0.0,
                "message": f"Download failed: {str(e)}",
            }

tts_service = TTSService()
