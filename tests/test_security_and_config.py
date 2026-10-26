import _bootstrap  # noqa: F401
import os
import sys
import json
import unittest

# Ensure project root is in sys.path
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)


class TestSecurityAndConfiguration(unittest.TestCase):

    # =========================================================================
    # 1. CONFIGURATION INTEGRITY TESTS
    # =========================================================================

    def test_models_config_json_validity(self):
        """Verify models_config.json is valid JSON and all models have required attributes."""
        config_path = os.path.join(PROJECT_ROOT, "models_config.json")
        self.assertTrue(os.path.exists(config_path), "models_config.json must exist in project root")
        
        with open(config_path, "r", encoding="utf-8") as f:
            data = json.load(f)
            
        self.assertIn("models", data)
        models = data["models"]
        self.assertIsInstance(models, list)
        self.assertGreater(len(models), 0)

        required_keys = {"id", "name", "size", "speed", "accuracy"}
        for model in models:
            for key in required_keys:
                self.assertIn(key, model, f"Model {model.get('id', 'unknown')} is missing required key '{key}'")
            self.assertIsInstance(model["id"], str)
            self.assertIsInstance(model["name"], str)
            self.assertIsInstance(model["speed"], (int, float))
            self.assertIsInstance(model["accuracy"], (int, float))

    def test_prompts_templates_validity(self):
        """Verify prompt generator functions return non-empty strings."""
        from prompts import (
            get_reconcile_system_prompt,
            get_reconcile_user_prompt,
            get_architecture_system_prompt,
            get_architecture_user_prompt,
            get_meeting_diarization_system_prompt
        )
        
        self.assertIsInstance(get_reconcile_system_prompt(), str)
        self.assertGreater(len(get_reconcile_system_prompt()), 50)

        self.assertIsInstance(get_architecture_system_prompt(), str)
        self.assertGreater(len(get_architecture_system_prompt()), 50)

        self.assertIsInstance(get_meeting_diarization_system_prompt(), str)
        self.assertGreater(len(get_meeting_diarization_system_prompt()), 50)

        reconcile_sys = get_reconcile_system_prompt()
        self.assertIn("DEVELOPER VOICE INTENT IS THE SUPREME DIRECTIVE", reconcile_sys)
        self.assertNotIn("NEVER write from the perspective of an announcement or diff summary", reconcile_sys)

        user_prompt = get_reconcile_user_prompt("Updated architecture", "git diff", "repo context")
        self.assertIn("Updated architecture", user_prompt)
        self.assertIn("PRIMARY DIRECTIVE:", user_prompt)

    # =========================================================================
    # 2. TOKEN & SECURITY SANITIZATION
    # =========================================================================

    def test_no_hardcoded_secret_keys_in_repo_configs(self):
        """Ensure json config files in repository do not contain active live secret keys."""
        config_files = ["models_config.json", "custom_prompts.json", "vocabulary.json"]
        forbidden_substrings = ["sk-or-v1-", "secret_", "ghp_", "bearer "]

        for fname in config_files:
            fpath = os.path.join(PROJECT_ROOT, fname)
            if not os.path.exists(fpath):
                continue
            with open(fpath, "r", encoding="utf-8") as f:
                content = f.read().lower()
                for secret in forbidden_substrings:
                    self.assertNotIn(secret, content, f"Potentially leaked secret pattern '{secret}' found in {fname}")

    def test_auth_token_helpers(self):
        """Verify auth token generation and validation safety."""
        from auth import create_access_token, decode_access_token
        
        payload = {"sub": "test_user_id", "email": "test@dicty.ai"}
        token = create_access_token(payload)
        self.assertIsInstance(token, str)
        self.assertGreater(len(token), 20)

        decoded = decode_access_token(token)
        self.assertEqual(decoded.get("sub"), "test_user_id")
        self.assertEqual(decoded.get("email"), "test@dicty.ai")

    def test_jwt_tampering_strictly_rejected(self):
        """Ensure tampered or unsigned tokens cannot bypass signature verification."""
        from auth import decode_access_token
        from jose import jwt as raw_jwt
        
        # Token signed with an arbitrary attacker key
        fake_token = raw_jwt.encode({"sub": "admin", "email": "admin@dicty.ai"}, "wrong-secret-key", algorithm="HS256")
        decoded = decode_access_token(fake_token)
        self.assertIsNone(decoded, "Tampered JWT with invalid signature must NOT be decoded!")


if __name__ == "__main__":
    unittest.main(verbosity=2)
