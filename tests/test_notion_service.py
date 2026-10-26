import _bootstrap  # noqa: F401
import os
import sys
import unittest

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from notion_service import NotionService


class TestNotionServiceMarkdownSync(unittest.TestCase):
    
    @classmethod
    def setUpClass(cls):
        cls.service = NotionService(api_key="mock_key", parent_page_id="mock_page")

    # =========================================================================
    # 1. LINK SANITIZATION & RICH TEXT (PREVENT NOTION HTTP 400 ERRORS)
    # =========================================================================

    def test_build_rich_text_with_relative_links(self):
        """Test that relative links in markdown do not inject invalid link URLs into Notion rich text."""
        text = "Check [dicty_engine.py](dicty_engine.py) for the backend implementation and [website](https://dicty.ai)."
        rich_text = self.service._parse_inline_markdown(text)
        
        self.assertIsInstance(rich_text, list)
        self.assertGreater(len(rich_text), 0)
        
        # Verify relative link has no href / link property (treated as styled text/code)
        relative_link_item = next((item for item in rich_text if "dicty_engine.py" in item["text"]["content"]), None)
        self.assertIsNotNone(relative_link_item)
        self.assertIsNone(relative_link_item["text"].get("link"))

        # Verify absolute link has valid url
        absolute_link_item = next((item for item in rich_text if item["text"]["content"] == "website"), None)
        self.assertIsNotNone(absolute_link_item)
        self.assertEqual(absolute_link_item["text"]["link"]["url"], "https://dicty.ai")

    # =========================================================================
    # 2. BLOCK CONVERSIONS
    # =========================================================================

    def test_header_conversions(self):
        """Test markdown headings are converted to Notion heading blocks."""
        markdown = """# Heading 1
## Heading 2
### Heading 3"""
        blocks = self.service._markdown_to_blocks(markdown)
        self.assertEqual(len(blocks), 3)
        self.assertEqual(blocks[0]["type"], "heading_1")
        self.assertEqual(blocks[1]["type"], "heading_2")
        self.assertEqual(blocks[2]["type"], "heading_3")

    def test_bullet_and_numbered_lists(self):
        """Test bulleted and numbered lists."""
        markdown = """- Bullet item 1
* Bullet item 2
1. Numbered item 1
2. Numbered item 2"""
        blocks = self.service._markdown_to_blocks(markdown)
        self.assertEqual(len(blocks), 4)
        self.assertEqual(blocks[0]["type"], "bulleted_list_item")
        self.assertEqual(blocks[1]["type"], "bulleted_list_item")
        self.assertEqual(blocks[2]["type"], "numbered_list_item")
        self.assertEqual(blocks[3]["type"], "numbered_list_item")

    def test_blockquotes_and_callouts(self):
        """Test blockquote lines starting with >."""
        markdown = "> This is an important architecture note."
        blocks = self.service._markdown_to_blocks(markdown)
        self.assertEqual(len(blocks), 1)
        self.assertEqual(blocks[0]["type"], "quote")
        self.assertEqual(blocks[0]["quote"]["rich_text"][0]["text"]["content"], "This is an important architecture note.")

    def test_code_blocks_and_mermaid(self):
        """Test code blocks and Mermaid diagrams."""
        markdown = """```mermaid
flowchart TD
    A[Client] --> B[FastAPI Engine]
```

```swift
let app = DictyClient()
```"""
        blocks = self.service._markdown_to_blocks(markdown)
        self.assertEqual(len(blocks), 2)
        self.assertEqual(blocks[0]["type"], "code")
        self.assertEqual(blocks[0]["code"]["language"], "mermaid")
        self.assertEqual(blocks[1]["type"], "code")
        self.assertEqual(blocks[1]["code"]["language"], "swift")

    def test_table_parsing(self):
        """Test markdown table parsing into Notion table and table_row blocks."""
        markdown = """| Component | Technology | Purpose |
| --- | --- | --- |
| Client | SwiftUI / AppKit | Native macOS UI |
| Engine | FastAPI / Python | Local AI Audio & LLM |"""
        blocks = self.service._markdown_to_blocks(markdown)
        self.assertEqual(len(blocks), 1)
        table_block = blocks[0]
        self.assertEqual(table_block["type"], "table")
        self.assertEqual(table_block["table"]["table_width"], 3)
        self.assertEqual(table_block["table"]["has_column_header"], True)
        self.assertEqual(len(table_block["table"]["children"]), 3)  # 1 header + 2 rows

    def test_page_id_normalization(self):
        """Test UUID page id normalization removes dashes."""
        raw_uuid = "123e4567-e89b-12d3-a456-426614174000"
        normalized = NotionService._normalize_page_id(raw_uuid)
        self.assertEqual(normalized, "123e4567e89b12d3a456426614174000")


if __name__ == "__main__":
    unittest.main(verbosity=2)
