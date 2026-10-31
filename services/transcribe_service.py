import os
import sys
import platform
import time
import asyncio
import httpx
import local_whisper
import subprocess
import shutil
import multiprocessing
from urllib.parse import quote_plus
from transcript_join import join_transcript_parts, normalize_whisper_text

# PyTorch 2.6+ compatibility for openai-whisper
os.environ["TORCH_FORCE_WEIGHTS_ONLY_LOAD"] = "0"

_whisper_model_cache = {}
_faster_whisper_cache = {}

def setup_nvidia_cuda_dlls():
    """
    On Windows, ensures that NVIDIA CUDA cuBLAS runtime DLLs from pip wheels
    (nvidia-cublas-cu12) or local environment are discoverable and loaded.
    """
    import sys
    if sys.platform != "win32":
        return
        
    candidate_roots = []
    if hasattr(sys, '_MEIPASS'):
        candidate_roots.append(sys._MEIPASS)
    if getattr(sys, 'frozen', False):
        exe_dir = os.path.dirname(sys.executable)
        candidate_roots.append(exe_dir)
        candidate_roots.append(os.path.join(exe_dir, '_internal'))
    venv_site = os.path.join(os.path.dirname(sys.executable), '..', 'Lib', 'site-packages')
    if os.path.isdir(venv_site):
        candidate_roots.append(os.path.join(venv_site, 'nvidia'))
    
    try:
        import site
        for sp in site.getsitepackages():
            candidate_roots.append(os.path.join(sp, 'nvidia'))
    except Exception:
        pass

    import ctypes
    loaded_dlls = []
    for base in candidate_roots:
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            if any(f.endswith('.dll') and ('cublas' in f.lower() or 'cudnn' in f.lower()) for f in files):
                if hasattr(os, 'add_dll_directory'):
                    try:
                        os.add_dll_directory(root)
                    except Exception:
                        pass
                try:
                    ctypes.windll.kernel32.SetDllDirectoryW(root)
                except Exception:
                    pass
                if root not in os.environ.get("PATH", ""):
                    os.environ["PATH"] = root + os.pathsep + os.environ.get("PATH", "")
                # Explicitly pre-load cublasLt, cublas, and cudnn into process memory
                for dll_name in ['cublasLt64_12.dll', 'cublas64_12.dll', 'cudnn64_9.dll']:
                    full_dll_path = os.path.join(root, dll_name)
                    if os.path.isfile(full_dll_path) and full_dll_path not in loaded_dlls:
                        try:
                            ctypes.CDLL(full_dll_path)
                            loaded_dlls.append(full_dll_path)
                        except Exception:
                            pass

# Initialize CUDA DLL paths immediately on module import
setup_nvidia_cuda_dlls()

def is_nvidia_gpu_available() -> bool:
    """
    Checks if an NVIDIA GPU is physically present on the Windows machine.
    """
    import sys
    if sys.platform == "win32":
        system32 = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32")
        if os.path.isfile(os.path.join(system32, "nvcuda.dll")):
            return True
    return False

def get_whisper_device_and_compute_type():
    """
    Detects if NVIDIA CUDA is usable for faster-whisper.
    Enforces CUDA on Windows when a physical NVIDIA GPU is available.
    Returns (device, compute_type).
    """
    setup_nvidia_cuda_dlls()
    has_physical_gpu = is_nvidia_gpu_available()
    
    try:
        import ctranslate2
        cuda_count = ctranslate2.get_cuda_device_count()
        if cuda_count > 0:
            print(f"[+] CUDA acceleration active: detected {cuda_count} NVIDIA GPU(s).")
            return "cuda", "float16"
        elif has_physical_gpu:
            print("[!] Physical NVIDIA GPU detected on machine. Retrying CUDA initialization...")
            setup_nvidia_cuda_dlls()
            if ctranslate2.get_cuda_device_count() > 0:
                return "cuda", "float16"
    except Exception as e:
        print(f"[*] CUDA probe error: {e}")
    
    if has_physical_gpu:
        print("[+] Physical NVIDIA GPU present on Windows. Enforcing CUDA float16 acceleration.")
        return "cuda", "float16"

    return "cpu", "int8"

def resolve_faster_whisper_model_name(active_model: str = None, language: str = "auto") -> str:
    """
    Standardizes user model IDs (e.g. 'tiny.en', 'turbo', 'base') to CTranslate2 model identifiers.
    """
    from model_manager import ModelManager
    if not active_model:
        active_model = ModelManager().get_active_model()
    
    active_model_lower = (active_model or "").lower()
    if "tiny" in active_model_lower:
        return "tiny.en" if ("en" in active_model_lower or language == "en") else "tiny"
    elif "small" in active_model_lower:
        return "small.en" if ("en" in active_model_lower or language == "en") else "small"
    elif "medium" in active_model_lower:
        return "medium.en" if ("en" in active_model_lower or language == "en") else "medium"
    elif "turbo" in active_model_lower:
        return "deepdml/faster-whisper-large-v3-turbo-ct2"
    elif "distil" in active_model_lower:
        return "distil-large-v3"
    elif "large" in active_model_lower:
        return "large-v3"
    elif "/" in active_model_lower or not active_model_lower:
        mm_check = ModelManager()
        if mm_check.is_model_downloaded("tiny.en"):
            return "tiny.en"
        elif mm_check.is_model_downloaded("base.en"):
            return "base.en"
        else:
            return "tiny.en"
    else:
        return "base.en" if language in ["en", "auto"] else "base"

