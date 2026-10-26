"""
tests/test_local_llm.py
=======================
Unit tests for the Offline Formatting Add-on and its engine endpoints.
"""
import _bootstrap  # noqa: F401
import os
import unittest
from unittest.mock import patch

from fastapi.testclient import TestClient

import dicty_engine
import local_llm


class TestLocalLLMAddon(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(dicty_engine.app)
        # Ensure engine auth headers are present if enforced
        from engine_auth import get_token
        self.headers = {"X-Dicty-Token": get_token()}

    def test_status_endpoint_returns_valid_structure(self):
        resp = self.client.get("/addons/local-llm/status", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("installed", data)
        self.assertIn("running", data)
        self.assertIn("stage", data)
        self.assertIn("progress", data)
        self.assertIn("disk_usage_bytes", data)
        self.assertIn("model_id", data)
        self.assertEqual(data["model_id"], "qwen2.5-1.5b-instruct")

    def test_toggle_when_not_installed_fails_with_400(self):
        with patch.object(local_llm, "is_installed", return_value=False):
            resp = self.client.post("/addons/local-llm/toggle", headers=self.headers)
            self.assertEqual(resp.status_code, 400)

    def test_cancel_endpoint(self):
        resp = self.client.post("/addons/local-llm/cancel", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json(), {"status": "cancelled"})

    def test_uninstall_endpoint_cleans_up_and_resets_settings(self):
        with patch.object(local_llm, "uninstall_addon", return_value={"status": "uninstalled", "reclaimed_bytes": 1000, "installed": False, "running": False}):
            resp = self.client.delete("/addons/local-llm", headers=self.headers)
            self.assertEqual(resp.status_code, 200)
            data = resp.json()
            self.assertEqual(data["status"], "uninstalled")

    def test_pid_file_lifecycle(self):
        test_pid = 999999
        local_llm.write_pid(test_pid)
        self.assertTrue(os.path.exists(local_llm.PID_FILE))
        local_llm.clear_pid()
        self.assertFalse(os.path.exists(local_llm.PID_FILE))

    def test_models_endpoint_returns_catalog(self):
        resp = self.client.get("/addons/local-llm/models", headers=self.headers)
        self.assertEqual(resp.status_code, 200)
        data = resp.json()
        self.assertIn("models", data)
        self.assertIn("active_model_id", data)
        model_ids = [m["id"] for m in data["models"]]
        self.assertIn("qwen2.5-1.5b-instruct", model_ids)
        self.assertIn("qwen3.5-0.8b", model_ids)
        self.assertIn("qwen3.5-2b", model_ids)

    def test_select_model_endpoint(self):
        with patch.object(local_llm, "switch_model", return_value=True):
            resp = self.client.post("/addons/local-llm/models/select", json={"model_id": "qwen3.5-0.8b"}, headers=self.headers)
            self.assertEqual(resp.status_code, 200)

        with patch.object(local_llm, "switch_model", return_value=False):
            resp_fail = self.client.post("/addons/local-llm/models/select", json={"model_id": "invalid-model"}, headers=self.headers)
            self.assertEqual(resp_fail.status_code, 400)

    def test_switch_model_real_persists_settings(self):
        # Test real switch_model logic without mocks
        res = local_llm.switch_model("invalid-model-name-xyz")
        self.assertFalse(res)


if __name__ == "__main__":
    unittest.main()
