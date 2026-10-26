"""Unit and integration tests for per-app dictation modes (app_rules).

Tests:
1. Full resolution order (each step)
2. User rule beats builtin; disabled builtin falls through
3. Deleted mode is skipped; meeting modes are rejected
4. Defaults updated in code don't overwrite user overrides
5. Windows exe names are matched case-insensitively
6. Atomic save; corrupt file falls back to defaults without crashing
7. resolve_mode takes < 1 ms benchmark
8. All FastAPI endpoints (/app-rules, /app-rules/settings, /app-rules/resolve, /stats/app-rules, etc.)
"""

import _bootstrap  # noqa: F401
import os
import shutil
import tempfile
import time
import unittest
from typing import Dict, Any

from app_rules import AppRulesManager
import app_rules_defaults
from fastapi.testclient import TestClient


class TestAppRulesCore(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="dicty_app_rules_test_")
        self.mgr = AppRulesManager(data_dir=self.test_dir)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_full_resolution_order(self):
        """Verify each of the 6 resolution steps in order."""
        # Setup: Slack has builtin "message"
        # Step 1: User picked a mode for THIS recording -> "book"
        mode, reason = self.mgr.resolve_mode(
            app_id="com.tinyspeck.slackmacgap",
            selected_mode_id="dictation",
            recording_override_mode_id="book",
            manual_override_active=True,  # Even if manual override is active, recording override wins
        )
        self.assertEqual(mode, "book")
        self.assertEqual(reason, "recording_override")

        # Step 2: Manual override active -> uses selected_mode_id
        mode, reason = self.mgr.resolve_mode(
            app_id="com.tinyspeck.slackmacgap",
            selected_mode_id="prose_mode",
            manual_override_active=True,
        )
        self.assertEqual(mode, "prose_mode")
        self.assertEqual(reason, "manual_override")

        # Step 3: Feature disabled -> uses selected_mode_id
        self.mgr.update_settings(enabled=False)
        mode, reason = self.mgr.resolve_mode(
            app_id="com.tinyspeck.slackmacgap",
            selected_mode_id="custom_default",
            manual_override_active=False,
        )
        self.assertEqual(mode, "custom_default")
        self.assertEqual(reason, "disabled")
        self.mgr.update_settings(enabled=True)

        # Step 4: User rule matches app -> wins over builtin
        self.mgr.add_rule(
            match={"type": "app", "value": "com.tinyspeck.slackmacgap"},
            mode_id="note",
            display_name="Slack Notes",
        )
        mode, reason = self.mgr.resolve_mode(
            app_id="com.tinyspeck.slackmacgap",
            selected_mode_id="dictation",
        )
        self.assertEqual(mode, "note")
        self.assertEqual(reason, "user_rule")

        # Step 5: Builtin rule matches app (e.g. Chrome -> "dictation")
        mode, reason = self.mgr.resolve_mode(
            app_id="com.google.Chrome",
            selected_mode_id="prose",
        )
        self.assertEqual(mode, "dictation")
        self.assertEqual(reason, "builtin_rule")

        # Step 6: Fallback to default when no rule matches
        mode, reason = self.mgr.resolve_mode(
            app_id="com.unknown.calculator",
            selected_mode_id="general_dictation",
        )
        self.assertEqual(mode, "general_dictation")
        self.assertEqual(reason, "default")

    def test_user_rule_beats_builtin_and_disabled_builtin_falls_through(self):
        """User rule beats builtin; disabling a builtin falls through to default."""
        # Enable Cursor builtin for testing
        self.mgr.update_rule("builtin.cursor", enabled=True)

        # 1. Cursor builtin is "code". Add a user rule for Cursor -> "note"
        rule = self.mgr.add_rule(
            match={"type": "app", "value": "com.todesktop.230313mzl4w4u92"},
            mode_id="note",
            display_name="Cursor",
        )
        mode, reason = self.mgr.resolve_mode(
            app_id="com.todesktop.230313mzl4w4u92",
            selected_mode_id="general",
        )
        self.assertEqual(mode, "note")
        self.assertEqual(reason, "user_rule")

        # Remove the user rule
        self.mgr.delete_rule(rule["id"])

        # Now Cursor resolves via builtin
        mode, reason = self.mgr.resolve_mode(
            app_id="com.todesktop.230313mzl4w4u92",
            selected_mode_id="general",
        )
        self.assertEqual(mode, "code")
        self.assertEqual(reason, "builtin_rule")

        # Disable the builtin for Cursor
        self.mgr.update_rule("builtin.cursor", enabled=False)
        mode, reason = self.mgr.resolve_mode(
            app_id="com.todesktop.230313mzl4w4u92",
            selected_mode_id="general",
        )
        self.assertEqual(mode, "general")
        self.assertEqual(reason, "default")

    def test_deleted_mode_skipped_and_meeting_modes_rejected(self):
        """A deleted mode falls through; meeting modes are rejected."""
        # Cannot add a rule targeting meeting modes
        with self.assertRaises(ValueError):
            self.mgr.add_rule(
                match={"type": "app", "value": "com.apple.mail"},
                mode_id="meeting",
            )
        with self.assertRaises(ValueError):
            self.mgr.add_rule(
                match={"type": "app", "value": "com.apple.mail"},
                mode_id="focused_meeting",
            )

        # Cannot update a builtin to a meeting mode
        with self.assertRaises(ValueError):
            self.mgr.update_rule("builtin.mail", mode_id="meeting")

        # User rule pointing to a deleted mode ID
        self.mgr.add_rule(
            match={"type": "app", "value": "com.random.app"},
            mode_id="custom_mode_123",
        )
        # If available_mode_ids is provided and does not contain "custom_mode_123"
        mode, reason = self.mgr.resolve_mode(
            app_id="com.random.app",
            selected_mode_id="standard_dictation",
            available_mode_ids={"standard_dictation", "other_mode"},
        )
        # Should skip deleted mode and fall through to default
        self.assertEqual(mode, "standard_dictation")
        self.assertEqual(reason, "default")

        # If custom_mode_123 IS available:
        mode, reason = self.mgr.resolve_mode(
            app_id="com.random.app",
            selected_mode_id="standard_dictation",
            available_mode_ids={"standard_dictation", "custom_mode_123"},
        )
        self.assertEqual(mode, "custom_mode_123")
        self.assertEqual(reason, "user_rule")

    def test_defaults_in_code_dont_overwrite_user_overrides(self):
        """User overrides to builtins persist even if code defaults exist."""
        # Override builtin.slack to "note"
        self.mgr.update_rule("builtin.slack", mode_id="note")

        eff = {r["id"]: r for r in self.mgr.effective_rules()}
        self.assertEqual(eff["builtin.slack"]["mode_id"], "note")
        self.assertEqual(eff["builtin.slack"]["source"], "builtin_override")

        # Simulate reloading from disk
        new_mgr = AppRulesManager(data_dir=self.test_dir)
        eff_new = {r["id"]: r for r in new_mgr.effective_rules()}
        self.assertEqual(eff_new["builtin.slack"]["mode_id"], "note")
        self.assertEqual(eff_new["builtin.slack"]["source"], "builtin_override")

    def test_case_insensitive_and_windows_exe_matching(self):
        """Windows exe names and bundle IDs match case-insensitively."""
        # Enable builtins for testing
        self.mgr.update_rule("builtin.slack", enabled=True)
        self.mgr.update_rule("builtin.cursor", enabled=True)
        self.mgr.update_rule("builtin.outlook", enabled=True)

        # Slack exe
        for name in ["SLACK.EXE", "slack.exe", "Slack.exe"]:
            mode, reason = self.mgr.resolve_mode(app_id=name, selected_mode_id="default")
            self.assertEqual(mode, "message", f"Failed for {name}")
            self.assertEqual(reason, "builtin_rule")

        # Cursor exe
        for name in ["CURSOR.EXE", "cursor.exe", "Cursor.EXE"]:
            mode, reason = self.mgr.resolve_mode(app_id=name, selected_mode_id="default")
            self.assertEqual(mode, "code", f"Failed for {name}")
            self.assertEqual(reason, "builtin_rule")

        # Bundle ID uppercase
        mode, reason = self.mgr.resolve_mode(app_id="COM.MICROSOFT.OUTLOOK", selected_mode_id="default")
        self.assertEqual(mode, "email")
        self.assertEqual(reason, "builtin_rule")

    def test_atomic_save_and_corruption_recovery(self):
        """A corrupted app_rules.json does not crash and falls back safely to defaults."""
        # Write invalid JSON
        corrupt_path = os.path.join(self.test_dir, "app_rules.json")
        with open(corrupt_path, "w", encoding="utf-8") as f:
            f.write("{invalid json syntax, missing quotes")

        mgr2 = AppRulesManager(data_dir=self.test_dir)
        settings = mgr2.get_settings()
        self.assertTrue(settings["enabled"])
        self.assertEqual(settings["override_scope"], "recording")

        eff = mgr2.effective_rules()
        self.assertGreater(len(eff), 10)  # Built-ins loaded cleanly

        # Resolve mode still works for default-enabled browser rule
        mode, reason = mgr2.resolve_mode(app_id="chrome.exe", selected_mode_id="default")
        self.assertEqual(mode, "dictation")
        self.assertEqual(reason, "builtin_rule")

    def test_resolve_mode_performance(self):
        """resolve_mode must take < 1 ms (typically < 0.05 ms)."""
        iterations = 5000
        t0 = time.perf_counter()
        for _ in range(iterations):
            self.mgr.resolve_mode(
                app_id="com.tinyspeck.slackmacgap",
                selected_mode_id="dictation",
            )
        elapsed = time.perf_counter() - t0
        avg_ms = (elapsed / iterations) * 1000.0
        self.assertLess(avg_ms, 1.0, f"resolve_mode too slow: {avg_ms:.4f} ms per call")


