"""
Dicty Piper TTS Service
=======================
Offline neural speech synthesis for German (de_DE) and Russian (ru_RU)
backed by the Piper ONNX engine and Rhasspy voice models.
"""

import os
import io
import time
import wave
import logging
import threading
import platform
import ssl
import urllib.request
from typing import Dict, Any, Optional, Tuple, List

logger = logging.getLogger("dicty.piper")

def open_url_safe(req_or_url, timeout=30):
    """Safely opens a URL with certificate fallback to ensure downloads never fail due to macOS CA bundle issues."""
    ctx = None
    try:
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
    except Exception:
        pass
    try:
        if ctx is not None:
            return urllib.request.urlopen(req_or_url, context=ctx, timeout=timeout)
        return urllib.request.urlopen(req_or_url, timeout=timeout)
    except Exception as e:
        try:
            unverified_ctx = ssl._create_unverified_context()
            return urllib.request.urlopen(req_or_url, context=unverified_ctx, timeout=timeout)
        except Exception:
            raise e

from dicty_paths import get_user_data_dir

PIPER_MODELS_DIR = os.path.join(get_user_data_dir(), "models", "tts", "piper")
HF_BASE_URL = "https://huggingface.co/rhasspy/piper-voices/resolve/main"

# Catalog of supported Piper voices (on-demand download only)
PIPER_VOICES_CONFIG: Dict[str, Dict[str, Any]] = {
    # German (de_DE)
    "piper:de_DE-thorsten-medium": {
        "id": "piper:de_DE-thorsten-medium",
        "model_key": "de_DE-thorsten-medium",
        "name": "Thorsten",
        "gender": "male",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Clear, natural German narrator (Piper Neural)",
        "hf_subpath": "de/de_DE/thorsten/medium",
    },
    "piper:de_DE-kerstin-medium": {
        "id": "piper:de_DE-kerstin-medium",
        "model_key": "de_DE-kerstin-medium",
        "name": "Kerstin",
        "gender": "female",
        "lang": "de",
        "accent": "DE",
        "flag": "🇩🇪",
        "description": "Warm and balanced German female narrator (Piper Neural)",
        "hf_subpath": "de/de_DE/kerstin/medium",
    },
    # Russian (ru_RU)
    "piper:ru_RU-dmitri-medium": {
        "id": "piper:ru_RU-dmitri-medium",
        "model_key": "ru_RU-dmitri-medium",
        "name": "Dmitri",
        "gender": "male",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Expressive Russian male narrator (Piper Neural)",
        "hf_subpath": "ru/ru_RU/dmitri/medium",
    },
    "piper:ru_RU-irina-medium": {
        "id": "piper:ru_RU-irina-medium",
        "model_key": "ru_RU-irina-medium",
        "name": "Irina",
        "gender": "female",
        "lang": "ru",
        "accent": "RU",
        "flag": "🇷🇺",
        "description": "Clear conversational Russian female voice (Piper Neural)",
        "hf_subpath": "ru/ru_RU/irina/medium",
    },
    # Ukrainian (uk_UA)
    "piper:uk_UA-ukrainian_tts-medium": {
        "id": "piper:uk_UA-ukrainian_tts-medium",
        "model_key": "uk_UA-ukrainian_tts-medium",
        "name": "Lada",
        "gender": "female",
        "lang": "uk",
        "accent": "UA",
        "flag": "🇺🇦",
        "description": "Natural Ukrainian narrator (Piper Neural)",
        "hf_subpath": "uk/uk_UA/ukrainian_tts/medium",
    },
    # Polish (pl_PL)
    "piper:pl_PL-darkman-medium": {
        "id": "piper:pl_PL-darkman-medium",
        "model_key": "pl_PL-darkman-medium",
        "name": "Darkman",
        "gender": "male",
        "lang": "pl",
        "accent": "PL",
        "flag": "🇵🇱",
        "description": "Natural Polish male narrator (Piper Neural)",
        "hf_subpath": "pl/pl_PL/darkman/medium",
    },
    # Spanish (es_ES)
    "piper:es_ES-sharvard-medium": {
        "id": "piper:es_ES-sharvard-medium",
        "model_key": "es_ES-sharvard-medium",
        "name": "Sharvard",
        "gender": "male",
        "lang": "es",
        "accent": "ES",
        "flag": "🇪🇸",
        "description": "Clean conversational Spanish narrator (Piper Neural)",
        "hf_subpath": "es/es_ES/sharvard/medium",
    },
    # French (fr_FR)
    "piper:fr_FR-siwis-medium": {
        "id": "piper:fr_FR-siwis-medium",
        "model_key": "fr_FR-siwis-medium",
        "name": "Siwis",
        "gender": "female",
        "lang": "fr",
        "accent": "FR",
        "flag": "🇫🇷",
        "description": "Articulate French female narrator (Piper Neural)",
        "hf_subpath": "fr/fr_FR/siwis/medium",
    },
    # Italian (it_IT)
    "piper:it_IT-paola-medium": {
        "id": "piper:it_IT-paola-medium",
        "model_key": "it_IT-paola-medium",
        "name": "Paola",
        "gender": "female",
        "lang": "it",
        "accent": "IT",
        "flag": "🇮🇹",
        "description": "Expressive Italian narrator (Piper Neural)",
        "hf_subpath": "it/it_IT/paola/medium",
    },
    # Portuguese (pt_BR)
    "piper:pt_BR-faber-medium": {
        "id": "piper:pt_BR-faber-medium",
        "model_key": "pt_BR-faber-medium",
        "name": "Faber",
        "gender": "male",
        "lang": "pt",
        "accent": "BR",
        "flag": "🇧🇷",
        "description": "Natural Portuguese male narrator (Piper Neural)",
        "hf_subpath": "pt/pt_BR/faber/medium",
    },
    # Dutch (nl_BE)
    "piper:nl_BE-rdh-medium": {
        "id": "piper:nl_BE-rdh-medium",
        "model_key": "nl_BE-rdh-medium",
        "name": "RDH",
        "gender": "male",
        "lang": "nl",
        "accent": "NL",
        "flag": "🇳🇱",
        "description": "Clear Dutch narrator (Piper Neural)",
        "hf_subpath": "nl/nl_BE/rdh/medium",
    },
    # Swedish (sv_SE)
    "piper:sv_SE-nst-medium": {
        "id": "piper:sv_SE-nst-medium",
        "model_key": "sv_SE-nst-medium",
        "name": "NST",
        "gender": "female",
        "lang": "sv",
        "accent": "SE",
        "flag": "🇸🇪",
        "description": "Natural Swedish female narrator (Piper Neural)",
        "hf_subpath": "sv/sv_SE/nst/medium",
    },
}