def prewarm_faster_whisper(target_model: str = None):
    """
    Pre-warms faster-whisper model into GPU/CPU RAM and executes a dummy
    inference pass with silence to force CUDA kernel compilation and cuBLAS context
    allocation so that the first real user dictation has 0ms cold-start latency.
    """
    try:
        from faster_whisper import WhisperModel
        model_size = resolve_faster_whisper_model_name(target_model)

        global _faster_whisper_cache
        if model_size not in _faster_whisper_cache:
            device, compute_type = get_whisper_device_and_compute_type()
            cpu_threads = min(8, os.cpu_count() or 4) if device == "cpu" else 4
            print(f"[*] Pre-warming faster-whisper '{model_size}' onto {device.upper()} ({compute_type})...")
            try:
                model = WhisperModel(
                    model_size,
                    device=device,
                    compute_type=compute_type,
                    cpu_threads=cpu_threads
                )
                _faster_whisper_cache[model_size] = model
                print(f"[+] Loaded faster-whisper model '{model_size}' on {device.upper()} successfully.")
            except Exception as load_err:
                if device == "cuda":
                    print(f"[!] Prewarm on CUDA failed ({load_err}). Falling back to CPU...")
                    cpu_threads = min(8, os.cpu_count() or 4)
                    model = WhisperModel(
                        model_size,
                        device="cpu",
                        compute_type="int8",
                        cpu_threads=cpu_threads
                    )
                    _faster_whisper_cache[model_size] = model
                else:
                    return

        # Crucial: Run a 0.1s dummy tensor to trigger CUDA JIT kernel compilation & cuBLAS context creation
        model = _faster_whisper_cache.get(model_size)
        if model is not None:
            try:
                import numpy as np
                dummy = np.zeros(1600, dtype=np.float32)
                list(model.transcribe(dummy, beam_size=1, language="en")[0])
                print(f"[+] CUDA/CTranslate2 kernels pre-warmed for '{model_size}'. First dictation will have 0ms cold-start.")
            except Exception as dummy_err:
                print(f"[*] Warmup dummy inference notice: {dummy_err}")
    except Exception as e:
        print(f"[-] Prewarm failed: {e}")

# ---------------------------------------------------------------------------
# Shared HTTP clients (keep-alive / connection pooling).
# Creating a new client per request forces a fresh TCP+TLS handshake every
# dictation (~100-300ms for cloud endpoints).
# ---------------------------------------------------------------------------
_local_http_client = None
_shared_async_client = None

def _get_local_http_client() -> "httpx.Client":
    """Sync keep-alive client for the local whisper-server."""
    global _local_http_client
    if _local_http_client is None:
        _local_http_client = httpx.Client(timeout=30.0)
    return _local_http_client

def get_shared_async_client() -> "httpx.AsyncClient":
    """Async keep-alive client for cloud STT / LLM calls (reuses TLS connections)."""
    global _shared_async_client
    if _shared_async_client is None or _shared_async_client.is_closed:
        _shared_async_client = httpx.AsyncClient(
            timeout=60.0,
            limits=httpx.Limits(max_keepalive_connections=10, keepalive_expiry=300.0),
        )
    return _shared_async_client

# ---------------------------------------------------------------------------
# Bring-your-own speech-to-text provider keys.
# Set by the app (from the macOS Keychain) via POST /settings/stt_keys and kept in memory only.
# Environment variables are a fallback for developers (both *_API_KEY and the shorter *_API names).
# ---------------------------------------------------------------------------
_user_stt_keys: dict = {}

_STT_ENV_NAMES = {
    "openai": ("OPENAI_API_KEY", "OPENAI_API"),
    "deepgram": ("DEEPGRAM_API_KEY", "DEEPGRAM_API"),
    "groq": ("GROQ_API_KEY", "GROQ_API"),
    "elevenlabs": ("ELEVENLABS_API_KEY", "ELEVENLABS_API", "XI_API_KEY"),
    "openrouter": ("OPENROUTER_API_KEY",),
}


def set_user_stt_keys(keys: dict) -> None:
    for provider in _STT_ENV_NAMES:
        if provider in keys:
            v = (keys.get(provider) or "").strip()
            if v:
                _user_stt_keys[provider] = v
            else:
                _user_stt_keys.pop(provider, None)


def get_stt_key(provider: str) -> str:
    """User key from the app first, then environment variables."""
    if _user_stt_keys.get(provider):
        return _user_stt_keys[provider]
    for name in _STT_ENV_NAMES.get(provider, ()):
        v = os.getenv(name, "").strip()
        if v:
            return v
    return ""


def stt_key_status() -> dict:
    return {p: bool(get_stt_key(p)) for p in _STT_ENV_NAMES}


_DEEPGRAM_HOSTS = {"us": "api.deepgram.com", "eu": "api.eu.deepgram.com"}
_deepgram_host_cache = None


def _deepgram_host() -> str:
    """Picks the nearest Deepgram region once (TCP connect time), cached for the process.
    Measured from Germany: US endpoint ~1.4-2.6s per 7s clip vs EU ~0.4-0.7s.
    Override with DEEPGRAM_REGION=us|eu."""
    global _deepgram_host_cache
    forced = os.getenv("DEEPGRAM_REGION", "").strip().lower()
    if forced in _DEEPGRAM_HOSTS:
        return _DEEPGRAM_HOSTS[forced]
    if _deepgram_host_cache:
        return _deepgram_host_cache
    import socket
    best, best_t = _DEEPGRAM_HOSTS["us"], float("inf")
    for host in _DEEPGRAM_HOSTS.values():
        try:
            t0 = time.perf_counter()
            # 2 connects; take the faster to reduce noise
            for _ in range(2):
                with socket.create_connection((host, 443), timeout=1.5):
                    pass
            t = (time.perf_counter() - t0) / 2
            if t < best_t:
                best, best_t = host, t
        except Exception:
            continue
    _deepgram_host_cache = best
    print(f"[*] Deepgram region selected: {best} (connect {best_t*1000:.0f} ms)")
    return best


_PROVIDER_WARM_URLS = {
    "groq": "https://api.groq.com/openai/v1/models",
    "elevenlabs": "https://api.elevenlabs.io/v1/models",
}


async def prewarm_direct_provider(model_name: str, route: str = "") -> None:
    """Called when recording starts: resolves the Deepgram region and opens a keep-alive TLS
    connection on the shared client, so the transcription request after stop skips the handshake."""
    try:
        provider = direct_provider_for_model(model_name)
        if not provider or not get_stt_key(provider):
            # Cloud model routed through Dicty Cloud or OpenRouter: warm that host instead
            if "/" in model_name:
                if route == "dicty_cloud":
                    url = os.getenv("DICTY_CLOUD_URL", "https://dicty-backend.dicty-backend.workers.dev") + "/health"
                else:
                    url = "https://openrouter.ai/api/v1/models?limit=1"
                await get_shared_async_client().head(url, timeout=3.0)
            return
        if provider == "deepgram":
            host = await asyncio.to_thread(_deepgram_host)
            url = f"https://{host}/v1/projects"
        else:
            url = _PROVIDER_WARM_URLS.get(provider)
        if url:
            # Unauthenticated HEAD: status is irrelevant, only the pooled connection matters
            await get_shared_async_client().head(url, timeout=3.0)
    except Exception:
        pass


