import os
import sys
import platform
import subprocess
import tempfile
import urllib.request
import json
import time
import threading
import ssl
import re
import urllib.parse
import shlex

ALLOWED_UPDATE_HOSTS = {
    "github.com",
    "api.github.com",
    "objects.githubusercontent.com",
    "github-releases.githubusercontent.com",
    "raw.githubusercontent.com",
}

SAFE_ASSET_NAME_REGEX = re.compile(r'^[A-Za-z0-9_.-]+$')

def is_safe_update_url(url: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme != "https":
            return False
        hostname = (parsed.hostname or "").lower()
        if not any(hostname == h or hostname.endswith("." + h) for h in ALLOWED_UPDATE_HOSTS):
            return False
        return True
    except Exception:
        return False

GITHUB_REPO = os.environ.get("DICTY_RELEASE_REPO", "dicty-io/dicty")

def parse_semver(v_str: str):
    if not v_str:
        return (0, 0, 0, 0)
    clean = str(v_str).strip().lstrip("vV")
    serial = 0
    if "-" in clean:
        base_part, suffix = clean.split("-", 1)
        # Extract leading numeric digits for serial build/patch (e.g., 1.0.40-1)
        digits = ""
        for ch in suffix:
            if ch.isdigit():
                digits += ch
            else:
                break
        serial = int(digits) if digits else 0
    else:
        base_part = clean

    parts = []
    for p in base_part.split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(0)
    while len(parts) < 3:
        parts.append(0)
    return (parts[0], parts[1], parts[2], serial)

class UpdateManager:
    def __init__(self):
        self.os_type = platform.system() # 'Darwin', 'Windows', 'Linux'
        self.download_progress = 0.0
        self.is_updating = False
        self.last_error = None
        self._update_thread = None
        
    def _download_report_hook(self, block_num, block_size, total_size):
        if total_size > 0:
            downloaded = block_num * block_size
            self.download_progress = min(100.0, (downloaded / total_size) * 100.0)
            
    def _find_matching_asset(self, assets: list):
        if not assets or not isinstance(assets, list):
            return None
        # On Windows: look for .exe or .msi, prioritizing setup / installer executables
        if self.os_type == "Windows":
            for a in assets:
                n = a.get("name", "").lower()
                if (n.endswith(".exe") or n.endswith(".msi")) and ("setup" in n or "installer" in n):
                    return a
            for a in assets:
                n = a.get("name", "").lower()
                if n.endswith(".exe") or n.endswith(".msi"):
                    return a
        # On macOS (Darwin): look for .dmg or .pkg
        elif self.os_type == "Darwin":
            for a in assets:
                n = a.get("name", "").lower()
                if n.endswith(".dmg") or n.endswith(".pkg"):
                    return a
        # On Linux: look for .appimage, .tar.gz, .deb
        elif self.os_type == "Linux":
            for a in assets:
                n = a.get("name", "").lower()
                if n.endswith(".appimage") or n.endswith(".tar.gz") or n.endswith(".deb"):
                    return a
        return None

    def check_for_updates(self, current_version: str, repo: str = None, token: str = None):
        # Reset progress and updating flag if no active download thread is running
        if not (self._update_thread and self._update_thread.is_alive()):
            self.download_progress = 0.0
            self.is_updating = False
            self.last_error = None

        target_repo = repo or GITHUB_REPO or "dicty-io/dicty"
        # Fetch releases list so we can scan for the latest release containing
        # an installer asset built specifically for the current operating system.
        urls = [
            f"https://api.github.com/repos/{target_repo}/releases?per_page=30",
            "https://api.github.com/repos/dicty-io/dicty/releases?per_page=30",
            f"https://api.github.com/repos/{target_repo}/releases/latest",
            "https://api.github.com/repos/dicty-io/dicty/releases/latest",
            "https://api.github.com/repos/vkazmin1/dicty/releases/latest",
        ]
        
        headers = {
            "User-Agent": "DictyApp/1.0",
            "Accept": "application/vnd.github.v3+json"
        }
        if token and token.strip():
            headers["Authorization"] = f"Bearer {token.strip()}"
        
        all_releases = []
        last_err = None
        
        for url in urls:
            try:
                req = urllib.request.Request(url, headers=headers)
                ctx = ssl._create_unverified_context()
                with urllib.request.urlopen(req, timeout=6.0, context=ctx) as res:
                    if res.status in (200, 301, 302):
                        payload = json.loads(res.read().decode("utf-8"))
                        if isinstance(payload, list) and len(payload) > 0:
                            all_releases = payload
                            break
                        elif isinstance(payload, dict) and payload.get("tag_name"):
                            all_releases = [payload]
                            break
            except Exception as e:
                last_err = str(e)
                continue

        # Sort all discovered releases descending by semver version
        if all_releases:
            all_releases.sort(key=lambda r: parse_semver(r.get("tag_name", "")), reverse=True)

        # Find the latest release that actually contains an installer asset for our OS
        matching_release = None
        matching_asset = None
        for rel in all_releases:
            if rel.get("draft", False):
                continue
            asset = self._find_matching_asset(rel.get("assets", []))
            if asset:
                matching_release = rel
                matching_asset = asset
                break

        # Fallback if no releases returned: check tags
        latest_tag = None
        tag_notes = ""
        if not matching_release and not all_releases:
            tag_urls = [
                f"https://api.github.com/repos/{target_repo}/tags",
                "https://api.github.com/repos/vkazmin1/dicty/tags"
            ]
            for url in tag_urls:
                try:
                    req = urllib.request.Request(url, headers=headers)
                    ctx = ssl._create_unverified_context()
                    with urllib.request.urlopen(req, timeout=6.0, context=ctx) as res:
                        if res.status in (200, 301, 302):
                            tag_list = json.loads(res.read().decode("utf-8"))
                            if isinstance(tag_list, list) and len(tag_list) > 0:
                                latest_tag = tag_list[0].get("name")
                                break
                except Exception:
                    continue

            if not latest_tag:
                try:
                    out = subprocess.check_output(["git", "tag", "-l"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
                    all_tags = [t.strip() for t in out.splitlines() if t.strip()]
                    v_tags = [t for t in all_tags if t.startswith("v1.") or t.startswith("v0.")]
                    if v_tags:
                        v_tags.sort(key=lambda t: parse_semver(t))
                        latest_tag = v_tags[-1]
                    try:
                        tag_notes = subprocess.check_output(["git", "log", "-n", "5", "--oneline"], stderr=subprocess.DEVNULL).decode("utf-8", errors="ignore")
                    except Exception:
                        pass
                except Exception:
                    pass

            if not latest_tag:
                return {
                    "has_update": False,
                    "latest_version": current_version,
                    "current_version": current_version,
                    "release_name": f"v{current_version}",
                    "release_notes": "Up to date with repository.",
                    "repo": target_repo,
                    "error": last_err
                }

        try:
            # 1. Best match: an installer specifically for current operating system was found
            if matching_release and matching_asset:
                latest_version = matching_release.get("tag_name", "").lstrip("vV")
                has_update = parse_semver(latest_version) > parse_semver(current_version)
                return {
                    "has_update": has_update,
                    "latest_version": latest_version,
                    "current_version": current_version,
                    "release_name": matching_release.get("name") or matching_release.get("tag_name", ""),
                    "release_notes": matching_release.get("body", "") or f"Dicty v{latest_version} is available for your operating system.",
                    "download_url": matching_asset.get("browser_download_url"),
                    "asset_name": matching_asset.get("name"),
                    "repo": target_repo,
                    "published_at": matching_release.get("published_at"),
                    "html_url": matching_release.get("html_url") or f"https://github.com/{target_repo}/releases",
                    "error": None
                }

            # 2. Releases exist, but none contained an installer for current OS
            if all_releases:
                top_rel = all_releases[0]
                latest_version = top_rel.get("tag_name", "").lstrip("vV")
                has_update = parse_semver(latest_version) > parse_semver(current_version)
                return {
                    "has_update": has_update,
                    "latest_version": latest_version,
                    "current_version": current_version,
                    "release_name": top_rel.get("name") or top_rel.get("tag_name", ""),
                    "release_notes": top_rel.get("body", "") or "Newer release found, but installer for your operating system is currently unavailable.",
                    "download_url": None,
                    "asset_name": None,
                    "repo": target_repo,
                    "published_at": top_rel.get("published_at"),
                    "html_url": top_rel.get("html_url") or f"https://github.com/{target_repo}/releases",
                    "error": None
                }

            # 3. Tag fallback
            if latest_tag:
                latest_version = latest_tag.lstrip("vV")
                has_update = parse_semver(latest_version) > parse_semver(current_version)
                return {
                    "has_update": has_update,
                    "latest_version": latest_version,
                    "current_version": current_version,
                    "release_name": latest_tag,
                    "release_notes": tag_notes or f"Synchronized with GitHub repository {target_repo} tag {latest_tag}.",
                    "download_url": None,
                    "asset_name": None,
                    "repo": target_repo,
                    "published_at": None,
                    "html_url": f"https://github.com/{target_repo}/releases/tag/{latest_tag}",
                    "error": None
                }
        except Exception as e:
            return {
                "has_update": False,
                "latest_version": current_version,
                "current_version": current_version,
                "release_notes": "",
                "error": str(e)
            }

    def apply_update(self, download_url: str, asset_name: str):
        if not download_url or not asset_name:
            self.last_error = "Missing download URL or asset name."
            return False

        # Guard: Strict OS compatibility check
        name_lower = asset_name.lower()
        if self.os_type == "Windows" and not (name_lower.endswith(".exe") or name_lower.endswith(".msi")):
            self.last_error = f"Cannot install non-Windows asset '{asset_name}' on Windows."
            print(f"[!] {self.last_error}")
            return False
        elif self.os_type == "Darwin" and not (name_lower.endswith(".dmg") or name_lower.endswith(".pkg")):
            self.last_error = f"Cannot install non-macOS asset '{asset_name}' on macOS."
            print(f"[!] {self.last_error}")
            return False

        if not asset_name or asset_name != os.path.basename(asset_name) or not SAFE_ASSET_NAME_REGEX.match(asset_name):
            self.last_error = f"Invalid or unsafe asset name '{asset_name}'."
            print(f"[!] {self.last_error}")
            return False

        if not is_safe_update_url(download_url):
            self.last_error = f"Untrusted update source URL: {download_url}"
            print(f"[!] {self.last_error}")
            return False

        # If an active download worker thread is already executing, let it continue
        if self._update_thread and self._update_thread.is_alive():
            return True
            
        self.is_updating = True
        self.download_progress = 0.0
        self.last_error = None
        
        self._update_thread = threading.Thread(target=self._run_apply_update, args=(download_url, asset_name), daemon=True)
        self._update_thread.start()
        return True

    def _run_apply_update(self, download_url: str, asset_name: str):
        my_pid = os.getpid()
        # Guard against cross-OS execution
        name_lower = asset_name.lower()
        if self.os_type == "Windows" and not (name_lower.endswith(".exe") or name_lower.endswith(".msi")):
            self.last_error = f"Cannot install non-Windows asset '{asset_name}' on Windows."
            self.is_updating = False
            return
        elif self.os_type == "Darwin" and not (name_lower.endswith(".dmg") or name_lower.endswith(".pkg")):
            self.last_error = f"Cannot install non-macOS asset '{asset_name}' on macOS."
            self.is_updating = False
            return

        if not asset_name or asset_name != os.path.basename(asset_name) or not SAFE_ASSET_NAME_REGEX.match(asset_name):
            self.last_error = f"Invalid or unsafe asset name '{asset_name}'."
            self.is_updating = False
            return

        if not is_safe_update_url(download_url):
            self.last_error = f"Untrusted update source URL: {download_url}"
            self.is_updating = False
            return

        clean_asset_name = os.path.basename(asset_name)
        temp_dir = tempfile.gettempdir()
        download_path = os.path.realpath(os.path.join(temp_dir, clean_asset_name))
        if not download_path.startswith(os.path.realpath(temp_dir)):
            self.last_error = "Directory traversal detected in asset path."
            self.is_updating = False
            return
        
        # Clean up any stale installer files from previous downloads
        try:
            for old_file in os.listdir(temp_dir):
                if (old_file.startswith("Dicty_") or old_file.startswith("dicty_") or old_file == "Dicty.dmg") and (old_file.endswith(".exe") or old_file.endswith(".dmg")):
                    try:
                        os.remove(os.path.join(temp_dir, old_file))
                    except Exception:
                        pass
        except Exception:
            pass

        try:
            print(f"[*] Downloading update from {download_url} to {download_path}")
            req = urllib.request.Request(download_url, headers={"User-Agent": "DictyApp/1.0"})
            try:
                import certifi
                ctx = ssl.create_default_context(cafile=certifi.where())
            except Exception:
                ctx = ssl.create_default_context()
            with urllib.request.urlopen(req, timeout=180.0, context=ctx) as response, open(download_path, 'wb') as out_file:
                total_size = int(response.info().get('Content-Length', -1))
                downloaded = 0
                block_size = 65536
                while True:
                    buffer = response.read(block_size)
                    if not buffer:
                        break
                    downloaded += len(buffer)
                    out_file.write(buffer)
                    if total_size > 0:
                        self.download_progress = min(100.0, (downloaded / total_size) * 100.0)
                    else:
                        # Fallback if Content-Length is missing: estimate 75MB
                        estimated_size = 75.0 * 1024 * 1024
                        self.download_progress = min(99.0, (downloaded / estimated_size) * 100.0)
            
            self.download_progress = 100.0
            time.sleep(0.5)
            
            if self.os_type == "Darwin":
                script_path = os.path.join(temp_dir, "dicty_updater.sh")
                from local_whisper import PID_FILE as ws_pid_file
                safe_download_path = shlex.quote(download_path)
                with open(script_path, "w") as f:
                    f.write(f'''#!/bin/bash
exec > /tmp/dicty_update.log 2>&1
set -x
echo "[*] Update script started at $(date)..."
sleep 1
echo "[*] Terminating existing Dicty instance and engine (PID: {my_pid})..."
killall "Dicty" 2>/dev/null || true
kill -9 {my_pid} 2>/dev/null || true
killall -9 "dicty_engine" 2>/dev/null || true
pkill -9 -f "dicty_engine" 2>/dev/null || true
# Only kill Dicty's own whisper-server (tracked by pidfile), never other apps' servers
WS_PID=$(cat {shlex.quote(ws_pid_file)} 2>/dev/null)
if [ -n "$WS_PID" ] && ps -p "$WS_PID" -o comm= | grep -q whisper-server; then kill -9 "$WS_PID" 2>/dev/null || true; fi
sleep 1

echo "[*] Unmounting old DMG mount if present..."
hdiutil detach "/tmp/dicty_dmg" -force 2>/dev/null || true
mkdir -p "/tmp/dicty_dmg"

echo "[*] Mounting DMG from {safe_download_path}..."
hdiutil attach "{safe_download_path}" -nobrowse -mountpoint "/tmp/dicty_dmg" -quiet || hdiutil attach "{safe_download_path}" -nobrowse -mountpoint "/tmp/dicty_dmg"

if [ -d "/tmp/dicty_dmg/Dicty.app" ]; then
    echo "[*] Installing to /Applications/Dicty.app..."
    rm -rf "/Applications/Dicty.app"
    cp -R "/tmp/dicty_dmg/Dicty.app" "/Applications/"
    xattr -cr "/Applications/Dicty.app" 2>/dev/null || true
else
    echo "[-] Error: /tmp/dicty_dmg/Dicty.app not found!"
fi

echo "[*] Cleaning up mount and DMG..."
hdiutil detach "/tmp/dicty_dmg" -force 2>/dev/null || true
rm -rf "/tmp/dicty_dmg"
rm -f "{safe_download_path}"

echo "[*] Relaunching Dicty..."
open -a "/Applications/Dicty.app"
echo "[+] Done."
''')
                os.chmod(script_path, 0o755)
                subprocess.Popen(["/bin/bash", script_path], start_new_session=True)
                
                # Self-terminate engine process to free port 8075
                def _self_terminate_darwin():
                    time.sleep(1.5)
                    os._exit(0)
                threading.Thread(target=_self_terminate_darwin, daemon=True).start()
                
            elif self.os_type == "Windows":
                script_path = os.path.join(temp_dir, "dicty_updater.bat")
                from local_whisper import PID_FILE as ws_pid_file_win
                with open(script_path, "w") as f:
                    f.write(f'''@echo off
set "LOGFILE=%TEMP%\\dicty_update.log"
call :main >> "%LOGFILE%" 2>&1
(goto) 2>nul & del "%~f0"
exit /b

:main
echo ===================================================
echo [*] Dicty Windows Update started at %DATE% %TIME%
echo [*] Installer: {download_path}
echo [*] Waiting 2 seconds for engine to initiate shutdown...
ping 127.0.0.1 -n 3 > nul

echo [*] Terminating any remaining Dicty processes...
:: Do NOT use /T to prevent terminating updater or unrelated child processes
taskkill /F /IM "dicty-client-tauri.exe" >nul 2>&1
taskkill /F /IM "Dicty.exe" >nul 2>&1
taskkill /F /IM "dicty_engine.exe" >nul 2>&1
for /f %%p in ('type "{ws_pid_file_win}" 2^>nul') do taskkill /F /PID %%p >nul 2>&1
ping 127.0.0.1 -n 2 > nul

echo [*] Launching installer in passive update mode...
start /wait "" "{download_path}" /P /UPDATE
set "INSTALL_EXIT=%ERRORLEVEL%"
echo [*] Installer exited with code %INSTALL_EXIT%

if "%INSTALL_EXIT%"=="0" (
    echo [+] Update installation completed successfully.
    echo [*] Cleaning up installer...
    del /f /q "{download_path}" >nul 2>&1
    ping 127.0.0.1 -n 2 > nul
    echo [*] Relaunching Dicty...
    if exist "%LOCALAPPDATA%\\Dicty\\dicty-client-tauri.exe" (
        start "" "%LOCALAPPDATA%\\Dicty\\dicty-client-tauri.exe"
        echo [+] Launched %LOCALAPPDATA%\\Dicty\\dicty-client-tauri.exe
    ) else if exist "%LOCALAPPDATA%\\Dicty\\Dicty.exe" (
        start "" "%LOCALAPPDATA%\\Dicty\\Dicty.exe"
        echo [+] Launched %LOCALAPPDATA%\\Dicty\\Dicty.exe
    ) else if exist "%LOCALAPPDATA%\\Programs\\Dicty\\dicty-client-tauri.exe" (
        start "" "%LOCALAPPDATA%\\Programs\\Dicty\\dicty-client-tauri.exe"
        echo [+] Launched %LOCALAPPDATA%\\Programs\\Dicty\\dicty-client-tauri.exe
    ) else if exist "%LOCALAPPDATA%\\Programs\\Dicty\\Dicty.exe" (
        start "" "%LOCALAPPDATA%\\Programs\\Dicty\\Dicty.exe"
        echo [+] Launched %LOCALAPPDATA%\\Programs\\Dicty\\Dicty.exe
    ) else if exist "%ProgramFiles%\\Dicty\\dicty-client-tauri.exe" (
        start "" "%ProgramFiles%\\Dicty\\dicty-client-tauri.exe"
        echo [+] Launched %ProgramFiles%\\Dicty\\dicty-client-tauri.exe
    ) else if exist "%ProgramFiles%\\Dicty\\Dicty.exe" (
        start "" "%ProgramFiles%\\Dicty\\Dicty.exe"
        echo [+] Launched %ProgramFiles%\\Dicty\\Dicty.exe
    ) else (
        echo [-] Error: Dicty executable not found to relaunch!
    )
) else (
    echo [-] Error: Installer failed with code %INSTALL_EXIT%. Leaving installer at {download_path} for inspection.
)
exit /b
''')
                kwargs = {}
                if sys.platform == "win32":
                    # DETACHED_PROCESS (0x8) | CREATE_NEW_PROCESS_GROUP (0x200)
                    kwargs["creationflags"] = 0x00000008 | 0x00000200
                    kwargs["close_fds"] = True
                subprocess.Popen(["cmd.exe", "/c", script_path], **kwargs)

                # Schedule current process self-termination to release file locks
                def _self_terminate():
                    time.sleep(1.5)
                    os._exit(0)

                threading.Thread(target=_self_terminate, daemon=True).start()
                
            return True
        except Exception as e:
            print(f"[!] Update execution failed: {e}")
            self.last_error = str(e)
            return False
        finally:
            self.is_updating = False