class PiperService:
    _instance = None
    _lock = threading.Lock()

    def __new__(cls, *args, **kwargs):
        if not cls._instance:
            with cls._lock:
                if not cls._instance:
                    cls._instance = super(PiperService, cls).__new__(cls)
                    cls._instance._initialized = False
        return cls._instance

    def __init__(self):
        if getattr(self, "_initialized", False):
            return
        self._initialized = True
        self._loaded_voices: Dict[str, Any] = {}
        self._voice_lock = threading.Lock()
        self._download_lock = threading.Lock()
        self._download_progress: Dict[str, Dict[str, Any]] = {}
        os.makedirs(PIPER_MODELS_DIR, exist_ok=True)

    def get_supported_voices(self) -> List[Dict[str, Any]]:
        """Returns catalog of Piper voices with installation status."""
        catalog = []
        for voice_id, meta in PIPER_VOICES_CONFIG.items():
            installed = self.is_voice_installed(voice_id)
            entry = dict(meta)
            entry["engine"] = "piper"
            entry["installed"] = installed
            catalog.append(entry)
        return catalog

    def is_voice_installed(self, voice_id: str) -> bool:
        meta = PIPER_VOICES_CONFIG.get(voice_id)
        if not meta:
            return False
        model_key = meta["model_key"]
        onnx_file = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx")
        json_file = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx.json")
        return (
            os.path.exists(onnx_file)
            and os.path.getsize(onnx_file) > 10_000_000
            and os.path.exists(json_file)
            and os.path.getsize(json_file) > 100
        )

    def get_download_status(self, voice_id: Optional[str] = None) -> Dict[str, Any]:
        if voice_id:
            return self._download_progress.get(
                voice_id,
                {"status": "idle", "percent": 0.0, "message": ""}
            )
        return self._download_progress

    def download_voice(self, voice_id: str) -> bool:
        meta = PIPER_VOICES_CONFIG.get(voice_id)
        if not meta:
            raise ValueError(f"Unknown Piper voice: {voice_id}")

        if self.is_voice_installed(voice_id):
            return True

        with self._download_lock:
            if self.is_voice_installed(voice_id):
                return True

            model_key = meta["model_key"]
            subpath = meta["hf_subpath"]
            onnx_url = f"{HF_BASE_URL}/{subpath}/{model_key}.onnx"
            json_url = f"{HF_BASE_URL}/{subpath}/{model_key}.onnx.json"

            onnx_path = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx")
            json_path = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx.json")
            tmp_onnx = onnx_path + ".tmp"
            tmp_json = json_path + ".tmp"

            self._download_progress[voice_id] = {
                "status": "downloading",
                "percent": 0.0,
                "message": f"Downloading {meta['name']} voice..."
            }

            try:
                # 1. Download JSON config
                logger.info("Downloading Piper config: %s", json_url)
                req_json = urllib.request.Request(json_url, headers={"User-Agent": "Dicty-Client/1.0"})
                with open_url_safe(req_json, timeout=20) as resp_j, open(tmp_json, "wb") as out_j:
                    out_j.write(resp_j.read())
                os.replace(tmp_json, json_path)

                # 2. Download ONNX model with progress tracking
                logger.info("Downloading Piper ONNX model: %s", onnx_url)
                
                req = urllib.request.Request(
                    onnx_url,
                    headers={"User-Agent": "Dicty-Client/1.0"}
                )
                with open_url_safe(req, timeout=60) as resp, open(tmp_onnx, "wb") as out_f:
                    total_size = int(resp.headers.get("content-length", 65_000_000))
                    downloaded = 0
                    chunk_size = 512 * 1024

                    while True:
                        chunk = resp.read(chunk_size)
                        if not chunk:
                            break
                        out_f.write(chunk)
                        downloaded += len(chunk)
                        pct = min(1.0, downloaded / max(1, total_size))
                        self._download_progress[voice_id] = {
                            "status": "downloading",
                            "percent": pct,
                            "message": f"Downloading {meta['name']} ({int(pct * 100)}%)..."
                        }

                os.replace(tmp_onnx, onnx_path)
                self._download_progress[voice_id] = {
                    "status": "completed",
                    "percent": 1.0,
                    "message": f"{meta['name']} ready."
                }
                logger.info("Successfully downloaded Piper voice %s", voice_id)
                return True

            except Exception as e:
                logger.error("Failed to download Piper voice %s: %s", voice_id, e, exc_info=True)
                self._download_progress[voice_id] = {
                    "status": "failed",
                    "percent": 0.0,
                    "message": f"Download failed: {e}"
                }
                if os.path.exists(tmp_onnx):
                    try:
                        os.remove(tmp_onnx)
                    except OSError:
                        pass
                if os.path.exists(tmp_json):
                    try:
                        os.remove(tmp_json)
                    except OSError:
                        pass
                raise

    def _get_voice(self, voice_id: str):
        """Loads and caches PiperVoice instance."""
        if voice_id in self._loaded_voices:
            return self._loaded_voices[voice_id]

        with self._voice_lock:
            if voice_id in self._loaded_voices:
                return self._loaded_voices[voice_id]

            if not self.is_voice_installed(voice_id):
                # Attempt to download automatically
                self.download_voice(voice_id)

            meta = PIPER_VOICES_CONFIG[voice_id]
            model_key = meta["model_key"]
            onnx_path = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx")
            json_path = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx.json")

            logger.info("Loading Piper model %s...", model_key)
            from piper import PiperVoice
            voice = PiperVoice.load(onnx_path, config_path=json_path)
            self._loaded_voices[voice_id] = voice
            return voice

    def delete_voice(self, voice_id: str) -> bool:
        """Unloads and deletes cached Piper model to reclaim disk space."""
        meta = PIPER_VOICES_CONFIG.get(voice_id)
        if not meta:
            return False

        with self._voice_lock:
            if voice_id in self._loaded_voices:
                del self._loaded_voices[voice_id]

        model_key = meta["model_key"]
        onnx_path = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx")
        json_path = os.path.join(PIPER_MODELS_DIR, f"{model_key}.onnx.json")

        deleted = False
        for path in [onnx_path, json_path]:
            if os.path.exists(path):
                try:
                    os.remove(path)
                    deleted = True
                except OSError as e:
                    logger.warning("Failed to remove %s: %s", path, e)
        return deleted

    def synthesize(
        self,
        text: str,
        voice_id: str,
        speed: float = 1.0,
        expressiveness: float = 0.0,
        sentence_pause: float = 0.25,
        clause_pause: float = 0.1,
    ) -> bytes:
        """
        Synthesizes text into standard 16-bit linear PCM WAV audio bytes.
        """
        if not text or not text.strip():
            raise ValueError("Input text cannot be empty.")

        voice = self._get_voice(voice_id)
        from piper import SynthesisConfig
        import re
        import numpy as np

        speed = max(0.5, min(2.5, float(speed)))
        length_scale = 1.0 / speed

        # Dynamic VITS expressiveness:
        # noise_scale (phoneme duration variance): 0.33 (calm) to 0.85 (lively)
        # noise_w_scale (pitch contour variance): 0.40 (steady) to 1.00 (animated/expressive)
        exp = max(0.0, min(1.0, float(expressiveness or 0.0)))
        noise_scale = 0.333 + exp * 0.52
        noise_w_scale = 0.40 + exp * 0.60

        syn_config = SynthesisConfig(
            length_scale=length_scale,
            noise_scale=noise_scale,
            noise_w_scale=noise_w_scale,
            normalize_audio=True
        )

        t_start = time.perf_counter()
        words = len(text.strip().split())
        chars = len(text.strip())
        print(f"\n[TTS:Piper] Synthesizing {chars} chars ({words} words) with '{voice_id}' @ {speed:.2g}x (exp: {int(exp*100)}%)...")

        # Split into sentences if requested pauses > 0.05
        raw_sentences = [s.strip() for s in re.split(r'(?<=[.!?])\s+', text.strip()) if s.strip()]
        sample_rate = voice.config.sample_rate

        if len(raw_sentences) > 1 and sentence_pause > 0.05:
            audio_chunks = []
            pause_samples = int(sentence_pause * sample_rate)
            pause_chunk = np.zeros(pause_samples, dtype=np.int16).tobytes()

            clause_samples = int(max(0.02, clause_pause) * sample_rate) if clause_pause > 0.03 else 0
            clause_chunk = np.zeros(clause_samples, dtype=np.int16).tobytes() if clause_samples > 0 else None

            for idx, sentence in enumerate(raw_sentences):
                if clause_chunk is not None and any(punct in sentence for punct in [",", ";", ":"]):
                    sub_clauses = [c.strip() for c in re.split(r'(?<=[,;:])\s+', sentence) if c.strip()]
                    if len(sub_clauses) > 1:
                        for c_idx, sub_c in enumerate(sub_clauses):
                            buf = io.BytesIO()
                            with wave.open(buf, "wb") as wf:
                                voice.synthesize_wav(sub_c, wf, syn_config=syn_config)
                            buf.seek(0)
                            with wave.open(buf, "rb") as rf:
                                audio_chunks.append(rf.readframes(rf.getnframes()))
                            if c_idx < len(sub_clauses) - 1:
                                audio_chunks.append(clause_chunk)
                    else:
                        buf = io.BytesIO()
                        with wave.open(buf, "wb") as wf:
                            voice.synthesize_wav(sentence, wf, syn_config=syn_config)
                        buf.seek(0)
                        with wave.open(buf, "rb") as rf:
                            audio_chunks.append(rf.readframes(rf.getnframes()))
                else:
                    buf = io.BytesIO()
                    with wave.open(buf, "wb") as wf:
                        voice.synthesize_wav(sentence, wf, syn_config=syn_config)
                    buf.seek(0)
                    with wave.open(buf, "rb") as rf:
                        audio_chunks.append(rf.readframes(rf.getnframes()))

                if idx < len(raw_sentences) - 1:
                    audio_chunks.append(pause_chunk)

            combined_pcm = b"".join(audio_chunks)
            out_buf = io.BytesIO()
            with wave.open(out_buf, "wb") as wf:
                wf.setnchannels(1)
                wf.setsampwidth(2)
                wf.setframerate(sample_rate)
                wf.writeframes(combined_pcm)
            wav_bytes = out_buf.getvalue()
        else:
            out_buf = io.BytesIO()
            with wave.open(out_buf, "wb") as wf:
                voice.synthesize_wav(text.strip(), wf, syn_config=syn_config)
            wav_bytes = out_buf.getvalue()

        t_end = time.perf_counter()
        compute_time = t_end - t_start

        # Compute audio duration from WAV header
        try:
            with wave.open(io.BytesIO(wav_bytes), "rb") as wf:
                audio_dur = wf.getnframes() / float(wf.getframerate())
        except Exception:
            audio_dur = 1.0

        rtf = compute_time / max(0.001, audio_dur)
        rt_mult = 1.0 / max(0.001, rtf)
        wps = words / max(0.001, compute_time)

        print(
            f"[TTS:Piper] Complete: Metrics: audio={audio_dur:.2f}s | "
            f"compute={compute_time:.2f}s | speed={rt_mult:.1f}x real-time (RTF={rtf:.3f}) | "
            f"throughput={wps:.1f} words/sec\n"
        )

        return wav_bytes
