"""Single source of truth for the user data directory.

Every engine module (history, vocabulary, settings, metrics, snippets, queue,
prompts, auth, models) must resolve its storage through here so that:

* ``DICTY_DATA_DIR`` relocates all user data in one place, and
* the test suite can never write into the real ``~/Library/Application Support``
  directory. When ``DICTY_TESTING=1`` is set, resolving the real default directory
  raises instead of silently touching the user's data.
"""

import os
import platform
import shutil
import sys

# Ensure services and integrations directories are always available for direct imports
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
_PROJECT_ROOT = PROJECT_ROOT

_SERVICES_DIR = os.path.join(PROJECT_ROOT, "services")
if os.path.isdir(_SERVICES_DIR) and _SERVICES_DIR not in sys.path:
    sys.path.insert(0, _SERVICES_DIR)

_INTEGRATIONS_DIR = os.path.join(PROJECT_ROOT, "integrations")
if os.path.isdir(_INTEGRATIONS_DIR) and _INTEGRATIONS_DIR not in sys.path:
    sys.path.insert(0, _INTEGRATIONS_DIR)



def default_data_dir() -> str:
    if platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Dicty")
    return os.path.expanduser("~/.dicty")


def get_user_data_dir() -> str:
    override = os.getenv("DICTY_DATA_DIR")
    path = os.path.abspath(override) if override else default_data_dir()

    if os.getenv("DICTY_TESTING") == "1":
        real_default = os.path.realpath(default_data_dir())
        real_path = os.path.realpath(path)
        try:
            inside_default = os.path.commonpath([real_default, real_path]) == real_default
        except ValueError:
            inside_default = False
        if inside_default:
            raise RuntimeError(
                "Refusing to use the real user data directory while DICTY_TESTING=1. "
                "Set DICTY_DATA_DIR to a temporary directory."
            )

    os.makedirs(path, exist_ok=True)
    return path


def migrate_legacy_file(filename: str, new_path: str) -> bool:
    """Copy a legacy CWD-relative data file into the data dir once.

    Older builds stored some JSON files next to the working directory. Tests are
    excluded so they can never import the real user's file into a temp directory.
    """
    if os.getenv("DICTY_TESTING") == "1":
        return False
    if os.path.exists(new_path):
        return False

    legacy = os.path.abspath(filename)
    if not os.path.isfile(legacy) or legacy == os.path.abspath(new_path):
        return False

    try:
        os.makedirs(os.path.dirname(new_path), exist_ok=True)
        shutil.copy2(legacy, new_path)
        print(f"[*] Migrated {legacy} -> {new_path}")
        return True
    except OSError as exc:
        print(f"[!] Could not migrate {legacy}: {exc}")
        return False
