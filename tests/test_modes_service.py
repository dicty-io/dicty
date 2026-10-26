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

import modes_service as ms
import style_rules as sr

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")
EXPORT_FIXTURE = os.path.join(FIXTURES, "legacy_export_real.json")
PROFILES_FIXTURE = os.path.join(FIXTURES, "legacy_profiles_real.json")


def load(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


class ModesTestCase(unittest.TestCase):
    def setUp(self):
        self.data_dir = tempfile.mkdtemp(prefix="dicty-modes-")
        self.service = ms.ModesService(self.data_dir)

    def tearDown(self):
        shutil.rmtree(self.data_dir, ignore_errors=True)


class SeedTests(ModesTestCase):
    def test_new_install_defaults(self):
        document = self.service.get_document()
        self.assertEqual(document["schema_version"], ms.MODE_SCHEMA_VERSION)
        self.assertEqual(document["ai_location"], "local")
        self.assertTrue(document["automatic_app_rules"])
        self.assertEqual(document["active_mode_id"], "general")
        modes = {mode["id"]: mode for mode in document["modes"]}
        self.assertIn("general", modes)
        self.assertEqual(modes["general"]["style"], "clean")
        self.assertTrue(modes["general"]["fix_corrections"])
        self.assertEqual(modes["code"]["style"], "code")
        self.assertEqual(modes["meeting"]["kind"], "meeting")

    def test_seed_is_persisted(self):
        self.service.get_document()
        self.assertTrue(os.path.exists(self.service.path))
        with open(self.service.path, "r", encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["schema_version"], 2)


class ExportMigrationTests(ModesTestCase):
    def setUp(self):
        super().setUp()
        self.config = load(EXPORT_FIXTURE)
        self.report = self.service.migrate_config(self.config, source="legacy_export_real.json")
        self.document = self.service.get_document()
        self.modes = {mode["id"]: mode for mode in self.document["modes"]}

    def test_global_defaults(self):
        self.assertTrue(self.report["migrated"])
        self.assertEqual(self.document["ai_location"], "local")
        self.assertTrue(self.document["automatic_app_rules"])
        self.assertEqual(self.document["active_mode_id"], "general")

    def test_raw_maps_to_exact_on_active_mode(self):
        general = self.modes["general"]
        self.assertEqual(general["style"], "exact")
        self.assertEqual(general["dictation_format_style"], "raw")
        self.assertEqual(general["active_mode"], "dictation")

    def test_self_correction_toggle_maps_to_fix_corrections(self):
        self.assertTrue(self.modes["general"]["fix_corrections"])
        self.assertTrue(self.modes["email"]["fix_corrections"])
        self.assertTrue(self.modes["general"]["enable_self_correction"])

    def test_translation_lands_on_active_mode_only(self):
        self.assertEqual(self.modes["general"]["translate_to"], "de")
        for mode_id, mode in self.modes.items():
            if mode_id == "general":
                continue
            self.assertIsNone(mode["translate_to"], mode_id)
        translation = [m for m in self.report["mapping"] if m["setting"].startswith("translationMethod")]
        self.assertEqual(len(translation), 1)
        self.assertIn("translate_to=de", translation[0]["to"])

    def test_edited_prompts_become_custom_instructions(self):
        self.assertTrue(self.modes["email"]["custom_instructions"].startswith("Convert this voice dictation"))
        self.assertIn("Organize this dictation", self.modes["notes"]["custom_instructions"])
        # A note prompt must not leak into meeting modes.
        self.assertIsNone(self.modes["meeting"]["custom_instructions"])
        prompts = {m["setting"] for m in self.report["mapping"] if m["setting"].startswith("prompt:")}
        self.assertIn("prompt:dictation_email_system", prompts)
        self.assertIn("prompt:dictation_note_system", prompts)
        # The message prompt in this export is identical to the built-in one.
        self.assertNotIn("prompt:dictation_message_system", prompts)

    def test_meeting_modes_keep_their_kind(self):
        self.assertEqual(self.modes["meeting"]["kind"], "meeting")
        self.assertEqual(self.modes["meeting"]["meeting"]["legacy_mode"], "meeting")
        self.assertEqual(self.modes["focused-meeting"]["meeting"]["legacy_mode"], "focused_meeting")

    def test_every_export_key_is_accounted_for(self):
        mapped = {entry["setting"] for entry in self.report["mapping"]}
        # Credentials are removed from the document and reported separately.
        for key in self.report["redacted_keys"]:
            self.assertIn(key, self.config)
        for key in self.config:
            if key in self.report["redacted_keys"]:
                continue
            self.assertIn(key, mapped, f"{key} was not mapped or preserved")

    def test_secrets_are_redacted_everywhere(self):
        self.assertIn("llmApiKey", self.report["redacted_keys"])
        self.assertIn("openaiApiKey", self.report["redacted_keys"])
        self.assertIn("githubToken", self.report["redacted_keys"])
        with open(self.service.path, "r", encoding="utf-8") as handle:
            raw = handle.read()
        for secret in ("sk-or-v1-secret-value", "sk-secret-value", "ghp_secret"):
            self.assertNotIn(secret, raw)
        with open(self.report["backup"], "r", encoding="utf-8") as handle:
            backup = handle.read()
        for secret in ("sk-or-v1-secret-value", "sk-secret-value", "ghp_secret"):
            self.assertNotIn(secret, backup)

    def test_old_settings_are_preserved_in_legacy_globals(self):
        legacy = self.document["legacy_globals"]
        self.assertEqual(legacy["hotkeyKeyCode"], self.config["hotkeyKeyCode"])
        self.assertEqual(legacy["appTheme"], "Auto")
        self.assertEqual(legacy["localStorageBackup"]["active_mode"], "dictation")

    def test_deprecated_fields_are_readable(self):
        general = self.modes["general"]
        for field in (
            "active_mode", "dictation_format_style", "custom_prompt",
            "enable_self_correction", "translation_method", "target_language",
            "self_correction_model", "whisper_model",
        ):
            self.assertIn(field, general)
        self.assertEqual(general["target_language"], "de")

    def test_migration_report_includes_style_table(self):
        with open(self.service.path, "r", encoding="utf-8") as handle:
            document = json.load(handle)
        self.assertEqual(document["migration"]["style_map"], sr.LEGACY_STYLE_MAP)
        self.assertTrue(self.report["backup"].endswith(".json"))
        self.assertTrue(os.path.exists(self.report["backup"]))


class ProfilesMigrationTests(ModesTestCase):
    def setUp(self):
        super().setUp()
        self.profiles = load(PROFILES_FIXTURE)
        self.report = self.service.migrate_config(self.profiles, source="legacy_profiles_real.json")
        self.document = self.service.get_document()
        self.modes = {mode["id"]: mode for mode in self.document["modes"]}

    def test_all_real_profiles_are_kept(self):
        self.assertEqual(len(self.modes), len(self.profiles))
        for profile in self.profiles:
            self.assertIn(profile["id"], self.modes)

    def test_kinds_and_styles(self):
        self.assertEqual(self.modes["97181D1C-608D-4B46-B971-A34F4AE37456"]["style"], "exact")
        self.assertEqual(self.modes["0AF69BE9-FDC5-4983-9981-0A5031509114"]["style"], "clean")
        self.assertEqual(self.modes["A3DEA447-F4A8-43E7-BF4E-22D6E197EA60"]["kind"], "meeting")
        self.assertEqual(self.modes["E37F6B4A-7A6D-46BD-85BA-CDD4909283F2"]["meeting"]["enable_diarization"], True)
        prose = self.modes["F7182BF7-1BDB-4B9A-9DD0-72C02CE950BB"]
        self.assertEqual(prose["style"], "note")
        self.assertIn("literary editor", prose["custom_instructions"])
        self.assertEqual(self.modes["5DA4B040-3DF2-4BEC-99A5-E36CD4CF0980"]["style"], "email")

    def test_meeting_options_are_preserved(self):
        meeting = self.modes["A3DEA447-F4A8-43E7-BF4E-22D6E197EA60"]["meeting"]
        self.assertEqual(meeting["diarization_model"], "deepseek/deepseek-chat")
        self.assertEqual(meeting["speaker_you_label"], "Me")
        self.assertEqual(meeting["speaker_separation"], "you_others")

    def test_no_profile_field_is_lost(self):
        by_name = {entry["setting"]: entry for entry in self.report["mapping"] if entry["setting"].startswith("profile:")}
        for profile in self.profiles:
            entry = by_name[f"profile:{profile['name']}"]
            self.assertEqual(set(entry["fields"]), set(profile.keys()))
            mode = self.modes[profile["id"]]
            # Every field is either promoted or kept in the legacy object.
            for key in profile:
                self.assertTrue(
                    key in mode["legacy"] or key in mode,
                    f"{profile['name']}: {key} not preserved",
                )

    def test_fix_corrections_keeps_off_state(self):
        for mode in self.modes.values():
            self.assertFalse(mode["fix_corrections"])

    def test_idempotent_second_run_does_not_touch_the_file(self):
        with open(self.service.path, "rb") as handle:
            before = handle.read()
        second = self.service.migrate_config(self.profiles, source="again")
        self.assertFalse(second["migrated"])
        self.assertEqual(second["reason"], "already_migrated")
        with open(self.service.path, "rb") as handle:
            self.assertEqual(handle.read(), before)

    def test_force_with_same_config_is_still_idempotent(self):
        with open(self.service.path, "rb") as handle:
            before = handle.read()
        second = self.service.migrate_config(self.profiles, force=True, source="again")
        self.assertFalse(second["migrated"])
        with open(self.service.path, "rb") as handle:
            self.assertEqual(handle.read(), before)


class ValidationTests(ModesTestCase):
    def test_invalid_style_is_rejected(self):
        with self.assertRaises(ValueError):
            self.service.create_mode({"name": "Bad", "style": "purple"})

    def test_invalid_kind_is_rejected(self):
        with self.assertRaises(ValueError):
            self.service.create_mode({"name": "Bad", "kind": "podcast"})

    def test_duplicate_ids_are_rejected(self):
        with self.assertRaises(ValueError):
            self.service.replace_modes([
                {"id": "same", "name": "One"},
                {"id": "same", "name": "Two"},
            ])

    def test_old_fields_are_accepted(self):
        mode = self.service.create_mode({
            "id": "legacy",
            "name": "Legacy",
            "dictation_format_style": "raw",
            "enable_self_correction": True,
            "target_language": "fr",
            "translation_method": "cloud",
        })
        self.assertEqual(mode["style"], "exact")
        self.assertTrue(mode["fix_corrections"])
        self.assertEqual(mode["translate_to"], "fr")

    def test_update_keeps_the_id_and_normalises(self):
        updated = self.service.update_mode("general", {"id": "hijacked", "style": "code"})
        self.assertEqual(updated["id"], "general")
        self.assertEqual(updated["style"], "code")
        self.assertEqual(self.service.get_mode("general")["style"], "code")

    def test_delete_keeps_at_least_one_mode(self):
        document = self.service.get_document()
        for mode in document["modes"][1:]:
            self.service.delete_mode(mode["id"])
        with self.assertRaises(ValueError):
            self.service.delete_mode("general")

    def test_active_mode_falls_back(self):
        updated = self.service.set_settings({"active_mode_id": "missing"})
        self.assertEqual(updated["active_mode_id"], "general")

    def test_invalid_ai_location_is_rejected(self):
        with self.assertRaises(ValueError):
            self.service.set_settings({"ai_location": "somewhere"})


class ResolveModeTests(ModesTestCase):
    def test_resolve_by_id(self):
        self.service.migrate_config(load(EXPORT_FIXTURE))
        resolved = self.service.resolve_for_request(mode_id="code")
        self.assertEqual(resolved["mode_id"], "code")
        self.assertEqual(resolved["style"], "code")
        self.assertEqual(resolved["ai_location"], "local")
        self.assertTrue(resolved["fix_corrections"])

    def test_resolve_by_legacy_mode(self):
        self.service.migrate_config(load(EXPORT_FIXTURE))
        self.assertEqual(self.service.resolve_for_request(legacy_mode="meeting")["mode_id"], "meeting")
        self.assertEqual(self.service.resolve_for_request(legacy_mode="focused_meeting")["mode_id"], "focused-meeting")
        self.assertEqual(self.service.resolve_for_request(legacy_mode="dictation")["mode_id"], "general")

    def test_resolve_librarian_profile(self):
        self.service.migrate_config(load(PROFILES_FIXTURE))
        resolved = self.service.resolve_for_request(legacy_mode="librarian")
        self.assertEqual(resolved["mode_id"], "0AF69BE9-FDC5-4983-9981-0A5031509114")
        self.assertFalse(resolved["fix_corrections"])

    def test_resolve_defaults_when_nothing_matches(self):
        resolved = self.service.resolve_for_request()
        self.assertEqual(resolved["mode_id"], "general")
        self.assertEqual(resolved["ai_location"], "local")

    def test_unknown_mode_id_returns_none(self):
        # The caller must fall back to the values the client sent, not guess.
        self.assertIsNone(self.service.resolve_for_request(mode_id="ghost"))

    def test_correction_location_follows_ai_location(self):
        self.assertEqual(self.service.resolve_for_request(mode_id="general")["ai_location"], "local")
        self.service.set_settings({"ai_location": "cloud_when_better"})
        self.assertEqual(self.service.resolve_for_request(mode_id="general")["ai_location"], "cloud_when_better")


class CapabilityTests(ModesTestCase):
    def setUp(self):
        super().setUp()
        self.service.migrate_config(load(EXPORT_FIXTURE))

    def test_local_without_text_model_reports_download(self):
        with patch.object(self.service, "_downloaded_local_text_models", return_value=[]):
            capabilities = self.service.get_capabilities()
        by_id = {entry["mode_id"]: entry for entry in capabilities["modes"]}
        self.assertEqual(by_id["email"]["missing"], "text_model")
        self.assertEqual(by_id["email"]["fix"], f"download:{ms.DEFAULT_LOCAL_TEXT_MODEL}")
        self.assertEqual(by_id["email"]["size_mb"], 980)
        # The exported config translates into German, so General needs a model.
        self.assertEqual(by_id["general"]["missing"], "text_model")
        self.assertIsNone(by_id["message"]["missing"])
        self.assertIsNone(by_id["code"]["missing"])

    def test_local_reports_rule_based_correction(self):
        with patch.object(self.service, "_downloaded_local_text_models", return_value=[]):
            capabilities = self.service.get_capabilities()
        self.assertEqual(capabilities["correction_location"], "local_rules")
        for entry in capabilities["modes"]:
            self.assertEqual(entry["correction"], "local_rules")

    def test_cloud_reports_cloud_correction(self):
        self.service.set_settings({"ai_location": "cloud_when_better"})
        capabilities = self.service.get_capabilities()
        self.assertEqual(capabilities["correction_location"], "cloud")

    def test_download_target_for_waiting_mode(self):
        with patch.object(self.service, "_downloaded_local_text_models", return_value=[]):
            target = self.service.download_target_for_mode("email")
        self.assertIsNotNone(target)
        self.assertEqual(target["model_id"], ms.DEFAULT_LOCAL_TEXT_MODEL)
        self.assertEqual(target["size_mb"], 980)

    def test_download_target_is_none_when_ready(self):
        with patch.object(self.service, "_downloaded_local_text_models", return_value=[ms.DEFAULT_LOCAL_TEXT_MODEL]):
            self.assertIsNone(self.service.download_target_for_mode("email"))
        # Code is rule-based and never needs a model.
        self.assertIsNone(self.service.download_target_for_mode("code"))

    def test_local_with_text_model_is_ready(self):
        with patch.object(self.service, "_downloaded_local_text_models", return_value=["qwen2.5-1.5b-instruct"]):
            capabilities = self.service.get_capabilities()
        for entry in capabilities["modes"]:
            self.assertIsNone(entry["missing"], entry["mode_id"])

    def test_cloud_without_access_reports_sign_in(self):
        self.service.set_settings({"ai_location": "cloud_when_better"})
        with patch.object(self.service, "_has_cloud_access", return_value=False):
            capabilities = self.service.get_capabilities()
        by_id = {entry["mode_id"]: entry for entry in capabilities["modes"]}
        self.assertEqual(by_id["email"]["missing"], "cloud_access")
        self.assertEqual(by_id["email"]["fix"], "sign_in")

    def test_cloud_with_access_is_ready(self):
        self.service.set_settings({"ai_location": "cloud_when_better"})
        with patch.object(self.service, "_has_cloud_access", return_value=True):
            capabilities = self.service.get_capabilities()
        for entry in capabilities["modes"]:
            self.assertIsNone(entry["missing"], entry["mode_id"])


class AppRuleTests(ModesTestCase):
    def test_existing_app_rules_file_is_imported(self):
        rules = {
            "version": 1,
            "enabled": True,
            "rules": [
                {
                    "id": "builtin.chrome",
                    "match": {"type": "app", "value": "com.google.Chrome"},
                    "display_name": "Google Chrome",
                    "mode_id": "general",
                    "enabled": True,
                }
            ],
        }
        with open(os.path.join(self.data_dir, "app_rules.json"), "w", encoding="utf-8") as handle:
            json.dump(rules, handle)
        report = self.service.migrate_config(load(EXPORT_FIXTURE))
        self.assertIn("app_rules", {entry["setting"] for entry in report["mapping"]})
        self.assertEqual(self.service.get_app_rules()["rules"][0]["id"], "builtin.chrome")

    def test_replace_app_rules(self):
        updated = self.service.replace_app_rules({
            "enabled": False,
            "rules": [{"id": "x", "display_name": "X", "mode_id": "general", "enabled": True}],
        })
        self.assertFalse(updated["enabled"])
        self.assertEqual(updated["rules"][0]["id"], "x")


if __name__ == "__main__":
    unittest.main(verbosity=2)
