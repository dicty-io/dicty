"""
local_llm.py
============
Lifecycle, process supervision, and on-demand installer for Dicty's Offline Formatting Add-on.

Features:
- 100% on-demand opt-in: zero extra weight in the base Dicty app bundle.
- Runs a dedicated local llama-server on an isolated loopback port (OpenAI-compatible /v1/chat/completions).
- Apple Silicon Metal GPU acceleration (-ngl 99) for sub-second offline formatting.
- Strict orphan cleanup by PID and launchd reparenting (mirrors local_whisper.py).
- 1-click uninstall and disk reclaim (~1 GB).
"""

import os
import sys
import time
import socket
import json
import tarfile
import platform
import threading
import subprocess
import shutil
import urllib.request
from typing import Dict, Any, Optional

import requests

from dicty_paths import get_user_data_dir

DATA_DIR = get_user_data_dir()
MODELS_DIR = os.path.join(DATA_DIR, "models")
BIN_DIR = os.path.join(DATA_DIR, "bin")
LLAMA_DIR = os.path.join(BIN_DIR, "llama")
PID_FILE = os.path.join(DATA_DIR, "local-llm.pid")

# Addon Assets
RUNNER_TAG = "b11840"
RUNNER_URLS = {
    ("Darwin", "arm64"): f"https://github.com/ggml-org/llama.cpp/releases/download/{RUNNER_TAG}/llama-{RUNNER_TAG}-bin-macos-arm64.tar.gz",
    ("Darwin", "x86_64"): f"https://github.com/ggml-org/llama.cpp/releases/download/{RUNNER_TAG}/llama-{RUNNER_TAG}-bin-macos-x64.tar.gz",
}

# Multi-Model Catalog for On-Device SLM
LOCAL_MODELS: Dict[str, Dict[str, Any]] = {
    "qwen3.5-0.8b": {
        "id": "qwen3.5-0.8b",
        "name": "Qwen 3.5 0.8B",
        "display_name": "Qwen 3.5 0.8B",
        "tag": "Ultra-Fast",
        "filename": "Qwen_Qwen3.5-0.8B-Q4_K_M.gguf",
        "url": "https://huggingface.co/bartowski/Qwen_Qwen3.5-0.8B-GGUF/resolve/main/Qwen_Qwen3.5-0.8B-Q4_K_M.gguf",
        "size_bytes": 550_000_000,
        "approx_ram": "550 MB",
        "description": "Fastest, light cleanup (~550 MB RAM)",
        "min_size": 300_000_000,
    },
    "qwen2.5-1.5b-instruct": {
        "id": "qwen2.5-1.5b-instruct",
        "name": "Qwen 2.5 1.5B",
        "display_name": "Qwen 2.5 1.5B",
        "tag": "Standard",
        "filename": "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        "url": "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
        "size_bytes": 986_000_000,
        "approx_ram": "1.0 GB",
        "description": "Everyday cleanup (~1.0 GB RAM)",
        "min_size": 500_000_000,
    },
    "qwen3.5-2b": {
        "id": "qwen3.5-2b",
        "name": "Qwen 3.5 2B",
        "display_name": "Qwen 3.5 2B",
        "tag": "Balanced",
        "filename": "Qwen_Qwen3.5-2B-Q4_K_M.gguf",
        "url": "https://huggingface.co/bartowski/Qwen_Qwen3.5-2B-GGUF/resolve/main/Qwen_Qwen3.5-2B-Q4_K_M.gguf",
        "size_bytes": 1_350_000_000,
        "approx_ram": "1.3 GB",
        "description": "Better emails and notes (~1.3 GB RAM)",
        "min_size": 800_000_000,
    },
    "llama-3.2-3b-instruct": {
        "id": "llama-3.2-3b-instruct",
        "name": "Llama 3.2 3B",
        "display_name": "Llama 3.2 3B",
        "tag": "Best Quality",
        "filename": "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        "url": "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf",
        "size_bytes": 1_900_000_000,
        "approx_ram": "1.9 GB",
        "description": "Best quality, slower (~1.9 GB RAM)",
        "min_size": 1_000_000_000,
    },
}

DEFAULT_MODEL_ID = "qwen2.5-1.5b-instruct"
DEFAULT_MODEL_FILENAME = LOCAL_MODELS[DEFAULT_MODEL_ID]["filename"]
DEFAULT_MODEL_URL = LOCAL_MODELS[DEFAULT_MODEL_ID]["url"]
APPROX_TOTAL_SIZE_BYTES = 1045000000  # ~996 MB (runner ~16 MB + model ~980 MB)

