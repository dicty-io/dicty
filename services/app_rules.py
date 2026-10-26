"""Per-app dictation modes management, persistence, and resolution engine.

Resolves formatting and dictation modes deterministically (< 1 ms, no LLM)
based on the active application or website domain, honoring user rules,
built-in defaults, and manual/recording overrides.
"""

import copy
import fnmatch
import json
import logging
import os
import threading
import time
import uuid
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

import dicty_paths
from app_rules_defaults import (
    BUILTIN_RULES,
    DEFAULT_ENABLED,
    DEFAULT_OVERRIDE_SCOPE,
    MEETING_MODES,
)

logger = logging.getLogger("dicty.app_rules")

SCHEMA_VERSION = 1


def _normalize_identifier(val: Optional[str]) -> str:
    """Lowercase and strip whitespace for case-insensitive matching."""
    return (val or "").strip().lower()


def _matches_rule(rule: Dict[str, Any], app_id: str, domain: str) -> bool:
    """Check whether a single rule matches the given app_id or domain."""
    match = rule.get("match", {})
    match_type = match.get("type", "app")
    if match_type in ("bundle_id", "process_name", "exe"):
        match_type = "app"
    match_val = _normalize_identifier(match.get("value"))

    if match_type == "domain":
        if not domain or not match_val:
            return False
        norm_domain = _normalize_identifier(domain)
        if match_val.startswith("*."):
            suffix = match_val[2:]
            return norm_domain == suffix or norm_domain.endswith("." + suffix)
        return norm_domain == match_val

    if match_type == "app":
        if not app_id or not match_val:
            return False
        norm_app = _normalize_identifier(app_id)
        if norm_app == match_val:
            return True
        aliases = [_normalize_identifier(a) for a in match.get("aliases", []) if a]
        if norm_app in aliases:
            return True
        # Special case: generic JetBrains prefix for JetBrains IDEs if rule matches bundle ID prefix
        if match_val.startswith("com.jetbrains.") and norm_app.startswith("com.jetbrains."):
            return True
        return False

    return False


def is_valid_rule_mode(
    mode: Optional[str],
    meeting_modes: Optional[Any] = None,
    available_modes: Optional[Any] = None,
) -> bool:
    """Validate that mode is not empty, not a meeting mode, and in available_modes if provided."""
    if not mode or not isinstance(mode, str):
        return False
    clean = mode.strip()
    if not clean:
        return False
    disallowed = set(meeting_modes) if meeting_modes is not None else MEETING_MODES
    if clean in disallowed:
        return False
    if available_modes is not None and clean not in set(available_modes):
        return False
    return True


