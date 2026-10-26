import os
import sys
import json
import uuid
import platform
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional, List
from abc import ABC, abstractmethod

logger = logging.getLogger("dicty.telemetry")

class TelemetrySink(ABC):
    """Abstract base class for all telemetry exporters/sinks."""
    @abstractmethod
    def send(self, payload: Dict[str, Any]) -> None:
        pass


class ConsoleTelemetrySink(TelemetrySink):
    """Default Sink: Formats OpenTelemetry-compliant structured JSON logs."""
    def send(self, payload: Dict[str, Any]) -> None:
        event_name = payload.get("event", "unknown")
        properties = payload.get("properties", {})
        props_str = " ".join([f"{k}={repr(v)}" for k, v in properties.items()])
        try:
            print(f"[Telemetry] [STATS] {event_name} | {props_str}")
        except Exception:
            pass


class FileTelemetrySink(TelemetrySink):
    """Persists events locally as Newline-Delimited JSON (NDJSON) for easy analysis."""
    def __init__(self, filepath: str):
        self.filepath = filepath

    def send(self, payload: Dict[str, Any]) -> None:
        try:
            with open(self.filepath, "a", encoding="utf-8") as f:
                f.write(json.dumps(payload, ensure_ascii=False) + "\n")
        except Exception as e:
            logger.warning(f"Failed to append event to {self.filepath}: {e}")


# Fields that may identify a person or their activity; never recorded in telemetry.
_REDACTED_PROPS = {
    "user_id", "email", "target_app_name", "target_app_bundle_id",
    "text", "transcript", "audio", "title", "traits", "profile_name"
}


class ConsoleTelemetrySink(TelemetrySink):
    """Formats OpenTelemetry-compliant structured logs when DICTY_DEBUG=1."""
    def send(self, payload: Dict[str, Any]) -> None:
        if os.getenv("DICTY_DEBUG") != "1":
            return
        event_name = payload.get("event", "unknown")
        properties = payload.get("properties", {})
        props_str = " ".join([f"{k}={repr(v)}" for k, v in properties.items()])
        try:
            print(f"[Telemetry] [STATS] {event_name} | {props_str}")
        except Exception:
            pass


class FileTelemetrySink(TelemetrySink):
    """Persists events locally as Newline-Delimited JSON (NDJSON) for optional diagnostics export."""
    def __init__(self, filepath: str):
        self.filepath = filepath

    def send(self, payload: Dict[str, Any]) -> None:
        try:
            with open(self.filepath, "a", encoding="utf-8") as f:
                f.write(json.dumps(payload, ensure_ascii=False) + "\n")
        except Exception as e:
            logger.warning(f"Failed to append event to {self.filepath}: {e}")


class PostHogTelemetrySink(TelemetrySink):
    """Dispatches anonymous aggregate metrics asynchronously to PostHog without blocking audio/STT."""
    def __init__(self, api_key: str, host: str = "https://us.i.posthog.com"):
        self.api_key = api_key
        self.host = host.rstrip("/")

    def send(self, payload: Dict[str, Any]) -> None:
        def _post():
            try:
                import urllib.request
                ph_payload = {
                    "api_key": self.api_key,
                    "event": payload.get("event"),
                    "properties": {
                        # Anonymous install ID only: no account ID, email, or user info is ever sent
                        "distinct_id": payload.get("distinct_id"),
                        "$process_person_profile": False,
                        **(payload.get("context") or {}),
                        **(payload.get("properties") or {})
                    },
                    "timestamp": payload.get("timestamp")
                }
                data = json.dumps(ph_payload).encode("utf-8")
                req = urllib.request.Request(
                    f"{self.host}/capture/",
                    data=data,
                    headers={"Content-Type": "application/json", "User-Agent": "Dicty-Engine/1.0.8"}
                )
                with urllib.request.urlopen(req, timeout=3.0) as resp:
                    pass
            except Exception:
                pass

        import threading
        threading.Thread(target=_post, daemon=True).start()