# Process handle and port
_server_process: Optional[subprocess.Popen] = None
_lock = threading.Lock()


def _pick_free_port() -> int:
    override = os.getenv("DICTY_LOCAL_LLM_PORT")
    if override and override.isdigit():
        return int(override)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


PORT = _pick_free_port()
BASE_URL = f"http://127.0.0.1:{PORT}"
COMPLETIONS_URL = f"{BASE_URL}/v1/chat/completions"
HEALTH_URL = f"{BASE_URL}/health"

# Idle Auto-Unload: terminates llama-server when unused for 5 minutes to release ~1 GB RAM
IDLE_TIMEOUT_SECONDS = int(os.getenv("DICTY_LOCAL_LLM_IDLE_TIMEOUT", "300"))
_last_activity_time = time.time()


def touch_activity() -> None:
    """Updates the last activity timestamp to prevent idle unloading."""
    global _last_activity_time
    _last_activity_time = time.time()


def start_server_async() -> None:
    """Launches local llama-server in background so it warms up in parallel while user speaks."""
    touch_activity()
    if is_server_running():
        return
    threading.Thread(target=start_server, daemon=True, name="local-llm-async-warmup").start()


def _idle_watchdog() -> None:
    """Periodically terminates the local LLM if it has been inactive for IDLE_TIMEOUT_SECONDS."""
    while True:
        time.sleep(15)
        try:
            if is_server_running():
                idle_duration = time.time() - _last_activity_time
                if idle_duration >= IDLE_TIMEOUT_SECONDS:
                    print(f"[*] Local LLM server has been idle for {int(idle_duration // 60)} minutes. Unloading to reclaim RAM.")
                    stop_server()
        except Exception:
            pass

threading.Thread(target=_idle_watchdog, daemon=True, name="local-llm-watchdog").start()

# Download / install progress tracking
_install_state: Dict[str, Any] = {
    "installing": False,
    "stage": "idle",  # "downloading_runner", "downloading_model", "starting", "ready", "error"
    "progress": 0.0,  # 0.0 - 1.0
    "downloaded_bytes": 0,
    "total_bytes": APPROX_TOTAL_SIZE_BYTES,
    "error": None,
    "cancel_requested": False,
}
_install_thread: Optional[threading.Thread] = None


def write_pid(pid: int) -> None:
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(pid))
    except Exception:
        pass


def clear_pid() -> None:
    try:
        os.remove(PID_FILE)
    except (FileNotFoundError, Exception):
        pass


def _is_llama_server(pid: int) -> bool:
    try:
        if sys.platform == "win32":
            out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                                 capture_output=True, text=True, timeout=3).stdout
        else:
            out = subprocess.run(["ps", "-p", str(pid), "-o", "comm="],
                                 capture_output=True, text=True, timeout=3).stdout
        return "llama-server" in out
    except Exception:
        return False


def _is_orphan(pid: int) -> bool:
    if sys.platform == "win32":
        return True
    try:
        out = subprocess.run(["ps", "-p", str(pid), "-o", "ppid="],
                             capture_output=True, text=True, timeout=3).stdout.strip()
        return out == "1"
    except Exception:
        return False


def _kill(pid: int) -> None:
    try:
        if sys.platform == "win32":
            subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
        else:
            os.kill(pid, 9)
        print(f"[*] Cleaned up orphaned Dicty llama-server (PID {pid})")
    except Exception:
        pass


def kill_orphaned_server() -> None:
    """Kills llama-servers left behind by previous crashed or killed engine runs."""
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
    except Exception:
        pid = 0
    if pid > 0 and pid != os.getpid() and _is_llama_server(pid) and _is_orphan(pid):
        _kill(pid)
    clear_pid()
    kill_all_orphans()


def kill_all_orphans() -> None:
    """Kills any orphaned llama-server serving models from Dicty's data dir reparented to launchd."""
    if sys.platform == "win32":
        return
    try:
        out = subprocess.run(["ps", "-axo", "pid=,ppid=,command="],
                             capture_output=True, text=True, timeout=3).stdout
    except Exception:
        return
    for line in out.splitlines():
        parts = line.strip().split(None, 2)
        if len(parts) < 3 or not parts[0].isdigit():
            continue
        pid, ppid, cmd = int(parts[0]), parts[1], parts[2]
        if ppid == "1" and "llama-server" in cmd and DATA_DIR in cmd:
            _kill(pid)


