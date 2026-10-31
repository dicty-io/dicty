import os
import json
import httpx
import threading

import sys
import platform

from dicty_paths import get_user_data_dir

def get_resource_path(relative_path):
    if getattr(sys, 'frozen', False):
        base = sys._MEIPASS
    else:
        from dicty_paths import PROJECT_ROOT
        base = PROJECT_ROOT
    return os.path.join(base, relative_path)

DATA_DIR = get_user_data_dir()
MODELS_DIR = os.path.join(DATA_DIR, "models")
SETTINGS_FILE = os.path.join(DATA_DIR, "settings.json")
CONFIG_FILE = get_resource_path("models_config.json")

os.makedirs(MODELS_DIR, exist_ok=True)

def ensure_models_dir_setup():
    os.makedirs(MODELS_DIR, exist_ok=True)
    readme_path = os.path.join(MODELS_DIR, "README.txt")
    if not os.path.exists(readme_path):
        try:
            content = f"""================================================================================
DICTY LOCAL MODELS DIRECTORY
Location: {MODELS_DIR}
================================================================================

This is the local storage folder for Dicty voice recognition and text AI models.

1. SUPPORTED MODEL FORMATS:
   -----------------------------------------------------------------------------
   * Whisper Speech Recognition (GGML/GGUF):
     - File extensions: .bin or .gguf
     - Example filenames:
       * ggml-base.en.bin
       * ggml-small.bin
       * ggml-large-v3-turbo.bin
       * whisper-base.gguf
     - Download repository: https://huggingface.co/ggerganov/whisper.cpp/tree/main

   * Local AI / LLM Text Models:
     - File extension: .gguf
     - Example filenames:
       * llama-3.2-3b-instruct.gguf
       * qwen2.5-1.5b-instruct.gguf
     - Download repository: https://huggingface.co/models?search=gguf

   * Fast Dictation Engine (faster-whisper / CTranslate2):
     - On Windows, Dicty uses CTranslate2 for ultra-fast local dictation (<200ms).
     - Standard runtime models are cached in:
       %USERPROFILE%\\.cache\\huggingface\\hub\\
       (A junction link to this cache is provided in this folder as 'huggingface_cache')

2. HOW TO ADD MODELS:
   -----------------------------------------------------------------------------
   * OPTION A (Automatic via App):
     In the Dicty app, navigate to 'Models', choose your preferred quantization 
     (e.g., Q5, Q8, F16), and click the download button (arrow down). 
     Dicty will download the model directly into this directory.
   
   * OPTION B (Manual File Placement):
     Download or copy any supported .bin or .gguf model file directly into 
     this folder. Dicty will automatically detect and list it in the app.

3. ACTIVATING A MODEL:
   -----------------------------------------------------------------------------
   Once downloaded or copied here, open Dicty's 'Models' library, click the 
   model row, and click the Activate icon (or assign it to your desired mode 
   in 'Modes & Shortcuts').
================================================================================
"""
            with open(readme_path, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception as e:
            print(f"[!] Warning: Could not create models README.txt: {e}")

    # On Windows, link ~/.cache/huggingface/hub as a junction inside MODELS_DIR so users can see faster-whisper models
    if platform.system() == "Windows":
        hf_cache = os.path.expanduser("~/.cache/huggingface/hub")
        junction_path = os.path.join(MODELS_DIR, "huggingface_cache")
        if os.path.isdir(hf_cache) and not os.path.exists(junction_path):
            try:
                import subprocess
                subprocess.run(["cmd", "/c", "mklink", "/J", junction_path, hf_cache], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except Exception as e:
                print(f"[!] Warning: Could not create junction to HF cache: {e}")

ensure_models_dir_setup()

FALLBACK_MODELS = [
    {"id": "openai/whisper-1", "name": "Cloud Whisper 1", "size": "Cloud", "speed": 1.0, "accuracy": 0.99, "url": "", "is_cloud": True, "description": "Official OpenAI Whisper cloud API for ultra-high accuracy speech recognition across all languages."},
    {"id": "nvidia/parakeet-tdt-0.6b-v3", "name": "Nvidia Parakeet", "size": "Cloud", "speed": 1.0, "accuracy": 0.98, "url": "", "is_cloud": True, "description": "Blazing-fast cloud speech recognition powered by Nvidia Parakeet architecture."},
    {"id": "tiny.en", "name": "Nano", "size": "31 MB", "speed": 1.0, "accuracy": 0.4, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin", "description": "Ultra-fast, lightweight English model with minimal memory footprint.", "is_cloud": False},
    {"id": "tiny", "name": "Nano", "size": "31 MB", "speed": 1.0, "accuracy": 0.4, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin", "description": "Ultra-fast, lightweight multilingual model for resource-constrained systems.", "is_cloud": False},
    {"id": "base.en", "name": "Base", "size": "57 MB", "speed": 0.8, "accuracy": 0.6, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin", "description": "Fast, reliable baseline model for everyday clear English speech.", "is_cloud": False},
    {"id": "base", "name": "Base", "size": "57 MB", "speed": 0.8, "accuracy": 0.6, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin", "description": "Balanced multilingual baseline model for everyday transcription across 90+ languages.", "is_cloud": False},
    {"id": "small.en", "name": "Fast", "size": "181 MB", "speed": 0.6, "accuracy": 0.8, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin", "description": "The ideal balance of high accuracy and rapid speed for English dictation.", "is_cloud": False},
    {"id": "small", "name": "Fast", "size": "181 MB", "speed": 0.6, "accuracy": 0.8, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin", "description": "High-speed multilingual model offering great accuracy across 90+ languages.", "is_cloud": False},
    {"id": "medium.en", "name": "Pro", "size": "514 MB", "speed": 0.4, "accuracy": 0.9, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.en.bin", "description": "Professional-grade English accuracy, highly tuned for complex and technical vocabulary.", "is_cloud": False},
    {"id": "medium", "name": "Pro", "size": "514 MB", "speed": 0.4, "accuracy": 0.9, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin", "description": "Professional-grade multilingual accuracy, excellent for nuanced vocabulary and accents.", "is_cloud": False},
    {"id": "distil-large-v3", "name": "Turbo (Distil)", "size": "1.5 GB", "speed": 0.8, "accuracy": 0.8, "url": "https://huggingface.co/distil-whisper/distil-large-v3-ggml/resolve/main/ggml-distil-large-v3.bin", "description": "Ultra-fast distilled model delivering near-maximum accuracy, optimized specifically for English speech.", "is_cloud": False},
    {"id": "large-v3-turbo", "name": "Turbo", "size": "547 MB", "speed": 0.8, "accuracy": 0.85, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin", "description": "OpenAI's flagship turbo architecture, delivering near-maximum accuracy with blazing fast speed across all languages.", "is_cloud": False},
    {"id": "large-v3", "name": "Max", "size": "3.1 GB", "speed": 0.2, "accuracy": 1.0, "url": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin", "description": "Maximum-precision open-source model, offering highest accuracy for complex audio, dialects, and quiet speech.", "is_cloud": False},
    {"id": "large-v3-turbo-ja", "name": "Turbo (Japanese)", "size": "1.6 GB", "speed": 0.8, "accuracy": 0.98, "url": "https://huggingface.co/litagin/whisper-large-v3-turbo-ja-gguf/resolve/main/ggml-large-v3-turbo-ja.bin", "description": "Turbo architecture fine-tuned specifically for natural, accurate Japanese transcription.", "is_cloud": False},
    {"id": "large-v2-zh", "name": "BELLE (Chinese)", "size": "3.1 GB", "speed": 0.2, "accuracy": 0.95, "url": "https://huggingface.co/BELLE-2/BELLE-Whisper-large-v2-zh/resolve/main/ggml-model.bin", "description": "Specialized Chinese model optimized for Mandarin and regional dialect recognition.", "is_cloud": False},
    {"id": "large-v2-french", "name": "Large (French)", "size": "3.1 GB", "speed": 0.2, "accuracy": 0.95, "url": "https://huggingface.co/bofenghuang/whisper-large-v2-french/resolve/main/ggml-model.bin", "description": "Specialized French model optimized on extensive native speech to eliminate silent letter errors.", "is_cloud": False}
]

LOCAL_TEXT_MODEL_FILES = {
    "qwen3.5-0.8b": ["Qwen_Qwen3.5-0.8B-Q4_K_M.gguf", "qwen3.5-0.8b.gguf", "qwen3.5-0.8b.bin"],
    "qwen2.5-1.5b-instruct": ["qwen2.5-1.5b-instruct-q4_k_m.gguf", "qwen2.5-1.5b-instruct.gguf", "qwen2.5-1.5b-instruct.bin"],
    "qwen3.5-2b": ["Qwen_Qwen3.5-2B-Q4_K_M.gguf", "qwen3.5-2b.gguf", "qwen3.5-2b.bin"],
    "llama-3.2-3b-instruct": ["Llama-3.2-3B-Instruct-Q4_K_M.gguf", "llama-3.2-3b-instruct.gguf", "llama-3.2-3b-instruct.bin"],
}

class ModelManager:
    def __init__(self):
        self.download_progress = {}  # model_id -> float (0.0 to 100.0, or -1.0 on error)
        self.downloading = set()
        self.cancelled_downloads = set()
        self.MODELS_DIR = MODELS_DIR
        self.models_dir = MODELS_DIR
        ensure_models_dir_setup()

    def get_available_models(self) -> list:
        candidate_paths = [
            CONFIG_FILE,
            get_resource_path("models_config.json"),
            "models_config.json"
        ]
        if getattr(sys, 'frozen', False):
            candidate_paths.insert(0, os.path.join(sys._MEIPASS, "models_config.json"))
            
        models = []
        for path in candidate_paths:
            if path and os.path.exists(path):
                try:
                    with open(path, "r") as f:
                        data = json.load(f)
                        models = data.get("models", [])
                        if models:
                            break
                except Exception as e:
                    print(f"[!] Error loading models config from {path}: {e}")
                    
        if not models:
            models = list(FALLBACK_MODELS)

        # Detect user-placed custom model files in MODELS_DIR
        try:
            existing_ids = {m["id"] for m in models}
            known_filenames = set()
            for m in models:
                if m.get("filename"):
                    known_filenames.add(m["filename"].lower())
            for fnames in LOCAL_TEXT_MODEL_FILES.values():
                for fn in fnames:
                    known_filenames.add(fn.lower())

            for f in self.get_downloaded_models():
                if f.lower() in known_filenames:
                    continue
                clean_id = f.replace("ggml-", "").replace(".bin", "").replace(".gguf", "")
                if clean_id in existing_ids or f in existing_ids:
                    continue
                full_p = os.path.join(MODELS_DIR, f)
                if os.path.isfile(full_p):
                    size_bytes = os.path.getsize(full_p)
                    size_mb = size_bytes / (1024 * 1024)
                    size_str = f"{size_mb:.0f} MB" if size_mb < 1000 else f"{size_mb/1024:.1f} GB"
                    is_text = f.endswith(".gguf") or any(k in clean_id.lower() for k in ["llama", "qwen", "gemma", "mistral", "phi"])
                    display_name = clean_id.replace("_", " ").replace("-", " ").title()
                    models.append({
                        "id": clean_id,
                        "name": display_name,
                        "size": size_str,
                        "speed": 0.7,
                        "accuracy": 0.8,
                        "url": "",
                        "is_cloud": False,
                        "category": "text" if is_text else "voice",
                        "is_custom": True,
                        "tag": "Your file",
                        "best_for": "Your file",
                        "description": f"Custom model file ({f}) in local models directory."
                    })
                    existing_ids.add(clean_id)
        except Exception as e:
            print(f"[!] Error detecting custom models: {e}")

        return models

    def get_downloaded_models(self) -> list:
        if not os.path.exists(MODELS_DIR):
            return []
        valid_files = []
        try:
            for f in os.listdir(MODELS_DIR):
                if f == "huggingface_cache" or f.lower() == "readme.txt":
                    continue
                full_p = os.path.join(MODELS_DIR, f)
                if os.path.isfile(full_p) and (f.endswith(".bin") or f.endswith(".gguf")):
                    try:
                        if os.path.getsize(full_p) > 1_000_000:
                            valid_files.append(f)
                        else:
                            print(f"[!] Removing corrupt/incomplete model file: {full_p}")
                            os.remove(full_p)
                    except Exception:
                        pass
        except Exception as e:
            print(f"[!] Error reading models dir: {e}")
        return valid_files

    def _is_hf_cached(self, model_id: str) -> bool:
        hf_hub_dir = os.path.expanduser("~/.cache/huggingface/hub")
        if not os.path.isdir(hf_hub_dir):
            return False
        if model_id == "distil-large-v3":
            exact_folder = "models--Systran--faster-distil-whisper-large-v3"
        elif model_id in ["tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large-v1", "large-v2", "large-v3"]:
            exact_folder = f"models--Systran--faster-whisper-{model_id}"
        elif "turbo" in model_id:
            exact_folder = "models--deepdml--faster-whisper-large-v3-turbo-ct2"
        else:
            exact_folder = f"models--Systran--faster-whisper-{model_id}"

        target_dir = os.path.join(hf_hub_dir, exact_folder)
        if os.path.isdir(target_dir):
            snapshots = os.path.join(target_dir, "snapshots")
            if os.path.isdir(snapshots) and os.listdir(snapshots):
                return True
        return False

    def is_model_downloaded(self, model_id: str) -> bool:
        # 1. Cloud models (OpenRouter, Dicty Cloud, Groq, Deepgram, ElevenLabs) are always ready
        if "/" in model_id:
            return True
        models = self.get_available_models()
        for m in models:
            if m["id"] == model_id and m.get("is_cloud", False):
                return True

        # 2. Check local text models catalog filenames
        if model_id in LOCAL_TEXT_MODEL_FILES:
            for fn in LOCAL_TEXT_MODEL_FILES[model_id]:
                p = os.path.join(MODELS_DIR, fn)
                if os.path.isfile(p) and os.path.getsize(p) >= 100_000_000:
                    return True

        # 3. Explicit local GGUF/bin files in MODELS_DIR
        downloaded = self.get_downloaded_models()
        for d in downloaded:
            clean_id = d.replace("ggml-", "").replace(".bin", "").replace(".gguf", "")
            if clean_id == model_id or d == f"ggml-{model_id}.bin" or d == f"ggml-{model_id}.gguf" or d == f"{model_id}.bin" or d == f"{model_id}.gguf":
                return True
            if self._is_model_variant(d, model_id):
                return True

        # 4. Check if cached in Hugging Face Hub (for faster-whisper on Windows / CPU)
        if self._is_hf_cached(model_id):
            return True

        return False

    def get_settings(self) -> dict:
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    return json.load(f)
            except Exception as e:
                print(f"[!] Error reading settings from {SETTINGS_FILE}: {e}")
        return {}

    def get_active_model(self) -> str:
        # 1. First priority: What the user explicitly selected in settings.json
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
                    if "active_model" in config and config["active_model"]:
                        return config["active_model"]
            except Exception as e:
                print(f"[!] Error loading active_model from {SETTINGS_FILE}: {e}")
                
        # 2. Check if WHISPER_MODEL_PATH env var points to a valid model
        env_model = os.getenv("WHISPER_MODEL_PATH")
        if env_model:
            clean_env = os.path.basename(env_model).replace("ggml-", "").replace(".bin", "").replace(".gguf", "")
            if clean_env:
                return clean_env

        # 3. If no explicit selection in settings, check downloaded models
        downloaded = self.get_downloaded_models()
        for d in downloaded:
            clean_id = d.replace("ggml-", "").replace(".bin", "").replace(".gguf", "")
            if clean_id in ["tiny.en", "tiny", "base.en", "base"]:
                return clean_id
        if downloaded:
            for d in downloaded:
                clean_id = d.replace("ggml-", "").replace(".bin", "").replace(".gguf", "")
                for m in self.get_available_models():
                    if m["id"] == clean_id:
                        return m["id"]
                        
        # 4. Fallback default: fast and reliable baseline
        return "tiny.en" if platform.system() == "Windows" else "base.en"

    def set_active_model(self, model_id: str):
        config = {}
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
            except:
                pass
        config["active_model"] = model_id
        with open(SETTINGS_FILE, "w") as f:
            json.dump(config, f, indent=2)
            
        self._update_env_model_path(model_id)

    def get_active_text_model(self) -> str:
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
                    val = config.get("local_llm_model") or config.get("llm_model")
                    if val and not ("/" in val or config.get("llm_provider") == "openrouter"):
                        return val
            except Exception as e:
                print(f"[!] Error loading active text model: {e}")
        # Default local text model
        return "qwen2.5-1.5b-instruct"

    def set_active_text_model(self, model_id: str):
        config = {}
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
            except:
                pass
        config["local_llm_model"] = model_id
        config["llm_model"] = model_id
        config["llm_provider"] = "local"
        with open(SETTINGS_FILE, "w") as f:
            json.dump(config, f, indent=2)

    def get_keep_model_loaded(self) -> bool:
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
                    return config.get("keep_model_loaded", True)
            except:
                pass
        return True

    def set_keep_model_loaded(self, keep_loaded: bool):
        config = {}
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
            except:
                pass
        config["keep_model_loaded"] = keep_loaded
        with open(SETTINGS_FILE, "w") as f:
            json.dump(config, f, indent=2)

    def _update_env_model_path(self, model_id: str):
        env_path = ".env"
        model_filename = f"ggml-{model_id}.bin"
        full_model_path = os.path.abspath(os.path.join(MODELS_DIR, model_filename))
        
        lines = []
        if os.path.exists(env_path):
            with open(env_path, "r") as f:
                lines = f.readlines()
                
        updated = False
        new_lines = []
        for line in lines:
            if line.startswith("WHISPER_MODEL_PATH="):
                new_lines.append(f"WHISPER_MODEL_PATH={full_model_path}\n")
                updated = True
            else:
                new_lines.append(line)
                
        if not updated:
            new_lines.append(f"\nWHISPER_MODEL_PATH={full_model_path}\n")
            
        with open(env_path, "w") as f:
            f.writelines(new_lines)

    # ggml ftype -> quality label (whisper.cpp ggml_ftype, modulo GGML_QNT_VERSION_FACTOR=1000)
    _GGML_FTYPES = {0: "f32", 1: "f16", 2: "q4_0", 3: "q4_1", 7: "q8_0", 8: "q5_0", 9: "q5_1"}
    _RECOGNIZED_QUALITY_VARIANTS = {
        "q4_0", "q4_1", "q5_0", "q5_1", "q8_0", "f16", "f32", "fp16", "fp32",
        "q2_k", "q3_k_s", "q3_k_m", "q3_k_l", "q4_k_s", "q4_k_m", "q5_k_s", "q5_k_m", "q6_k", "q8_k"
    }

    @classmethod
    def _is_model_variant(cls, filename: str, model_id: str) -> bool:
        """Checks if filename matches model_id with a recognized quality variant,
        preventing large-v3 from matching large-v3-turbo."""
        for prefix in (f"ggml-{model_id}-", f"{model_id}-"):
            if filename.startswith(prefix):
                for ext in (".bin", ".gguf"):
                    if filename.endswith(ext):
                        suffix = filename[len(prefix):-len(ext)].lower()
                        if suffix in cls._RECOGNIZED_QUALITY_VARIANTS or (suffix.startswith("q") and any(c.isdigit() for c in suffix)):
                            return True
        return False

    def get_model_file_path(self, model_id: str):
        for ext in (".bin", ".gguf"):
            p = os.path.join(MODELS_DIR, f"ggml-{model_id}{ext}")
            if os.path.isfile(p):
                return p
            p_no_prefix = os.path.join(MODELS_DIR, f"{model_id}{ext}")
            if os.path.isfile(p_no_prefix):
                return p_no_prefix
        try:
            if os.path.exists(MODELS_DIR):
                for f in os.listdir(MODELS_DIR):
                    if self._is_model_variant(f, model_id):
                        p = os.path.join(MODELS_DIR, f)
                        if os.path.isfile(p):
                            return p
        except Exception:
            pass
        return None

    def detect_file_quality(self, model_id: str):
        """Reads the real quantization from the ggml model header (source of truth)."""
        p = self.get_model_file_path(model_id)
        if not p or not p.endswith(".bin"):
            return None
        try:
            import struct
            with open(p, "rb") as f:
                h = struct.unpack("<12i", f.read(48))
            if h[0] != 0x67676D6C:  # 'ggml'
                return None
            return self._GGML_FTYPES.get(h[11] % 1000)
        except Exception:
            return None

    def get_model_quality(self, model_id: str) -> str:
        actual = self.detect_file_quality(model_id)
        if actual:
            return actual
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
                    qualities = config.get("model_qualities", {})
                    if model_id in qualities:
                        return qualities[model_id]
            except:
                pass
        return "q5_0"

    def set_model_quality(self, model_id: str, quality: str):
        config = {}
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
            except:
                pass
        if "model_qualities" not in config:
            config["model_qualities"] = {}
        config["model_qualities"][model_id] = quality
        with open(SETTINGS_FILE, "w") as f:
            json.dump(config, f, indent=2)

    def start_download(self, model_id: str, quality: str = "q5_0", on_progress=None, on_complete=None):
        if model_id in self.downloading:
            return
        
        models = self.get_available_models()
        target_model = next((m for m in models if m["id"] == model_id), None)
        if not target_model:
            return
            
        self.downloading.add(model_id)
        self.download_progress[model_id] = 0.0
        
        thread = threading.Thread(
            target=self._download_worker,
            args=(target_model, quality, on_progress, on_complete),
            daemon=True
        )
        thread.start()

    def cancel_download(self, model_id: str):
        if model_id in self.downloading:
            self.cancelled_downloads.add(model_id)

    # Pre-quantized variants published in ggerganov/whisper.cpp on Hugging Face.
    # tiny/base/small are only published as q5_1/q8_0; medium/large as q5_0/q8_0.
    _PREQUANTIZED = {
        "tiny": ("q5_1", "q8_0"), "tiny.en": ("q5_1", "q8_0"),
        "base": ("q5_1", "q8_0"), "base.en": ("q5_1", "q8_0"),
        "small": ("q5_1", "q8_0"), "small.en": ("q5_1", "q8_0"),
        "medium": ("q5_0", "q8_0"), "medium.en": ("q5_0", "q8_0"),
        "large-v3": ("q5_0",), "large-v3-turbo": ("q5_0", "q8_0"),
    }
    _GGERGANOV_PREFIX = "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-"

    def _prequantized_url(self, model_id: str, url: str, quality: str):
        """Returns (url, quality) for an upstream pre-quantized file, or (url, None) if not applicable."""
        if not quality or quality == "f16" or not url.startswith(self._GGERGANOV_PREFIX):
            return url, None
        available = self._PREQUANTIZED.get(model_id)
        if not available:
            return url, None
        if quality.startswith("q8"):
            if "q8_0" not in available:
                return url, None  # don't silently downgrade precision
            q = "q8_0"
        else:
            q = available[0]  # q5 family: q5_0 or q5_1 depending on what upstream publishes
        return f"{self._GGERGANOV_PREFIX}{model_id}-{q}.bin", q

    def _download_worker(self, model_data, quality, on_progress, on_complete):
        model_id = model_data["id"]
        url = model_data.get("url", "")

        # On Windows or systems using faster-whisper, download CTranslate2 weights to Hugging Face cache
        is_windows = platform.system() == "Windows"
        can_faster = False
        try:
            import faster_whisper
            can_faster = True
        except ImportError:
            pass

        whisper_models = ["tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large-v1", "large-v2", "large-v3", "distil-large-v3", "large-v3-turbo"]

        if (is_windows or can_faster) and model_id in whisper_models:
            try:
                print(f"[*] Downloading {model_id} via faster-whisper (CTranslate2 for Windows/CPU)...")
                import huggingface_hub
                from faster_whisper.utils import _MODELS

                repo_id = _MODELS.get(model_id)
                if not repo_id:
                    if "turbo" in model_id:
                        repo_id = "deepdml/faster-whisper-large-v3-turbo-ct2"
                    elif "distil" in model_id:
                        repo_id = "Systran/faster-distil-whisper-large-v3"
                    else:
                        repo_id = f"Systran/faster-whisper-{model_id}"

                # Set a generous but finite download timeout so the worker never
                # hangs forever when HuggingFace is slow or unreachable.
                HF_TIMEOUT = int(os.getenv("DICTY_HF_TIMEOUT", "120"))
                try:
                    huggingface_hub.constants.HF_HUB_DOWNLOAD_TIMEOUT = HF_TIMEOUT
                except Exception:
                    pass

                # Use per-file hf_hub_download so we get real byte-level progress
                # instead of the unreliable snapshot_download tqdm_class hook.
                FILES_TO_FETCH = [
                    "config.json",
                    "preprocessor_config.json",
                    "model.bin",
                    "tokenizer.json",
                ]
                # vocabulary files may have varying names; try both common variants
                VOCAB_VARIANTS = ["vocabulary.json", "vocabulary.txt", "vocab.json"]

                self.download_progress[model_id] = 2.0
                if on_progress:
                    on_progress(model_id, 2.0)

                files_done = 0
                files_total = len(FILES_TO_FETCH) + 1  # +1 for vocab

                for fname in FILES_TO_FETCH:
                    if model_id in self.cancelled_downloads:
                        break
                    try:
                        huggingface_hub.hf_hub_download(
                            repo_id=repo_id,
                            filename=fname,
                            local_files_only=False,
                        )
                    except Exception as fe:
                        print(f"[*] HF file '{fname}' skipped: {fe}")
                    files_done += 1
                    pct = 5.0 + (files_done / files_total) * 90.0
                    self.download_progress[model_id] = pct
                    if on_progress:
                        on_progress(model_id, pct)

                # Try vocab file variants
                if model_id not in self.cancelled_downloads:
                    for vname in VOCAB_VARIANTS:
                        try:
                            huggingface_hub.hf_hub_download(repo_id=repo_id, filename=vname)
                            break
                        except Exception:
                            pass
                    files_done += 1
                    pct = 5.0 + (files_done / files_total) * 90.0
                    self.download_progress[model_id] = pct
                    if on_progress:
                        on_progress(model_id, pct)

                if model_id in self.cancelled_downloads:
                    self.cancelled_downloads.discard(model_id)
                    self.downloading.discard(model_id)
                    self.download_progress[model_id] = -1.0
                    if on_complete:
                        on_complete(model_id, False)
                    return

                # Pre-warm model in RAM/VRAM for instant first inference.
                # Run in a *separate* daemon thread so the download completes
                # immediately and the UI can reflect 100% progress.
                def _prewarm(m_id):
                    try:
                        from faster_whisper import WhisperModel
                        import transcribe_service
                        device, compute_type = transcribe_service.get_whisper_device_and_compute_type()
                        cpu_threads = min(8, os.cpu_count() or 4) if device == "cpu" else 4
                        fw_key = m_id
                        transcribe_service._faster_whisper_cache[fw_key] = WhisperModel(
                            fw_key,
                            device=device,
                            compute_type=compute_type,
                            cpu_threads=cpu_threads
                        )
                        print(f"[+] Pre-warmed faster-whisper model '{fw_key}' on {device.upper()} ({compute_type}).")
                    except Exception as warm_err:
                        print(f"[*] Model pre-warm skipped: {warm_err}")

                threading.Thread(target=_prewarm, args=(model_id,), daemon=True).start()

                self.set_model_quality(model_id, quality)
                self.downloading.discard(model_id)
                self.download_progress[model_id] = 100.0
                if not self.is_model_downloaded(self.get_active_model()):
                    self.set_active_model(model_id)
                if on_complete:
                    on_complete(model_id, True)
                return
            except Exception as hf_err:
                print(f"[!] faster-whisper HF download failed: {hf_err}. Falling back to standard download...")
                self.downloading.discard(model_id)
                self.download_progress[model_id] = -1.0
                if on_complete:
                    on_complete(model_id, False)
                return

        dest_path = None
        part_path = None
        try:
            # Prefer downloading an upstream pre-quantized file instead of quantizing locally.
            # (whisper-quantize is not bundled in the packaged app, so local quantization silently
            # left fp16 models on disk: ~2.5x more RAM and slower inference.)
            url, prequantized_quality = self._prequantized_url(model_id, url, quality)
            if prequantized_quality:
                print(f"[*] Using pre-quantized {model_id} ({prequantized_quality}): {url}")
                quality = prequantized_quality

            if model_data.get("filename"):
                filename = model_data["filename"]
            else:
                ext = ".gguf" if url.endswith(".gguf") else ".bin"
                filename = f"ggml-{model_id}{ext}"
            ext = (os.path.splitext(filename)[1] or (".gguf" if url.endswith(".gguf") else ".bin")).lower()
            dest_path = os.path.realpath(os.path.join(MODELS_DIR, filename))
            if not dest_path.startswith(os.path.realpath(MODELS_DIR)):
                print(f"[!] Invalid model path for model_id {model_id}")
                self.downloading.discard(model_id)
                self.download_progress[model_id] = -1.0
                if on_complete:
                    on_complete(model_id, False)
                return

            part_path = dest_path + ".part"
            timeout_config = httpx.Timeout(connect=30.0, read=120.0, write=60.0, pool=30.0)
            with httpx.stream("GET", url, follow_redirects=True, timeout=timeout_config) as response:
                response.raise_for_status()
                total_bytes = int(response.headers.get("content-length", 0))
                downloaded_bytes = 0
                
                with open(part_path, "wb") as f:
                    for chunk in response.iter_bytes(chunk_size=1024*1024):
                        if model_id in self.cancelled_downloads:
                            print(f"[*] Download cancelled for {model_id}")
                            break
                        f.write(chunk)
                        downloaded_bytes += len(chunk)
                        
                        if total_bytes > 0:
                            progress = (downloaded_bytes / total_bytes) * 100.0
                            self.download_progress[model_id] = progress
                            if on_progress:
                                on_progress(model_id, progress)
                                
                if model_id in self.cancelled_downloads:
                    self.cancelled_downloads.discard(model_id)
                    if os.path.exists(part_path):
                        os.remove(part_path)
                    if os.path.exists(dest_path):
                        os.remove(dest_path)
                    self.downloading.discard(model_id)
                    self.download_progress[model_id] = -1.0
                    if on_complete:
                        on_complete(model_id, False)
                    return

                # Download finished successfully - atomically move part to destination
                if os.path.exists(part_path):
                    os.replace(part_path, dest_path)
                                
                if not ext == ".gguf" and quality != "f16" and not prequantized_quality:
                    quantize_bin = get_resource_path(os.path.join("bin", "whisper.cpp", "build", "bin", "whisper-quantize"))
                    if os.path.exists(quantize_bin):
                        print(f"[*] Quantizing {model_id} to {quality} to boost performance...")
                        quant_path = dest_path + ".quant"
                        try:
                            import subprocess
                            subprocess.run([quantize_bin, dest_path, quant_path, quality], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                            os.replace(quant_path, dest_path)
                            print(f"[+] Quantization complete for {model_id} ({quality}).")
                        except Exception as e:
                            print(f"[-] Quantization failed: {e}. Keeping original model.")
                            if os.path.exists(quant_path):
                                os.remove(quant_path)
                            quality = "f16"
                    else:
                        print(f"[!] whisper-quantize not found; keeping {model_id} as f16.")
                        quality = "f16"
                
                self.set_model_quality(model_id, quality)
            
            self.downloading.discard(model_id)
            self.download_progress[model_id] = 100.0
            if not self.is_model_downloaded(self.get_active_model()):
                self.set_active_model(model_id)
            if on_complete:
                on_complete(model_id, True)
        except Exception as e:
            print(f"[!] Download failed for {model_id}: {e}")
            if part_path and os.path.exists(part_path):
                try:
                    os.remove(part_path)
                except Exception:
                    pass
            self.downloading.discard(model_id)
            self.download_progress[model_id] = -1.0
            if on_complete:
                on_complete(model_id, False)

    def delete_model(self, model_id: str) -> bool:
        was_active = (model_id == self.get_active_model())
        deleted = False
        models_dir_real = os.path.realpath(MODELS_DIR)

        # 1. Delete matching model files in MODELS_DIR
        try:
            if os.path.exists(MODELS_DIR):
                for f in os.listdir(MODELS_DIR):
                    if f == "huggingface_cache" or f.lower() == "readme.txt" or f == "tts":
                        continue
                    is_match = False
                    if model_id in LOCAL_TEXT_MODEL_FILES and f in LOCAL_TEXT_MODEL_FILES[model_id]:
                        is_match = True
                    for ext in [".bin", ".gguf", ".quant"]:
                        if is_match:
                            break
                        if f == f"ggml-{model_id}{ext}" or f == f"{model_id}{ext}":
                            is_match = True
                            break
                        if f.startswith(f"ggml-{model_id}-") and f.endswith(ext):
                            is_match = True
                            break
                    if is_match:
                        full_path = os.path.realpath(os.path.join(MODELS_DIR, f))
                        if full_path.startswith(models_dir_real) and os.path.exists(full_path):
                            try:
                                os.remove(full_path)
                                deleted = True
                                print(f"[+] Deleted model file: {full_path}")
                            except Exception as e:
                                print(f"[!] Error deleting model file {full_path}: {e}")
        except Exception as e:
            print(f"[!] Error listing models directory during delete: {e}")

        # 2. Delete faster-whisper HF cache if present
        try:
            hf_hub_dir = os.path.expanduser("~/.cache/huggingface/hub")
            exact_folder = None
            if model_id == "distil-large-v3":
                exact_folder = "models--Systran--faster-distil-whisper-large-v3"
            elif model_id in ["tiny", "tiny.en", "base", "base.en", "small", "small.en", "medium", "medium.en", "large-v1", "large-v2", "large-v3"]:
                exact_folder = f"models--Systran--faster-whisper-{model_id}"
            elif "turbo" in model_id:
                exact_folder = "models--deepdml--faster-whisper-large-v3-turbo-ct2"
            elif model_id:
                exact_folder = f"models--Systran--faster-whisper-{model_id}"

            if exact_folder and os.path.isdir(hf_hub_dir):
                target_dir = os.path.join(hf_hub_dir, exact_folder)
                if os.path.isdir(target_dir):
                    import shutil
                    shutil.rmtree(target_dir, ignore_errors=True)
                    deleted = True
                    print(f"[+] Deleted HF cached model folder: {target_dir}")
        except Exception as e:
            print(f"[!] Error removing HF cache for {model_id}: {e}")

        # 3. Clean up download tracking and model quality settings
        self.download_progress.pop(model_id, None)
        self.downloading.discard(model_id)
        if os.path.exists(SETTINGS_FILE):
            try:
                with open(SETTINGS_FILE, "r") as f:
                    config = json.load(f)
                changed = False
                if "model_qualities" in config and model_id in config["model_qualities"]:
                    del config["model_qualities"][model_id]
                    changed = True
                if changed:
                    with open(SETTINGS_FILE, "w") as f:
                        json.dump(config, f, indent=2)
            except Exception as e:
                print(f"[!] Error updating settings during model delete: {e}")

        # 4. If the deleted model was active, switch active model to another downloaded model or default fallback
        if was_active:
            downloaded = self.get_downloaded_models()
            next_model = None
            for d in downloaded:
                clean_id = d.replace("ggml-", "").replace(".bin", "").replace(".gguf", "")
                if clean_id != model_id:
                    next_model = clean_id
                    break
            if not next_model:
                next_model = "tiny.en" if platform.system() == "Windows" else "base.en"

            print(f"[*] Active model {model_id} deleted. Switching active model to {next_model}.")
            self.set_active_model(next_model)

        return deleted