class TestAppRulesEndpoints(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from dicty_engine import app, app_rules_manager
        import engine_auth
        cls.client = TestClient(app)
        cls.token = engine_auth.get_token()
        cls.headers = {"X-Dicty-Token": cls.token}
        cls.rules_mgr = app_rules_manager

    def setUp(self):
        # Reset rules before each test
        self.client.post("/app-rules/reset", headers=self.headers)

    def test_get_and_put_settings(self):
        # GET /app-rules
        res = self.client.get("/app-rules", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        data = res.json()
        self.assertTrue(data["settings"]["enabled"])
        self.assertEqual(data["settings"]["override_scope"], "recording")
        self.assertIsInstance(data["rules"], list)

        # PUT /app-rules/settings
        res = self.client.put("/app-rules/settings", json={"enabled": False, "override_scope": "manual"}, headers=self.headers)
        self.assertEqual(res.status_code, 200)
        updated = res.json()["settings"]
        self.assertFalse(updated["enabled"])
        self.assertEqual(updated["override_scope"], "manual")

        # Invalid scope
        res = self.client.put("/app-rules/settings", json={"override_scope": "invalid"}, headers=self.headers)
        self.assertEqual(res.status_code, 400)

    def test_crud_rules(self):
        # 1. POST /app-rules with match.type = "bundle_id" (macOS Swift client format)
        res_swift = self.client.post("/app-rules", json={
            "match": {"type": "bundle_id", "value": "com.antigravity.ide"},
            "mode_id": "code",
            "display_name": "Antigravity IDE"
        }, headers=self.headers)
        self.assertEqual(res_swift.status_code, 200)
        self.assertEqual(res_swift.json()["rule"]["match"]["type"], "app")
        self.assertEqual(res_swift.json()["rule"]["match"]["value"], "com.antigravity.ide")
        self.assertFalse(res_swift.json()["rule"]["is_default"])

        # 2. POST /app-rules with app_id and app_name (Tauri React client format)
        res_tauri = self.client.post("/app-rules", json={
            "app_id": "slack.exe",
            "app_name": "Slack",
            "mode_id": "message",
            "enabled": True
        }, headers=self.headers)
        self.assertEqual(res_tauri.status_code, 200)
        self.assertEqual(res_tauri.json()["rule"]["match"]["value"], "slack.exe")

        # 3. POST /app-rules (standard match format)
        res = self.client.post("/app-rules", json={
            "match": {"type": "app", "value": "com.sublimetext.4"},
            "mode_id": "code",
            "display_name": "Sublime"
        }, headers=self.headers)
        self.assertEqual(res.status_code, 200)
        created = res.json()["rule"]
        rule_id = created["id"]
        self.assertEqual(created["mode_id"], "code")
        self.assertEqual(created["source"], "user")
        self.assertFalse(created["is_default"])

        # Check effective rules have is_default and overridden
        all_rules = self.client.get("/app-rules", headers=self.headers).json()["rules"]
        for r in all_rules:
            self.assertIn("is_default", r)
            self.assertIn("overridden", r)

        # PATCH /app-rules/{id} (update user rule)
        res = self.client.patch(f"/app-rules/{rule_id}", json={
            "mode_id": "note",
            "display_name": "Sublime Notes"
        }, headers=self.headers)
        self.assertEqual(res.status_code, 200)
        updated = res.json()["rule"]
        self.assertEqual(updated["mode_id"], "note")
        self.assertEqual(updated["display_name"], "Sublime Notes")

        # PATCH builtin rule
        res = self.client.patch("/app-rules/builtin.cursor", json={
            "mode_id": "note"
        }, headers=self.headers)
        self.assertEqual(res.status_code, 200)
        ov = res.json()["rule"]
        self.assertEqual(ov["mode_id"], "note")
        self.assertEqual(ov["source"], "builtin_override")

        # DELETE builtin rule (resets override)
        res = self.client.delete("/app-rules/builtin.cursor", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        # Check that it reverted to default "code"
        res_list = self.client.get("/app-rules", headers=self.headers).json()["rules"]
        cursor_rule = next(r for r in res_list if r["id"] == "builtin.cursor")
        self.assertEqual(cursor_rule["mode_id"], "code")
        self.assertEqual(cursor_rule["source"], "builtin")

        # DELETE user rule
        res = self.client.delete(f"/app-rules/{rule_id}", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        # Delete non-existent
        res = self.client.delete(f"/app-rules/{rule_id}", headers=self.headers)
        self.assertEqual(res.status_code, 404)

    def test_resolve_endpoint(self):
        # GET /app-rules/resolve?app_id=com.google.Chrome
        res = self.client.get("/app-rules/resolve?app_id=com.google.Chrome", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json(), {"mode_id": "dictation", "reason": "builtin_rule"})

        # With recording override
        res = self.client.get("/app-rules/resolve?app_id=com.google.Chrome&recording_override_mode_id=book", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json(), {"mode_id": "book", "reason": "recording_override"})

    def test_stats_app_rules_endpoint(self):
        res = self.client.get("/stats/app-rules", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertIn("stats", res.json())

    def test_suggestion_endpoints(self):
        # 1. Accept suggestion
        res = self.client.post("/app-rules/accept-suggestion", json={
            "app_id": "com.test.learnapp",
            "mode_id": "note",
            "display_name": "Learn App"
        }, headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertEqual(res.json()["rule"]["mode_id"], "note")

        # 2. Suppress suggestion
        res = self.client.post("/app-rules/suppress-suggestion", json={
            "app_id": "com.test.suppressapp",
            "display_name": "Suppress App"
        }, headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertTrue(res.json()["result"]["suppress_suggestion"])

        # 3. Get suggestion endpoint
        res = self.client.get("/app-rules/suggestion?app_id=com.test.suppressapp", headers=self.headers)
        self.assertEqual(res.status_code, 200)
        self.assertIsNone(res.json()["suggestion"])


class TestAppRulesPhase3Learning(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp(prefix="dicty_app_rules_phase3_test_")
        self.mgr = AppRulesManager(data_dir=self.test_dir)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_suggestion_threshold_and_cooldown(self):
        now = time.time()
        app_id = "com.apple.mobilesms"
        # Builtin for MobileSMS is "message"

        # 1. Only 1 override -> No suggestion
        history_1 = [
            {
                "id": "1",
                "app_id": app_id,
                "mode_id": "note",
                "mode_reason": "recording_override",
                "timestamp": now - 3600,
            }
        ]
        self.assertIsNone(self.mgr.check_suggestion(history_1, app_id))

        # 2. 2 overrides in 7 days -> Triggers suggestion
        history_2 = history_1 + [
            {
                "id": "2",
                "app_id": app_id,
                "mode_id": "note",
                "mode_reason": "manual_override",
                "timestamp": now - 1800,
            }
        ]
        sug = self.mgr.check_suggestion(history_2, app_id)
        self.assertIsNotNone(sug)
        self.assertEqual(sug["mode_id"], "note")
        self.assertEqual(sug["count"], 2)

        # 3. Mark prompted -> Cooldown prevents re-prompting within 7 days
        self.mgr.mark_suggestion_prompted(app_id)
        self.assertIsNone(self.mgr.check_suggestion(history_2, app_id))

        # 4. If rule is already "note", don't suggest
        self.mgr.update_rule("builtin.messages", mode_id="note", enabled=True)
        # Reset last_suggested_at
        data = self.mgr._read_data()
        data["suggestions_meta"][app_id]["last_suggested_at"] = now - (8 * 86400)
        self.mgr._write_data(data)
        self.assertIsNone(self.mgr.check_suggestion(history_2, app_id))

    def test_suppress_suggestion_persistence(self):
        app_id = "com.custom.app"
        now = time.time()
        history = [
            {"id": "1", "app_id": app_id, "mode_id": "code", "mode_reason": "manual_override", "timestamp": now - 100},
            {"id": "2", "app_id": app_id, "mode_id": "code", "mode_reason": "manual_override", "timestamp": now - 50},
        ]
        # Initially qualifies
        self.assertIsNotNone(self.mgr.check_suggestion(history, app_id))

        # Suppress
        res = self.mgr.suppress_suggestion(app_id, display_name="Custom App")
        self.assertTrue(res["suppress_suggestion"])

        # Check suppression
        self.assertTrue(self.mgr.is_suggestion_suppressed(app_id))
        self.assertIsNone(self.mgr.check_suggestion(history, app_id))

        # Verify disk persistence with new manager instance
        new_mgr = AppRulesManager(data_dir=self.test_dir)
        self.assertTrue(new_mgr.is_suggestion_suppressed(app_id))
        eff = new_mgr.effective_rules()
        custom_rule = next(r for r in eff if r.get("match", {}).get("value") == app_id)
        self.assertTrue(custom_rule.get("suppress_suggestion"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
