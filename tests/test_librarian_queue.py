import _bootstrap  # noqa: F401
import os
import unittest
from queue_manager import QueueManager

TEST_QUEUE_FILE = "test_librarian_queue.json"

class TestLibrarianQueue(unittest.TestCase):
    def setUp(self):
        if os.path.exists(TEST_QUEUE_FILE):
            os.remove(TEST_QUEUE_FILE)
        self.qm = QueueManager(storage_path=TEST_QUEUE_FILE)

    def tearDown(self):
        if os.path.exists(TEST_QUEUE_FILE):
            os.remove(TEST_QUEUE_FILE)

    def test_queue_add_and_list(self):
        self.assertEqual(self.qm.count(), 0)
        
        item1 = self.qm.add_item("First thought about auth architecture", source="voice", git_branch="feature/auth")
        self.assertEqual(item1["text"], "First thought about auth architecture")
        self.assertEqual(item1["git_branch"], "feature/auth")
        self.assertEqual(self.qm.count(), 1)
        
        item2 = self.qm.add_item("Second thought: Redis token rotation with 7d TTL", source="voice", git_branch="feature/auth")
        self.assertEqual(self.qm.count(), 2)
        
        items = self.qm.list_items()
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]["id"], item1["id"])
        self.assertEqual(items[1]["id"], item2["id"])

    def test_queue_update_and_delete(self):
        item1 = self.qm.add_item("Typo in this thought", source="voice")
        item2 = self.qm.add_item("Correct thought", source="manual")
        
        # Update item 1
        updated = self.qm.update_item(item1["id"], "Fixed thought text")
        self.assertIsNotNone(updated)
        self.assertEqual(updated["text"], "Fixed thought text")
        
        # Delete item 1
        deleted = self.qm.delete_item(item1["id"])
        self.assertTrue(deleted)
        self.assertEqual(self.qm.count(), 1)
        
        remaining = self.qm.list_items()
        self.assertEqual(remaining[0]["id"], item2["id"])
        
        # Clear queue
        self.qm.clear()
        self.assertEqual(self.qm.count(), 0)

if __name__ == "__main__":
    unittest.main()
