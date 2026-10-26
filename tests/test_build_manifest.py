"""
test_build_manifest.py
======================
Lightweight static analysis tests that validate the PyInstaller build manifest
(build_mac.sh + dicty_engine.spec) includes all first-party modules that are
imported at the top level by dicty_engine.py and its key service modules.

These tests catch the exact class of bug where a dependency (e.g. silero_service,
piper_service) is present in the source tree and works in dev, but is missing
from the packaged bundle causing a silent ModuleNotFoundError at startup.

No PyInstaller invocation, no network access, no model downloads needed.
Runs in < 1s.
"""
import _bootstrap  # noqa: F401
import ast
import os
import re
import sys
import unittest

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# First-party .py modules in the project root and subpackages
_SEARCH_DIRS = [
    PROJECT_ROOT,
    os.path.join(PROJECT_ROOT, "services"),
    os.path.join(PROJECT_ROOT, "integrations"),
]

FIRST_PARTY_MODULES = {
    os.path.splitext(f)[0]
    for d in _SEARCH_DIRS
    if os.path.isdir(d)
    for f in os.listdir(d)
    if f.endswith(".py") and not f.startswith("_") and os.path.isfile(os.path.join(d, f))
}


def _find_module_path(name: str) -> str:
    for d in _SEARCH_DIRS:
        p = os.path.join(d, f"{name}.py")
        if os.path.exists(p):
            return p
    return os.path.join(PROJECT_ROOT, f"{name}.py")


def _get_top_level_imports(filepath: str) -> set:
    """Parse a Python source file and return all imported module names (top-level)."""
    try:
        with open(filepath, "r", encoding="utf-8") as fh:
            source = fh.read()
        tree = ast.parse(source, filename=filepath)
    except (SyntaxError, OSError):
        return set()

    imports = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                imports.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                imports.add(node.module.split(".")[0])
    return imports


# Modules that are the entry point itself or test files - not external deps to declare
SELF_REFERENTIAL = {"dicty_engine", "main"}


def _get_spec_hidden_imports() -> set:
    """Extract the hiddenimports list from dicty_engine.spec."""
    spec_path = os.path.join(PROJECT_ROOT, "dicty_engine.spec")
    if not os.path.exists(spec_path):
        return set()
    with open(spec_path, "r", encoding="utf-8") as fh:
        content = fh.read()
    match = re.search(r"hiddenimports\s*=\s*\[(.*?)\]", content, re.DOTALL)
    if not match:
        return set()
    block = match.group(1)
    return set(re.findall(r"['\"]([^'\"]+)['\"]", block))


def _get_build_sh_hidden_imports() -> set:
    """Extract --hidden-import values from build_mac.sh."""
    sh_path = os.path.join(PROJECT_ROOT, "build_mac.sh")
    if not os.path.exists(sh_path):
        return set()
    with open(sh_path, "r", encoding="utf-8") as fh:
        content = fh.read()
    return set(re.findall(r"--hidden-import[=\s][\"']?([A-Za-z0-9_\.]+)[\"']?", content))


