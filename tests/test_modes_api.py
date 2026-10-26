import _bootstrap  # noqa: F401
import json
import os
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from fastapi.testclient import TestClient

from dicty_engine import app
import modes_service as ms

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
EXPORT_FIXTURE = os.path.join(FIXTURES, "legacy_export_real.json")


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


class ModesApiTests(unittest.TestCase):
    def setUp(self):
        self.data_dir = tempfile.mkdtemp(prefix="dicty-modes-api-")
        self.patch_dir = patch.object(ms.modes_service, "data_dir", self.data_dir)
        self.patch_path = patch.object(ms.modes_service, "path", os.path.join(self.data_dir, "modes.json"))
        self.patch_dir.start()
        self.patch_path.start()
        self.client = TestClient(app)

    def tearDown(self):
        self.patch_path.stop()
        self.patch_dir.stop()
        shutil.rmtree(self.data_dir, ignore_errors=True)

    def test_get_modes_seeds_defaults(self):
        response = self.client.get("/modes")
        self.assertEqual(response.status_code, 200)
        document = response.json()
        self.assertEqual(document["schema_version"], ms.MODE_SCHEMA_VERSION)
        ids = [mode["id"] for mode in document["modes"]]
        self.assertIn("general", ids)
        self.assertIn("meeting", ids)

    def test_mode_crud(self):
        created = self.client.post("/modes", json={
            "id": "standup",
            "name": "Standup",
            "style": "clean",
        })
        self.assertEqual(created.status_code, 200, created.text)
        self.assertEqual(created.json()["id"], "standup")

        updated = self.client.put("/modes/standup", json={"style": "code"})
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["style"], "code")

        fetched = self.client.get("/modes/standup")
        self.assertEqual(fetched.status_code, 200)
        self.assertEqual(fetched.json()["id"], "standup")

        deleted = self.client.delete("/modes/standup")
        self.assertEqual(deleted.status_code, 200, deleted.text)
        self.assertNotIn("standup", [mode["id"] for mode in deleted.json()["modes"]])

    def test_unknown_mode_returns_404(self):
        self.assertEqual(self.client.get("/modes/nope").status_code, 404)
        self.assertEqual(self.client.put("/modes/nope", json={"style": "code"}).status_code, 404)
        self.assertEqual(self.client.delete("/modes/nope").status_code, 404)

    def test_invalid_mode_returns_400(self):
        response = self.client.post("/modes", json={"name": "Bad", "style": "purple"})
        self.assertEqual(response.status_code, 400)
        self.assertIn("style", response.json()["detail"])

    def test_settings_route_is_not_a_mode_id(self):
        response = self.client.get("/modes/settings")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["ai_location"], "local")

        updated = self.client.put("/modes/settings", json={"ai_location": "cloud_when_better"})
        self.assertEqual(updated.status_code, 200, updated.text)
        self.assertEqual(updated.json()["ai_location"], "cloud_when_better")

    def test_invalid_settings_returns_400(self):
        response = self.client.put("/modes/settings", json={"ai_location": "mars"})
        self.assertEqual(response.status_code, 400)

    def test_app_rules_round_trip(self):
        payload = {
            "enabled": True,
            "rules": [{"id": "chrome", "display_name": "Chrome", "mode_id": "general", "enabled": True}],
        }
        response = self.client.put("/modes/app_rules", json=payload)
        self.assertEqual(response.status_code, 200, response.text)
        self.assertEqual(response.json()["rules"][0]["id"], "chrome")
        fetched = self.client.get("/modes/app_rules")
        self.assertEqual(fetched.status_code, 200)
        self.assertTrue(fetched.json()["enabled"])

    def test_replace_modes_rejects_duplicates(self):
        response = self.client.put("/modes", json={"modes": [
            {"id": "same", "name": "One"},
            {"id": "same", "name": "Two"},
        ]})
        self.assertEqual(response.status_code, 400)

    def test_migrate_then_read_migration_and_capabilities(self):
        config = load(EXPORT_FIXTURE)
        response = self.client.post("/modes/migrate", json={
            "config": config,
            "force": True,
            "source": "api-test",
        })
        self.assertEqual(response.status_code, 200, response.text)
        report = response.json()
        self.assertTrue(report["migrated"])
        self.assertTrue(os.path.exists(report["backup"]))
        self.assertIn("llmApiKey", report["redacted_keys"])

        migration = self.client.get("/modes/migration")
        self.assertEqual(migration.status_code, 200)
        self.assertEqual(migration.json()["source"], "api-test")

        capabilities = self.client.get("/capabilities")
        self.assertEqual(capabilities.status_code, 200)
        self.assertIn("modes", capabilities.json())

        document = self.client.get("/modes").json()
        general = next(mode for mode in document["modes"] if mode["id"] == "general")
        self.assertEqual(general["style"], "exact")
        self.assertEqual(general["translate_to"], "de")

    def test_second_migration_is_idempotent(self):
        config = load(EXPORT_FIXTURE)
        first = self.client.post("/modes/migrate", json=config)
        self.assertEqual(first.status_code, 200, first.text)
        self.assertTrue(first.json()["migrated"])

        second = self.client.post("/modes/migrate", json=config)
        self.assertEqual(second.status_code, 200)
        self.assertFalse(second.json()["migrated"])
        self.assertEqual(second.json()["reason"], "already_migrated")

    def test_capabilities_report_correction_location(self):
        response = self.client.get("/capabilities")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["correction_location"], "local_rules")

    def test_capabilities_fix_starts_the_needed_download(self):
        self.client.post("/modes/migrate", json={"config": load(EXPORT_FIXTURE), "force": True})
        with patch.object(ms.modes_service, "_downloaded_local_text_models", return_value=[]), \
             patch.object(ms.modes_service, "_has_cloud_access", return_value=True), \
             patch("dicty_engine.model_manager.is_model_downloaded", return_value=False), \
             patch("dicty_engine.model_manager.start_download") as start:
            response = self.client.post("/capabilities/fix", json={"mode_id": "email"})
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body["status"], "download_started")
        self.assertEqual(body["model_id"], ms.DEFAULT_LOCAL_TEXT_MODEL)
        start.assert_called_once()
        self.assertEqual(start.call_args.args[0], ms.DEFAULT_LOCAL_TEXT_MODEL)

    def test_capabilities_fix_is_a_no_op_for_rule_based_modes(self):
        response = self.client.post("/capabilities/fix", json={"mode_id": "code"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["status"], "nothing_to_do")

    def test_capabilities_fix_requires_a_mode_id(self):
        response = self.client.post("/capabilities/fix", json={})
        self.assertEqual(response.status_code, 400)


if __name__ == "__main__":
    unittest.main(verbosity=2)
