"""
Endpoint + process bookkeeping for Dicty's own local whisper-server.

- The port is chosen dynamically (a free localhost port) instead of hardcoding 8080,
  which collides with common dev servers and other whisper.cpp installs.
- The server PID is written to a pidfile, so cleanup only ever kills the process
  Dicty itself started (never `killall whisper-server`, which would kill other apps' servers).
"""
import os
import socket
import subprocess
import sys

from model_manager import DATA_DIR

PID_FILE = os.path.join(DATA_DIR, "whisper-server.pid")


def _pick_free_port() -> int:
    override = os.getenv("DICTY_WHISPER_PORT")
    if override and override.isdigit():
        return int(override)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


PORT = _pick_free_port()
BASE_URL = f"http://127.0.0.1:{PORT}"
INFERENCE_URL = f"{BASE_URL}/inference"
HEALTH_URL = f"{BASE_URL}/health"


def write_pid(pid: int) -> None:
    try:
        with open(PID_FILE, "w") as f:
            f.write(str(pid))
    except Exception:
        pass


def clear_pid() -> None:
    try:
        os.remove(PID_FILE)
    except FileNotFoundError:
        pass
    except Exception:
        pass


def _is_whisper_server(pid: int) -> bool:
    """Guards against PID reuse: only treat the pid as ours if it is still a whisper-server."""
    try:
        if sys.platform == "win32":
            out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                                 capture_output=True, text=True, timeout=3).stdout
        else:
            out = subprocess.run(["ps", "-p", str(pid), "-o", "comm="],
                                 capture_output=True, text=True, timeout=3).stdout
        return "whisper-server" in out
    except Exception:
        return False


def kill_orphaned_server() -> None:
    """Kills whisper-servers left behind by previous (crashed / SIGKILLed) Dicty engine runs, and nothing else."""
    try:
        with open(PID_FILE) as f:
            pid = int(f.read().strip())
    except Exception:
        pid = 0
    if pid > 0 and pid != os.getpid() and _is_whisper_server(pid) and _is_orphan(pid):
        _kill(pid)
    clear_pid()
    # The pidfile only remembers the LAST server: each engine start overwrote it, so servers from
    # older runs piled up untracked. Sweep all of them too.
    kill_all_orphans()


def _is_orphan(pid: int) -> bool:
    """True if the process' parent engine is gone (reparented to launchd, PPID 1)."""
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
        print(f"[*] Cleaned up orphaned Dicty whisper-server (PID {pid})")
    except Exception:
        pass


def kill_all_orphans() -> None:
    """Kills every orphaned whisper-server that serves a model from Dicty's data dir.

    Only processes reparented to launchd (PPID 1) are touched, so the current engine's own server and
    whisper-servers belonging to other apps (different model paths) are never killed."""
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
        if ppid == "1" and "whisper-server" in cmd and DATA_DIR in cmd:
            _kill(pid)
