import _bootstrap  # noqa: F401
import os
import tempfile
import unittest

import dicty_paths
import dictation_metrics
import model_manager
import prompts
import queue_manager


class TestStorageIsolation(unittest.TestCase):
    def test_engine_paths_are_under_the_test_data_dir(self):
        root = os.path.realpath(_bootstrap.test_data_dir())
        temp_root = os.path.realpath(tempfile.gettempdir())
        real_root = os.path.realpath(_bootstrap.real_data_dir())
        resolved = [
            model_manager.DATA_DIR,
            model_manager.MODELS_DIR,
            model_manager.SETTINGS_FILE,
            queue_manager.QUEUE_FILE,
            prompts.PROMPTS_FILE,
            dictation_metrics.METRICS_FILE,
        ]
        for path in resolved:
            resolved_path = os.path.realpath(str(path))
            # The model cache is shared in the system temp dir; everything else lives
            # in the per-run data dir. Nothing may resolve into the real data dir.
            self.assertTrue(
                resolved_path.startswith(root) or resolved_path.startswith(temp_root),
                f"{path} is outside the isolated temp roots ({root}, {temp_root})",
            )
            self.assertFalse(
                resolved_path.startswith(real_root),
                f"{path} points into the real user data dir {real_root}",
            )

    def test_test_data_dir_is_not_the_real_data_dir(self):
        self.assertNotEqual(
            os.path.realpath(_bootstrap.test_data_dir()),
            os.path.realpath(_bootstrap.real_data_dir()),
        )
        self.assertEqual(
            os.path.realpath(dicty_paths.get_user_data_dir()),
            os.path.realpath(_bootstrap.test_data_dir()),
        )

    def test_guard_rejects_real_data_dir_under_testing(self):
        original = os.environ.pop("DICTY_DATA_DIR", None)
        try:
            with self.assertRaises(RuntimeError):
                dicty_paths.get_user_data_dir()

            os.environ["DICTY_DATA_DIR"] = os.path.join(
                _bootstrap.real_data_dir(), "nested-test-dir"
            )
            with self.assertRaises(RuntimeError):
                dicty_paths.get_user_data_dir()
        finally:
            if original is not None:
                os.environ["DICTY_DATA_DIR"] = original
            else:
                os.environ.pop("DICTY_DATA_DIR", None)
            os.environ["DICTY_TESTING"] = "1"

    def test_queue_writes_into_isolated_dir(self):
        manager = queue_manager.QueueManager()
        item = manager.add_item("storage isolation check", source="test")
        try:
            self.assertTrue(
                os.path.realpath(manager.storage_path).startswith(
                    os.path.realpath(_bootstrap.test_data_dir())
                )
            )
            self.assertTrue(os.path.exists(manager.storage_path))
        finally:
            manager.delete_item(item["id"])


if __name__ == "__main__":
    unittest.main()