class AppRulesManager:
    """Manages app-specific dictation rules, atomic persistence, and mode resolution."""

    def __init__(self, data_dir: Optional[str] = None):
        self._data_dir = data_dir
        self.lock = threading.RLock()
        self._cache: Optional[Dict[str, Any]] = None
        self._mtime: float = -1.0
        self._effective_cache: Optional[List[Dict[str, Any]]] = None

    @property
    def file_path(self) -> str:
        base_dir = self._data_dir if self._data_dir is not None else dicty_paths.get_user_data_dir()
        return os.path.join(base_dir, "app_rules.json")

    def _default_data(self) -> Dict[str, Any]:
        return {
            "version": SCHEMA_VERSION,
            "enabled": DEFAULT_ENABLED,
            "override_scope": DEFAULT_OVERRIDE_SCOPE,
            "rules": [],
            "suggestions_meta": {},
        }

    def _read_data(self) -> Dict[str, Any]:
        """Read data from disk with caching and graceful corruption recovery."""
        path = self.file_path
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            return self._default_data()

        if self._cache is not None and mtime == self._mtime:
            return copy.deepcopy(self._cache)

        try:
            with open(path, "r", encoding="utf-8") as f:
                data = json.load(f)

            if not isinstance(data, dict):
                raise ValueError("app_rules.json root must be a JSON object")

            # Schema migration if needed
            if data.get("version", 0) < SCHEMA_VERSION:
                data["version"] = SCHEMA_VERSION
                if "enabled" not in data:
                    data["enabled"] = DEFAULT_ENABLED
                if "override_scope" not in data:
                    data["override_scope"] = DEFAULT_OVERRIDE_SCOPE
                if "rules" not in data or not isinstance(data["rules"], list):
                    data["rules"] = []

            if "suggestions_meta" not in data or not isinstance(data["suggestions_meta"], dict):
                data["suggestions_meta"] = {}

            self._cache = data
            self._mtime = mtime
            self._effective_cache = None
            return copy.deepcopy(data)
        except Exception as e:
            logger.error("Failed to read app_rules.json (corrupt or invalid); falling back to defaults: %s", e)
            return self._default_data()

    def _write_data(self, data: Dict[str, Any]) -> None:
        """Atomically persist data to disk using temporary file replacement."""
        path = self.file_path
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        tmp_path = f"{path}.tmp.{os.getpid()}"
        try:
            with open(tmp_path, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2, ensure_ascii=False)
                f.flush()
                os.fsync(f.fileno())
            os.replace(tmp_path, path)
            self._cache = data
            self._mtime = os.path.getmtime(path)
            self._effective_cache = None
        except Exception as e:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass
            logger.error("Failed to write app_rules.json: %s", e)
            raise

    # -------------------------------------------------------------------------
    # Settings Management
    # -------------------------------------------------------------------------

    def get_settings(self) -> Dict[str, Any]:
        """Retrieve current global settings for app rules."""
        with self.lock:
            data = self._read_data()
            return {
                "enabled": bool(data.get("enabled", DEFAULT_ENABLED)),
                "override_scope": str(data.get("override_scope", DEFAULT_OVERRIDE_SCOPE)),
            }

    def update_settings(
        self,
        enabled: Optional[bool] = None,
        override_scope: Optional[str] = None,
    ) -> Dict[str, Any]:
        """Update global settings."""
        if override_scope is not None and override_scope not in ("recording", "manual"):
            raise ValueError("override_scope must be either 'recording' or 'manual'")

        with self.lock:
            data = self._read_data()
            if enabled is not None:
                data["enabled"] = bool(enabled)
            if override_scope is not None:
                data["override_scope"] = str(override_scope)
            self._write_data(data)
            return {
                "enabled": data["enabled"],
                "override_scope": data["override_scope"],
            }

    # -------------------------------------------------------------------------
    # Effective Rules & Merging
    # -------------------------------------------------------------------------

    def effective_rules(self) -> List[Dict[str, Any]]:
        """Return all active rules: built-ins with overrides applied, followed by user rules.

        Each rule is annotated with:
          source: 'builtin' | 'builtin_override' | 'user'
        """
        with self.lock:
            if self._effective_cache is not None:
                return copy.deepcopy(self._effective_cache)

            data = self._read_data()
            stored_rules = data.get("rules", [])

            # Index stored builtin overrides and user rules
            builtin_overrides: Dict[str, Dict[str, Any]] = {}
            user_rules: List[Dict[str, Any]] = []

            for r in stored_rules:
                source = r.get("source", "user")
                r_id = r.get("id", "")
                if source == "builtin_override" or r_id.startswith("builtin."):
                    builtin_overrides[r_id] = r
                else:
                    item = copy.deepcopy(r)
                    item["source"] = "user"
                    item["is_default"] = False
                    item["overridden"] = False
                    user_rules.append(item)

            # Build effective built-in rules
            merged_builtins: List[Dict[str, Any]] = []
            for b in BUILTIN_RULES:
                rule = copy.deepcopy(b)
                b_id = rule["id"]
                if b_id in builtin_overrides:
                    ov = builtin_overrides[b_id]
                    if ov.get("mode_id") is not None:
                        rule["mode_id"] = ov["mode_id"]
                    if "enabled" in ov and ov["enabled"] is not None:
                        rule["enabled"] = bool(ov["enabled"])
                    if "suppress_suggestion" in ov:
                        rule["suppress_suggestion"] = bool(ov["suppress_suggestion"])
                    rule["source"] = "builtin_override"
                    rule["is_default"] = True
                    rule["overridden"] = True
                else:
                    rule["source"] = "builtin"
                    rule["is_default"] = True
                    rule["overridden"] = False
                merged_builtins.append(rule)

            # Order: user rules take precedence over built-ins
            combined = user_rules + merged_builtins
            self._effective_cache = combined
            return copy.deepcopy(combined)

    # -------------------------------------------------------------------------
    # Rule Mutations
    # -------------------------------------------------------------------------

    def add_rule(
        self,
        match: Dict[str, Any],
        mode_id: str,
        display_name: str = "",
        enabled: bool = True,
    ) -> Dict[str, Any]:
        """Add a custom user rule."""
        if not isinstance(match, dict):
            raise ValueError("match must be an object with 'type' and 'value'")
        raw_type = (match.get("type") or "").strip().lower()
        if raw_type in ("app", "bundle_id", "process_name", "exe"):
            match_type = "app"
        elif raw_type in ("domain", "url", "web"):
            match_type = "domain"
        else:
            raise ValueError(f"match.type must be 'app' or 'domain' (got '{match.get('type')}')")

        match_val = (match.get("value") or "").strip()
        if not match_val:
            raise ValueError("match.value must not be empty")

        clean_mode = (mode_id or "").strip()
        if not clean_mode:
            raise ValueError("mode_id must not be empty")
        if clean_mode in MEETING_MODES:
            raise ValueError(f"Meeting modes ({', '.join(sorted(MEETING_MODES))}) cannot be targeted by app rules")

        rule_id = str(uuid.uuid4())
        new_rule = {
            "id": rule_id,
            "match": {
                "type": match_type,
                "value": match_val.lower() if match_type == "app" else match_val,
            },
            "display_name": (display_name or "").strip() or match_val,
            "mode_id": clean_mode,
            "enabled": bool(enabled),
            "source": "user",
            "is_default": False,
            "overridden": False,
        }

        with self.lock:
            data = self._read_data()
            rules = data.get("rules", [])
            rules.append(new_rule)
            data["rules"] = rules
            self._write_data(data)

        return new_rule

    def update_rule(
        self,
        rule_id: str,
        mode_id: Optional[str] = None,
        enabled: Optional[bool] = None,
        display_name: Optional[str] = None,
        suppress_suggestion: Optional[bool] = None,
    ) -> Optional[Dict[str, Any]]:
        """Update an existing user rule or apply an override to a built-in rule."""
        clean_mode = mode_id.strip() if mode_id is not None else None
        if clean_mode is not None:
            if not clean_mode:
                raise ValueError("mode_id cannot be empty")
            if clean_mode in MEETING_MODES:
                raise ValueError(f"Meeting modes ({', '.join(sorted(MEETING_MODES))}) cannot be targeted by app rules")

        with self.lock:
            data = self._read_data()
            rules = data.get("rules", [])

            # Check if this rule is a built-in
            is_builtin = rule_id.startswith("builtin.") or any(b["id"] == rule_id for b in BUILTIN_RULES)

            if is_builtin:
                builtin_def = next((b for b in BUILTIN_RULES if b["id"] == rule_id), None)
                if not builtin_def:
                    return None

                existing_ov = next((r for r in rules if r.get("id") == rule_id), None)
                if existing_ov:
                    if clean_mode is not None:
                        existing_ov["mode_id"] = clean_mode
                    if enabled is not None:
                        existing_ov["enabled"] = bool(enabled)
                    if suppress_suggestion is not None:
                        existing_ov["suppress_suggestion"] = bool(suppress_suggestion)
                    existing_ov["source"] = "builtin_override"
                else:
                    new_ov = {
                        "id": rule_id,
                        "match": copy.deepcopy(builtin_def["match"]),
                        "display_name": builtin_def.get("display_name", ""),
                        "mode_id": clean_mode if clean_mode is not None else builtin_def.get("mode_id"),
                        "enabled": bool(enabled) if enabled is not None else builtin_def.get("enabled", True),
                        "source": "builtin_override",
                    }
                    if suppress_suggestion is not None:
                        new_ov["suppress_suggestion"] = bool(suppress_suggestion)
                    rules.append(new_ov)

                data["rules"] = rules
                self._write_data(data)
                # Return the effective updated rule
                eff = self.effective_rules()
                return next((r for r in eff if r["id"] == rule_id), None)

            # Otherwise, update user rule
            target = next((r for r in rules if r.get("id") == rule_id), None)
            if not target:
                return None

            if clean_mode is not None:
                target["mode_id"] = clean_mode
            if enabled is not None:
                target["enabled"] = bool(enabled)
            if display_name is not None:
                target["display_name"] = display_name.strip()
            if suppress_suggestion is not None:
                target["suppress_suggestion"] = bool(suppress_suggestion)

            data["rules"] = rules
            self._write_data(data)
            res = copy.deepcopy(target)
            res["is_default"] = False
            res["overridden"] = False
            return res

    def delete_rule(self, rule_id: str) -> bool:
        """Remove a user rule, or reset a built-in rule override back to default."""
        with self.lock:
            data = self._read_data()
            rules = data.get("rules", [])
            initial_count = len(rules)

            is_builtin = rule_id.startswith("builtin.") or any(b["id"] == rule_id for b in BUILTIN_RULES)

            if is_builtin:
                # Removing the override resets the builtin to defaults
                rules = [r for r in rules if r.get("id") != rule_id]
                data["rules"] = rules
                self._write_data(data)
                # Success if the builtin actually exists
                return any(b["id"] == rule_id for b in BUILTIN_RULES)

            # Removing a user rule
            rules = [r for r in rules if r.get("id") != rule_id]
            if len(rules) == initial_count:
                return False

            data["rules"] = rules
            self._write_data(data)
            return True

    def reset_all(self) -> None:
        """Restore all defaults: clears user rules and overrides, resets settings."""
        with self.lock:
            data = self._default_data()
            self._write_data(data)

    # -------------------------------------------------------------------------
    # Resolution Engine
    # -------------------------------------------------------------------------

    def resolve_mode(
        self,
        app_id: Optional[str] = None,
        domain: Optional[str] = None,
        selected_mode_id: str = "dictation",
        recording_override_mode_id: Optional[str] = None,
        manual_override_active: bool = False,
        available_mode_ids: Optional[Iterable[str]] = None,
        meeting_mode_ids: Optional[Iterable[str]] = None,
    ) -> Tuple[str, str]:
        """Pure, deterministic mode resolution in under 1 ms.

        Resolution order:
          1. Recording override (overlay chip picked for this recording)
          2. Manual override active (hotkey / modes page switched)
          3. Feature disabled in settings
          4. User rule matches app / domain
          5. Built-in default rule matches app / domain
          6. Fallback to user's selected mode

        Returns:
          (mode_id, reason) where reason is one of:
          'recording_override' | 'manual_override' | 'user_rule' | 'builtin_rule' | 'default' | 'disabled'
        """
        disallowed_meeting_modes = set(meeting_mode_ids) if meeting_mode_ids is not None else MEETING_MODES
        valid_modes_set = set(available_mode_ids) if available_mode_ids is not None else None

        # 1. Recording override
        if recording_override_mode_id:
            # Reject meeting modes if set
            if recording_override_mode_id not in disallowed_meeting_modes:
                return recording_override_mode_id, "recording_override"

        # 2. Manual override
        if manual_override_active:
            return selected_mode_id, "manual_override"

        # 3. Feature enabled check
        settings = self.get_settings()
        if not settings.get("enabled", True):
            return selected_mode_id, "disabled"

        norm_app = _normalize_identifier(app_id)
        norm_domain = _normalize_identifier(domain)

        # 4 & 5. Evaluate effective rules
        rules = self.effective_rules()

        # Separate into domain and app rules, user and builtin
        def _check_mode(mode: Optional[str]) -> bool:
            return is_valid_rule_mode(mode, meeting_modes=disallowed_meeting_modes, available_modes=valid_modes_set)

        # Phase 5 domain matches (user rules then builtin rules)
        if norm_domain:
            for rule in rules:
                if not rule.get("enabled", True):
                    continue
                match = rule.get("match", {})
                if match.get("type") == "domain" and _matches_rule(rule, "", norm_domain):
                    target_mode = rule.get("mode_id")
                    if _check_mode(target_mode):
                        reason = "user_rule" if rule.get("source") == "user" else "builtin_rule"
                        return str(target_mode), reason

        # App matches (user rules first, then builtin rules)
        if norm_app:
            for rule in rules:
                if not rule.get("enabled", True):
                    continue
                match = rule.get("match", {})
                if match.get("type") == "app" and _matches_rule(rule, norm_app, ""):
                    target_mode = rule.get("mode_id")
                    if _check_mode(target_mode):
                        reason = "user_rule" if rule.get("source") == "user" else "builtin_rule"
                        return str(target_mode), reason

        # 6. Fallback to default
        return selected_mode_id, "default"

    # -------------------------------------------------------------------------
    # Learning Stats (Feeds Phase 3)
    # -------------------------------------------------------------------------

    def compute_stats(self, history_records: List[Dict[str, Any]], max_days: int = 7) -> List[Dict[str, Any]]:
        """Calculate per-app statistics on how often automatic modes were overridden."""
        now = time.time()
        max_age_sec = max_days * 86400

        # Map effective rules to check suppress_suggestion
        eff_rules = {r.get("id"): r for r in self.effective_rules()}

        app_stats: Dict[str, Dict[str, Any]] = {}

        for rec in history_records:
            app_id = (rec.get("app_id") or rec.get("target_app_bundle_id") or "").strip().lower()
            app_name = (rec.get("app_name") or rec.get("target_app_name") or "").strip()
            if not app_id and not app_name:
                continue

            key = app_id or app_name.lower()
            if key not in app_stats:
                app_stats[key] = {
                    "app_id": app_id,
                    "app_name": app_name,
                    "total_runs": 0,
                    "auto_count": 0,
                    "override_count": 0,
                    "overrides_by_mode": {},
                    "recent_overrides_7d": [],
                    "suppress_suggestion": False,
                }

            entry = app_stats[key]
            if app_name and not entry["app_name"]:
                entry["app_name"] = app_name

            entry["total_runs"] += 1
            reason = rec.get("mode_reason", "")
            mode_id = rec.get("mode_id", "")

            if reason in ("recording_override", "manual_override"):
                entry["override_count"] += 1
                if mode_id:
                    entry["overrides_by_mode"][mode_id] = entry["overrides_by_mode"].get(mode_id, 0) + 1

                # Timestamp check
                rec_ts = rec.get("timestamp")
                ts_num = 0.0
                if isinstance(rec_ts, (int, float)):
                    ts_num = float(rec_ts)
                elif isinstance(rec_ts, str):
                    try:
                        from datetime import datetime
                        dt = datetime.fromisoformat(rec_ts.replace("Z", "+00:00"))
                        ts_num = dt.timestamp()
                    except Exception:
                        pass

                if ts_num > 0 and (now - ts_num) <= max_age_sec:
                    entry["recent_overrides_7d"].append({
                        "mode_id": mode_id,
                        "timestamp": rec_ts,
                    })
            elif reason in ("user_rule", "builtin_rule"):
                entry["auto_count"] += 1

        # Check suppression from rules
        for key, st in app_stats.items():
            for r in eff_rules.values():
                val = _normalize_identifier(r.get("match", {}).get("value"))
                aliases = [_normalize_identifier(a) for a in r.get("match", {}).get("aliases", [])]
                if st["app_id"] and (st["app_id"] == val or st["app_id"] in aliases):
                    if r.get("suppress_suggestion"):
                        st["suppress_suggestion"] = True
                    break

        return sorted(app_stats.values(), key=lambda s: s["override_count"], reverse=True)

    # -------------------------------------------------------------------------
    # Learning Suggestions (Phase 3)
    # -------------------------------------------------------------------------

    def is_suggestion_suppressed(self, app_id: str) -> bool:
        """Check whether suggestions are suppressed for this app either via rule or meta."""
        norm_app = _normalize_identifier(app_id)
        if not norm_app:
            return True

        with self.lock:
            data = self._read_data()
            meta = data.get("suggestions_meta", {}).get(norm_app, {})
            if meta.get("suppress_suggestion"):
                return True

            for r in self.effective_rules():
                val = _normalize_identifier(r.get("match", {}).get("value"))
                aliases = [_normalize_identifier(a) for a in r.get("match", {}).get("aliases", [])]
                if norm_app == val or norm_app in aliases:
                    if r.get("suppress_suggestion"):
                        return True

            return False

    def was_suggested_recently(self, app_id: str, cooldown_seconds: int = 7 * 86400) -> bool:
        """Check whether a suggestion for this app was already shown within cooldown (default 7 days)."""
        norm_app = _normalize_identifier(app_id)
        if not norm_app:
            return True

        with self.lock:
            data = self._read_data()
            meta = data.get("suggestions_meta", {}).get(norm_app, {})
            last_ts = meta.get("last_suggested_at")
            if last_ts is not None:
                try:
                    last_num = float(last_ts)
                    if (time.time() - last_num) < cooldown_seconds:
                        return True
                except (ValueError, TypeError):
                    pass
            return False

    def mark_suggestion_prompted(self, app_id: str, timestamp: Optional[float] = None) -> None:
        """Record that a suggestion was shown to the user for this app."""
        norm_app = _normalize_identifier(app_id)
        if not norm_app:
            return

        with self.lock:
            data = self._read_data()
            if "suggestions_meta" not in data or not isinstance(data["suggestions_meta"], dict):
                data["suggestions_meta"] = {}
            if norm_app not in data["suggestions_meta"]:
                data["suggestions_meta"][norm_app] = {}
            data["suggestions_meta"][norm_app]["last_suggested_at"] = timestamp if timestamp is not None else time.time()
            self._write_data(data)

    def suppress_suggestion(self, app_id: str, display_name: Optional[str] = None) -> Dict[str, Any]:
        """Store the 'don't ask' choice in the rule file (suppress_suggestion: true)."""
        norm_app = _normalize_identifier(app_id)
        if not norm_app:
            raise ValueError("app_id cannot be empty")

        with self.lock:
            data = self._read_data()
            if "suggestions_meta" not in data or not isinstance(data["suggestions_meta"], dict):
                data["suggestions_meta"] = {}
            if norm_app not in data["suggestions_meta"]:
                data["suggestions_meta"][norm_app] = {}
            data["suggestions_meta"][norm_app]["suppress_suggestion"] = True

            rules = data.get("rules", [])
            # 1. Look for existing user rule matching app
            user_rule = next(
                (
                    r for r in rules
                    if r.get("match", {}).get("type") == "app"
                    and _normalize_identifier(r.get("match", {}).get("value")) == norm_app
                ),
                None,
            )
            if user_rule:
                user_rule["suppress_suggestion"] = True
            else:
                # 2. Look for existing builtin rule matching app
                builtin_def = next(
                    (
                        b for b in BUILTIN_RULES
                        if _normalize_identifier(b.get("match", {}).get("value")) == norm_app
                        or norm_app in [_normalize_identifier(a) for a in b.get("match", {}).get("aliases", [])]
                    ),
                    None,
                )
                if builtin_def:
                    b_id = builtin_def["id"]
                    ov = next((r for r in rules if r.get("id") == b_id), None)
                    if ov:
                        ov["suppress_suggestion"] = True
                    else:
                        rules.append({
                            "id": b_id,
                            "match": copy.deepcopy(builtin_def["match"]),
                            "display_name": builtin_def.get("display_name", ""),
                            "mode_id": builtin_def.get("mode_id"),
                            "enabled": builtin_def.get("enabled", True),
                            "suppress_suggestion": True,
                            "source": "builtin_override",
                        })
                else:
                    # 3. No rule exists yet: create a rule with suppress_suggestion: True and enabled: False
                    new_rule = {
                        "id": str(uuid.uuid4()),
                        "match": {"type": "app", "value": norm_app},
                        "display_name": (display_name or norm_app).strip(),
                        "mode_id": "default",
                        "enabled": False,
                        "suppress_suggestion": True,
                        "source": "user",
                    }
                    rules.append(new_rule)

            data["rules"] = rules
            self._write_data(data)
            return {"app_id": app_id, "suppress_suggestion": True}

    def accept_suggestion(
        self,
        app_id: str,
        mode_id: str,
        display_name: Optional[str] = None,
    ) -> Dict[str, Any]:
        """User accepted 'Always use <Mode> in <App>': create or update the rule."""
        norm_app = _normalize_identifier(app_id)
        if not norm_app:
            raise ValueError("app_id cannot be empty")
        clean_mode = (mode_id or "").strip()
        if not clean_mode:
            raise ValueError("mode_id cannot be empty")
        if clean_mode in MEETING_MODES:
            raise ValueError(f"Meeting modes ({', '.join(sorted(MEETING_MODES))}) cannot be targeted by app rules")

        with self.lock:
            # Check if there is an existing rule
            eff = self.effective_rules()
            target_rule = None
            for r in eff:
                if r.get("match", {}).get("type") == "app":
                    val = _normalize_identifier(r.get("match", {}).get("value"))
                    aliases = [_normalize_identifier(a) for a in r.get("match", {}).get("aliases", [])]
                    if norm_app == val or norm_app in aliases:
                        target_rule = r
                        break

            if target_rule:
                updated = self.update_rule(
                    rule_id=target_rule["id"],
                    mode_id=clean_mode,
                    enabled=True,
                    display_name=display_name,
                )
                if updated:
                    return updated

            # Add new rule
            return self.add_rule(
                match={"type": "app", "value": norm_app},
                mode_id=clean_mode,
                display_name=(display_name or norm_app).strip(),
                enabled=True,
            )

    def check_suggestion(
        self,
        history_records: List[Dict[str, Any]],
        app_id: str,
        app_name: Optional[str] = None,
        max_days: int = 7,
        min_overrides: int = 2,
    ) -> Optional[Dict[str, Any]]:
        """Determine if user should be prompted 'Always use <Mode> in <App>?'.

        Rules:
        1. If user overrides auto mode for the same app to the same mode >= 2 times within 7 days.
        2. Not suppressed (`suppress_suggestion: true`).
        3. Never asked more than once per app per week (cooldown).
        4. Not suggested if the app is ALREADY set to that mode.
        5. Meeting modes are excluded.
        """
        settings = self.get_settings()
        if not settings.get("enabled", True):
            return None

        norm_app = _normalize_identifier(app_id)
        if not norm_app:
            return None

        if self.is_suggestion_suppressed(norm_app):
            return None

        if self.was_suggested_recently(norm_app, cooldown_seconds=max_days * 86400):
            return None

        now = time.time()
        max_age_sec = max_days * 86400
        overrides_by_mode: Dict[str, int] = {}

        for rec in history_records:
            # Timestamp check
            rec_ts = rec.get("timestamp")
            ts_num = 0.0
            if isinstance(rec_ts, (int, float)):
                ts_num = float(rec_ts)
            elif isinstance(rec_ts, str):
                try:
                    from datetime import datetime
                    dt = datetime.fromisoformat(rec_ts.replace("Z", "+00:00"))
                    ts_num = dt.timestamp()
                except Exception:
                    pass

            if ts_num <= 0 or (now - ts_num) > max_age_sec:
                continue

            r_app = _normalize_identifier(rec.get("app_id") or rec.get("target_app_bundle_id"))
            r_name = (rec.get("app_name") or rec.get("target_app_name") or "").strip().lower()

            matches = (r_app and r_app == norm_app) or (not r_app and app_name and r_name == app_name.strip().lower())
            if not matches:
                continue

            reason = rec.get("mode_reason", "")
            if reason in ("recording_override", "manual_override"):
                m_id = (rec.get("mode_id") or rec.get("mode") or "").strip()
                if is_valid_rule_mode(m_id):
                    overrides_by_mode[m_id] = overrides_by_mode.get(m_id, 0) + 1

        if not overrides_by_mode:
            return None

        # Check what the effective auto mode is currently for this app
        current_auto_mode, _ = self.resolve_mode(app_id=norm_app, selected_mode_id="default")

        # Pick candidate mode with count >= min_overrides (highest count first)
        sorted_candidates = sorted(overrides_by_mode.items(), key=lambda kv: kv[1], reverse=True)
        for cand_mode, count in sorted_candidates:
            if count >= min_overrides and cand_mode != current_auto_mode:
                return {
                    "app_id": app_id,
                    "app_name": app_name or app_id,
                    "mode_id": cand_mode,
                    "count": count,
                }

        return None


# Global singleton instance
app_rules_manager = AppRulesManager()
