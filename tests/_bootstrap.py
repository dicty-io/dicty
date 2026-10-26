"""Test bootstrap: isolate all engine storage before any test imports it.

All engine storage (history, vocabulary, settings, metrics, snippets, queue,
prompts, models) resolves through ``DICTY_DATA_DIR``. This module points it at a
temporary directory so the suite can never write into the real
``~/Library/Application Support/Dicty`` directory.

Every test module imports this first. ``tests/__init__.py`` also imports it so
``python -m unittest tests.<module>`` is isolated too.

Downloaded models are shared through a cache under the system temp directory so
repeated runs do not re-download them, while still never touching user data.
"""

import atexit
import os
import platform
import shutil
import sys
import tempfile

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

SERVICES_DIR = os.path.join(PROJECT_ROOT, "services")
if os.path.isdir(SERVICES_DIR) and SERVICES_DIR not in sys.path:
    sys.path.insert(0, SERVICES_DIR)

INTEGRATIONS_DIR = os.path.join(PROJECT_ROOT, "integrations")
if os.path.isdir(INTEGRATIONS_DIR) and INTEGRATIONS_DIR not in sys.path:
    sys.path.insert(0, INTEGRATIONS_DIR)


def _default_data_dir() -> str:
    if platform.system() == "Darwin":
        return os.path.expanduser("~/Library/Application Support/Dicty")
    return os.path.expanduser("~/.dicty")


REAL_DATA_DIR = os.environ.get("DICTY_REAL_DATA_DIR") or _default_data_dir()
os.environ["DICTY_REAL_DATA_DIR"] = REAL_DATA_DIR

# Idempotent: the module can be imported as ``_bootstrap`` and ``tests._bootstrap``.
if os.environ.get("DICTY_TESTING") == "1" and os.environ.get("DICTY_DATA_DIR"):
    TEST_DATA_DIR = os.environ["DICTY_DATA_DIR"]
else:
    TEST_DATA_DIR = tempfile.mkdtemp(prefix="dicty-tests-")
    os.environ["DICTY_DATA_DIR"] = TEST_DATA_DIR
    os.environ["DICTY_TESTING"] = "1"

    # Reuse model downloads across test runs without writing into the user's data dir.
    _MODEL_CACHE = os.environ.get(
        "DICTY_TEST_MODEL_CACHE",
        os.path.join(tempfile.gettempdir(), "dicty-test-models"),
    )
    os.makedirs(_MODEL_CACHE, exist_ok=True)
    try:
        os.symlink(_MODEL_CACHE, os.path.join(TEST_DATA_DIR, "models"), target_is_directory=True)
    except OSError:
        os.makedirs(os.path.join(TEST_DATA_DIR, "models"), exist_ok=True)

    def _cleanup() -> None:
        shutil.rmtree(TEST_DATA_DIR, ignore_errors=True)

    atexit.register(_cleanup)


def real_data_dir() -> str:
    return REAL_DATA_DIR


def test_data_dir() -> str:
    return TEST_DATA_DIR


# Initialize session token in isolated test directory and provide shared TestClient fixture
import engine_auth
TEST_TOKEN = os.environ.get("DICTY_SESSION_TOKEN") or "dicty-test-session-token-32bytes-secret"
os.environ["DICTY_SESSION_TOKEN"] = TEST_TOKEN
engine_auth.init_token(TEST_TOKEN)

try:
    from fastapi.testclient import TestClient as _FastAPITestClient
    _orig_testclient_init = _FastAPITestClient.__init__

    def _patched_testclient_init(self, app, *args, **kwargs):
        headers = kwargs.get("headers")
        if headers is None:
            headers = {}
            kwargs["headers"] = headers
        else:
            headers = dict(headers)
            kwargs["headers"] = headers

        if headers.get("_dicty_no_auth"):
            del headers["_dicty_no_auth"]
        elif "X-Dicty-Token" not in headers:
            headers["X-Dicty-Token"] = engine_auth.get_token()

        _orig_testclient_init(self, app, *args, **kwargs)

    _FastAPITestClient.__init__ = _patched_testclient_init
except ImportError:
    pass