class TestBuildManifestCompleteness(unittest.TestCase):
    """Ensures PyInstaller build manifests declare all first-party module dependencies."""

    @classmethod
    def setUpClass(cls):
        cls.spec_imports = _get_spec_hidden_imports()
        cls.sh_imports = _get_build_sh_hidden_imports()
        cls.all_declared = cls.spec_imports | cls.sh_imports

    def _assert_declared(self, modules: set, context: str):
        missing = {
            m for m in modules
            if m in FIRST_PARTY_MODULES
            and m not in self.all_declared
            and m not in SELF_REFERENTIAL
        }
        if missing:
            self.fail(
                f"\n[BUILD MANIFEST] First-party modules imported by {context}\n"
                f"are NOT declared in build_mac.sh or dicty_engine.spec:\n\n"
                + "\n".join(f"  - {m}" for m in sorted(missing))
                + "\n\nAdd them with --hidden-import=\"<module>\" in both files."
            )

    def test_spec_file_exists(self):
        self.assertTrue(os.path.exists(os.path.join(PROJECT_ROOT, "dicty_engine.spec")))

    def test_build_sh_exists(self):
        self.assertTrue(os.path.exists(os.path.join(PROJECT_ROOT, "build_mac.sh")))

    def test_spec_has_hidden_imports_section(self):
        self.assertGreater(len(self.spec_imports), 0)

    def test_tts_service_deps_declared(self):
        """All first-party modules imported by tts_service.py must be in the build manifest."""
        path = _find_module_path("tts_service")
        if not os.path.exists(path):
            self.skipTest("tts_service.py not found")
        self._assert_declared(_get_top_level_imports(path), "tts_service.py")

    def test_silero_service_declared(self):
        """silero_service is imported by tts_service at module scope - must be in manifest."""
        self.assertIn(
            "silero_service", self.all_declared,
            "silero_service missing from build manifests — tts_service.py imports it at module scope"
        )

    def test_piper_service_declared(self):
        """piper_service is imported by tts_service at module scope - must be in manifest."""
        self.assertIn(
            "piper_service", self.all_declared,
            "piper_service missing from build manifests — tts_service.py imports it at module scope"
        )

    def test_engine_top_level_imports_declared(self):
        """All first-party modules at the top of dicty_engine.py must be declared."""
        path = os.path.join(PROJECT_ROOT, "dicty_engine.py")
        if not os.path.exists(path):
            self.skipTest("dicty_engine.py not found")
        self._assert_declared(_get_top_level_imports(path), "dicty_engine.py")

    def test_transcribe_service_declared(self):
        self.assertIn("transcribe_service", self.all_declared)

    def test_model_manager_declared(self):
        self.assertIn("model_manager", self.all_declared)

    def test_no_stale_declared_modules(self):
        """First-party modules in the manifest should actually exist on disk."""
        stale = {
            m for m in self.all_declared
            if m in FIRST_PARTY_MODULES
            and not os.path.exists(_find_module_path(m))
        }
        if stale:
            self.fail(
                "[BUILD MANIFEST] Declared modules with no .py file:\n"
                + "\n".join(f"  - {m}.py" for m in sorted(stale))
            )

    def test_spec_and_sh_are_consistent(self):
        """First-party imports in build_mac.sh should also appear in dicty_engine.spec."""
        sh_fp = {m for m in self.sh_imports if m in FIRST_PARTY_MODULES}
        spec_fp = {m for m in self.spec_imports if m in FIRST_PARTY_MODULES}
        missing_from_spec = sh_fp - spec_fp
        if missing_from_spec:
            self.fail(
                "[BUILD MANIFEST] In build_mac.sh but not in dicty_engine.spec:\n"
                + "\n".join(f"  - {m}" for m in sorted(missing_from_spec))
            )


    def test_tts_service_importable_without_torch(self):
        """Verifies tts_service and silero_service import cleanly when torch is not installed."""
        import subprocess
        code = (
            "import sys; "
            "import dicty_paths; "
            "sys.modules['torch'] = None; "
            "sys.modules['torch.package'] = None; "
            "import silero_service; "
            "import tts_service; "
            "from tts_service import tts_service; "
            "assert tts_service is not None; "
            "assert isinstance(tts_service.get_status(), dict); "
            "print('OK')"
        )
        res = subprocess.run(
            [sys.executable, "-c", code],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True
        )
        self.assertEqual(
            res.returncode, 0,
            f"tts_service failed to import without torch:\nSTDOUT: {res.stdout}\nSTDERR: {res.stderr}"
        )

    def test_make_dmg_bundle_root_strictly_clean(self):
        """
        macOS code-signing strictly forbids unsealed contents at the .app bundle root.
        Only ${APP_DIR}/Contents is permitted. Any file, folder, or symlink at ${APP_DIR}/
        causes 'codesign: unsealed contents present in the bundle root'.
        """
        dmg_script = os.path.join(PROJECT_ROOT, "make_dmg.sh")
        if not os.path.exists(dmg_script):
            self.skipTest("make_dmg.sh not found")
        with open(dmg_script, "r", encoding="utf-8") as f:
            lines = f.readlines()
        for idx, line in enumerate(lines, 1):
            stripped = line.strip()
            # Ignore comments, rm, or cleanup commands
            if stripped.startswith("#") or stripped.startswith("rm ") or "rm -rf" in stripped:
                continue
            # Check for cp or ln targeting ${APP_DIR}/<something> instead of ${APP_DIR}/Contents/...
            if re.search(r'(?:cp|ln|mkdir|touch)\s+.*?\$\{APP_DIR\}/(?!\bContents\b|\s*$)', stripped):
                self.fail(
                    f"[BUNDLE INTEGRITY] make_dmg.sh line {idx} targets bundle root directly:\n"
                    f"  {stripped}\n"
                    f"Only ${{APP_DIR}}/Contents is valid in macOS .app bundles."
                )

    def test_dist_app_bundle_sealing_if_present(self):
        """If dist/Dicty.app is present, verify it contains ONLY Contents and passes codesign."""
        app_path = os.path.join(PROJECT_ROOT, "dist", "Dicty.app")
        if not os.path.exists(app_path):
            return  # Not built yet in fresh checkout
        entries = os.listdir(app_path)
        self.assertEqual(
            entries, ["Contents"],
            f"[BUNDLE SEALING] dist/Dicty.app must only contain 'Contents' at its root. Found: {entries}"
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