def get_llama_binary_path() -> Optional[str]:
    """Finds downloaded llama-server executable and verifies dynamic library bundle is intact."""
    custom_bin = os.path.join(LLAMA_DIR, "llama-server")
    common_dylib = os.path.join(LLAMA_DIR, "libllama-common.0.dylib")
    if os.path.isfile(custom_bin) and os.access(custom_bin, os.X_OK) and os.path.isfile(common_dylib):
        return custom_bin
    # Check system PATH
    sys_bin = shutil.which("llama-server")
    if sys_bin and os.path.isfile(sys_bin) and os.access(sys_bin, os.X_OK):
        return sys_bin
    return None


def get_active_model_id() -> str:
    """Returns the currently selected local model ID from settings.json."""
    try:
        from model_manager import SETTINGS_FILE
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                cfg = json.load(f)
                chosen = cfg.get("local_llm_model") or cfg.get("llm_model")
                if chosen in LOCAL_MODELS:
                    return chosen
    except Exception:
        pass
    return DEFAULT_MODEL_ID


def get_active_model_info() -> Dict[str, Any]:
    """Returns metadata dictionary for the currently active local model."""
    mid = get_active_model_id()
    return LOCAL_MODELS.get(mid, LOCAL_MODELS[DEFAULT_MODEL_ID])


def get_available_models() -> list:
    """Returns catalog of local models with their download and active status."""
    active_id = get_active_model_id()
    results = []
    for mid, info in LOCAL_MODELS.items():
        p = os.path.join(MODELS_DIR, info["filename"])
        downloaded = os.path.isfile(p) and os.path.getsize(p) >= info.get("min_size", 100_000_000)
        results.append({
            "id": info["id"],
            "name": info["name"],
            "display_name": info.get("display_name", info["name"]),
            "tag": info.get("tag", "Standard"),
            "description": info.get("description", ""),
            "size_bytes": info["size_bytes"],
            "approx_ram": info.get("approx_ram", "1.0 GB"),
            "downloaded": downloaded,
            "is_active": downloaded and (mid == active_id),
        })
    return results


def get_model_path(model_id: Optional[str] = None) -> Optional[str]:
    """Finds the GGUF model file on disk for the requested model or active model."""
    target_id = model_id or get_active_model_id()
    info = LOCAL_MODELS.get(target_id)
    if info:
        target = os.path.join(MODELS_DIR, info["filename"])
        if os.path.isfile(target) and os.path.getsize(target) >= info.get("min_size", 100_000_000):
            return target

    # Fallback: check if ANY model in the catalog is present
    for mid, m_info in LOCAL_MODELS.items():
        p = os.path.join(MODELS_DIR, m_info["filename"])
        if os.path.isfile(p) and os.path.getsize(p) >= m_info.get("min_size", 100_000_000):
            return p
    return None


def switch_model(model_id: str) -> bool:
    """Switches the active local model in settings and restarts llama-server if running."""
    if model_id not in LOCAL_MODELS:
        return False
    path = get_model_path(model_id)
    if not path:
        return False
    try:
        from model_manager import SETTINGS_FILE
        cfg = {}
        if os.path.exists(SETTINGS_FILE):
            with open(SETTINGS_FILE, "r") as f:
                cfg = json.load(f)
        cfg["local_llm_model"] = model_id
        cfg["llm_model"] = model_id
        cfg["llm_provider"] = "local"
        with open(SETTINGS_FILE, "w") as f:
            json.dump(cfg, f, indent=2)
    except Exception as e:
        print(f"[!] Error updating settings on model switch: {e}")
        return False

    # If server is running, restart with the new model
    if is_server_running():
        stop_server()
        return start_server()
    return True


def delete_model(model_id: str) -> Dict[str, Any]:
    """Removes a downloaded model file to reclaim disk space."""
    if model_id not in LOCAL_MODELS:
        return {"status": "error", "message": "Unknown model"}
    info = LOCAL_MODELS[model_id]
    p = os.path.join(MODELS_DIR, info["filename"])
    if not os.path.isfile(p):
        return {"status": "not_found", "reclaimed_bytes": 0}
    
    # If the active model is deleted while running, stop the server
    if get_active_model_id() == model_id and is_server_running():
        stop_server()

    size = os.path.getsize(p)
    try:
        os.remove(p)
        print(f"[*] Deleted local model {model_id} ({size} bytes)")
        return {"status": "deleted", "model_id": model_id, "reclaimed_bytes": size}
    except Exception as e:
        return {"status": "error", "message": str(e)}


