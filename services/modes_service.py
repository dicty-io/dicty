"""Engine-owned dictation and meeting modes.

One document (``modes.json`` in the user data directory) is the single source of
truth for:

* the mode list (name, style, corrections, translation, custom instructions),
* global ``ai_location`` (local vs cloud when better),
* whether app rules are applied automatically,
* the per-app rules themselves.

The document is versioned. ``migrate_config`` imports a legacy client export
(``dicty_setup.json``/``config.json``) or a raw ``profiles`` array once, writes a
redacted backup and records every mapping it performed so the migration can be
audited.

Old fields stay readable for one release through ``_serialize_mode`` but are
never written back as the source of truth.
"""

from __future__ import annotations

import copy
import hashlib
import json
import os
import re
import threading
import uuid
from datetime import datetime, timezone
from typing import Any

import style_rules
from dicty_paths import get_user_data_dir

MODE_SCHEMA_VERSION = 2
MIGRATION_VERSION = 1

KINDS = ("dictation", "meeting")
AI_LOCATIONS = ("local", "cloud_when_better")

DEFAULT_AI_LOCATION = "local"
DEFAULT_AUTOMATIC_APP_RULES = True
DEFAULT_FIX_CORRECTIONS = True

DEFAULT_LOCAL_TEXT_MODEL = "qwen2.5-1.5b-instruct"
DEFAULT_LOCAL_TEXT_MODEL_MB = 980

_SECRET_KEY_RE = re.compile(r"(api[_-]?key|token|secret|password|credential)", re.IGNORECASE)

# Which built-in prompt belongs to which new style. Used when a legacy export
# contains an edited prompt.
PROMPT_STYLE_MAP = {
    "dictation_custom_system": "message",
    "dictation_message_system": "message",
    "dictation_email_system": "email",
    "dictation_note_system": "note",
    "dictation_meeting_system": "note",
    "dictation_book_system": "note",
}

# A prompt can only be attached to a mode when that mode actually uses the
# style. Book prose is special: only the active book mode should receive it.
_BOOK_PROMPT = "dictation_book_system"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _slugify(value: str | None, fallback: str | None = None) -> str:
    raw = str(value or "").strip()
    if not raw:
        return fallback or uuid.uuid4().hex[:8]
    if re.fullmatch(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}", raw):
        return raw
    slug = re.sub(r"[^a-z0-9]+", "-", raw.lower()).strip("-")
    return slug or fallback or uuid.uuid4().hex[:8]


