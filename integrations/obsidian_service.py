import os

class ObsidianService:
    def __init__(self, vault_path: str):
        self.vault_path = vault_path

    def _get_full_path(self, page_title: str) -> str:
        # If title already ends with .md, keep it, otherwise append
        if not page_title.endswith('.md'):
            page_title += '.md'
        return os.path.join(self.vault_path, page_title)

    def get_page_content_by_title(self, page_title: str):
        """Fetches the existing content of an Obsidian markdown file."""
        full_path = self._get_full_path(page_title)
        
        if not os.path.exists(full_path):
            return None
            
        try:
            with open(full_path, "r", encoding="utf-8") as f:
                content = f.read()
            return {
                "id": page_title,
                "version": 1,
                "content": content
            }
        except Exception as e:
            print(f"[!] Obsidian read error: {e}")
            return None

    def update_page(self, page_id: str, title: str, content: str, version: int = 1):
        """Updates an existing Obsidian markdown file."""
        # For local files, page_id and title are effectively the same
        return self.create_page(title, content)
            
    def create_page(self, title: str, content: str):
        """Creates or overwrites an Obsidian markdown file."""
        full_path = self._get_full_path(title)
        
        # Ensure directories exist
        os.makedirs(os.path.dirname(os.path.abspath(full_path)), exist_ok=True)
        
        try:
            with open(full_path, "w", encoding="utf-8") as f:
                f.write(content)
            return {"status": "success", "file": full_path}
        except Exception as e:
            print(f"[!] Obsidian write error: {e}")
            raise e

    def delete_page(self, title: str):
        """Soft-deletes an Obsidian markdown file by moving it to a .trash directory."""
        full_path = self._get_full_path(title)
        
        if not os.path.exists(full_path):
            return {"status": "not_found", "file": full_path}
            
        trash_dir = os.path.join(self.vault_path, ".trash")
        os.makedirs(trash_dir, exist_ok=True)
        
        # Get filename and handle potential collisions in trash
        filename = os.path.basename(full_path)
        trash_path = os.path.join(trash_dir, filename)
        
        import shutil
        if os.path.exists(trash_path):
            # If a file with the same name exists in trash, append a timestamp
            import time
            trash_path = os.path.join(trash_dir, f"{int(time.time())}_{filename}")
            
        try:
            shutil.move(full_path, trash_path)
            return {"status": "success", "file": full_path, "trashed_to": trash_path}
        except Exception as e:
            print(f"[!] Obsidian delete error: {e}")
            raise e
