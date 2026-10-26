import os
import json
import time
import uuid
from typing import List, Dict, Any, Optional

from dicty_paths import get_user_data_dir, migrate_legacy_file

DATA_DIR = get_user_data_dir()
QUEUE_FILE = os.path.join(DATA_DIR, "librarian_queue.json")


class QueueManager:
    def __init__(self, storage_path: Optional[str] = None):
        if storage_path is None:
            migrate_legacy_file("librarian_queue.json", QUEUE_FILE)
            storage_path = QUEUE_FILE
        self.storage_path = storage_path
        self._ensure_file()

    def _ensure_file(self):
        if not os.path.exists(self.storage_path):
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump([], f, ensure_ascii=False, indent=2)

    def _read_queue(self) -> List[Dict[str, Any]]:
        self._ensure_file()
        try:
            with open(self.storage_path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception as e:
            print(f"[!] Error reading queue file: {e}")
            return []

    def _write_queue(self, items: List[Dict[str, Any]]) -> bool:
        try:
            with open(self.storage_path, "w", encoding="utf-8") as f:
                json.dump(items, f, ensure_ascii=False, indent=2)
            return True
        except Exception as e:
            print(f"[!] Error writing queue file: {e}")
            return False

    def list_items(self) -> List[Dict[str, Any]]:
        return self._read_queue()

    def count(self) -> int:
        return len(self._read_queue())

    def add_item(
        self,
        text: str,
        source: str = "voice",
        git_branch: Optional[str] = None,
        git_commit: Optional[str] = None,
        tags: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        items = self._read_queue()
        new_item = {
            "id": str(uuid.uuid4()),
            "timestamp": time.time(),
            "text": text.strip(),
            "source": source,
            "git_branch": git_branch or "",
            "git_commit": git_commit or "",
            "tags": tags or []
        }
        items.append(new_item)
        self._write_queue(items)
        return new_item

    def update_item(self, item_id: str, text: str) -> Optional[Dict[str, Any]]:
        items = self._read_queue()
        for item in items:
            if item.get("id") == item_id:
                item["text"] = text.strip()
                item["updated_at"] = time.time()
                self._write_queue(items)
                return item
        return None

    def delete_item(self, item_id: str) -> bool:
        items = self._read_queue()
        initial_len = len(items)
        items = [i for i in items if i.get("id") != item_id]
        if len(items) < initial_len:
            self._write_queue(items)
            return True
        return False

    def clear(self) -> bool:
        return self._write_queue([])


queue_manager = QueueManager()
