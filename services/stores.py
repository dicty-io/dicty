import app_rules
import json
import os
import snippet_service
import threading
import uuid
from services.paths import DATA_DIR
from pending_manager import PendingManager
from services import paths

DEFAULT_VOCABULARY = [
    {"id": "default-dicty", "word": "dicti", "replacement": "Dicty"},
    {"id": "default-fastapi", "word": "fast api", "replacement": "FastAPI"},
    {"id": "default-github", "word": "git hub", "replacement": "GitHub"},
    {"id": "default-k8s", "word": "kuber netes", "replacement": "Kubernetes"},
    {"id": "default-postgres", "word": "post gres", "replacement": "PostgreSQL"},
    {"id": "default-typescript", "word": "type script", "replacement": "TypeScript"},
    {"id": "default-nextjs", "word": "next js", "replacement": "Next.js"},
    {"id": "default-json", "word": "j son", "replacement": "JSON"},
    {"id": "default-oauth", "word": "o auth", "replacement": "OAuth"},
    {"id": "default-cicd", "word": "ci cd", "replacement": "CI/CD"},
]

class VocabularyManager:
    def __init__(self):
        self.lock = threading.Lock()
        if not os.path.exists(paths.VOCABULARY_FILE):
            with open(paths.VOCABULARY_FILE, "w") as f:
                json.dump(DEFAULT_VOCABULARY, f, indent=2)
                
    def get_all(self):
        with self.lock:
            with open(paths.VOCABULARY_FILE, "r") as f:
                return json.load(f)
            
    def add_item(self, item):
        with self.lock:
            with open(paths.VOCABULARY_FILE, "r") as f:
                data = json.load(f)
            item["id"] = str(uuid.uuid4())
            data.insert(0, item)
            with open(paths.VOCABULARY_FILE, "w") as f:
                json.dump(data, f, indent=2)
            return item
            
    def delete_item(self, item_id):
        with self.lock:
            with open(paths.VOCABULARY_FILE, "r") as f:
                data = json.load(f)
            item = next((r for r in data if r["id"] == item_id), None)
            if item:
                data = [r for r in data if r["id"] != item_id]
                with open(paths.VOCABULARY_FILE, "w") as f:
                    json.dump(data, f, indent=2)
                return True
            return False
            
    def update_item(self, item_id, word, replacement):
        with self.lock:
            with open(paths.VOCABULARY_FILE, "r") as f:
                data = json.load(f)
            item = next((r for r in data if r["id"] == item_id), None)
            if item:
                item["word"] = word
                item["replacement"] = replacement
                with open(paths.VOCABULARY_FILE, "w") as f:
                    json.dump(data, f, indent=2)
                return item
            return None

    def load_defaults(self, replace: bool = False):
        with self.lock:
            if replace:
                data = [dict(item) for item in DEFAULT_VOCABULARY]
            else:
                existing = []
                if os.path.exists(paths.VOCABULARY_FILE):
                    try:
                        with open(paths.VOCABULARY_FILE, "r") as f:
                            existing = json.load(f)
                    except Exception:
                        existing = []
                existing_words = {r.get("word", "").strip().lower() for r in existing}
                data = list(existing)
                for item in DEFAULT_VOCABULARY:
                    if item["word"].strip().lower() not in existing_words:
                        data.append(dict(item))
            with open(paths.VOCABULARY_FILE, "w") as f:
                json.dump(data, f, indent=2)
            return data

vocabulary_manager = VocabularyManager()
snippets_manager = snippet_service.SnippetsManager(os.path.join(DATA_DIR, "snippets.json"))
app_rules_manager = app_rules.AppRulesManager(DATA_DIR)