class TelemetryService:
    """
    Central Cross-Platform Telemetry Hub for Dicty.
    
    Privacy Philosophy:
    - Strictly OPT-IN (Disabled by default).
    - Zero telemetry events recorded, persisted, or sent unless explicitly enabled by user.
    - Zero PII: never records transcripts, audio, user email, or frontmost app names.
    - Anonymized installation ID (UUIDv4) only.
    """
    _instance: Optional['TelemetryService'] = None

    def __init__(self):
        from dicty_paths import get_user_data_dir
        self.config_dir = get_user_data_dir()
        os.makedirs(self.config_dir, exist_ok=True)
        self.id_file = os.path.join(self.config_dir, "telemetry_id")
        self.jsonl_file = os.path.join(self.config_dir, "telemetry.jsonl")
        self.distinct_id = self._load_or_create_distinct_id()
        self.sinks: List[TelemetrySink] = [
            ConsoleTelemetrySink(),
            FileTelemetrySink(self.jsonl_file)
        ]
        
        # Remote analytics endpoint (PostHog)
        posthog_key = os.getenv("POSTHOG_API_KEY") or os.getenv("NEXT_PUBLIC_POSTHOG_KEY")
        posthog_host = os.getenv("POSTHOG_HOST") or os.getenv("NEXT_PUBLIC_POSTHOG_HOST") or "https://us.i.posthog.com"
        
        if not posthog_key:
            from dicty_paths import PROJECT_ROOT
            bundle_dir = getattr(sys, '_MEIPASS', PROJECT_ROOT)
            bundled_config_path = os.path.join(bundle_dir, "telemetry_config.json")
            if os.path.exists(bundled_config_path):
                try:
                    with open(bundled_config_path, "r", encoding="utf-8") as f:
                        cfg = json.load(f)
                        posthog_key = cfg.get("posthog_api_key")
                        posthog_host = cfg.get("posthog_host") or posthog_host
                except Exception:
                    pass

        self.remote_sink: Optional[TelemetrySink] = PostHogTelemetrySink(posthog_key, posthog_host) if posthog_key else None
        self.remote_enabled = self._load_opt_in()
        if self.remote_sink and self.is_enabled():
            print(f"[*] Anonymous usage analytics enabled by user (Host: {posthog_host})")
            
        self.common_context = self._build_system_context()

    @staticmethod
    def _settings_file() -> str:
        from model_manager import SETTINGS_FILE
        return SETTINGS_FILE

    def _load_opt_in(self) -> bool:
        env_val = os.getenv("DICTY_TELEMETRY", "").lower()
        if env_val in ("0", "false", "off", "no"):
            return False
        if env_val in ("1", "true", "on", "yes"):
            return True
        try:
            with open(self._settings_file(), "r", encoding="utf-8") as f:
                return bool(json.load(f).get("share_anonymous_usage", False))
        except Exception:
            return False

    def is_enabled(self) -> bool:
        """Returns True only if telemetry is explicitly opted in."""
        env_val = os.getenv("DICTY_TELEMETRY", "").lower()
        if env_val in ("0", "false", "off", "no"):
            return False
        if env_val in ("1", "true", "on", "yes"):
            return True
        return bool(self.remote_enabled)

    def set_remote_enabled(self, enabled: bool) -> None:
        """Persists the user's opt-in choice in local settings."""
        self.remote_enabled = bool(enabled)
        path = self._settings_file()
        try:
            cfg = {}
            if os.path.exists(path):
                with open(path, "r", encoding="utf-8") as f:
                    cfg = json.load(f)
            cfg["share_anonymous_usage"] = self.remote_enabled
            with open(path, "w", encoding="utf-8") as f:
                json.dump(cfg, f, indent=2)
        except Exception as e:
            logger.warning(f"Failed to persist telemetry preference: {e}")

    def clear_local_data(self) -> None:
        """Purges locally stored telemetry NDJSON log upon user request."""
        try:
            if os.path.exists(self.jsonl_file):
                os.remove(self.jsonl_file)
        except Exception as e:
            logger.warning(f"Failed to remove telemetry log: {e}")

    @classmethod
    def shared(cls) -> 'TelemetryService':
        if cls._instance is None:
            cls._instance = TelemetryService()
        return cls._instance

    def _load_or_create_distinct_id(self) -> str:
        try:
            if os.path.exists(self.id_file):
                with open(self.id_file, "r", encoding="utf-8") as f:
                    stored_id = f.read().strip()
                    if stored_id:
                        return stored_id
            new_id = str(uuid.uuid4())
            with open(self.id_file, "w", encoding="utf-8") as f:
                f.write(new_id)
            return new_id
        except Exception as e:
            logger.warning(f"Failed to persist telemetry ID: {e}")
            return str(uuid.uuid4())

    def _build_system_context(self) -> Dict[str, Any]:
        """Gathers OpenTelemetry-compliant host and runtime metadata."""
        return {
            "os.name": platform.system(),
            "os.version": platform.release(),
            "host.arch": platform.machine(),
            "host.cpu_count": os.cpu_count() or 1,
            "runtime.python_version": platform.python_version(),
            "app.name": "Dicty",
            "app.version": "1.0.8"
        }

    def add_sink(self, sink: TelemetrySink) -> None:
        self.sinks.append(sink)

    def identify(self, user_id: str, traits: Optional[Dict[str, Any]] = None) -> None:
        """No-op: Dicty enforces zero-knowledge telemetry and never links personal emails or IDs."""
        pass

    def reset_identity(self) -> None:
        """No-op: Dicty does not track user identities."""
        pass

    def track(self, event_name: str, properties: Optional[Dict[str, Any]] = None) -> None:
        """
        Tracks an event only when telemetry is explicitly enabled by the user.
        All properties are sanitized against the redaction list to guarantee zero PII leakage.
        """
        if not self.is_enabled():
            return

        props = properties or {}
        # Strictly sanitize and strip sensitive or personal fields
        clean_props = {
            k: v for k, v in props.items()
            if k not in _REDACTED_PROPS and not k.startswith("user_")
        }

        payload = {
            "event": event_name,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "distinct_id": self.distinct_id,
            "properties": clean_props,
            "context": self.common_context
        }

        sinks = list(self.sinks)
        if self.remote_sink and self.remote_enabled:
            sinks.append(self.remote_sink)
        for sink in sinks:
            try:
                sink.send(payload)
            except Exception as e:
                logger.error(f"Telemetry sink {sink.__class__.__name__} failed: {e}")

# Global convenient accessor
telemetry = TelemetryService.shared()

