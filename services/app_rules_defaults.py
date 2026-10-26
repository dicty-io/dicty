"""Built-in default app rules for Dicty.

Built-in defaults live in code, not in the data file.
The data file (app_rules.json) stores only what the user changed:
new rules, changed modes for built-ins, and disabled built-ins.
Updating defaults in a new release then never overwrites user choices.
"""

from typing import Any, Dict, List

DEFAULT_ENABLED = True
DEFAULT_OVERRIDE_SCOPE = "recording"  # "recording" (for this recording only) or "manual" (until switched back)

# Meeting modes cannot be targeted by app rules
MEETING_MODES = {"meeting", "focused_meeting"}

# Built-in default rules table: only widely spread and popular applications
# Stable IDs prefixed with builtin.
BUILTIN_RULES: List[Dict[str, Any]] = [
    # --- Browsers ---
    {
        "id": "builtin.chrome",
        "match": {
            "type": "app",
            "value": "com.google.Chrome",
            "aliases": ["chrome.exe", "google chrome"],
        },
        "display_name": "Google Chrome",
        "mode_id": "dictation",
        "enabled": True,
        "source": "builtin",
    },
    {
        "id": "builtin.safari",
        "match": {
            "type": "app",
            "value": "com.apple.Safari",
            "aliases": [],
        },
        "display_name": "Safari",
        "mode_id": "dictation",
        "enabled": True,
        "source": "builtin",
    },

    # --- Code Editors (disabled by default until user turns them on) ---
    {
        "id": "builtin.vscode",
        "match": {
            "type": "app",
            "value": "com.microsoft.VSCode",
            "aliases": ["code.exe", "com.microsoft.vscode"],
        },
        "display_name": "Visual Studio Code",
        "mode_id": "code",
        "enabled": False,
        "source": "builtin",
    },
    {
        "id": "builtin.cursor",
        "match": {
            "type": "app",
            "value": "com.todesktop.230313mzl4w4u92",
            "aliases": ["cursor.exe"],
        },
        "display_name": "Cursor",
        "mode_id": "code",
        "enabled": False,
        "source": "builtin",
    },

    # --- Messaging (disabled by default until user turns them on) ---
    {
        "id": "builtin.slack",
        "match": {
            "type": "app",
            "value": "com.tinyspeck.slackmacgap",
            "aliases": ["slack.exe"],
        },
        "display_name": "Slack",
        "mode_id": "message",
        "enabled": False,
        "source": "builtin",
    },
    {
        "id": "builtin.telegram",
        "match": {
            "type": "app",
            "value": "ru.keepcoder.Telegram",
            "aliases": ["com.tdesktop.mac", "telegram.exe", "ru.keepcoder.telegram"],
        },
        "display_name": "Telegram",
        "mode_id": "message",
        "enabled": False,
        "source": "builtin",
    },
    {
        "id": "builtin.whatsapp",
        "match": {
            "type": "app",
            "value": "net.whatsapp.WhatsApp",
            "aliases": ["net.whatsapp.whatsapp", "whatsapp.exe"],
        },
        "display_name": "WhatsApp",
        "mode_id": "message",
        "enabled": False,
        "source": "builtin",
    },
    {
        "id": "builtin.messages",
        "match": {
            "type": "app",
            "value": "com.apple.MobileSMS",
            "aliases": ["com.apple.mobilesms"],
        },
        "display_name": "Messages",
        "mode_id": "message",
        "enabled": False,
        "source": "builtin",
    },

    # --- Email (disabled by default until user turns them on) ---
    {
        "id": "builtin.mail",
        "match": {
            "type": "app",
            "value": "com.apple.mail",
            "aliases": [],
        },
        "display_name": "Apple Mail",
        "mode_id": "email",
        "enabled": False,
        "source": "builtin",
    },
    {
        "id": "builtin.outlook",
        "match": {
            "type": "app",
            "value": "com.microsoft.Outlook",
            "aliases": ["com.microsoft.outlook", "outlook.exe"],
        },
        "display_name": "Microsoft Outlook",
        "mode_id": "email",
        "enabled": False,
        "source": "builtin",
    },

    # --- Notes (disabled by default until user turns them on) ---
    {
        "id": "builtin.apple_notes",
        "match": {
            "type": "app",
            "value": "com.apple.Notes",
            "aliases": ["com.apple.notes"],
        },
        "display_name": "Notes",
        "mode_id": "note",
        "enabled": False,
        "source": "builtin",
    },
]
