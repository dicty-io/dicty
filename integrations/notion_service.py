import os
import re
import asyncio
import httpx
from typing import Optional, Dict, Any, List

_notion_page_locks: Dict[str, asyncio.Lock] = {}

class NotionService:
    def __init__(self, api_key: Optional[str] = None, parent_page_id: Optional[str] = None):
        self.api_key = api_key or os.getenv("NOTION_API_KEY", "")
        # Clean parent_page_id in case a full Notion URL or hyphenated UUID was provided
        raw_page_id = parent_page_id or os.getenv("NOTION_PAGE_ID", "")
        self.parent_page_id = self._normalize_page_id(raw_page_id)
        
        self.headers = {}
        if self.api_key and not self.api_key.startswith("your-"):
            self.headers = {
                "Authorization": f"Bearer {self.api_key.strip()}",
                "Content-Type": "application/json",
                "Notion-Version": "2022-06-28"
            }

    @staticmethod
    def _normalize_page_id(raw_id: str) -> str:
        if not raw_id:
            return ""
        raw_id = raw_id.strip()
        # If full URL: extract 32 hex char ID from the end
        if "notion.so" in raw_id or "notion.site" in raw_id:
            parts = raw_id.split("?")[0].split("-")
            last_part = parts[-1]
            if len(last_part) == 32:
                return last_part
            # Try 32 hex char regex match
            matches = re.findall(r'[a-fA-F0-9]{32}', raw_id)
            if matches:
                return matches[-1]
        # Remove hyphens if formatted as standard UUID
        clean_id = raw_id.replace("-", "")
        return clean_id

    async def test_connection(self) -> Dict[str, Any]:
        """Tests whether the API token is valid and the parent page is accessible."""
        if not self.api_key or self.api_key.startswith("your-"):
            return {"success": False, "error": "Notion API key is missing or invalid."}
        
        if not self.parent_page_id or self.parent_page_id.startswith("your-"):
            return {"success": False, "error": "Parent Page / Database ID is missing."}

        async with httpx.AsyncClient(timeout=15.0) as client:
            # 1. Verify Bot Token
            try:
                user_resp = await client.get("https://api.notion.com/v1/users/me", headers=self.headers)
                if user_resp.status_code == 401:
                    return {"success": False, "error": "Invalid Notion API token. Check your integration secret."}
                user_resp.raise_for_status()
                bot_name = user_resp.json().get("name", "Dicty Integration")
            except Exception as e:
                return {"success": False, "error": f"Failed to authenticate with Notion: {str(e)}"}

            # 2. Verify Parent Page Access
            try:
                # Try fetching as page
                page_resp = await client.get(f"https://api.notion.com/v1/pages/{self.parent_page_id}", headers=self.headers)
                if page_resp.status_code == 200:
                    data = page_resp.json()
                    props = data.get("properties", {})
                    title_obj = props.get("title", {}) or props.get("Name", {})
                    title_list = title_obj.get("title", []) if isinstance(title_obj, dict) else []
                    page_title = title_list[0]["text"]["content"] if title_list else "Untitled Page"
                    return {
                        "success": True,
                        "bot_name": bot_name,
                        "parent_title": page_title,
                        "message": f"Connected as '{bot_name}' to page '{page_title}'."
                    }
                elif page_resp.status_code == 404:
                    # Try fetching as database
                    db_resp = await client.get(f"https://api.notion.com/v1/databases/{self.parent_page_id}", headers=self.headers)
                    if db_resp.status_code == 200:
                        db_data = db_resp.json()
                        db_title = "".join([t.get("plain_text", "") for t in db_data.get("title", [])]) or "Database"
                        return {
                            "success": True,
                            "bot_name": bot_name,
                            "parent_title": db_title,
                            "message": f"Connected as '{bot_name}' to database '{db_title}'."
                        }
                    return {
                        "success": False,
                        "error": "Parent page/database not found or not shared with this integration. In Notion, click '...' -> 'Add connections' -> select your integration."
                    }
                else:
                    return {"success": False, "error": f"Notion API error ({page_resp.status_code}): {page_resp.text}"}
            except Exception as e:
                return {"success": False, "error": f"Failed to access parent page: {str(e)}"}

    def _parse_inline_markdown(self, text: str) -> List[Dict[str, Any]]:
        """Parses inline Markdown (bold, italic, inline code, links, strikethrough) into Notion rich_text objects."""
        if not text:
            return []

        pattern = re.compile(
            r'(?P<link>\[(?P<link_text>[^\]]+)\]\((?P<link_url>[^\)]+)\))|'
            r'(?P<bold_italic>(?:\*\*\*|___)(?P<bi_text>.+?)(?:\*\*\*|___))|'
            r'(?P<bold>(?:\*\*|__)(?P<bold_text>.+?)(?:\*\*|__))|'
            r'(?P<code>`(?P<code_text>[^`]+)`)|'
            r'(?P<strike>~~(?P<strike_text>.+?)~~)|'
            r'(?P<italic>(?:\*|_)(?P<italic_text>.+?)(?:\*|_))'
        )

        rich_text = []
        last_idx = 0

        for match in pattern.finditer(text):
            start, end = match.span()
            if start > last_idx:
                plain_segment = text[last_idx:start]
                if plain_segment:
                    rich_text.append({"type": "text", "text": {"content": plain_segment[:2000]}})

            m_dict = match.groupdict()
            if m_dict.get("link"):
                link_url = (m_dict.get("link_url") or "").strip()
                link_text = m_dict.get("link_text") or link_url
                if link_url.startswith("http://") or link_url.startswith("https://") or link_url.startswith("mailto:"):
                    rich_text.append({
                        "type": "text",
                        "text": {"content": link_text[:2000], "link": {"url": link_url}}
                    })
                else:
                    rich_text.append({
                        "type": "text",
                        "text": {"content": link_text[:2000]},
                        "annotations": {"code": True}
                    })
            elif m_dict.get("bold_italic"):
                rich_text.append({
                    "type": "text",
                    "text": {"content": m_dict["bi_text"][:2000]},
                    "annotations": {"bold": True, "italic": True}
                })
            elif m_dict.get("bold"):
                rich_text.append({
                    "type": "text",
                    "text": {"content": m_dict["bold_text"][:2000]},
                    "annotations": {"bold": True}
                })
            elif m_dict.get("code"):
                rich_text.append({
                    "type": "text",
                    "text": {"content": m_dict["code_text"][:2000]},
                    "annotations": {"code": True}
                })
            elif m_dict.get("strike"):
                rich_text.append({
                    "type": "text",
                    "text": {"content": m_dict["strike_text"][:2000]},
                    "annotations": {"strikethrough": True}
                })
            elif m_dict.get("italic"):
                rich_text.append({
                    "type": "text",
                    "text": {"content": m_dict["italic_text"][:2000]},
                    "annotations": {"italic": True}
                })

            last_idx = end

        if last_idx < len(text):
            trailing = text[last_idx:]
            if trailing:
                rich_text.append({"type": "text", "text": {"content": trailing[:2000]}})

        return rich_text if rich_text else [{"type": "text", "text": {"content": text[:2000]}}]

    def _markdown_to_blocks(self, markdown_text: str) -> List[Dict[str, Any]]:
        """Parses standard Markdown into rich Notion Block JSON objects including tables and inline formatting."""
        blocks: List[Dict[str, Any]] = []
        lines = markdown_text.split("\n")
        in_code_block = False
        code_language = "plain text"
        code_lines: List[str] = []

        in_table = False
        table_rows: List[List[str]] = []

        def flush_table():
            nonlocal in_table, table_rows, blocks
            if not in_table or not table_rows:
                in_table = False
                table_rows = []
                return

            width = max(len(r) for r in table_rows) if table_rows else 0
            if width > 0:
                notion_rows = []
                for r in table_rows:
                    padded = r + [""] * (width - len(r))
                    row_cells = [self._parse_inline_markdown(cell.strip()) for cell in padded]
                    notion_rows.append({
                        "type": "table_row",
                        "table_row": {
                            "cells": row_cells
                        }
                    })

                blocks.append({
                    "object": "block",
                    "type": "table",
                    "table": {
                        "table_width": width,
                        "has_column_header": True,
                        "has_row_header": False,
                        "children": notion_rows
                    }
                })
            in_table = False
            table_rows = []

        for line in lines:
            stripped = line.strip()

            # Handle Code Blocks
            if stripped.startswith("```"):
                flush_table()
                if in_code_block:
                    code_content = "\n".join(code_lines)
                    blocks.append({
                        "object": "block",
                        "type": "code",
                        "code": {
                            "rich_text": [{"type": "text", "text": {"content": code_content[:2000]}}],
                            "language": code_language
                        }
                    })
                    code_lines = []
                    in_code_block = False
                else:
                    in_code_block = True
                    lang = stripped[3:].strip().lower()
                    code_language = lang if lang in ["python", "javascript", "typescript", "swift", "bash", "json", "html", "css", "sql", "markdown", "rust", "go", "yaml", "mermaid"] else "plain text"
                continue

            if in_code_block:
                code_lines.append(line)
                continue

            # Handle Tables
            if stripped.startswith("|") and stripped.endswith("|"):
                inner = stripped[1:-1].strip()
                is_separator = all(c in "-: |" for c in inner) and "-" in inner
                if is_separator:
                    in_table = True
                    continue

                cells = [c.strip() for c in stripped[1:-1].split("|")]
                in_table = True
                table_rows.append(cells)
                continue
            else:
                if in_table:
                    flush_table()

            if not stripped:
                continue

            # Headings
            if re.match(r'^#\s+', stripped):
                content = re.sub(r'^#\s+', '', stripped)
                blocks.append({
                    "object": "block",
                    "type": "heading_1",
                    "heading_1": {
                        "rich_text": self._parse_inline_markdown(content)
                    }
                })
            elif re.match(r'^##\s+', stripped):
                content = re.sub(r'^##\s+', '', stripped)
                blocks.append({
                    "object": "block",
                    "type": "heading_2",
                    "heading_2": {
                        "rich_text": self._parse_inline_markdown(content)
                    }
                })
            elif re.match(r'^#{3,6}\s+', stripped):
                content = re.sub(r'^#{3,6}\s+', '', stripped)
                blocks.append({
                    "object": "block",
                    "type": "heading_3",
                    "heading_3": {
                        "rich_text": self._parse_inline_markdown(content)
                    }
                })
            # Divider
            elif stripped in ["---", "***", "___"]:
                blocks.append({
                    "object": "block",
                    "type": "divider",
                    "divider": {}
                })
            # Callout / Quote
            elif stripped.startswith("> "):
                blocks.append({
                    "object": "block",
                    "type": "quote",
                    "quote": {
                        "rich_text": self._parse_inline_markdown(stripped[2:])
                    }
                })
            # Bulleted List
            elif re.match(r'^[-*+]\s+', stripped):
                content = re.sub(r'^[-*+]\s+', '', stripped)
                blocks.append({
                    "object": "block",
                    "type": "bulleted_list_item",
                    "bulleted_list_item": {
                        "rich_text": self._parse_inline_markdown(content)
                    }
                })
            # Numbered List
            elif re.match(r'^\d+[\.\)]\s+', stripped):
                text_content = re.sub(r'^\d+[\.\)]\s+', '', stripped)
                blocks.append({
                    "object": "block",
                    "type": "numbered_list_item",
                    "numbered_list_item": {
                        "rich_text": self._parse_inline_markdown(text_content)
                    }
                })
            # Paragraph
            else:
                blocks.append({
                    "object": "block",
                    "type": "paragraph",
                    "paragraph": {
                        "rich_text": self._parse_inline_markdown(stripped)
                    }
                })

        flush_table()

        # Handle unclosed code block
        if in_code_block and code_lines:
            blocks.append({
                "object": "block",
                "type": "code",
                "code": {
                    "rich_text": [{"type": "text", "text": {"content": "\n".join(code_lines)[:2000]}}],
                    "language": code_language
                }
            })

        return blocks

    async def find_child_page_by_title(self, title: str) -> Optional[str]:
        """Searches for an existing child page with the given title under parent_page_id, cleaning up any duplicates."""
        if not self.api_key or not self.parent_page_id:
            return None

        clean_title = title.strip().lower()
        base_name = clean_title.replace(".md", "").strip()
        matching_ids = []

        # 1. Check direct child blocks under parent_page_id
        url = f"https://api.notion.com/v1/blocks/{self.parent_page_id}/children"
        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                has_more = True
                start_cursor = None
                while has_more:
                    params = {"page_size": 100}
                    if start_cursor:
                        params["start_cursor"] = start_cursor
                    resp = await client.get(url, headers=self.headers, params=params)
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                    for block in data.get("results", []):
                        if block.get("type") == "child_page":
                            child_title = block.get("child_page", {}).get("title", "").strip().lower()
                            child_base = child_title.replace(".md", "").strip()
                            if child_title == clean_title or child_base == base_name or (base_name and base_name in child_base) or (child_base and child_base in base_name):
                                matching_ids.append(block.get("id"))
                    has_more = data.get("has_more", False)
                    start_cursor = data.get("next_cursor")
            except Exception as e:
                print(f"[!] Warning: Failed to query child pages in Notion: {e}")

        # If multiple duplicate pages exist, keep the primary one and archive older duplicates
        if len(matching_ids) > 1:
            primary_id = matching_ids[0]
            async with httpx.AsyncClient(timeout=20.0) as client:
                for dup_id in matching_ids[1:]:
                    try:
                        print(f"[*] Archiving duplicate Notion child page: {dup_id}", flush=True)
                        await client.delete(f"https://api.notion.com/v1/blocks/{dup_id}", headers=self.headers)
                    except Exception:
                        pass
            return primary_id
        elif matching_ids:
            return matching_ids[0]

        # 2. Fallback to Notion Search API scoped to this parent
        try:
            async with httpx.AsyncClient(timeout=20.0) as client:
                search_resp = await client.post(
                    "https://api.notion.com/v1/search",
                    headers=self.headers,
                    json={"query": base_name, "filter": {"value": "page", "property": "object"}}
                )
                if search_resp.status_code == 200:
                    search_data = search_resp.json()
                    for r in search_data.get("results", []):
                        parent = r.get("parent", {})
                        parent_id = parent.get("page_id", "").replace("-", "")
                        if parent_id == self.parent_page_id or not self.parent_page_id:
                            return r.get("id")
        except Exception as e:
            print(f"[!] Warning: Notion search fallback error: {e}")

        return None

    async def get_page_markdown(self, page_id: str) -> str:
        """Retrieves and reconstructs clean markdown content from an existing Notion page."""
        if not self.api_key or not page_id:
            return ""
        clean_page_id = self._normalize_page_id(page_id)
        url = f"https://api.notion.com/v1/blocks/{clean_page_id}/children"
        lines = []
        async with httpx.AsyncClient(timeout=20.0) as client:
            try:
                has_more = True
                start_cursor = None
                while has_more:
                    params = {"page_size": 100}
                    if start_cursor:
                        params["start_cursor"] = start_cursor
                    resp = await client.get(url, headers=self.headers, params=params)
                    if resp.status_code != 200:
                        break
                    data = resp.json()
                    for b in data.get("results", []):
                        b_type = b.get("type")
                        if b_type == "heading_1":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("heading_1", {}).get("rich_text", [])])
                            lines.append(f"# {text}")
                        elif b_type == "heading_2":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("heading_2", {}).get("rich_text", [])])
                            lines.append(f"## {text}")
                        elif b_type == "heading_3":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("heading_3", {}).get("rich_text", [])])
                            lines.append(f"### {text}")
                        elif b_type == "bulleted_list_item":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("bulleted_list_item", {}).get("rich_text", [])])
                            lines.append(f"- {text}")
                        elif b_type == "numbered_list_item":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("numbered_list_item", {}).get("rich_text", [])])
                            lines.append(f"1. {text}")
                        elif b_type == "quote":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("quote", {}).get("rich_text", [])])
                            lines.append(f"> {text}")
                        elif b_type == "code":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("code", {}).get("rich_text", [])])
                            lang = b.get("code", {}).get("language", "")
                            lines.append(f"```{lang}\n{text}\n```")
                        elif b_type == "paragraph":
                            text = "".join([t.get("text", {}).get("content", "") for t in b.get("paragraph", {}).get("rich_text", [])])
                            lines.append(text)
                        elif b_type == "divider":
                            lines.append("---")
                    has_more = data.get("has_more", False)
                    start_cursor = data.get("next_cursor")
            except Exception as e:
                print(f"[!] Warning: Failed to fetch Notion page markdown: {e}")
        return "\n\n".join(lines)

    def _get_page_lock(self, page_id: str) -> asyncio.Lock:
        clean_id = self._normalize_page_id(page_id)
        if clean_id not in _notion_page_locks:
            _notion_page_locks[clean_id] = asyncio.Lock()
        return _notion_page_locks[clean_id]

    async def update_page(self, page_id: str, title: str, markdown_content: str) -> Dict[str, Any]:
        """Overwrites an existing Notion page by archiving previous blocks and appending new blocks."""
        if not self.api_key or not page_id:
            return {"status": "failed", "error": "Missing Notion API key or page_id"}

        clean_page_id = self._normalize_page_id(page_id)
        blocks = self._markdown_to_blocks(markdown_content)
        lock = self._get_page_lock(clean_page_id)

        async with lock:
            async with httpx.AsyncClient(timeout=120.0) as client:
                try:
                    # 1. Update Title & check page URL
                    page_url_resp = await client.patch(
                        f"https://api.notion.com/v1/pages/{clean_page_id}",
                        headers=self.headers,
                        json={"properties": {"title": {"title": [{"text": {"content": title[:2000]}}]}}}
                    )
                    page_url_data = page_url_resp.json() if page_url_resp.status_code == 200 else {}
                    page_url = page_url_data.get("url")

                    # 2. Delete / archive existing child blocks concurrently
                    children_url = f"https://api.notion.com/v1/blocks/{clean_page_id}/children"
                    has_more = True
                    start_cursor = None
                    while has_more:
                        params = {"page_size": 100}
                        if start_cursor:
                            params["start_cursor"] = start_cursor
                        c_resp = await client.get(children_url, headers=self.headers, params=params)
                        if c_resp.status_code != 200:
                            break
                        c_data = c_resp.json()
                        delete_tasks = []
                        for b in c_data.get("results", []):
                            b_id = b.get("id")
                            if b_id:
                                delete_tasks.append(client.delete(f"https://api.notion.com/v1/blocks/{b_id}", headers=self.headers))
                        if delete_tasks:
                            # Delete in small batches to respect Notion rate limits
                            for batch_i in range(0, len(delete_tasks), 10):
                                batch = delete_tasks[batch_i:batch_i+10]
                                await asyncio.gather(*batch, return_exceptions=True)
                                await asyncio.sleep(0.15)
                        has_more = c_data.get("has_more", False)
                        start_cursor = c_data.get("next_cursor")

                    # 3. Append new blocks in chunks of 95 with automatic 429 retry
                    total_chunks = (len(blocks) + 94) // 95 if blocks else 1
                    for idx, i in enumerate(range(0, len(blocks), 95)):
                        chunk = blocks[i:i+95]
                        chunk_num = idx + 1
                        success = False
                        
                        for attempt in range(5):
                            append_resp = await client.patch(
                                f"https://api.notion.com/v1/blocks/{clean_page_id}/children",
                                headers=self.headers,
                                json={"children": chunk}
                            )
                            if append_resp.status_code == 200:
                                success = True
                                break
                            elif append_resp.status_code == 429:
                                wait_sec = 3.0
                                try:
                                    err_json = append_resp.json()
                                    retry_after_val = err_json.get("additional_data", {}).get("retry_after")
                                    if retry_after_val:
                                        wait_sec = float(retry_after_val) + 1.0
                                except Exception:
                                    pass
                                print(f"[*] Notion API rate limit hit (429) on chunk {chunk_num}/{total_chunks}. Waiting {wait_sec:.1f}s before retry (attempt {attempt+1}/5)...", flush=True)
                                await asyncio.sleep(wait_sec)
                            else:
                                print(f"[!] Warning: Appending chunk {chunk_num}/{total_chunks} failed ({append_resp.status_code}): {append_resp.text}", flush=True)
                                await asyncio.sleep(1.5)
                        
                        if not success:
                            print(f"[!] Error: Chunk {chunk_num}/{total_chunks} failed to upload after 5 attempts.", flush=True)
                        else:
                            # Subtle pacing to avoid hitting rate limits on subsequent chunks
                            await asyncio.sleep(0.35)

                    return {"status": "success", "url": page_url, "id": clean_page_id}
                except Exception as e:
                    return {"status": "failed", "error": f"Failed to update Notion page: {str(e)}"}

    async def upsert_page(self, title: str, markdown_content: str, page_id: Optional[str] = None) -> Dict[str, Any]:
        """Overwrites existing page if it exists with the same title or ID, otherwise creates a new page."""
        target_page_id = page_id or await self.find_child_page_by_title(title)
        if target_page_id:
            print(f"[*] Found existing Notion page '{title}' ({target_page_id}). Overwriting content in-place...", flush=True)
            return await self.update_page(target_page_id, title, markdown_content)
        else:
            print(f"[*] No existing Notion page found for '{title}'. Creating new page...", flush=True)
            return await self.create_page(title, markdown_content)