def _unique(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        text = str(value).strip()
        if text and text not in seen:
            seen.add(text)
            out.append(text)
    return out


def _as_bool(value: Any, default: bool = False) -> bool:
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return bool(value)
    text = str(value).strip().lower()
    if text in ("1", "true", "yes", "on"):
        return True
    if text in ("0", "false", "no", "off", ""):
        return False
    return default


def _as_text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def _redact(value: Any, redacted: list[str], prefix: str = "") -> Any:
    """Copy JSON data while dropping credentials. Never mutates the input."""
    if isinstance(value, dict):
        out = {}
        for key, item in value.items():
            path = f"{prefix}.{key}" if prefix else str(key)
            if _SECRET_KEY_RE.search(str(key)):
                redacted.append(path)
                continue
            out[key] = _redact(item, redacted, path)
        return out
    if isinstance(value, list):
        return [_redact(item, redacted, f"{prefix}[{index}]") for index, item in enumerate(value)]
    if isinstance(value, bytes):
        return "<binary>"
    return value


def _prompt_defaults() -> dict[str, str]:
    try:
        import prompts
        return {
            "dictation_custom_system": prompts.get_dictation_custom_system_prompt_default(),
            "dictation_message_system": prompts.get_dictation_message_system_prompt_default(),
            "dictation_email_system": prompts.get_dictation_email_system_prompt_default(),
            "dictation_note_system": prompts.get_dictation_note_system_prompt_default(),
            "dictation_meeting_system": prompts.get_dictation_meeting_system_prompt_default(),
            "dictation_book_system": prompts.get_dictation_book_system_prompt_default(),
        }
    except Exception:
        return {}


def _prompt_overrides(config: dict[str, Any]) -> dict[str, str]:
    """Normalise both export prompt shapes: list of items or a plain dict."""
    raw = config.get("prompts")
    if isinstance(raw, dict):
        return {str(k): _as_text(v) for k, v in raw.items() if _as_text(v)}
    if isinstance(raw, list):
        out: dict[str, str] = {}
        for item in raw:
            if not isinstance(item, dict):
                continue
            key = item.get("key")
            value = item.get("active_value") or item.get("value") or item.get("default_value")
            if key and _as_text(value):
                out[str(key)] = _as_text(value)
        return out
    return {}


def _translation_target(source: dict[str, Any]) -> str | None:
    target = _as_text(source.get("targetLanguage") or source.get("target_language") or "none").lower()
    method = _as_text(source.get("translationMethod") or source.get("translation_method") or "none").lower()
    if _as_bool(source.get("translateToEnglish") or source.get("translate_to_english"), False):
        return "en"
    if method == "built_in":
        return "en"
    if method in ("cloud", "lm_studio", "llm"):
        if target not in ("", "none", "auto", "same"):
            return target
    return None


def _meeting_options(source: dict[str, Any], legacy_mode: str | None = None) -> dict[str, Any]:
    options = {
        "enable_diarization": _as_bool(source.get("enableDiarization") or source.get("enable_diarization"), False),
        "diarization_model": _as_text(source.get("diarizationModel") or source.get("diarization_model")),
        "speaker_separation": _as_text(source.get("speakerSeparation") or source.get("speaker_separation") or "you_others"),
        "speaker_you_label": _as_text(source.get("speakerYouLabel") or source.get("speaker_you_label") or "You"),
        "show_timestamps": _as_bool(source.get("meetingShowTimestamps") or source.get("meeting_show_timestamps"), False),
        "mute_microphone": _as_bool(source.get("muteMicrophone") or source.get("mute_microphone"), False),
        "apps": copy.deepcopy(source.get("targetApps") or source.get("apps") or []),
    }
    if legacy_mode:
        options["legacy_mode"] = legacy_mode
    return options


def _legacy_mode_name(source: dict[str, Any]) -> str:
    return _as_text(source.get("activeMode") or source.get("active_mode") or source.get("modeType") or "dictation")


def _kind_for(source: dict[str, Any]) -> str:
    return "meeting" if _legacy_mode_name(source) in ("meeting", "focused_meeting") else "dictation"


def _new_mode(
    mode_id: str,
    name: str,
    *,
    kind: str = "dictation",
    style: str = "clean",
    fix_corrections: bool = DEFAULT_FIX_CORRECTIONS,
    translate_to: str | None = None,
    custom_instructions: str | None = None,
    tags: list[str] | None = None,
    meeting: dict[str, Any] | None = None,
    icon: str = "mic.fill",
    description: str = "",
    is_default: bool = False,
) -> dict[str, Any]:
    return {
        "id": mode_id,
        "name": name,
        "kind": kind,
        "style": style,
        "fix_corrections": bool(fix_corrections),
        "translate_to": translate_to or None,
        "custom_instructions": custom_instructions or None,
        "tags": tags or [],
        "meeting": meeting or {},
        "icon": icon,
        "description": description,
        "is_default": bool(is_default),
        "speech_model": "",
        "language": "auto",
        "keep_model_in_memory": True,
        "legacy": {},
    }


def default_modes() -> list[dict[str, Any]]:
    """Defaults for a new install: Clean style, corrections on, local AI."""
    return [
        _new_mode(
            "general",
            "General Dictation",
            style="clean",
            tags=["dictation"],
            icon="mic.fill",
            description="Type what you say into any app.",
            is_default=True,
        ),
        _new_mode(
            "email",
            "Email",
            style="email",
            tags=["email"],
            icon="envelope.fill",
            description="Turn a rough thought into an email with a greeting and sign-off.",
        ),
        _new_mode(
            "notes",
            "Notes",
            style="note",
            tags=["notes"],
            icon="note.text",
            description="Shape a thought into markdown headings and lists.",
        ),
        _new_mode(
            "message",
            "Message",
            style="message",
            tags=["message"],
            icon="bubble.left.fill",
            description="Short and casual, like a chat message.",
        ),
        _new_mode(
            "code",
            "Code",
            style="code",
            tags=["code", "dev"],
            icon="terminal.fill",
            description="Keep identifiers exactly as you said them. No added capitals or periods.",
        ),
        _new_mode(
            "meeting",
            "Meeting",
            kind="meeting",
            style="note",
            tags=["meeting"],
            icon="person.2.fill",
            description="Record both sides of a call and get notes and action items.",
            meeting=_meeting_options({}, "meeting"),
        ),
        _new_mode(
            "focused-meeting",
            "Focused App Meeting",
            kind="meeting",
            style="note",
            tags=["meeting", "app"],
            icon="app.connected.to.app.below.fill",
            description="Record your microphone and one app at the same time.",
            meeting=_meeting_options({}, "focused_meeting"),
        ),
    ]


class ModesService:
    def __init__(self, data_dir: str | None = None):
        self.data_dir = data_dir or get_user_data_dir()
        self.path = os.path.join(self.data_dir, "modes.json")
        self._lock = threading.RLock()

    # ------------------------------------------------------------------ storage
    def _read_raw(self) -> dict[str, Any] | None:
        if not os.path.exists(self.path):
            return None
        try:
            with open(self.path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else None
        except Exception as exc:
            print(f"[!] Could not read modes.json: {exc}")
            return None

    def _write_raw(self, document: dict[str, Any]) -> None:
        os.makedirs(self.data_dir, exist_ok=True)
        tmp = f"{self.path}.tmp"
        with open(tmp, "w", encoding="utf-8") as handle:
            json.dump(document, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        os.replace(tmp, self.path)

    def _backup(self, name: str, payload: Any) -> str:
        os.makedirs(self.data_dir, exist_ok=True)
        path = os.path.join(self.data_dir, name)
        with open(path, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.write("\n")
        return path

    def _seed_locked(self) -> dict[str, Any]:
        document = {
            "schema_version": MODE_SCHEMA_VERSION,
            "migration_version": MIGRATION_VERSION,
            "ai_location": DEFAULT_AI_LOCATION,
            "automatic_app_rules": DEFAULT_AUTOMATIC_APP_RULES,
            "active_mode_id": "general",
            "app_rules": {"enabled": True, "rules": []},
            "modes": default_modes(),
            "migration": {
                "version": MIGRATION_VERSION,
                "source": "seed",
                "migrated_at": _now(),
                "config_hash": None,
                "mapping": [],
                "notes": ["Fresh install: Clean style, corrections on, AI on this Mac."],
            },
            "created_at": _now(),
            "updated_at": _now(),
        }
        self._write_raw(document)
        return document

    def _ensure_locked(self) -> dict[str, Any]:
        document = self._read_raw()
        if document is None:
            return self._seed_locked()
        if int(document.get("schema_version") or 1) < MODE_SCHEMA_VERSION:
            # Engine-side modes.json from an earlier build.
            self.migrate_config_locked(document, force=True, source="modes.json (schema 1)")
            return self._read_raw() or self._seed_locked()
        return document

    # ------------------------------------------------------------------ public
    def get_document(self) -> dict[str, Any]:
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
        document["modes"] = [self._serialize_mode(mode) for mode in document.get("modes", [])]
        return document

    def get_mode(self, mode_id: str) -> dict[str, Any]:
        with self._lock:
            document = self._ensure_locked()
            mode = next((m for m in document.get("modes", []) if m.get("id") == mode_id), None)
            if mode is None:
                raise KeyError(f"Mode not found: {mode_id}")
            return self._serialize_mode(copy.deepcopy(mode))

    def replace_modes(self, payload: Any) -> dict[str, Any]:
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
            if isinstance(payload, list):
                incoming = payload
            elif isinstance(payload, dict):
                incoming = payload.get("modes")
                if incoming is None:
                    raise ValueError("Expected a 'modes' list")
                if "ai_location" in payload:
                    document["ai_location"] = self._validate_ai_location(payload["ai_location"])
                if "automatic_app_rules" in payload:
                    document["automatic_app_rules"] = _as_bool(payload["automatic_app_rules"], True)
                if "active_mode_id" in payload:
                    document["active_mode_id"] = _as_text(payload["active_mode_id"])
            else:
                raise ValueError("Expected a list of modes or an object with 'modes'")
            modes = self._normalize_modes(incoming)
            document["modes"] = modes
            document["active_mode_id"] = self._validate_active_id(document.get("active_mode_id"), modes)
            document["updated_at"] = _now()
            self._write_raw(document)
        return self.get_document()

    def create_mode(self, payload: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("Mode must be an object")
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
            mode = self._normalize_mode(payload)
            if any(m.get("id") == mode["id"] for m in document.get("modes", [])):
                raise ValueError(f"A mode with id '{mode['id']}' already exists")
            document.setdefault("modes", []).append(mode)
            document["updated_at"] = _now()
            self._write_raw(document)
        return self.get_mode(mode["id"])

    def update_mode(self, mode_id: str, patch: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(patch, dict):
            raise ValueError("Patch must be an object")
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
            modes = document.get("modes", [])
            index = next((i for i, m in enumerate(modes) if m.get("id") == mode_id), None)
            if index is None:
                raise KeyError(f"Mode not found: {mode_id}")
            merged = copy.deepcopy(modes[index])
            merged.update(copy.deepcopy(patch))
            merged["id"] = mode_id  # ids are stable
            modes[index] = self._normalize_mode(merged)
            document["modes"] = modes
            document["updated_at"] = _now()
            self._write_raw(document)
        return self.get_mode(mode_id)

    def delete_mode(self, mode_id: str) -> dict[str, Any]:
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
            modes = document.get("modes", [])
            if len(modes) <= 1:
                raise ValueError("Keep at least one mode")
            remaining = [m for m in modes if m.get("id") != mode_id]
            if len(remaining) == len(modes):
                raise KeyError(f"Mode not found: {mode_id}")
            document["modes"] = remaining
            if document.get("active_mode_id") == mode_id:
                document["active_mode_id"] = remaining[0]["id"]
            document["updated_at"] = _now()
            self._write_raw(document)
        return self.get_document()

    def set_settings(self, patch: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(patch, dict):
            raise ValueError("Settings must be an object")
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
            if "ai_location" in patch:
                document["ai_location"] = self._validate_ai_location(patch["ai_location"])
            if "automatic_app_rules" in patch:
                document["automatic_app_rules"] = _as_bool(patch["automatic_app_rules"], True)
            if "active_mode_id" in patch:
                document["active_mode_id"] = self._validate_active_id(patch["active_mode_id"], document.get("modes", []))
            document["updated_at"] = _now()
            self._write_raw(document)
        return self.get_document()

    def get_app_rules(self) -> dict[str, Any]:
        with self._lock:
            document = self._ensure_locked()
        return copy.deepcopy(document.get("app_rules") or {"enabled": True, "rules": []})

    def replace_app_rules(self, payload: dict[str, Any]) -> dict[str, Any]:
        if not isinstance(payload, dict):
            raise ValueError("App rules must be an object")
        with self._lock:
            document = copy.deepcopy(self._ensure_locked())
            rules = payload.get("rules", payload)
            if isinstance(rules, list):
                rules = {"enabled": payload.get("enabled", True), "rules": rules}
            if not isinstance(rules, dict) or not isinstance(rules.get("rules", []), list):
                raise ValueError("Expected {'enabled': bool, 'rules': [...]}")
            document["app_rules"] = copy.deepcopy(rules)
            document["updated_at"] = _now()
            self._write_raw(document)
        return self.get_app_rules()

    # ------------------------------------------------------------- validation
    def _validate_ai_location(self, value: Any) -> str:
        location = _as_text(value).lower()
        if location not in AI_LOCATIONS:
            raise ValueError(f"ai_location must be one of {AI_LOCATIONS}")
        return location

    def _validate_active_id(self, value: Any, modes: list[dict[str, Any]]) -> str:
        candidate = _as_text(value)
        ids = [m.get("id") for m in modes]
        if candidate in ids:
            return candidate
        preferred = next((m["id"] for m in modes if m.get("is_default")), None)
        return preferred or (ids[0] if ids else "")

    def _normalize_modes(self, incoming: Any) -> list[dict[str, Any]]:
        if not isinstance(incoming, list) or not incoming:
            raise ValueError("At least one mode is required")
        modes = [self._normalize_mode(item) for item in incoming]
        ids = [m["id"] for m in modes]
        if len(set(ids)) != len(ids):
            raise ValueError("Mode ids must be unique")
        return modes

    def _normalize_mode(self, raw: Any) -> dict[str, Any]:
        if not isinstance(raw, dict):
            raise ValueError("Each mode must be an object")
        name = _as_text(raw.get("name")) or "Untitled mode"
        mode_id = _slugify(raw.get("id") or name)
        kind = _as_text(raw.get("kind") or _kind_for(raw)).lower()
        if kind not in KINDS:
            raise ValueError(f"Mode '{mode_id}': kind must be one of {KINDS}")
        style = _as_text(raw.get("style") or style_rules.legacy_to_style(raw.get("dictation_format_style")))
        if style not in style_rules.STYLES:
            raise ValueError(f"Mode '{mode_id}': style must be one of {style_rules.STYLES}")
        if "translate_to" in raw:
            translate_to = _as_text(raw.get("translate_to")).lower()
            if translate_to in ("", "none", "auto", "same", "null"):
                translate_to_value = None
            else:
                translate_to_value = translate_to
        else:
            # Old clients only sent target_language + translation_method.
            translate_to_value = _translation_target(raw)
        custom = raw.get("custom_instructions")
        if custom is None and raw.get("custom_prompt") is not None:
            custom = raw.get("custom_prompt")
        custom_value = _as_text(custom) or None
        tags = raw.get("tags")
        if isinstance(tags, str):
            tags = [part.strip() for part in tags.split(",")]
        if not isinstance(tags, list):
            tags = []
        meeting = raw.get("meeting")
        if not isinstance(meeting, dict):
            meeting = {}
        if kind == "meeting" and not meeting:
            meeting = _meeting_options(raw)
        legacy = raw.get("legacy")
        if not isinstance(legacy, dict):
            legacy = self._legacy_from_mode(raw)
        mode = {
            "id": mode_id,
            "name": name,
            "kind": kind,
            "style": style,
            "fix_corrections": _as_bool(
                raw.get("fix_corrections", raw.get("enable_self_correction")),
                DEFAULT_FIX_CORRECTIONS,
            ),
            "translate_to": translate_to_value,
            "custom_instructions": custom_value,
            "tags": _unique([str(t) for t in tags]),
            "meeting": copy.deepcopy(meeting) if kind == "meeting" else {},
            "icon": _as_text(raw.get("icon")) or ("person.2.fill" if kind == "meeting" else "mic.fill"),
            "description": _as_text(raw.get("description")),
            "is_default": _as_bool(raw.get("is_default"), False),
            "speech_model": _as_text(raw.get("speech_model") or raw.get("whisper_model") or raw.get("whisperModel")),
            "language": _as_text(raw.get("language") or "auto") or "auto",
            "keep_model_in_memory": _as_bool(raw.get("keep_model_in_memory"), True),
            "legacy": copy.deepcopy(legacy),
        }
        return mode

    def _legacy_from_mode(self, raw: dict[str, Any]) -> dict[str, Any]:
        legacy = {}
        for key in (
            "active_mode", "activeMode", "dictation_format_style", "dictationFormatStyle",
            "custom_prompt", "customPrompt", "enable_self_correction", "enableSelfCorrection",
            "translation_method", "translationMethod", "target_language", "targetLanguage",
            "self_correction_model", "selfCorrectionModel", "whisperModel", "llmModel",
            "llmProvider", "targetSystem", "obsidianPath",
        ):
            if key in raw and raw[key] is not None:
                legacy[key] = copy.deepcopy(raw[key])
        return legacy

    def _serialize_mode(self, mode: dict[str, Any]) -> dict[str, Any]:
        out = copy.deepcopy(mode)
        legacy = out.get("legacy") if isinstance(out.get("legacy"), dict) else {}
        out["active_mode"] = legacy.get("active_mode") or legacy.get("activeMode") or (
            "meeting" if out.get("kind") == "meeting" else "dictation"
        )
        out["dictation_format_style"] = (
            legacy.get("dictation_format_style")
            or legacy.get("dictationFormatStyle")
            or style_rules.style_to_legacy(out.get("style"))
        )
        out["custom_prompt"] = out.get("custom_instructions") or ""
        out["enable_self_correction"] = bool(out.get("fix_corrections"))
        out["translation_method"] = legacy.get("translation_method") or legacy.get("translationMethod") or (
            "none" if not out.get("translate_to") else "cloud"
        )
        out["target_language"] = out.get("translate_to") or "none"
        out["self_correction_model"] = legacy.get("self_correction_model") or legacy.get("selfCorrectionModel") or ""
        out["whisper_model"] = out.get("speech_model") or legacy.get("whisperModel") or ""
        return out

    # ------------------------------------------------------------- migration
    def migrate_config(self, config: Any, *, force: bool = False, source: str = "payload") -> dict[str, Any]:
        with self._lock:
            return self.migrate_config_locked(config, force=force, source=source)

    def migrate_config_locked(self, config: Any, *, force: bool = False, source: str = "payload") -> dict[str, Any]:
        if isinstance(config, dict) and "config" in config and not any(
            key in config for key in ("profiles", "prompts", "activeMode", "active_mode", "modes")
        ):
            config = config["config"]
        if isinstance(config, list):
            config = {"profiles": config}
        if not isinstance(config, dict):
            raise ValueError("Migration input must be an object or a list of profiles")

        config_hash = hashlib.sha256(
            json.dumps(config, sort_keys=True, default=str).encode("utf-8")
        ).hexdigest()

        existing = self._read_raw()
        if existing and int(existing.get("schema_version") or 1) >= MODE_SCHEMA_VERSION:
            same_hash = (existing.get("migration") or {}).get("config_hash") == config_hash
            if same_hash or not force:
                return {
                    "migrated": False,
                    "reason": "already_migrated",
                    "schema_version": MODE_SCHEMA_VERSION,
                    "config_hash": config_hash,
                    "mapping": (existing.get("migration") or {}).get("mapping", []),
                    "notes": (existing.get("migration") or {}).get("notes", []),
                }

        redacted_keys: list[str] = []
        safe_config = _redact(config, redacted_keys)
        backup_name = f"modes.backup.{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        backup_path = self._backup(backup_name, safe_config)
        pre_migration_path = None
        if existing:
            pre_migration_path = self._backup(
                f"modes.pre_migration.{datetime.now().strftime('%Y%m%d-%H%M%S')}.json",
                _redact(existing, []),
            )

        document, mapping, notes = self._build_document(safe_config, source=source, config_hash=config_hash)
        document["migration"]["backup_file"] = backup_path
        if pre_migration_path:
            document["migration"]["pre_migration_file"] = pre_migration_path
        document["migration"]["redacted_keys"] = redacted_keys
        self._write_raw(document)

        return {
            "migrated": True,
            "schema_version": MODE_SCHEMA_VERSION,
            "source": source,
            "backup": backup_path,
            "pre_migration": pre_migration_path,
            "config_hash": config_hash,
            "mode_count": len(document["modes"]),
            "mapping": mapping,
            "notes": notes,
            "redacted_keys": redacted_keys,
        }

    def _build_document(
        self,
        config: dict[str, Any],
        *,
        source: str,
        config_hash: str,
    ) -> tuple[dict[str, Any], list[dict[str, Any]], list[str]]:
        mapping: list[dict[str, Any]] = []
        notes: list[str] = []
        handled: set[str] = set()

        profiles = config.get("profiles")
        if isinstance(profiles, list) and profiles:
            modes = [self._mode_from_profile(profile, mapping) for profile in profiles if isinstance(profile, dict)]
            notes.append(f"Imported {len(modes)} mode profiles from the exported client profile list.")
            mapping.append({"setting": "profiles", "to": "modes", "detail": len(modes)})
            handled.add("profiles")
            active = next((m["id"] for m in modes if m.get("is_default")), modes[0]["id"])
        elif isinstance(config.get("modes"), list) and config.get("modes"):
            modes = [self._mode_from_profile(profile, mapping) for profile in config["modes"] if isinstance(profile, dict)]
            notes.append("Imported modes from an earlier engine modes file.")
            mapping.append({"setting": "modes", "to": "modes", "detail": len(modes)})
            handled.add("modes")
            active = self._validate_active_id(config.get("active_mode_id"), modes)
        else:
            modes, active = self._modes_from_global_config(config, mapping, notes)
            handled.update({
                "activeMode", "active_mode", "dictationFormatStyle", "dictation_format_style",
                "translationMethod", "translation_method", "targetLanguage", "target_language",
                "translateToEnglish", "translate_to_english", "enableSelfCorrection",
                "enable_self_correction", "selfCorrectionModel", "self_correction_model",
                "customPrompt", "custom_prompt", "llmModel", "llm_model", "whisperModel",
            })

        # Edited prompts become custom instructions on the modes that use them.
        if "prompts" in config:
            mapping.append({"setting": "prompts", "to": "edited prompts -> mode custom_instructions"})
        self._apply_prompts(config, modes, mapping, notes)
        handled.add("prompts")

        # Vocabulary is already owned by vocabulary.json; it is not a mode setting.
        if "vocabulary" in config:
            mapping.append({"setting": "vocabulary", "to": "engine vocabulary (unchanged)"})
            handled.add("vocabulary")

        # App rules: prefer the payload, then the existing engine file.
        app_rules = config.get("app_rules")
        if app_rules is None:
            app_rules = self._read_app_rules_file()
        if app_rules is not None:
            mapping.append({"setting": "app_rules", "to": "app_rules", "detail": len(app_rules.get("rules", [])) if isinstance(app_rules, dict) else None})
            handled.add("app_rules")

        # Anything else is preserved verbatim (credentials removed) so no setting
        # disappears during the migration.
        legacy_globals = {}
        for key, value in config.items():
            if key in handled or key in ("app", "version", "exported_at", "localStorageBackup"):
                if key in ("app", "version", "exported_at"):
                    legacy_globals[key] = copy.deepcopy(value)
                    mapping.append({"setting": key, "to": "legacy_globals (metadata)"})
                elif key == "localStorageBackup":
                    legacy_globals["localStorageBackup"] = copy.deepcopy(value)
                    mapping.append({"setting": "localStorageBackup", "to": "legacy_globals"})
                continue
            legacy_globals[key] = copy.deepcopy(value)
            mapping.append({"setting": key, "to": "legacy_globals"})
        if "localStorageBackup" in config and "localStorageBackup" not in legacy_globals:
            legacy_globals["localStorageBackup"] = copy.deepcopy(config["localStorageBackup"])
            mapping.append({"setting": "localStorageBackup", "to": "legacy_globals"})

        if not modes:
            modes = default_modes()
            notes.append("No profiles found in the export; seeded the built-in modes.")
        active = self._validate_active_id(active, modes)

        document = {
            "schema_version": MODE_SCHEMA_VERSION,
            "migration_version": MIGRATION_VERSION,
            "ai_location": self._validate_ai_location(config.get("ai_location") or DEFAULT_AI_LOCATION),
            "automatic_app_rules": _as_bool(
                config.get("automatic_app_rules"), DEFAULT_AUTOMATIC_APP_RULES
            ),
            "active_mode_id": active,
            "app_rules": copy.deepcopy(app_rules) if isinstance(app_rules, dict) else {"enabled": True, "rules": []},
            "modes": modes,
            "legacy_globals": legacy_globals,
            "migration": {
                "version": MIGRATION_VERSION,
                "source": source,
                "migrated_at": _now(),
                "config_hash": config_hash,
                "mapping": mapping,
                "notes": notes,
                "style_map": copy.deepcopy(style_rules.LEGACY_STYLE_MAP),
            },
            "created_at": _now(),
            "updated_at": _now(),
        }
        return document, mapping, notes

    def _modes_from_global_config(
        self,
        config: dict[str, Any],
        mapping: list[dict[str, Any]],
        notes: list[str],
    ) -> tuple[list[dict[str, Any]], str]:
        modes = default_modes()
        fix = _as_bool(
            config.get("enableSelfCorrection", config.get("enable_self_correction")),
            False,
        )
        for mode in modes:
            mode["fix_corrections"] = fix

        active_legacy = _legacy_mode_name(config)
        old_style = _as_text(config.get("dictationFormatStyle") or config.get("dictation_format_style") or "raw")
        style = style_rules.legacy_to_style(old_style, default="exact")
        mapping.append({
            "setting": "dictationFormatStyle" if "dictationFormatStyle" in config else "dictation_format_style",
            "from": old_style,
            "to": f"style={style}",
        })

        target = self._pick_active_mode(modes, active_legacy, old_style)
        if target is None:
            target = _new_mode(
                _slugify(active_legacy, "migrated"),
                "Librarian (Docs)" if active_legacy == "librarian" else "Migrated mode",
                kind="meeting" if active_legacy in ("meeting", "focused_meeting") else "dictation",
                style=style,
                tags=["librarian"] if active_legacy == "librarian" else [],
                icon="book.fill" if active_legacy == "librarian" else "mic.fill",
            )
            modes.append(target)

        target["style"] = style
        target["kind"] = "meeting" if active_legacy in ("meeting", "focused_meeting") else "dictation"
        if target["kind"] == "meeting":
            target["meeting"] = _meeting_options(config, active_legacy)
        if active_legacy == "librarian":
            target["tags"] = _unique(target.get("tags", []) + ["librarian"])
            target["legacy"]["active_mode"] = "librarian"
        mapping.append({
            "setting": "activeMode" if "activeMode" in config else "active_mode",
            "from": active_legacy,
            "to": f"active_mode_id={target['id']}",
        })

        # Translation is global in the old UI, so it lands on the active mode only.
        translate_to = _translation_target(config)
        for mode in modes:
            mode["translate_to"] = None
        if translate_to:
            target["translate_to"] = translate_to
            mapping.append({
                "setting": "translationMethod",
                "from": config.get("translationMethod") or config.get("translation_method") or "none",
                "to": f"{target['id']}.translate_to={translate_to}",
            })
            mapping.append({
                "setting": "targetLanguage",
                "from": config.get("targetLanguage") or config.get("target_language") or "none",
                "to": f"{target['id']}.translate_to={translate_to}",
            })
        else:
            mapping.append({
                "setting": "translationMethod",
                "from": "none",
                "to": "translate_to=null (all modes)",
            })
            mapping.append({
                "setting": "targetLanguage",
                "from": "none",
                "to": "translate_to=null (all modes)",
            })

        # Common per-mode settings in the export.
        for key, field in (
            ("llmModel", "llm_model"),
            ("whisperModel", "speech_model"),
            ("language", "language"),
        ):
            value = _as_text(config.get(key) or config.get(field))
            if value:
                if field == "llm_model":
                    target["legacy"]["llmModel"] = value
                else:
                    target[field] = value
                mapping.append({"setting": key, "to": f"{target['id']}.{field}"})
        if "keepModelInMemory" in config:
            target["keep_model_in_memory"] = _as_bool(config.get("keepModelInMemory"), True)
            mapping.append({"setting": "keepModelInMemory", "to": f"{target['id']}.keep_model_in_memory"})
        if "selfCorrectionModel" in config:
            target["legacy"]["selfCorrectionModel"] = _as_text(config.get("selfCorrectionModel"))
            mapping.append({"setting": "selfCorrectionModel", "to": f"{target['id']}.legacy.selfCorrectionModel"})
        if "enableSelfCorrection" in config or "enable_self_correction" in config:
            mapping.append({
                "setting": "enableSelfCorrection",
                "from": _as_bool(config.get("enableSelfCorrection", config.get("enable_self_correction")), False),
                "to": "fix_corrections on all modes",
            })
        if "translateToEnglish" in config or "translate_to_english" in config:
            mapping.append({
                "setting": "translateToEnglish",
                "from": _as_bool(config.get("translateToEnglish", config.get("translate_to_english")), False),
                "to": "translate_to='en'" if _as_bool(config.get("translateToEnglish", config.get("translate_to_english")), False) else "translate_to=null",
            })

        # Custom / book prompts need their own instructions to keep behaviour.
        custom_prompt = _as_text(config.get("customPrompt") or config.get("custom_prompt"))
        if custom_prompt:
            target["custom_instructions"] = custom_prompt
            mapping.append({"setting": "customPrompt", "to": f"{target['id']}.custom_instructions"})
        elif old_style == "custom":
            target["custom_instructions"] = _prompt_defaults().get("dictation_custom_system")
            notes.append("Custom style had no saved prompt; used the built-in custom prompt.")
            mapping.append({"setting": "customPrompt", "from": "empty", "to": f"{target['id']}.custom_instructions (built-in custom prompt)"})
        elif old_style == "book":
            target["custom_instructions"] = _prompt_defaults().get("dictation_book_system")
            notes.append("Book style mapped to Note and kept the built-in book prompt as custom instructions.")
            mapping.append({"setting": "customPrompt", "from": "empty", "to": f"{target['id']}.custom_instructions (built-in book prompt)"})
        elif "customPrompt" in config or "custom_prompt" in config:
            mapping.append({"setting": "customPrompt", "from": "empty", "to": "no custom instructions"})

        target["legacy"] = {
            **(target.get("legacy") or {}),
            "active_mode": active_legacy,
            "dictation_format_style": old_style,
            "enable_self_correction": fix,
            "translation_method": _as_text(config.get("translationMethod") or config.get("translation_method") or "none"),
            "target_language": _as_text(config.get("targetLanguage") or config.get("target_language") or "none"),
            "custom_prompt": custom_prompt,
        }
        notes.append(
            f"Active mode {active_legacy!r} mapped to {target['id']!r} "
            f"with style {style!r}."
        )
        return modes, target["id"]

    def _pick_active_mode(
        self,
        modes: list[dict[str, Any]],
        active_legacy: str,
        old_style: str,
    ) -> dict[str, Any] | None:
        if active_legacy == "meeting":
            return next((m for m in modes if m["id"] == "meeting"), None)
        if active_legacy == "focused_meeting":
            return next((m for m in modes if m["id"] == "focused-meeting"), None)
        if active_legacy == "librarian":
            return next((m for m in modes if m["id"] == "librarian"), None)
        # A dictation profile keeps its identity; style changes, mode does not.
        if old_style in ("email", "message", "note"):
            # Prefer the matching built-in so the mode's name describes its job,
            # but only when the user has not renamed the default.
            return next((m for m in modes if m.get("id") == "general"), None)
        return next((m for m in modes if m.get("id") == "general"), None)

    def _mode_from_profile(self, profile: dict[str, Any], mapping: list[dict[str, Any]]) -> dict[str, Any]:
        name = _as_text(profile.get("name")) or "Untitled mode"
        mode_id = _slugify(profile.get("id") or name)
        old_style = _as_text(profile.get("dictationFormatStyle") or profile.get("dictation_format_style") or "raw")
        style = style_rules.legacy_to_style(old_style, default="exact")
        kind = _kind_for(profile)
        legacy_mode = _legacy_mode_name(profile)
        custom = _as_text(profile.get("customPrompt") or profile.get("custom_prompt"))
        if not custom and old_style == "custom":
            custom = _prompt_defaults().get("dictation_custom_system") or ""
        if not custom and old_style == "book":
            custom = _prompt_defaults().get("dictation_book_system") or ""
        tags = profile.get("tags")
        if not isinstance(tags, list):
            tags = []
        if kind == "meeting" and legacy_mode:
            tags = _unique(tags + ["meeting"] + (["app"] if legacy_mode == "focused_meeting" else []))
        if legacy_mode == "librarian":
            tags = _unique(tags + ["librarian"])
        mode = _new_mode(
            mode_id,
            name,
            kind=kind,
            style=style,
            fix_corrections=_as_bool(profile.get("enableSelfCorrection") or profile.get("enable_self_correction"), False),
            translate_to=_translation_target(profile),
            custom_instructions=custom or None,
            tags=tags,
            meeting=_meeting_options(profile, legacy_mode) if kind == "meeting" else {},
            icon=_as_text(profile.get("icon")) or ("person.2.fill" if kind == "meeting" else "mic.fill"),
            description=_as_text(profile.get("description")),
            is_default=_as_bool(profile.get("isDefault") or profile.get("is_default"), False),
        )
        mode["speech_model"] = _as_text(profile.get("whisperModel") or profile.get("whisper_model"))
        mode["language"] = _as_text(profile.get("language") or "auto") or "auto"
        mode["keep_model_in_memory"] = _as_bool(profile.get("keepModelInMemory"), True)
        mode["legacy"] = {
            **_redact(profile, []),
            **(self._legacy_from_mode(profile)),
            "active_mode": legacy_mode,
            "dictation_format_style": old_style,
            "enable_self_correction": mode["fix_corrections"],
            "translation_method": _as_text(profile.get("translationMethod") or "none"),
            "target_language": _as_text(profile.get("targetLanguage") or "none"),
            "custom_prompt": custom,
        }
        mapping.append({
            "setting": f"profile:{name}",
            "from": legacy_mode,
            "to": f"mode:{mode_id}",
            "style": style,
            "fields": sorted(str(key) for key in profile.keys()),
        })
        return mode

    def _apply_prompts(
        self,
        config: dict[str, Any],
        modes: list[dict[str, Any]],
        mapping: list[dict[str, Any]],
        notes: list[str],
    ) -> None:
        defaults = _prompt_defaults()
        overrides = _prompt_overrides(config)
        for key, value in overrides.items():
            if key not in PROMPT_STYLE_MAP:
                continue
            default = defaults.get(key)
            if default is not None and value.strip() == default.strip():
                continue
            target_style = PROMPT_STYLE_MAP[key]
            if key == _BOOK_PROMPT:
                candidates = [
                    m for m in modes
                    if (m.get("legacy") or {}).get("dictation_format_style") == "book"
                ]
            elif key == "dictation_meeting_system":
                candidates = [m for m in modes if m.get("kind") == "meeting"]
            elif key == "dictation_note_system":
                candidates = [
                    m for m in modes
                    if m.get("kind") == "dictation" and m.get("style") == target_style
                ]
            else:
                candidates = [m for m in modes if m.get("style") == target_style]
            if not candidates:
                notes.append(f"Edited prompt {key} had no matching mode; kept it in custom_prompts.json.")
                continue
            applied = []
            for mode in candidates:
                if not mode.get("custom_instructions"):
                    mode["custom_instructions"] = value
                applied.append(mode["id"])
            mapping.append({
                "setting": f"prompt:{key}",
                "from": "edited prompt",
                "to": f"custom_instructions on {', '.join(applied)}",
            })

    def _read_app_rules_file(self) -> dict[str, Any] | None:
        path = os.path.join(self.data_dir, "app_rules.json")
        if not os.path.exists(path):
            return None
        try:
            with open(path, "r", encoding="utf-8") as handle:
                data = json.load(handle)
            return data if isinstance(data, dict) else None
        except Exception as exc:
            print(f"[!] Could not read app_rules.json: {exc}")
            return None

    # ---------------------------------------------------------- capabilities
    def get_capabilities(self) -> dict[str, Any]:
        document = self.get_document()
        ai_location = document.get("ai_location", DEFAULT_AI_LOCATION)
        correction_location = "local_rules" if ai_location == "local" else "cloud"
        local_models = self._downloaded_local_text_models()
        cloud = self._has_cloud_access()
        modes_out = []
        for mode in document.get("modes", []):
            needs_llm = self._mode_needs_llm(mode)
            entry = {
                "mode_id": mode["id"],
                "missing": None,
                "fix": None,
                "size_mb": None,
                "correction": correction_location,
            }
            if needs_llm:
                if ai_location == "local":
                    if not local_models:
                        entry.update({
                            "missing": "text_model",
                            "fix": f"download:{DEFAULT_LOCAL_TEXT_MODEL}",
                            "size_mb": DEFAULT_LOCAL_TEXT_MODEL_MB,
                        })
                elif not cloud:
                    entry.update({"missing": "cloud_access", "fix": "sign_in"})
            modes_out.append(entry)
        return {
            "ai_location": ai_location,
            "correction_location": correction_location,
            "local_text_models": local_models,
            "cloud_access": cloud,
            "modes": modes_out,
        }

    def resolve_for_request(
        self,
        mode_id: str | None = None,
        legacy_mode: str | None = None,
    ) -> dict[str, Any] | None:
        """Pick the mode that owns a request so the engine reads one place.

        ``mode_id`` wins. Otherwise the old ``active_mode`` value is matched to
        the mode that carries it, then to the built-in mode of the same kind.
        """
        document = self.get_document()
        modes = document.get("modes", [])
        mode = None
        if mode_id:
            mode = next((m for m in modes if m.get("id") == mode_id), None)
            if mode is None:
                # The client named a mode the store does not have. Do not guess:
                # let the caller fall back to the values the client sent.
                print(f"[!] Mode '{mode_id}' not found in modes.json; using request values.")
                return None
        elif legacy_mode:
            mode = self._find_legacy_mode(modes, legacy_mode)
        if mode is None:
            mode = next((m for m in modes if m.get("is_default")), next(iter(modes), None))
        if mode is None:
            return None
        legacy = mode.get("legacy") if isinstance(mode.get("legacy"), dict) else {}
        return {
            "mode_id": mode.get("id"),
            "name": mode.get("name"),
            "kind": mode.get("kind"),
            "style": mode.get("style"),
            "fix_corrections": bool(mode.get("fix_corrections")),
            "translate_to": mode.get("translate_to"),
            "ai_location": document.get("ai_location", DEFAULT_AI_LOCATION),
            "self_correction_model": legacy.get("self_correction_model") or legacy.get("selfCorrectionModel") or "",
        }

    def _find_legacy_mode(self, modes: list[dict[str, Any]], legacy_mode: str) -> dict[str, Any] | None:
        wanted = _as_text(legacy_mode).lower()
        for mode in modes:
            legacy = mode.get("legacy") if isinstance(mode.get("legacy"), dict) else {}
            if legacy.get("active_mode") == wanted:
                return mode
        if wanted in ("meeting", "focused_meeting"):
            for mode in modes:
                if mode.get("kind") != "meeting":
                    continue
                is_app = "app" in (mode.get("tags") or [])
                if wanted == "focused_meeting" and is_app:
                    return mode
                if wanted == "meeting" and not is_app:
                    return mode
            return next((m for m in modes if m.get("kind") == "meeting"), None)
        return next((m for m in modes if m.get("is_default")), next(iter(modes), None))

    def download_target_for_mode(self, mode_id: str) -> dict[str, Any] | None:
        """Which model, if any, a mode is waiting for. ``None`` means ready."""
        capabilities = self.get_capabilities()
        entry = next((e for e in capabilities["modes"] if e["mode_id"] == mode_id), None)
        if not entry or not entry.get("missing"):
            return None
        fix = entry.get("fix") or ""
        if not fix.startswith("download:"):
            return None
        return {
            "mode_id": mode_id,
            "model_id": fix.split(":", 1)[1],
            "size_mb": entry.get("size_mb"),
        }

    def _mode_needs_llm(self, mode: dict[str, Any]) -> bool:
        style = mode.get("style")
        if style_rules.STYLE_NEEDS_LLM.get(style, False):
            return True
        if style == "message" and mode.get("custom_instructions"):
            return True
        if mode.get("translate_to"):
            return True
        return False

    def _downloaded_local_text_models(self) -> list[str]:
        try:
            import model_manager
            manager = model_manager.ModelManager()
            out = []
            for model in manager.get_available_models():
                if model.get("is_cloud"):
                    continue
                if model.get("category") != "text":
                    continue
                if manager.is_model_downloaded(model.get("id", "")):
                    out.append(model.get("id", ""))
            return [m for m in out if m]
        except Exception as exc:
            print(f"[!] Could not inspect local text models: {exc}")
            return []

    def _has_cloud_access(self) -> bool:
        try:
            if os.getenv("OPENROUTER_API_KEY") or os.getenv("OPENAI_API_KEY"):
                return True
        except Exception:
            pass
        try:
            import auth
            if auth.SecureAuthManager.get_jwt_token():
                return True
        except Exception:
            pass
        try:
            import transcribe_service
            if transcribe_service.stt_key_status().get("openrouter"):
                return True
        except Exception:
            pass
        return False


modes_service = ModesService()
