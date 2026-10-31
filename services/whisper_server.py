import local_whisper
import os
import platform
import subprocess
import threading
from services.state import model_manager

whisper_server_process = None
keep_model_loaded = model_manager.get_keep_model_loaded()

def get_whisper_server_cmd():
    from transcribe_service import TranscribeService
    from model_manager import ModelManager, MODELS_DIR
    import platform
    
    ts = TranscribeService()
    whisper_cli_path = ts._ensure_whisper_cpp_binary()
    if not whisper_cli_path:
        return None
    whisper_server_path = whisper_cli_path.replace("whisper-cli", "whisper-server")
    
    mm = ModelManager()
    active_model_id = mm.get_active_model()
    whisper_model_path = mm.get_model_file_path(active_model_id)
    if not whisper_model_path or not os.path.exists(whisper_model_path):
        whisper_model_path = os.path.abspath(os.path.join(MODELS_DIR, f"ggml-{active_model_id}.bin"))
        if not os.path.exists(whisper_model_path):
            cand_gguf = os.path.abspath(os.path.join(MODELS_DIR, f"ggml-{active_model_id}.gguf"))
            if os.path.exists(cand_gguf):
                whisper_model_path = cand_gguf
            else:
                downloaded = mm.get_downloaded_models()
                if downloaded:
                    whisper_model_path = os.path.abspath(os.path.join(MODELS_DIR, downloaded[0]))
    
    if not os.path.exists(whisper_server_path) or not os.path.exists(whisper_model_path):
        return None

        
    cmd = [
        whisper_server_path,
        "-m", whisper_model_path,
        "--port", str(local_whisper.PORT),
        "--host", "127.0.0.1",
        "-t", str(_whisper_thread_count()),
    ]
    
    # -ng = no gpu (fixes Intel Iris GPU timeout crashes and hallucinations)
    if platform.machine().lower() not in ["arm64", "aarch64"]:
        cmd.append("-ng")
        
    return cmd

def _whisper_thread_count() -> int:
    """Use performance cores on Apple Silicon (whisper.cpp default is only 4)."""
    try:
        if platform.system() == "Darwin":
            out = subprocess.run(["sysctl", "-n", "hw.perflevel0.physicalcpu"],
                                 capture_output=True, text=True, timeout=1).stdout.strip()
            if out.isdigit() and int(out) > 0:
                return min(int(out), 8)
    except Exception:
        pass
    return max(4, min((os.cpu_count() or 4) // 2, 8))

def start_whisper_server():
    global whisper_server_process
    if whisper_server_process is not None:
        if whisper_server_process.poll() is None:
            return
        whisper_server_process = None

    # Clean up only a whisper-server that a previous Dicty run started (tracked by pidfile)
    local_whisper.kill_orphaned_server()
        
    cmd = get_whisper_server_cmd()
    if not cmd:
        print("[-] Cannot start whisper-server: paths invalid or model not downloaded yet.")
        return
        
    print(f"[*] Starting whisper-server on port {local_whisper.PORT}...")
    try:
        whisper_server_process = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        local_whisper.write_pid(whisper_server_process.pid)
        
        # Whisper Metal backend often hallucinates dashes or punctuation on the very first 
        # inference due to uninitialized GPU KV cache. We run a silent warmup inference to eat the glitch.
        def _warmup():
            import time, requests
            for _ in range(20):
                try:
                    if requests.get(local_whisper.HEALTH_URL, timeout=1.0).status_code == 200:
                        break
                except: pass
                time.sleep(0.5)
            if os.path.exists("dummy.wav"):
                print("[*] Warming up Whisper GPU tensors...")
                try:
                    with open("dummy.wav", "rb") as f:
                        requests.post(local_whisper.INFERENCE_URL, files={"file": ("dummy.wav", f, "audio/wav")}, data={"response_format": "json"}, timeout=15.0)
                    print("[*] Whisper GPU warmup complete.")
                except: pass
                
        threading.Thread(target=_warmup, daemon=True).start()
    except Exception as e:
        print(f"[-] Failed to start whisper-server: {e}")

def stop_whisper_server():
    global whisper_server_process
    if whisper_server_process is not None:
        print("[*] Stopping whisper-server...")
        whisper_server_process.terminate()
        try:
            whisper_server_process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            whisper_server_process.kill()
        whisper_server_process = None
        local_whisper.clear_pid()
    try:
        local_whisper.kill_orphaned_server()
    except Exception:
        pass