def is_installed() -> bool:
    """Returns True if both the runner binary and at least one model are present on disk."""
    return get_llama_binary_path() is not None and get_model_path() is not None


def is_server_running() -> bool:
    """Checks if the local llama-server is healthy and listening on its port."""
    global _server_process
    with _lock:
        if _server_process is not None:
            if _server_process.poll() is not None:
                _server_process = None
                clear_pid()
                return False
    try:
        r = requests.get(HEALTH_URL, timeout=0.8)
        return r.status_code == 200
    except Exception:
        return False


def is_installing() -> bool:
    """Returns True if the background installer is currently downloading dependencies."""
    with _lock:
        return _install_state.get("installing", False)


def get_disk_usage_bytes() -> int:
    """Calculates total disk space used by the addon (runner + model)."""
    total = 0
    if os.path.isdir(LLAMA_DIR):
        for root, _, files in os.walk(LLAMA_DIR):
            for f in files:
                try:
                    total += os.path.getsize(os.path.join(root, f))
                except OSError:
                    pass
    model_p = get_model_path()
    if model_p and os.path.exists(model_p):
        try:
            total += os.path.getsize(model_p)
        except OSError:
            pass
    return total


def _cpu_threads() -> int:
    try:
        if platform.system() == "Darwin":
            out = subprocess.run(["sysctl", "-n", "hw.perflevel0.physicalcpu"],
                                 capture_output=True, text=True, timeout=1).stdout.strip()
            if out.isdigit() and int(out) > 0:
                return min(int(out), 8)
    except Exception:
        pass
    return max(4, min((os.cpu_count() or 4) // 2, 8))


def start_server() -> bool:
    """Starts local llama-server as a background process with Apple Metal GPU acceleration."""
    touch_activity()
    global _server_process
    with _lock:
        if _server_process is not None and _server_process.poll() is None:
            return True

        kill_orphaned_server()

        bin_path = get_llama_binary_path()
        model_p = get_model_path()
        if not bin_path or not model_p:
            print("[-] Cannot start local LLM: binary or model missing.")
            return False

        # Set library search path so dynamic libraries next to llama-server (e.g. libllama-server-impl.dylib) are found
        bin_dir = os.path.dirname(bin_path)
        env = os.environ.copy()
        if platform.system() == "Darwin":
            current_dyld = env.get("DYLD_LIBRARY_PATH", "")
            env["DYLD_LIBRARY_PATH"] = f"{bin_dir}:{current_dyld}" if current_dyld else bin_dir

        cmd = [
            bin_path,
            "-m", model_p,
            "--port", str(PORT),
            "--host", "127.0.0.1",
            "-c", "2048",
            "-b", "512",
            "-ub", "512",
            "-t", str(_cpu_threads()),
            "--reasoning", "off",
        ]

        # Enable Apple Metal acceleration & Flash Attention
        if platform.system() == "Darwin" and platform.machine() in ["arm64", "aarch64"]:
            cmd.extend(["-ngl", "99", "--flash-attn", "auto"])
        elif platform.system() == "Darwin":
            cmd.extend(["-ngl", "0"])

        print(f"[*] Starting local LLM server on port {PORT}: {' '.join(cmd[:4])}...")
        try:
            _server_process = subprocess.Popen(
                cmd,
                env=env,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            write_pid(_server_process.pid)
        except Exception as e:
            print(f"[!] Failed to launch llama-server: {e}")
            _server_process = None
            clear_pid()
            return False

    # Wait up to 10 seconds for /health with fast 100ms polling
    for _ in range(80):
        time.sleep(0.1)
        if is_server_running():
            print(f"[+] Local LLM server is ready on http://127.0.0.1:{PORT}")
            return True

    return is_server_running()


def stop_server() -> None:
    """Cleanly terminates the local llama-server."""
    global _server_process
    with _lock:
        if _server_process is not None:
            print("[*] Stopping local LLM server...")
            try:
                _server_process.terminate()
                _server_process.wait(timeout=3)
            except (subprocess.TimeoutExpired, Exception):
                try:
                    _server_process.kill()
                except Exception:
                    pass
            _server_process = None
            clear_pid()
    try:
        kill_orphaned_server()
    except Exception:
        pass


def get_status() -> Dict[str, Any]:
    """Returns complete status for the Add-on."""
    installed = is_installed()
    running = is_server_running() if installed else False
    with _lock:
        state = dict(_install_state)

    active_id = get_active_model_id()
    active_info = get_active_model_info()

    state["installed"] = installed
    state["running"] = running
    state["port"] = PORT
    state["disk_usage_bytes"] = get_disk_usage_bytes()
    state["model_id"] = active_id
    state["model_name"] = active_info.get("display_name", active_info.get("name", "Qwen 2.5 1.5B Instruct"))
    state["active_model_id"] = active_id
    state["available_models"] = get_available_models()
    return state


def cancel_installation() -> None:
    """Cancels any in-progress download."""
    with _lock:
        if _install_state["installing"]:
            _install_state["cancel_requested"] = True
            _install_state["stage"] = "cancelling"


def uninstall_addon() -> Dict[str, Any]:
    """Stops the server and removes downloaded runner and model files."""
    cancel_installation()
    stop_server()

    reclaimed = 0
    # 1. Remove runner directory
    if os.path.exists(LLAMA_DIR):
        try:
            for root, _, files in os.walk(LLAMA_DIR):
                for f in files:
                    try:
                        reclaimed += os.path.getsize(os.path.join(root, f))
                    except OSError:
                        pass
            shutil.rmtree(LLAMA_DIR, ignore_errors=True)
            print(f"[*] Removed {LLAMA_DIR}")
        except Exception as e:
            print(f"[!] Error removing {LLAMA_DIR}: {e}")

    # 2. Remove model file
    model_p = get_model_path()
    if model_p and os.path.exists(model_p):
        try:
            reclaimed += os.path.getsize(model_p)
            os.remove(model_p)
            print(f"[*] Removed {model_p}")
        except Exception as e:
            print(f"[!] Error removing {model_p}: {e}")

    with _lock:
        _install_state["installing"] = False
        _install_state["stage"] = "idle"
        _install_state["progress"] = 0.0
        _install_state["downloaded_bytes"] = 0
        _install_state["error"] = None
        _install_state["cancel_requested"] = False

    return {
        "status": "uninstalled",
        "reclaimed_bytes": reclaimed,
        "installed": False,
        "running": False
    }


def _download_file(url: str, dest_path: str, stage_name: str, base_offset: int, total_expected: int) -> bool:
    """Streams file download with byte-level progress reporting."""
    os.makedirs(os.path.dirname(dest_path), exist_ok=True)
    temp_path = dest_path + ".tmp"
    if os.path.exists(temp_path):
        try:
            os.remove(temp_path)
        except OSError:
            pass

    req = urllib.request.Request(url, headers={"User-Agent": "Dicty/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp, open(temp_path, "wb") as out_file:
        content_len = resp.getheader("Content-Length")
        file_total = int(content_len) if content_len and content_len.isdigit() else 0

        downloaded_for_file = 0
        chunk_size = 1024 * 1024  # 1 MB chunks
        while True:
            with _lock:
                if _install_state["cancel_requested"]:
                    return False

            chunk = resp.read(chunk_size)
            if not chunk:
                break
            out_file.write(chunk)
            downloaded_for_file += len(chunk)

            current_total_downloaded = base_offset + downloaded_for_file
            progress = min(0.98, max(0.01, current_total_downloaded / float(total_expected)))
            with _lock:
                _install_state["stage"] = stage_name
                _install_state["downloaded_bytes"] = current_total_downloaded
                _install_state["progress"] = progress

    if os.path.exists(dest_path):
        os.remove(dest_path)
    os.rename(temp_path, dest_path)
    return True


def _run_installer_task(target_model_id: str = DEFAULT_MODEL_ID) -> None:
    """Background worker that downloads the runner and model, unpacks, and starts server."""
    global _install_state
    try:
        if target_model_id not in LOCAL_MODELS:
            target_model_id = DEFAULT_MODEL_ID
        model_info = LOCAL_MODELS[target_model_id]

        plat = platform.system()
        arch = platform.machine()
        key = (plat, arch)
        runner_url = RUNNER_URLS.get(key)
        if not runner_url and plat == "Darwin":
            runner_url = RUNNER_URLS.get(("Darwin", "arm64"))

        runner_size = 16_500_000
        model_size = model_info["size_bytes"]
        needs_runner = get_llama_binary_path() is None
        target_model_file = os.path.join(MODELS_DIR, model_info["filename"])
        needs_model = not (os.path.isfile(target_model_file) and os.path.getsize(target_model_file) >= model_info.get("min_size", 100_000_000))

        total_size = (runner_size if needs_runner else 0) + (model_size if needs_model else 0)
        if total_size == 0:
            total_size = 1000

        with _lock:
            _install_state["total_bytes"] = total_size
            _install_state["downloaded_bytes"] = 0
            _install_state["progress"] = 0.05
            _install_state["target_model_id"] = target_model_id
            _install_state["target_model_name"] = model_info.get("display_name", model_info["name"])
            _install_state["stage"] = "downloading_runner" if needs_runner else "downloading_model"

        downloaded_accum = 0

        # Step 1: Download runner if needed
        if needs_runner:
            if not runner_url:
                raise RuntimeError(f"No precompiled llama-server runner available for {plat} {arch}.")

            tar_path = os.path.join(BIN_DIR, "llama_runner.tar.gz")
            print(f"[*] Downloading llama runner from {runner_url}...")
            ok = _download_file(runner_url, tar_path, "downloading_runner", downloaded_accum, total_size)
            if not ok:
                raise RuntimeError("Download cancelled by user.")

            downloaded_accum += runner_size
            print("[*] Unpacking llama-server runner...")
            os.makedirs(LLAMA_DIR, exist_ok=True)
            with tarfile.open(tar_path, "r:gz") as tar:
                for member in tar.getmembers():
                    member_basename = os.path.basename(member.name)
                    if member_basename:
                        member.name = member_basename
                        tar.extract(member, path=LLAMA_DIR)

            try:
                os.remove(tar_path)
            except OSError:
                pass

            bin_p = os.path.join(LLAMA_DIR, "llama-server")
            if os.path.exists(bin_p):
                os.chmod(bin_p, 0o755)

        # Step 2: Download model if needed
        if needs_model:
            print(f"[*] Downloading {model_info['name']} model from {model_info['url']}...")
            ok = _download_file(model_info["url"], target_model_file, "downloading_model", downloaded_accum, total_size)
            if not ok:
                raise RuntimeError("Download cancelled by user.")

        with _lock:
            _install_state["stage"] = "starting"
            _install_state["progress"] = 0.99

        # Step 3: Automatically activate in settings.json
        try:
            from model_manager import SETTINGS_FILE
            import json
            current_settings = {}
            if os.path.exists(SETTINGS_FILE):
                with open(SETTINGS_FILE, "r") as f:
                    current_settings = json.load(f)
            current_settings["llm_provider"] = "local"
            current_settings["llm_model"] = target_model_id
            current_settings["local_llm_model"] = target_model_id
            with open(SETTINGS_FILE, "w") as f:
                json.dump(current_settings, f, indent=2)
        except Exception as e:
            print(f"[!] Warning: Could not update settings on addon install: {e}")

        # Step 4: Start or restart the server
        if is_server_running():
            stop_server()
        started = start_server()
        if not started:
            raise RuntimeError("Failed to launch local LLM server after installation.")

        with _lock:
            _install_state["installing"] = False
            _install_state["stage"] = "ready"
            _install_state["progress"] = 1.0
            _install_state["error"] = None
        print(f"[+] Local model {model_info['name']} installed and activated successfully.")

    except Exception as e:
        err_msg = str(e)
        print(f"[!] Offline Formatting Add-on installation failed: {err_msg}")
        with _lock:
            _install_state["installing"] = False
            _install_state["stage"] = "error"
            _install_state["error"] = err_msg


def start_installation(model_id: Optional[str] = None) -> Dict[str, Any]:
    """Triggers background installation of the add-on and/or specified model."""
    global _install_thread, _install_state
    target_id = model_id or DEFAULT_MODEL_ID
    with _lock:
        if _install_state["installing"]:
            return {"status": "already_installing", "state": dict(_install_state)}
        _install_state["installing"] = True
        _install_state["stage"] = "preparing"
        _install_state["progress"] = 0.01
        _install_state["downloaded_bytes"] = 0
        _install_state["error"] = None
        _install_state["cancel_requested"] = False
        _install_state["target_model_id"] = target_id

    _install_thread = threading.Thread(target=_run_installer_task, args=(target_id,), daemon=True)
    _install_thread.start()
    return {"status": "started", "state": dict(_install_state)}
