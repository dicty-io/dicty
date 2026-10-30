import os
import platform
from dicty_paths import get_user_data_dir

def get_log_dir():
    if platform.system() == "Darwin":
        path = os.path.expanduser("~/Library/Logs/Dicty")
    elif platform.system() == "Windows":
        appdata = os.getenv("APPDATA")
        if appdata:
            path = os.path.join(appdata, "Dicty", "logs")
        else:
            path = os.path.expanduser("~/.dicty/logs")
    else:
        path = os.path.expanduser("~/.dicty/logs")
    try:
        os.makedirs(path, exist_ok=True)
    except Exception:
        pass
    return path

def get_downloads_dir():
    if platform.system() == "Windows":
        try:
            import winreg
            sub_key = r"SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders"
            with winreg.OpenKey(winreg.HKEY_CURRENT_USER, sub_key) as key:
                downloads_guid = "{374DE290-123F-4565-9164-39C4925E467B}"
                val, _ = winreg.QueryValueEx(key, downloads_guid)
                expanded = os.path.expandvars(val)
                if os.path.exists(expanded):
                    return expanded
        except Exception:
            pass
        fallback = os.path.join(os.path.expanduser("~"), "Downloads")
        if os.path.exists(fallback):
            return fallback
        return os.path.expanduser("~")
    else:
        return os.path.expanduser("~/Downloads")

DATA_DIR = get_user_data_dir()
INPUT_DIR = os.path.join(DATA_DIR, "transcripts_input")
HISTORY_DIR = os.path.join(INPUT_DIR, "history")
os.makedirs(HISTORY_DIR, exist_ok=True)

AUDIO_PATH = os.path.join(INPUT_DIR, "voice_command.wav")
SYSTEM_AUDIO_PATH = os.path.join(INPUT_DIR, "system_loopback.wav")
API_URL = "http://127.0.0.1:8081/reconcile"
ORCHESTRATOR_URL = "http://127.0.0.1:8081"

HISTORY_FILE = os.path.join(DATA_DIR, "history.json")
VOCABULARY_FILE = os.path.join(DATA_DIR, "vocabulary.json")
RETENTION_CONFIG_FILE = os.path.join(DATA_DIR, "retention_settings.json")