def postprocess_transcript(raw_text: str, vocab_data: list = None, keep_timestamps: bool = False) -> str:
    """Shared cleanup for every transcription path (batch, streamed, segmented):
    strips hallucinated tags like [BLANK_AUDIO] and applies vocabulary replacements."""
    import re
    if not raw_text:
        return ""
    if keep_timestamps:
        # Preserve [00:00 - 00:04] timestamp markers for diarization
        final_text = raw_text.strip()
    else:
        final_text = re.sub(r'\[.*?\]|\(.*?\)', '', raw_text).strip()
    for v in vocab_data or []:
        word = v.get("word", "")
        replacement = v.get("replacement", "")
        if word and replacement:
            final_text = re.compile(re.escape(word), re.IGNORECASE).sub(replacement, final_text)
    return final_text


def direct_provider_for_model(model_name: str) -> str:
    """Model id prefix -> provider whose own API serves it directly ('' if none)."""
    for prefix, provider in (("deepgram/", "deepgram"), ("groq/", "groq"), ("elevenlabs/", "elevenlabs")):
        if model_name.startswith(prefix):
            return provider
    return ""


class TranscribeService:
    last_whisper_ms: float = 0.0
    last_provider: str = "Unknown"

    def __init__(self):
        self.last_whisper_ms = 0.0
        self.last_provider = "Unknown"
        self.openai_key = os.getenv("OPENAI_API_KEY") or os.getenv("OPENROUTER_API_KEY")
        self.whisper_cpp_path = os.getenv("WHISPER_CPP_PATH")
        self.whisper_model_path = os.getenv("WHISPER_MODEL_PATH")
        self._ensure_whisper_cpp_binary()

    def _ensure_whisper_cpp_binary(self) -> str:
        """
        Locates the whisper.cpp binary.
        If running as a packaged app (via PyInstaller), it extracts it from the embedded bundle.
        If running from source, it checks the bin/ directory.
        """
        import sys
        
        # 0. Check if WHISPER_CPP_PATH from env exists
        if self.whisper_cpp_path and os.path.exists(self.whisper_cpp_path):
            return self.whisper_cpp_path

        # 1. Check if we are running inside a packaged PyInstaller app
        if hasattr(sys, '_MEIPASS'):
            packaged_bin = os.path.join(sys._MEIPASS, "bin", "whisper-cli")
            packaged_server_bin = os.path.join(sys._MEIPASS, "bin", "whisper-server")
            if os.path.exists(packaged_server_bin):
                os.chmod(packaged_server_bin, 0o755)
            if os.path.exists(packaged_bin):
                # Ensure it's executable
                os.chmod(packaged_bin, 0o755)
                self.whisper_cpp_path = packaged_bin
                return self.whisper_cpp_path
                
        # 2. Check local source directory
        local_bin_paths = [
            "bin/whisper.cpp/build/bin/Release/whisper-cli.exe",
            "bin/whisper.cpp/build/bin/whisper-cli.exe",
            "bin/whisper-cli.exe",
            "bin/whisper.cpp/main.exe",
            "bin/whisper.cpp/build/bin/whisper-cli",
            "bin/whisper-cli",
            "bin/whisper.cpp/main"
        ]
        
        for p in local_bin_paths:
            if os.path.exists(p):
                self.whisper_cpp_path = os.path.abspath(p)
                return self.whisper_cpp_path
                
        # 3. If missing, warn rather than crash engine startup
        print("[!] Warning: whisper-cli binary not found. Run ./compile_whisper.sh to compile local whisper.cpp.")
        return self.whisper_cpp_path


    def _update_env_cpp_path(self, cpp_path: str):
        env_path = ".env"
        lines = []
        if os.path.exists(env_path):
            with open(env_path, "r") as f:
                lines = f.readlines()
                
        updated = False
        new_lines = []
        for line in lines:
            if line.startswith("WHISPER_CPP_PATH="):
                new_lines.append(f"WHISPER_CPP_PATH={cpp_path}\n")
                updated = True
            else:
                new_lines.append(line)
                
        if not updated:
            new_lines.append(f"\nWHISPER_CPP_PATH={cpp_path}\n")
            
        with open(env_path, "w") as f:
            f.writelines(new_lines)

    def transcribe_whisper_cpp(self, audio_path: str, prompt_str: str = "", language: str = "auto", translate_to_english: bool = False, enable_auto_completion: bool = False, with_timestamps: bool = False) -> str:
        """
        Transcribes audio using a locally compiled whisper.cpp executable or server.
        Fastest local execution on M-series Macs using Metal/CoreML acceleration.
        """
        # 1. Try whisper-server for instant transcription first
        url = local_whisper.INFERENCE_URL
        client = _get_local_http_client()
        # Standard dictations (<= 30s) fit within a single Mel window: greedy decoding (beam=1)
        # is 2x faster, avoids 5 parallel beam evaluations, and preserves complete accuracy.
        # Long clips (> 30s) use beam=5 and fallback decoding to prevent dropped tails across 30s boundaries.
        is_long_clip = False
        try:
            # 16kHz 16-bit mono = 32,000 bytes/sec. 30s = 960,000 bytes.
            is_long_clip = os.path.getsize(audio_path) > 960000
        except Exception:
            pass

        beam_size = "5" if is_long_clip else "1"
        temp_inc = "0.2" if is_long_clip else "0.0"

        try:
            with open(audio_path, "rb") as f:
                files = {"file": (os.path.basename(audio_path), f, "audio/wav")}
                data = {
                    "response_format": "verbose_json" if with_timestamps else "json",
                    "language": language,
                    "temperature": "0.0",
                    "temperature_inc": temp_inc,
                    "beam_size": beam_size,
                    "best_of": beam_size,
                    "suppress_non_speech": "true",
                    "entropy_thold": "2.8",
                    "logprob_thold": "-1.0",
                    "no_speech_thold": "0.6"
                }
                if not enable_auto_completion:
                    data["no_context"] = "true"
                if prompt_str and len(prompt_str.strip()) > 0:
                    data["prompt"] = f"Vocabulary: {prompt_str.strip()}."
                if translate_to_english:
                    data["task"] = "translate"
                    data["translate"] = "true"
                
                t_w0 = time.perf_counter()
                response = client.post(url, files=files, data=data, timeout=30.0)
                self.last_whisper_ms = (time.perf_counter() - t_w0) * 1000.0
                self.last_provider = "whisper-server (RAM)"
                TranscribeService.last_whisper_ms = self.last_whisper_ms
                TranscribeService.last_provider = self.last_provider
                response.raise_for_status()
                result_json = response.json()
                    
                if with_timestamps and "segments" in result_json:
                    lines = []
                    for seg in result_json["segments"]:
                        start_s = int(seg.get("start", 0))
                        end_s = int(seg.get("end", 0))
                        start_str = f"{start_s//60:02d}:{start_s%60:02d}"
                        end_str = f"{end_s//60:02d}:{end_s%60:02d}"
                        text = seg.get("text", "").strip()
                        if text:
                            lines.append(f"[{start_str} - {end_str}] {text}")
                    if lines:
                        print(f"[*] Successfully extracted {len(lines)} timestamped segments in {self.last_whisper_ms:.1f}ms.")
                        return "\n".join(lines)

                if "text" in result_json:
                    print(f"[*] Successfully used whisper-server (Instant RAM Transcription in {self.last_whisper_ms:.1f}ms).")
                    return result_json["text"].strip()
        except Exception as e:
            print(f"[!] whisper-server inference error: {e}")

        # 2. Fall back to Command line whisper.cpp
        from dotenv import load_dotenv
        load_dotenv(override=True)
        
        cpp_path = self._ensure_whisper_cpp_binary()
        if not cpp_path or not os.path.exists(cpp_path):
            raise FileNotFoundError(f"whisper.cpp binary not found at: {cpp_path}")

        model_path = os.getenv("WHISPER_MODEL_PATH")
        if not model_path or not os.path.exists(model_path):
            from model_manager import ModelManager, MODELS_DIR
            mm = ModelManager()
            active_id = mm.get_active_model()
            candidate = os.path.join(MODELS_DIR, f"ggml-{active_id}.bin")
            if os.path.exists(candidate):
                model_path = candidate
                
        if not model_path or not os.path.exists(model_path):
            raise FileNotFoundError(f"whisper.cpp model not found at: {model_path}")

        cmd = [
            cpp_path,
            "-m", model_path,
            "-f", audio_path,
            "-l", language
        ]
        if not with_timestamps:
            cmd.append("-nt")
            
        import platform
        if platform.machine().lower() not in ["arm64", "aarch64"]:
            cmd.append("-ng")
        if translate_to_english:
            cmd.append("-tr")
        if not enable_auto_completion:
            cmd.extend(["-mc", "0", "-sns", "-nth", "0.6", "-et", "2.8", "-lpt", "-1.0"])
            
        if prompt_str:
            cmd.extend(["--prompt", prompt_str])

        try:
            t_w0 = time.perf_counter()
            result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, check=True)
            self.last_whisper_ms = (time.perf_counter() - t_w0) * 1000.0
            self.last_provider = f"whisper-cli ({os.path.basename(model_path)})"
            TranscribeService.last_whisper_ms = self.last_whisper_ms
            TranscribeService.last_provider = self.last_provider
            if with_timestamps:
                return result.stdout.strip()
            return normalize_whisper_text(result.stdout)
        except subprocess.CalledProcessError as e:
            error_msg = e.stderr or e.stdout
            raise RuntimeError(f"whisper.cpp execution failed: {error_msg}")

    def transcribe_faster_whisper(self, audio_path: str, prompt_str: str = "", language: str = "auto", translate_to_english: bool = False, enable_auto_completion: bool = False, with_timestamps: bool = False) -> str:
        """
        Ultra-fast CTranslate2 local whisper transcription.
        Runs in ~150-300ms on modern multicore CPU/CUDA with int8 quantization.
        """
        from faster_whisper import WhisperModel
        
        from model_manager import ModelManager
        active_model = ModelManager().get_active_model()
        model_size = resolve_faster_whisper_model_name(active_model, language)

        global _faster_whisper_cache
        if model_size not in _faster_whisper_cache:
            device, compute_type = get_whisper_device_and_compute_type()
            cpu_threads = min(8, os.cpu_count() or 4) if device == "cpu" else 4
            print(f"[*] Loading faster-whisper model '{model_size}' onto {device.upper()} ({compute_type})...")
            try:
                _faster_whisper_cache[model_size] = WhisperModel(
                    model_size,
                    device=device,
                    compute_type=compute_type,
                    cpu_threads=cpu_threads
                )
                print(f"[+] Loaded faster-whisper model '{model_size}' on {device.upper()} ({compute_type}) successfully.")
            except Exception as load_err:
                if device == "cuda":
                    print(f"[!] CUDA load failed for '{model_size}' ({load_err}). Falling back to CPU...")
                    cpu_threads = min(8, os.cpu_count() or 4)
                    _faster_whisper_cache[model_size] = WhisperModel(
                        model_size,
                        device="cpu",
                        compute_type="int8",
                        cpu_threads=cpu_threads
                    )
                else:
                    raise
        model = _faster_whisper_cache[model_size]

        kwargs = {
            "beam_size": 5, # Greedy (1) was measured to drop phrases on long dictations; keep beam search
            "vad_filter": True,
            "vad_parameters": dict(min_silence_duration_ms=350),
            "condition_on_previous_text": False,
        }
        if prompt_str:
            kwargs["initial_prompt"] = prompt_str
        if language != "auto":
            kwargs["language"] = language
        if translate_to_english:
            kwargs["task"] = "translate"

        t_w0 = time.perf_counter()
        try:
            segments, info = model.transcribe(audio_path, **kwargs)
            if with_timestamps:
                lines = []
                for seg in segments:
                    start_s = int(seg.start)
                    end_s = int(seg.end)
                    start_str = f"{start_s//60:02d}:{start_s%60:02d}"
                    end_str = f"{end_s//60:02d}:{end_s%60:02d}"
                    t = seg.text.strip()
                    if t:
                        lines.append(f"[{start_str} - {end_str}] {t}")
                result_text = "\n".join(lines)
            else:
                result_text = join_transcript_parts([seg.text for seg in segments])
        except Exception as e:
            err_str = str(e).lower()
            if "cuda" in err_str or "cublas" in err_str or "device" in err_str:
                print(f"[!] CUDA execution error ({e}). Falling back to CPU for '{model_size}'...")
                cpu_threads = min(8, os.cpu_count() or 4)
                model = WhisperModel(model_size, device="cpu", compute_type="int8", cpu_threads=cpu_threads)
                _faster_whisper_cache[model_size] = model
                segments, info = model.transcribe(audio_path, **kwargs)
                if with_timestamps:
                    lines = []
                    for seg in segments:
                        start_s = int(seg.start)
                        end_s = int(seg.end)
                        start_str = f"{start_s//60:02d}:{start_s%60:02d}"
                        end_str = f"{end_s//60:02d}:{end_s%60:02d}"
                        t = seg.text.strip()
                        if t:
                            lines.append(f"[{start_str} - {end_str}] {t}")
                    result_text = "\n".join(lines)
                else:
                    result_text = join_transcript_parts([seg.text for seg in segments])
            elif kwargs.get("vad_filter"):
                print(f"[!] faster-whisper VAD error ({e}). Retrying transcription with vad_filter=False...")
                kwargs["vad_filter"] = False
                kwargs.pop("vad_parameters", None)
                segments, info = model.transcribe(audio_path, **kwargs)
                if with_timestamps:
                    lines = []
                    for seg in segments:
                        start_s = int(seg.start)
                        end_s = int(seg.end)
                        start_str = f"{start_s//60:02d}:{start_s%60:02d}"
                        end_str = f"{end_s//60:02d}:{end_s%60:02d}"
                        t = seg.text.strip()
                        if t:
                            lines.append(f"[{start_str} - {end_str}] {t}")
                    result_text = "\n".join(lines)
                else:
                    result_text = join_transcript_parts([seg.text for seg in segments])
            else:
                raise e

        self.last_whisper_ms = (time.perf_counter() - t_w0) * 1000.0
        self.last_provider = f"faster-whisper ({model_size})"
        TranscribeService.last_whisper_ms = self.last_whisper_ms
        TranscribeService.last_provider = self.last_provider
        print(f"[*] faster-whisper transcribed audio in {self.last_whisper_ms:.1f}ms [{self.last_provider}]")
        return result_text

    def transcribe_local_python(self, audio_path: str, prompt_str: str = "", language: str = "auto", translate_to_english: bool = False, enable_auto_completion: bool = False) -> str:
        """
        Attempts to transcribe using standard Python 'openai-whisper' package.
        Uses 'soundfile' to load the audio, bypassing the need for a system 'ffmpeg' installation.
        """
        try:
            import whisper
            import soundfile as sf
            
            # Read the 16kHz WAV file directly into a numpy array using soundfile (packaged in wheels)
            audio_data, sample_rate = sf.read(audio_path)
            
            # Whisper expects a 16-bit float32 array
            audio_data = audio_data.astype('float32')
            
            # Load selected model and transcribe
            active_model = os.getenv("WHISPER_MODEL_PATH", "tiny")
            # Extract the correct string model name (e.g., "tiny", "base", "small")
            # openai-whisper requires a model name string to download its own PyTorch .pt model,
            # as it will crash with WeightsUnpickler error trying to load a C++ ggml .bin file
            model_to_load = "tiny"
            active_model_lower = active_model.lower()
            if "tiny" in active_model_lower:
                model_to_load = "tiny.en" if "en" in active_model_lower else "tiny"
            elif "base" in active_model_lower:
                model_to_load = "base.en" if "en" in active_model_lower else "base"
            elif "small" in active_model_lower:
                model_to_load = "small.en" if "en" in active_model_lower else "small"
            elif "medium" in active_model_lower:
                model_to_load = "medium.en" if "en" in active_model_lower else "medium"
            elif "large" in active_model_lower:
                # Map both large-v3 and distil-large to standard large-v3 in python-whisper
                model_to_load = "large-v3"
            elif "turbo" in active_model_lower:
                model_to_load = "turbo"
            
            # PyTorch 2.6 defaults torch.load to weights_only=True, which breaks openai-whisper.
            # We temporarily patch it to False to allow loading the cached model.
            import torch
            _original_torch_load = torch.load
            def _patched_torch_load(*args, **kwargs):
                kwargs['weights_only'] = False
                return _original_torch_load(*args, **kwargs)
            torch.load = _patched_torch_load
            
            try:
                global _whisper_model_cache
                if model_to_load not in _whisper_model_cache:
                    print(f"[*] Loading openai-whisper model '{model_to_load}' into RAM for the first time...")
                    _whisper_model_cache[model_to_load] = whisper.load_model(model_to_load)
                model = _whisper_model_cache[model_to_load]
            finally:
                # Restore original torch.load
                torch.load = _original_torch_load
                
            kwargs = {}
            if not enable_auto_completion:
                kwargs["condition_on_previous_text"] = False
                kwargs["no_speech_threshold"] = 0.6
            if prompt_str:
                kwargs["initial_prompt"] = prompt_str
            if language != "auto":
                kwargs["language"] = language
            if translate_to_english:
                kwargs["task"] = "translate"
                
            t_w0 = time.perf_counter()
            result = model.transcribe(audio_data, **kwargs)
            self.last_whisper_ms = (time.perf_counter() - t_w0) * 1000.0
            self.last_provider = f"openai-whisper ({model_to_load})"
            TranscribeService.last_whisper_ms = self.last_whisper_ms
            TranscribeService.last_provider = self.last_provider
            return result["text"]
        except ImportError:
            raise RuntimeError(
                "Local 'openai-whisper' python package is not installed. "
                "Configure whisper.cpp in .env or run `pip install openai-whisper`."
            )

    async def transcribe_remote(self, audio_path: str, model_name: str, prompt_str: str = "", language: str = "auto", override_key: str = "", openrouter_key: str = "", translate_to_english: bool = False, provider: str = "") -> str:
        """
        Remote transcription handling Dicty Cloud, direct providers (Groq, Deepgram, ElevenLabs, OpenAI),
        and OpenRouter with proper token routing.
        """
        import os
        from dotenv import load_dotenv
        load_dotenv()
        if os.path.exists("scratch_env"):
            load_dotenv("scratch_env")
        
        # Determine the effective keys
        effective_openai = override_key if override_key else self.openai_key
        effective_openrouter = openrouter_key
        
        env_openrouter = os.getenv("OPENROUTER_API_KEY", "")
        env_openai = get_stt_key("openai")
        env_groq = get_stt_key("groq")
        env_deepgram = get_stt_key("deepgram")
        env_elevenlabs = get_stt_key("elevenlabs")
        
        # If the user brought their own key for this model's provider, call that provider directly
        # (lowest latency, billed to the user) even when Dicty Cloud is the selected account mode.
        own_provider = direct_provider_for_model(model_name)
        has_own_key = bool(own_provider and get_stt_key(own_provider))
        is_dicty_cloud = provider == "dicty_cloud" and not has_own_key
        if provider == "dicty_cloud" and has_own_key:
            print(f"[*] [Cloud STT] Using your own {own_provider} key for '{model_name}' (bypassing Dicty Cloud)")
        fallback_note = ""
        
        url = ""
        api_key = ""
        headers = {}
        is_deepgram = False
        target_model = model_name

        # 1. Dicty Cloud Managed Mode
        if is_dicty_cloud:
            dicty_cloud_url = os.getenv("DICTY_CLOUD_URL", "https://dicty-backend.dicty-backend.workers.dev")
            url = f"{dicty_cloud_url}/v1/audio/transcriptions"
            api_key = override_key  # Dicty JWT Token
            if not api_key:
                try:
                    import auth
                    session = auth.SecureAuthManager.get_session()
                    if session and session.get("jwt_token"):
                        api_key = session["jwt_token"]
                except Exception:
                    pass

            if not api_key:
                # No valid Dicty token found! Fallback to OpenRouter if user has an OpenRouter key
                for k in [effective_openrouter, env_openrouter]:
                    if k and isinstance(k, str) and k.strip().startswith("sk-"):
                        api_key = k.strip()
                        url = "https://openrouter.ai/api/v1/audio/transcriptions"
                        target_model = "openai/whisper-large-v3" if model_name in ["whisper-1", "openai/whisper-1"] else model_name
                        headers = {"Authorization": f"Bearer {api_key}"}
                        print(f"[!] [Cloud STT] No Dicty Cloud token found. Falling back to user's OpenRouter token ({url}) for '{model_name}'")
                        break
                if not api_key:
                    raise ValueError("No Dicty Cloud token found. Please log in with an active Pro account in the Account tab, or switch to your personal OpenRouter key.")
            else:
                headers = {"Authorization": f"Bearer {api_key}"}
                print(f"[*] [Cloud STT] Routing via Dicty Cloud ({dicty_cloud_url}) for model '{model_name}'")

        # 2. Direct Groq Provider
        elif model_name.startswith("groq/"):
            # Check Groq key
            for k in [env_groq, effective_openrouter, effective_openai]:
                if k and isinstance(k, str) and k.strip().startswith("gsk_"):
                    api_key = k.strip()
                    break
            if not api_key and env_groq:
                api_key = env_groq.strip()
                
            if api_key:
                url = "https://api.groq.com/openai/v1/audio/transcriptions"
                target_model = model_name.replace("groq/", "")
                headers = {"Authorization": f"Bearer {api_key}"}
                print(f"[*] [Cloud STT] Direct Groq API routing ({url}) using key {api_key[:8]}... (Model: {target_model})")
                fallback_note = "your Groq key"
            else:
                # Fallback: check if user has OpenRouter key
                for k in [effective_openrouter, env_openrouter]:
                    if k and isinstance(k, str) and k.strip().startswith("sk-"):
                        api_key = k.strip()
                        url = "https://openrouter.ai/api/v1/audio/transcriptions"
                        target_model = "openai/whisper-large-v3"
                        headers = {"Authorization": f"Bearer {api_key}"}
                        print(f"[*] [Cloud STT] Groq key not configured, falling back to OpenRouter ({url}) for '{model_name}'")
                        fallback_note = "fallback: no Groq key"
                        break

        # 3. Direct Deepgram Provider
        elif model_name.startswith("deepgram/"):
            api_key = env_deepgram.strip()
            if api_key:
                deepgram_model = model_name.replace("deepgram/", "")
                dg_host = await asyncio.to_thread(_deepgram_host)
                url = f"https://{dg_host}/v1/listen?model={quote_plus(deepgram_model)}&smart_format=true"
                if language and language != "auto":
                    url += f"&language={quote_plus(language)}"
                elif deepgram_model.startswith("nova-3"):
                    url += "&language=multi"
                if prompt_str and deepgram_model.startswith("nova-3"):
                    for term in [t.strip() for t in prompt_str.split(",") if t.strip()][:50]:
                        url += f"&keyterm={quote_plus(term)}"
                headers = {"Authorization": f"Token {api_key}", "Content-Type": "audio/wav"}
                is_deepgram = True
                print(f"[*] [Cloud STT] Direct Deepgram API routing ({url}) using key {api_key[:8]}...")
            else:
                # Fallback to OpenRouter if available
                for k in [effective_openrouter, env_openrouter]:
                    if k and isinstance(k, str) and k.strip().startswith("sk-"):
                        api_key = k.strip()
                        url = "https://openrouter.ai/api/v1/audio/transcriptions"
                        target_model = "openai/whisper-large-v3"
                        headers = {"Authorization": f"Bearer {api_key}"}
                        print(f"[*] [Cloud STT] Deepgram key not configured, falling back to OpenRouter ({url}) for '{model_name}'")
                        fallback_note = "fallback: no Deepgram key"
                        break

        # 4. Direct ElevenLabs Provider
        elif model_name.startswith("elevenlabs/"):
            for k in [env_elevenlabs, effective_openrouter, effective_openai]:
                if k and isinstance(k, str) and k.strip().startswith("sk_"):
                    api_key = k.strip()
                    break
            if not api_key and env_elevenlabs:
                api_key = env_elevenlabs.strip()
                
            if api_key:
                url = "https://api.elevenlabs.io/v1/speech-to-text"
                target_model = model_name.replace("elevenlabs/", "").replace("-", "_")
                headers = {"xi-api-key": api_key}
                print(f"[*] [Cloud STT] Direct ElevenLabs API routing ({url}) using key {api_key[:8]}...")
                fallback_note = "your ElevenLabs key"
            else:
                for k in [effective_openrouter, env_openrouter]:
                    if k and isinstance(k, str) and k.strip().startswith("sk-"):
                        api_key = k.strip()
                        url = "https://openrouter.ai/api/v1/audio/transcriptions"
                        target_model = "openai/whisper-large-v3"
                        headers = {"Authorization": f"Bearer {api_key}"}
                        print(f"[*] [Cloud STT] ElevenLabs key not configured, falling back to OpenRouter ({url}) for '{model_name}'")
                        fallback_note = "fallback: no ElevenLabs key"
                        break

        # 5. Direct OpenAI Provider
        elif model_name == "whisper-1" or model_name.startswith("openai/"):
            # Check OpenAI key first (sk-proj-... or sk-... but not sk-or-)
            for k in [effective_openai, env_openai]:
                if k and isinstance(k, str):
                    k_clean = k.strip()
                    if k_clean.startswith("sk-") and not k_clean.startswith("sk-or-"):
                        api_key = k_clean
                        url = "https://api.openai.com/v1/audio/transcriptions"
                        if translate_to_english:
                            url = "https://api.openai.com/v1/audio/translations"
                        target_model = "whisper-1"
                        headers = {"Authorization": f"Bearer {api_key}"}
                        print(f"[*] [Cloud STT] Direct OpenAI API routing ({url}) using key {api_key[:10]}...")
                        break
                        
            # If no direct OpenAI key, route via OpenRouter using user's OpenRouter key
            if not api_key:
                for k in [effective_openrouter, env_openrouter]:
                    if k and isinstance(k, str) and k.strip().startswith("sk-"):
                        api_key = k.strip()
                        url = "https://openrouter.ai/api/v1/audio/transcriptions"
                        target_model = "openai/whisper-large-v3"
                        headers = {"Authorization": f"Bearer {api_key}"}
                        print(f"[*] [Cloud STT] Routing OpenAI model via user's OpenRouter token ({api_key[:10]}...) to {url}")
                        break

        # 6. OpenRouter Speech Models (e.g. nvidia/parakeet-tdt-0.6b-v3, or any model with "/")
        else:
            url = "https://openrouter.ai/api/v1/audio/transcriptions"
            target_model = model_name
            # Prioritize the user's entered OpenRouter token from the app UI!
            for k in [effective_openrouter, env_openrouter, effective_openai]:
                if k and isinstance(k, str):
                    k_clean = k.strip()
                    if k_clean.startswith("sk-"):
                        api_key = k_clean
                        if k_clean.startswith("sk-or-"):
                            break
            if api_key:
                headers = {"Authorization": f"Bearer {api_key}"}
                print(f"[*] [Cloud STT] OpenRouter API routing ({url}) using user token {api_key[:12]}... (Model: {target_model})")

        if not api_key or not url:
            raise ValueError(
                f"No valid API key configured for model '{model_name}'. "
                "Please configure your API key in Settings -> API Integrations or re-enable 'Use Dicty Cloud'."
            )
            
        api_key = api_key.strip()
        
        max_retries = 2
        for attempt in range(max_retries + 1):
            try:
                client = get_shared_async_client()
                if is_deepgram:
                    with open(audio_path, "rb") as f:
                        audio_bytes = f.read()
                    t_c0 = time.perf_counter()
                    response = await client.post(url, headers=headers, content=audio_bytes)
                    self.last_whisper_ms = (time.perf_counter() - t_c0) * 1000.0
                    self.last_provider = f"Deepgram ({deepgram_model}, your key)"
                    TranscribeService.last_whisper_ms = self.last_whisper_ms
                    TranscribeService.last_provider = self.last_provider
                    if response.status_code != 200:
                        print(f"[-] Deepgram API Error ({response.status_code}): {response.text}")
                    response.raise_for_status()
                    res_json = response.json()
                    channels = res_json.get("results", {}).get("channels", [])
                    if channels and channels[0].get("alternatives"):
                        return channels[0]["alternatives"][0].get("transcript", "").strip()
                    return ""
                else:
                    with open(audio_path, "rb") as f:
                        files = {"file": (os.path.basename(audio_path), f, "audio/wav")}
                        data = {"model": target_model}
                        if prompt_str:
                            data["prompt"] = prompt_str
                            
                        # ElevenLabs uses model_id instead of model
                        if "elevenlabs.io" in url:
                            data["model_id"] = target_model
                            data.pop("model", None)
                            
                        # If translation requested on OpenRouter, add to prompt as fallback
                        if "openrouter.ai" in url and translate_to_english:
                            if "prompt" in data:
                                data["prompt"] += " Please translate this audio to English."
                            else:
                                data["prompt"] = "Please translate this audio to English."
                                    
                        if language != "auto":
                            data["language"] = language
                            
                        t_c0 = time.perf_counter()
                        response = await client.post(url, headers=headers, files=files, data=data)
                        t_cloud_ms = (time.perf_counter() - t_c0) * 1000.0
                        self.last_whisper_ms = t_cloud_ms
                        self.last_provider = f"Cloud STT ({target_model})" + (f" [{fallback_note}]" if fallback_note else "")
                        TranscribeService.last_whisper_ms = self.last_whisper_ms
                        TranscribeService.last_provider = self.last_provider
                        if response.status_code != 200:
                            print(f"[-] Cloud STT API Error ({response.status_code}): {response.text}")
                        response.raise_for_status()
                        return response.json().get("text", "").strip()
            except Exception as e:
                # 4xx (bad key, bad request, no balance) won't succeed on retry; fail fast to fallback
                if isinstance(e, httpx.HTTPStatusError) and 400 <= e.response.status_code < 500 and e.response.status_code != 429:
                    raise
                if attempt < max_retries:
                    print(f"[*] Cloud API request failed: {e}. Retrying ({attempt + 1}/{max_retries})...")
                    await asyncio.sleep(0.5 * (attempt + 1))
                else:
                    raise

    async def transcribe(self, audio_path: str, vocab_data: list = None, openai_api_key: str = "", openrouter_key: str = "", language: str = "auto", translate_to_english: bool = False, enable_auto_completion: bool = False, with_timestamps: bool = False, provider: str = "", skip_cloud: bool = False) -> str:
        prompt_str = ""
        if vocab_data:
            # Extract canonical target words for initial prompt biasing
            words = []
            for v in vocab_data:
                target = v.get("replacement") or v.get("word")
                if target and target.strip() and target.strip() not in words:
                    words.append(target.strip())
            if words:
                # Cap to 25 terms to strictly preserve Whisper's 224-token prompt limit
                # and prevent prompt dilution or silence hallucinations
                prompt_str = ", ".join(words[:25])
                print(f"[*] Applying vocabulary prompt ({len(words[:25])} terms): {prompt_str}")
        
        raw_text = ""
        
        from model_manager import ModelManager
        mm = ModelManager()
        active_model_id = mm.get_active_model()
        
        models = mm.get_available_models()
        active_model_dict = next((m for m in models if m["id"] == active_model_id), None)
        
        cloud_success = False
        if not skip_cloud and active_model_dict and active_model_dict.get("is_cloud", False):
            own = direct_provider_for_model(active_model_id)
            has_api_key = bool(openai_api_key or openrouter_key or get_stt_key("openai") or os.getenv("OPENROUTER_API_KEY")
                               or (own and get_stt_key(own)) or provider == "dicty_cloud")
            if has_api_key:
                print(f"[*] Active model is Cloud. Routing directly to Cloud API (Model: {active_model_id})...")
                try:
                    raw_text = await self.transcribe_remote(audio_path, active_model_id, prompt_str, language, override_key=openai_api_key, openrouter_key=openrouter_key, translate_to_english=translate_to_english, provider=provider)
                    if raw_text and raw_text.strip():
                        cloud_success = True
                except Exception as remote_err:
                    print(f"[-] Cloud transcription failed: {remote_err}")
            else:
                print(f"[!] Active model is Cloud ({active_model_id}) but no API key configured. Falling back to local speech engine...")

        if not cloud_success:
            can_cpp = bool(self.whisper_cpp_path and os.path.exists(self.whisper_cpp_path))
            # find_spec checks availability without importing (importing openai-whisper pulls in torch: 1-2s)
            import importlib.util
            can_faster = importlib.util.find_spec("faster_whisper") is not None
            can_python = importlib.util.find_spec("whisper") is not None
            import asyncio

            transcription_done = False
            is_win = sys.platform == "win32" or platform.system() == "Windows"

            # 1. On Windows: faster-whisper (CTranslate2 + CUDA) is the native GPU engine
            if is_win and can_faster:
                try:
                    print(f"[*] Attempting local faster-whisper GPU transcription (Language: {language})...")
                    raw_text = await asyncio.to_thread(self.transcribe_faster_whisper, audio_path, prompt_str, language, translate_to_english=translate_to_english, enable_auto_completion=enable_auto_completion, with_timestamps=with_timestamps)
                    transcription_done = True
                except Exception as faster_err:
                    print(f"[-] Local faster-whisper failed: {faster_err}")

            if not transcription_done and can_cpp:
                # Preferred on macOS with Apple Silicon Metal/CoreML GPU
                try:
                    print(f"[*] Attempting local whisper.cpp transcription (Language: {language})...")
                    raw_text = await asyncio.to_thread(self.transcribe_whisper_cpp, audio_path, prompt_str, language, translate_to_english=translate_to_english, enable_auto_completion=enable_auto_completion, with_timestamps=with_timestamps)
                    transcription_done = True
                except Exception as cpp_err:
                    print(f"[-] whisper.cpp transcription failed: {cpp_err}")

            if not transcription_done and can_faster:
                try:
                    print(f"[*] Attempting local faster-whisper transcription (Language: {language})...")
                    raw_text = await asyncio.to_thread(self.transcribe_faster_whisper, audio_path, prompt_str, language, translate_to_english=translate_to_english, enable_auto_completion=enable_auto_completion, with_timestamps=with_timestamps)
                    transcription_done = True
                except Exception as faster_err:
                    print(f"[-] Local faster-whisper failed: {faster_err}")

            if not transcription_done and can_python:
                # 3. Fallback to local python whisper package
                try:
                    print(f"[*] Attempting local python-whisper package transcription (Language: {language})...")
                    raw_text = await asyncio.to_thread(self.transcribe_local_python, audio_path, prompt_str, language, translate_to_english=translate_to_english, enable_auto_completion=enable_auto_completion)
                    transcription_done = True
                except Exception as python_err:
                    print(f"[-] Local python-whisper failed: {python_err}")

            if not transcription_done:
                # 4. Direct fast remote transcription fallback (OpenAI / OpenRouter)
                try:
                    print(f"[*] Routing directly to Cloud STT Whisper transcription (Language: {language})...")
                    raw_text = await self.transcribe_remote(audio_path, "whisper-1", prompt_str, language, override_key=openai_api_key, openrouter_key=openrouter_key, translate_to_english=translate_to_english, provider=provider)
                    transcription_done = True
                except Exception as remote_err:
                    print(f"[-] Remote transcription failed: {remote_err}")

        if not raw_text:
            return ""
            
        return postprocess_transcript(raw_text, vocab_data, keep_timestamps=with_timestamps)

    async def diarize_dialogue(self, timestamped_text: str, raw_text: str = "", model: str = None, api_key: str = None, provider: str = None, base_url: str = None) -> str:
        from llm_service import LLMService
        from prompts import get_meeting_diarization_system_prompt, get_meeting_diarization_user_prompt
        import asyncio
        
        system_prompt = get_meeting_diarization_system_prompt()
        user_prompt = get_meeting_diarization_user_prompt(timestamped_transcript=timestamped_text, raw_text=raw_text)
        
        llm = LLMService()
        try:
            diarized_output = await asyncio.wait_for(
                llm.generate(
                    prompt=user_prompt,
                    system_prompt=system_prompt,
                    model=model,
                    api_key=api_key,
                    provider=provider,
                    base_url=base_url
                ),
                timeout=25.0
            )
            return diarized_output.strip()
        except Exception as e:
            print(f"[!] Diarization LLM error: {e}, falling back to timestamped transcript")
            return timestamped_text if timestamped_text else raw_text

    async def transcribe_segments(
        self,
        audio_path: str,
        vocab_data: list = None,
        openai_api_key: str = "",
        openrouter_key: str = "",
        language: str = "auto",
        translate_to_english: bool = False,
        enable_auto_completion: bool = False,
        provider: str = ""
    ) -> list[dict]:
        """
        Transcribes audio and returns a list of segment dicts:
        [{'start': float, 'end': float, 'text': str}]
        with precise float seconds where supported.
        """
        from meeting_dialogue import parse_whisper_timestamped
        import wave

        # Measure audio duration for fallback
        audio_dur = 0.0
        try:
            with wave.open(audio_path, 'rb') as w:
                audio_dur = w.getnframes() / float(w.getframerate())
        except Exception:
            pass

        # 1. Transcribe with timestamps enabled
        text_with_timestamps = await self.transcribe(
            audio_path,
            vocab_data=vocab_data,
            openai_api_key=openai_api_key,
            openrouter_key=openrouter_key,
            language=language,
            translate_to_english=translate_to_english,
            enable_auto_completion=enable_auto_completion,
            with_timestamps=True,
            provider=provider
        )

        if not text_with_timestamps or not text_with_timestamps.strip():
            return []

        parsed_segs = parse_whisper_timestamped(text_with_timestamps)
        if parsed_segs:
            # If the segments came back with 0.0 - 0.0 (plain text without timestamps, e.g. cloud model)
            if len(parsed_segs) == 1 and parsed_segs[0].start == 0.0 and parsed_segs[0].end == 0.0:
                return [{
                    "start": 0.0,
                    "end": max(audio_dur, 1.0),
                    "text": parsed_segs[0].text
                }]
            return [{
                "start": s.start,
                "end": s.end if s.end > s.start else s.start + 1.0,
                "text": s.text
            } for s in parsed_segs]

        return [{
            "start": 0.0,
            "end": max(audio_dur, 1.0),
            "text": text_with_timestamps.strip()
        }]
