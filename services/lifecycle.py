import engine_auth
import local_llm
import os
import platform
import subprocess
import threading
import time
from services.whisper_server import stop_whisper_server

def free_port(port=8075):
    try:
        port = int(port)
        my_pid = str(os.getpid())
        if platform.system() == "Windows":
            res = subprocess.run(["netstat", "-ano"], capture_output=True, text=True)
            for line in res.stdout.strip().splitlines():
                parts = line.strip().split()
                if len(parts) >= 5 and (parts[1].endswith(f":{port}") or parts[1].endswith(f"]:{port}")):
                    pid = parts[-1]
                    if pid and pid != my_pid and pid != "0":
                        print(f"[*] Terminating zombie process on port {port} (PID {pid})...")
                        subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
        else:
            # IMPORTANT: Add `-sTCP:LISTEN` so `lsof -t -i :8075` ONLY matches processes *listening*
            # on port 8075, and NEVER kills the Swift client (`swift run` / `Dicty.app`) that made an
            # outgoing HTTP health check connection to port 8075!
            res = subprocess.run(["lsof", "-t", "-i", f"TCP:{port}", "-sTCP:LISTEN"], capture_output=True, text=True)
            pids = res.stdout.strip().split()
            for pid in pids:
                if pid and pid != my_pid:
                    print(f"[*] Terminating zombie process on port {port} (PID {pid})...")
                    subprocess.run(["kill", "-9", str(pid)], capture_output=True)
    except Exception as e:
        print(f"[-] Could not free port {port}: {e}")

def _install_process_lifecycle_guards():
    """Makes sure the whisper-server (~300 MB RAM) never outlives this engine.

    - SIGHUP (terminal closed): uvicorn only handles SIGINT/SIGTERM, so without this the engine died
      without running its shutdown hook and orphaned the whisper-server.
    - atexit: covers normal interpreter exits.
    - Parent watchdog: when launched by the Dicty app (DICTY_PARENT_PID set), exit as soon as the app is
      gone, even if it crashed or was force-quit and never sent SIGTERM.
    SIGKILL cannot be caught; those leftovers are swept by local_whisper.kill_all_orphans() at next start.
    """
    import atexit
    import signal as _signal

    def _shutdown_and_exit(*_):
        try:
            stop_whisper_server()
            local_llm.stop_server()
            engine_auth.cleanup_token()
        finally:
            os._exit(0)

    atexit.register(lambda: (stop_whisper_server(), local_llm.stop_server(), engine_auth.cleanup_token()))
    if hasattr(_signal, "SIGHUP"):
        _signal.signal(_signal.SIGHUP, _shutdown_and_exit)

    parent_pid = os.getenv("DICTY_PARENT_PID", "")
    if parent_pid.isdigit():
        parent_pid = int(parent_pid)

        def _watch_parent():
            while True:
                time.sleep(2.0)
                try:
                    os.kill(parent_pid, 0)  # signal 0: existence check only
                    alive = os.getppid() == parent_pid
                except OSError:
                    alive = False
                if not alive:
                    print(f"[*] Dicty app (PID {parent_pid}) is gone. Shutting down engine and whisper-server.")
                    _shutdown_and_exit()

        threading.Thread(target=_watch_parent, daemon=True, name="parent-watchdog").start()
