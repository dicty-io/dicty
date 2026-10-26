"""Tests for target-app aware dictation formatting.

Validates:
- App category detection from bundle IDs and localized app names.
- "auto" style resolution for chat, email, notes, issues, code, docs, and terminals.
- Style-specific prompt guidance without overriding an explicit style.
- /recording/stop and /transcribe expose the target app multipart fields.
"""

import _bootstrap  # noqa: F401
import inspect
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from prompts import (
    detect_target_app_category,
    get_target_app_prompt_guidance,
    resolve_format_style_for_target,
)


class TestTargetAppDetection(unittest.TestCase):
    def test_bundle_ids_are_detected(self):
        cases = {
            "com.tinyspeck.slackmacgap": "chat",
            "com.hnc.Discord": "chat",
            "com.microsoft.teams2": "chat",
            "com.apple.mail": "email",
            "com.microsoft.Outlook": "email",
            "notion.id": "notes",
            "md.obsidian": "notes",
            "com.linear": "issues",
            "com.atlassian.jira": "issues",
            "com.apple.dt.Xcode": "code",
            "com.microsoft.VSCode": "code",
            "com.jetbrains.pycharm": "code",
            "com.apple.Terminal": "terminal",
            "com.googlecode.iterm2": "terminal",
        }
        for bundle_id, expected in cases.items():
            with self.subTest(bundle_id=bundle_id):
                self.assertEqual(detect_target_app_category("", bundle_id), expected)

    def test_app_names_are_detected(self):
        cases = {
            "Slack": "chat",
            "Microsoft Teams": "chat",
            "Mail": "email",
            "Notion": "notes",
            "Linear": "issues",
            "Visual Studio Code": "code",
            "Xcode": "code",
            "iTerm2": "terminal",
            "Confluence": "docs",
        }
        for app_name, expected in cases.items():
            with self.subTest(app_name=app_name):
                self.assertEqual(detect_target_app_category(app_name, ""), expected)

    def test_unknown_or_empty_app_is_unknown(self):
        self.assertEqual(detect_target_app_category("", ""), "")
        self.assertEqual(detect_target_app_category("Some Random App", ""), "")


class TestAutoStyleResolution(unittest.TestCase):
    def test_auto_matches_app_category(self):
        cases = {
            "com.tinyspeck.slackmacgap": "message",
            "com.apple.mail": "email",
            "notion.id": "note",
            "com.linear": "note",
            "com.apple.dt.Xcode": "code",
            "com.apple.Terminal": "raw",
        }
        for bundle_id, expected in cases.items():
            with self.subTest(bundle_id=bundle_id):
                self.assertEqual(resolve_format_style_for_target("auto", "", bundle_id), expected)

    def test_auto_unknown_app_falls_back_to_message(self):
        self.assertEqual(resolve_format_style_for_target("auto", "Unknown App", ""), "message")

    def test_explicit_style_is_not_changed(self):
        self.assertEqual(resolve_format_style_for_target("email", "Slack", ""), "email")
        self.assertEqual(resolve_format_style_for_target("raw", "Xcode", ""), "raw")


class TestTargetAppGuidance(unittest.TestCase):
    def test_chat_guidance_only_applies_to_message_style(self):
        guidance = get_target_app_prompt_guidance("message", "Slack", "com.tinyspeck.slackmacgap")
        self.assertIn("chat app", guidance)
        self.assertNotIn("greeting", get_target_app_prompt_guidance("email", "Slack", ""))

    def test_issue_guidance_applies_to_note_style(self):
        guidance = get_target_app_prompt_guidance("note", "Linear", "com.linear")
        self.assertIn("issue tracker", guidance)
        self.assertIn("acceptance criteria", guidance)

    def test_code_guidance_preserves_identifiers(self):
        guidance = get_target_app_prompt_guidance("code", "Xcode", "com.apple.dt.Xcode")
        self.assertIn("code editor", guidance)
        self.assertIn("Preserve identifiers", guidance)

    def test_non_llm_styles_get_no_guidance(self):
        self.assertEqual(get_target_app_prompt_guidance("raw", "Slack", ""), "")
        self.assertEqual(get_target_app_prompt_guidance("book", "Slack", ""), "")
        self.assertEqual(get_target_app_prompt_guidance("punctuation_fast", "Slack", ""), "")

    def test_unknown_app_gets_no_guidance(self):
        self.assertEqual(get_target_app_prompt_guidance("message", "Unknown App", ""), "")


class TestTargetAppRouteContract(unittest.TestCase):
    def test_transcribe_routes_accept_target_app_fields(self):
        from dicty_engine import stop_recording, transcribe_uploaded_audio

        for endpoint in (stop_recording, transcribe_uploaded_audio):
            params = inspect.signature(endpoint).parameters
            with self.subTest(endpoint=endpoint.__name__):
                self.assertIn("target_app_name", params)
                self.assertIn("target_app_bundle_id", params)


class TestTargetAppPipeline(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.created_record_ids = []

    def tearDown(self):
        from dicty_engine import history_manager

        for record_id in self.created_record_ids:
            try:
                history_manager.delete_record(record_id)
            except Exception:
                pass

    @patch("transcribe_service.TranscribeService.transcribe", new_callable=AsyncMock)
    @patch("httpx.AsyncClient.post", new_callable=AsyncMock)
    async def test_auto_style_resolves_and_injects_slack_guidance(self, mock_post, mock_transcribe):
        from dicty_engine import history_manager, process_transcription

        raw_transcript = "hey can we move the sync to tomorrow"
        mock_transcribe.return_value = raw_transcript

        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.raise_for_status = MagicMock()
        mock_resp.json.return_value = {
            "choices": [{"message": {"content": "Hey, can we move the sync to tomorrow?"}}]
        }
        mock_post.return_value = mock_resp

        result = await process_transcription(
            audio_path="test_audio.wav",
            mode="dictation",
            dictation_format_style="auto",
            llm_provider="openai",
            llm_model="gpt-4o-mini",
            llm_api_key="sk-test-mock-key",
            target_app_name="Slack",
            target_app_bundle_id="com.tinyspeck.slackmacgap",
        )

        self.assertEqual(result["status"], "success")
        self.assertEqual(result["dictation_format_style"], "message")

        payload = mock_post.call_args.kwargs["json"]
        system_prompt = payload["messages"][0]["content"]
        self.assertIn("chat app (Slack)", system_prompt)
        self.assertIn("Do not add an email greeting or sign-off", system_prompt)

        matching = [
            record for record in history_manager.get_all()
            if record.get("text") == result["text"]
        ]
        self.assertTrue(len(matching) > 0)
        self.created_record_ids.append(matching[0]["id"])


if __name__ == "__main__":
    unittest.main()
