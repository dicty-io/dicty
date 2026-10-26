import os
import json
import tempfile
import unittest
from unittest.mock import patch, MagicMock

import dicty_paths
from services.telemetry_service import TelemetryService, TelemetrySink, _REDACTED_PROPS


class DummySink(TelemetrySink):
    def __init__(self):
        self.events = []

    def send(self, payload):
        self.events.append(payload)


class TestTelemetryService(unittest.TestCase):
    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.settings_file = os.path.join(self.test_dir, "settings.json")
        self.id_file = os.path.join(self.test_dir, "telemetry_id")
        self.jsonl_file = os.path.join(self.test_dir, "telemetry.jsonl")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _create_service(self):
        with patch("dicty_paths.get_user_data_dir", return_value=self.test_dir), \
             patch.object(TelemetryService, "_settings_file", return_value=self.settings_file):
            svc = TelemetryService()
            svc.sinks = []
            return svc

    def test_default_is_disabled(self):
        with patch.dict(os.environ, {}, clear=True):
            svc = self._create_service()
            self.assertFalse(svc.is_enabled())

    def test_env_var_override_disable(self):
        with patch.dict(os.environ, {"DICTY_TELEMETRY": "0"}):
            svc = self._create_service()
            svc.remote_enabled = True
            self.assertFalse(svc.is_enabled())

    def test_env_var_override_enable(self):
        with patch.dict(os.environ, {"DICTY_TELEMETRY": "1"}):
            svc = self._create_service()
            svc.remote_enabled = False
            self.assertTrue(svc.is_enabled())

    def test_track_noop_when_disabled(self):
        with patch.dict(os.environ, {}, clear=True):
            svc = self._create_service()
            dummy = DummySink()
            svc.add_sink(dummy)
            
            svc.track("test_event", {"foo": "bar"})
            self.assertEqual(len(dummy.events), 0)

    def test_track_redacts_pii_when_enabled(self):
        with patch.dict(os.environ, {"DICTY_TELEMETRY": "1"}):
            svc = self._create_service()
            dummy = DummySink()
            svc.add_sink(dummy)

            svc.track("text_injected", {
                "target_app_name": "Antigravity IDE",
                "target_app_bundle_id": "com.google.antigravity-ide",
                "email": "user@example.com",
                "user_id": "12345",
                "transcript": "Secret text spoken here",
                "is_trusted_accessibility": True,
                "latency_ms": 120
            })

            self.assertEqual(len(dummy.events), 1)
            payload = dummy.events[0]
            props = payload["properties"]

            # Verify non-sensitive operational properties remain
            self.assertEqual(props.get("is_trusted_accessibility"), True)
            self.assertEqual(props.get("latency_ms"), 120)

            # Verify all sensitive properties are completely redacted
            for sensitive_key in _REDACTED_PROPS:
                self.assertNotIn(sensitive_key, props)
            self.assertNotIn("user_id", payload)

    def test_identify_is_noop(self):
        svc = self._create_service()
        svc.identify("sensitive@domain.com")
        # Ensure no user traits or user identity persisted
        self.assertFalse(hasattr(svc, "user_id") and svc.user_id is not None)

    def test_clear_local_data(self):
        svc = self._create_service()
        with open(svc.jsonl_file, "w") as f:
            f.write('{"event": "dummy"}\n')
        self.assertTrue(os.path.exists(svc.jsonl_file))
        
        svc.clear_local_data()
        self.assertFalse(os.path.exists(svc.jsonl_file))


if __name__ == "__main__":
    unittest.main()
