import os
import json
import uuid
from datetime import datetime

from dicty_paths import get_user_data_dir, migrate_legacy_file

DATA_DIR = get_user_data_dir()
PENDING_FILE = os.path.join(DATA_DIR, "pending_updates.json")
HISTORY_FILE = os.path.join(DATA_DIR, "updates_history.json")

class PendingManager:
    def __init__(self, file_path: str = None, history_path: str = None):
        if file_path is None:
            migrate_legacy_file("pending_updates.json", PENDING_FILE)
            file_path = PENDING_FILE
        if history_path is None:
            migrate_legacy_file("updates_history.json", HISTORY_FILE)
            history_path = HISTORY_FILE
        self.file_path = file_path
        self.history_path = history_path
        if not os.path.exists(self.file_path):
            with open(self.file_path, "w") as f:
                json.dump([], f)
        if not os.path.exists(self.history_path):
            with open(self.history_path, "w") as f:
                json.dump([], f)

    def _read(self):
        try:
            with open(self.file_path, "r") as f:
                return json.load(f)
        except:
            return []

    def _write(self, data):
        with open(self.file_path, "w") as f:
            json.dump(data, f, indent=4)

    def create_pending_update(self, title: str, original_content: str, proposed_content: str, page_id: str, version: int, confluence_url: str, space_key: str, target_type: str = "confluence", action: str = "update"):
        pending_id = str(uuid.uuid4())
        record = {
            "id": pending_id,
            "title": title,
            "original_content": original_content,
            "proposed_content": proposed_content,
            "page_id": page_id,
            "version": version,
            "confluence_url": confluence_url,
            "space_key": space_key,
            "target_type": target_type,
            "action": action,
            "timestamp": datetime.now().isoformat()
        }
        data = self._read()
        data.insert(0, record)
        self._write(data)
        return pending_id

    def get_all(self):
        return self._read()

    def get_by_id(self, pending_id: str):
        data = self._read()
        for item in data:
            if item["id"] == pending_id:
                return item
        return None

    def delete(self, pending_id: str):
        data = self._read()
        filtered = [item for item in data if item["id"] != pending_id]
        self._write(filtered)
        return True

    def move_to_history(self, pending_id: str, status: str):
        data = self._read()
        item_to_move = None
        filtered = []
        for item in data:
            if item["id"] == pending_id:
                item_to_move = item
            else:
                filtered.append(item)
        
        if item_to_move:
            self._write(filtered)
            item_to_move["status"] = status
            item_to_move["resolved_at"] = datetime.now().isoformat()
            
            try:
                with open(self.history_path, "r") as f:
                    history = json.load(f)
            except:
                history = []
                
            history.insert(0, item_to_move)
            with open(self.history_path, "w") as f:
                json.dump(history, f, indent=4)
            return True
        return False

    def get_history(self):
        try:
            with open(self.history_path, "r") as f:
                return json.load(f)
        except:
            return []

    def get_history_by_id(self, history_id: str):
        history = self.get_history()
        for item in history:
            if item.get("id") == history_id:
                return item
        return None

    def update_proposed_content(self, pending_id: str, new_content: str):
        data = self._read()
        for item in data:
            if item["id"] == pending_id:
                item["proposed_content"] = new_content
                self._write(data)
                return item
        return None

    def delete_history_item(self, history_id: str):
        history = self.get_history()
        filtered = [item for item in history if item.get("id") != history_id]
        if len(filtered) < len(history):
            with open(self.history_path, "w") as f:
                json.dump(filtered, f, indent=4)
            return True
        return False

    def clear_history(self):
        with open(self.history_path, "w") as f:
            json.dump([], f, indent=4)
        return True
