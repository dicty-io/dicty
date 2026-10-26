"""
tests/test_translation_and_ai_location.py
=========================================
Unit tests verifying:
1. Engine accepts any Whisper catalog language code for translate_to.
2. Switching ai_location ("local" <-> "cloud_when_better") preserves the speech model.
"""
import _bootstrap  # noqa: F401
import unittest
from fastapi.testclient import TestClient

import dicty_engine
from modes_service import ModesService, modes_service
from model_manager import ModelManager


class TestTranslationAndAILocation(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(dicty_engine.app)
        from engine_auth import get_token
        self.headers = {"X-Dicty-Token": get_token()}
        self.service = ModesService()
        self.mm = ModelManager()

    def test_translate_to_accepts_catalog_codes(self):
        # A representative sample of Whisper catalog language codes
        catalog_codes = [
            "en", "de", "fr", "es", "it", "ja", "zh", "ru", "uk", "ar",
            "hi", "pt", "nl", "pl", "tr", "haw", "af", "vi", "ko", "el"
        ]
        for code in catalog_codes:
            mode = self.service.update_mode("general", {"translate_to": code})
            self.assertEqual(mode["translate_to"], code, f"Failed to set translate_to for {code}")
            resolved = self.service.resolve_for_request(mode_id="general")
            self.assertEqual(resolved["translate_to"], code)

    def test_translate_to_none_and_sentinels_clear_translation(self):
        for sentinel in ["none", "auto", "same", "null", ""]:
            mode = self.service.update_mode("general", {"translate_to": sentinel})
            self.assertIsNone(mode["translate_to"], f"Sentinel {sentinel} did not clear translate_to")

    def test_ai_location_toggle_does_not_change_speech_model(self):
        # Pick an initial speech model
        initial_speech_model = "small"
        self.mm.set_active_model(initial_speech_model)
        self.assertEqual(self.mm.get_active_model(), initial_speech_model)

        # Switch ai_location to cloud_when_better via API
        resp = self.client.put(
            "/modes/settings",
            json={"ai_location": "cloud_when_better"},
            headers=self.headers,
        )
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(resp.json()["ai_location"], "cloud_when_better")

        # Speech model MUST be unchanged (not switched to Nova 3 or anything else)
        self.assertEqual(
            self.mm.get_active_model(),
            initial_speech_model,
            "Speech model changed when switching ai_location to cloud_when_better!"
        )

        # Switch ai_location back to local via API
        resp2 = self.client.put(
            "/modes/settings",
            json={"ai_location": "local"},
            headers=self.headers,
        )
        self.assertEqual(resp2.status_code, 200)
        self.assertEqual(resp2.json()["ai_location"], "local")

        # Speech model still unchanged
        self.assertEqual(
            self.mm.get_active_model(),
            initial_speech_model,
            "Speech model changed when switching ai_location to local!"
        )


if __name__ == "__main__":
    unittest.main()