def _is_safe_audio_to_delete(p: str) -> bool:
    if not p or not isinstance(p, str):
        return False
    try:
        import tempfile
        real_p = os.path.realpath(p)
        allowed_dirs = [
            os.path.realpath(paths.DATA_DIR),
            os.path.realpath(paths.INPUT_DIR),
            os.path.realpath(tempfile.gettempdir()),
            os.path.realpath("/private/var/folders"),
            os.path.realpath("/var/folders"),
        ]
        return any(real_p.startswith(d) for d in allowed_dirs) and not os.path.isdir(real_p)
    except Exception:
        return False

class HistoryManager:
    def __init__(self):
        self.lock = threading.Lock()
        self._cached_data = None
        if not os.path.exists(paths.HISTORY_FILE):
            try:
                with open(paths.HISTORY_FILE, "w") as f:
                    json.dump([], f)
            except Exception:
                pass
                
    def _read_data(self):
        if self._cached_data is not None:
            return list(self._cached_data)
        if not os.path.exists(paths.HISTORY_FILE):
            self._cached_data = []
            return []
        try:
            with open(paths.HISTORY_FILE, "r", encoding="utf-8", errors="replace") as f:
                content = f.read().strip()
                if not content:
                    self._cached_data = []
                    return []
                self._cached_data = json.loads(content)
                return list(self._cached_data)
        except Exception as e:
            print(f"[!] Warning reading history.json: {e}")
            self._cached_data = []
            return []

    def _write_data(self, data):
        self._cached_data = list(data)
        temp_file = f"{paths.HISTORY_FILE}.tmp.{os.getpid()}"
        try:
            with open(temp_file, "w", encoding="utf-8") as f:
                json.dump(data, f)
            os.replace(temp_file, paths.HISTORY_FILE)
        except Exception:
            try:
                with open(paths.HISTORY_FILE, "w", encoding="utf-8") as f:
                    json.dump(data, f)
            except Exception as e2:
                print(f"[!] Error writing history.json: {e2}")

    def get_all(self):
        with self.lock:
            return self._read_data()
            
    def add_record(self, record):
        with self.lock:
            data = self._read_data()
            data.insert(0, record)
            self._write_data(data)
                
    def update_record(self, record_id, updates):
        with self.lock:
            data = self._read_data()
            record = next((r for r in data if r.get("id") == record_id), None)
            if record:
                record.update(updates)
                self._write_data(data)
            return record
            
    def delete_record(self, record_id):
        with self.lock:
            data = self._read_data()
            record = next((r for r in data if r.get("id") == record_id), None)
            if record:
                data = [r for r in data if r.get("id") != record_id]
                self._write_data(data)
                for track in ("audio_file", "audio_file_mic", "audio_file_sys"):
                    path = record.get(track)
                    if path and _is_safe_audio_to_delete(path) and os.path.exists(path):
                        try:
                            os.remove(path)
                        except Exception:
                            pass
            return record

    def get_avg_wpm(self):
        # Kept for backward compatibility
        return self.get_stats("all")[1:3]

    def get_stats(self, period="all"):
        data = self.get_all()
        from datetime import datetime, timedelta
        
        now = datetime.now().astimezone()
        
        # Calculate cutoff based on exact calendar boundaries (resets at 00:00:00 local time)
        cutoff = None
        if period == "day":
            # Today at 00:00:00 local time
            cutoff = now.replace(hour=0, minute=0, second=0, microsecond=0)
        elif period == "week":
            # Monday of current week at 00:00:00 local time
            start_of_week = now - timedelta(days=now.weekday())
            cutoff = start_of_week.replace(hour=0, minute=0, second=0, microsecond=0)
        elif period == "month":
            # 1st of current month at 00:00:00 local time
            cutoff = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        
        filtered = []
        for r in data:
            try:
                ts_str = r.get("timestamp", "")
                if not ts_str:
                    continue
                dt = datetime.fromisoformat(ts_str)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=now.tzinfo)
                else:
                    dt = dt.astimezone(now.tzinfo)
                
                if cutoff is not None and dt < cutoff:
                    continue
                filtered.append(r)
            except Exception:
                pass
                
        total_words = sum(len(r.get("text", "").split()) for r in filtered)
        speaking_wpms = [r.get("speaking_wpm", r.get("wpm", 0)) for r in filtered if r.get("speaking_wpm", r.get("wpm", 0)) > 0]
        engine_wpms = [min(r.get("engine_wpm", 0), 2500) for r in filtered if r.get("engine_wpm", 0) > 0]
        
        avg_s = int(sum(speaking_wpms) / len(speaking_wpms)) if speaking_wpms else 0
        avg_e = int(sum(engine_wpms) / len(engine_wpms)) if engine_wpms else 0
        
        return total_words, avg_s, avg_e, len(filtered)

    def clear_all(self):
        with self.lock:
            data = self.get_all()
            for r in data:
                for track in ("audio_file", "audio_file_mic", "audio_file_sys"):
                    path = r.get(track, "")
                    if path and _is_safe_audio_to_delete(path) and os.path.exists(path):
                        try: os.remove(path)
                        except Exception: pass
            with open(paths.HISTORY_FILE, "w") as f:
                json.dump([], f)
        return True

    def get_retention_settings(self):
        default_settings = {
            "retention_period": "forever",  # "forever", "30d", "7d", "24h"
            "scrub_audio_immediately": False
        }
        if os.path.exists(paths.RETENTION_CONFIG_FILE):
            try:
                with open(paths.RETENTION_CONFIG_FILE, "r") as f:
                    data = json.load(f)
                    default_settings.update(data)
            except Exception:
                pass
        return default_settings

    def save_retention_settings(self, settings: dict):
        current = self.get_retention_settings()
        current.update(settings)
        with open(paths.RETENTION_CONFIG_FILE, "w") as f:
            json.dump(current, f, indent=2)
        return current

    def cleanup_retention(self, scrub_past_audio: bool = False):
        settings = self.get_retention_settings()
        period = settings.get("retention_period", "forever")
        
        from datetime import datetime, timedelta, timezone
        now = datetime.now(timezone.utc)
        
        with self.lock:
            with open(paths.HISTORY_FILE, "r") as f:
                records = json.load(f)
            
            kept_records = []
            deleted_count = 0
            scrubbed_audio_count = 0
            
            for r in records:
                should_delete_record = False
                ts_str = r.get("timestamp", "")
                if ts_str and period != "forever":
                    try:
                        dt = datetime.fromisoformat(ts_str)
                        if dt.tzinfo is None:
                            dt = dt.replace(tzinfo=timezone.utc)
                        else:
                            dt = dt.astimezone(timezone.utc)
                        diff = now - dt
                        
                        if period == "24h" and diff > timedelta(days=1):
                            should_delete_record = True
                        elif period == "7d" and diff > timedelta(days=7):
                            should_delete_record = True
                        elif period == "30d" and diff > timedelta(days=30):
                            should_delete_record = True
                    except Exception:
                        pass
                
                if should_delete_record:
                    deleted_count += 1
                    for track in ("audio_file", "audio_file_mic", "audio_file_sys"):
                        audio_path = r.get(track, "")
                        if audio_path and os.path.exists(audio_path):
                            try: os.remove(audio_path)
                            except Exception: pass
                else:
                    if scrub_past_audio:
                        for track in ("audio_file", "audio_file_mic", "audio_file_sys"):
                            audio_path = r.get(track, "")
                            if audio_path and os.path.exists(audio_path):
                                try:
                                    os.remove(audio_path)
                                    if track == "audio_file":
                                        scrubbed_audio_count += 1
                                except Exception: pass
                            if track in r:
                                r[track] = ""
                    kept_records.append(r)
                    
            if deleted_count > 0 or scrubbed_audio_count > 0:
                with open(paths.HISTORY_FILE, "w") as f:
                    json.dump(kept_records, f, indent=2)
                    
            return {
                "deleted_records": deleted_count,
                "scrubbed_audio": scrubbed_audio_count,
                "total_records": len(kept_records)
            }

history_manager = HistoryManager()
local_pending_manager = PendingManager()
