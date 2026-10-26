"""
tests/test_text_models_state.py
===============================
Unit tests for local text model classification, download detection,
and active text model state synchronization.
"""
import _bootstrap  # noqa: F401
import os
import tempfile
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import dicty_engine
from model_manager import ModelManager, LOCAL_TEXT_MODEL_FILES


class TestTextModelsState(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(dicty_engine.app)
        from engine_auth import get_token
        self.headers = {"X-Dicty-Token": get_token()}
        self.mm = ModelManager()

    def test_local_text_model_download_detection_with_variant(self):
        # Even if catalog ID is qwen2.5-1.5b-instruct, having qwen2.5-1.5b-instruct-q4_k_m.gguf
        # in MODELS_DIR with >= 100MB should mark it downloaded.
        with tempfile.TemporaryDirectory() as tmp_dir:
            fake_model = os.path.join(tmp_dir, "qwen2.5-1.5b-instruct-q4_k_m.gguf")
            with open(fake_model, "wb") as f:
                f.seek(101 * 1024 * 1024)  # 101 MB sparse file
                f.write(b"\0")

            with patch("model_manager.MODELS_DIR", tmp_dir):
                self.assertTrue(self.mm.is_model_downloaded("qwen2.5-1.5b-instruct"))

    def test_custom_user_gguf_detected_as_text_model_without_duplicating_catalog(self):
        with tempfile.TemporaryDirectory() as tmp_dir:
            # Create a catalog model file
            catalog_file = os.path.join(tmp_dir, "qwen2.5-1.5b-instruct-q4_k_m.gguf")
            with open(catalog_file, "wb") as f:
                f.seek(101 * 1024 * 1024)
                f.write(b"\0")

            # Create an arbitrary user custom GGUF
            user_file = os.path.join(tmp_dir, "my-custom-assistant.gguf")
            with open(user_file, "wb") as f:
                f.seek(50 * 1024 * 1024)
                f.write(b"\0")

            with patch("model_manager.MODELS_DIR", tmp_dir):
                models = self.mm.get_available_models()
                # 1. Catalog model should not be duplicated as custom
                custom_qwen = [m for m in models if m.get("id") == "qwen2.5-1.5b-instruct-q4_k_m"]
                self.assertEqual(len(custom_qwen), 0)

                # 2. User file should be detected as custom text model
                custom_models = [m for m in models if m.get("id") == "my-custom-assistant"]
                self.assertEqual(len(custom_models), 1)
                custom = custom_models[0]
                self.assertEqual(custom.get("category"), "text")
                self.assertTrue(custom.get("is_custom"))
                self.assertEqual(custom.get("tag"), "Your file")
                self.assertFalse(custom.get("is_cloud"))

    def test_active_models_endpoint_returns_active_text_model(self):
        resp = self.client.get("/models/active", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("active_model", data)
        self.assertIn("active_text_model", data)

    def test_active_text_model_get_and_set(self):
        # Test GET /models/active_text
        resp = self.client.get("/models/active_text", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertIn("active_text_model", resp.json())

        # Test POST /models/active_text with downloaded model
        with patch.object(ModelManager, "is_model_downloaded", return_value=True):
            resp2 = self.client.post("/models/active_text/qwen3.5-0.8b", headers=self.headers)
            self.assertEqual(resp2.status_code, 200)
            self.assertEqual(resp2.json()["active_text_model"], "qwen3.5-0.8b")


if __name__ == "__main__":
    unittest.main()
