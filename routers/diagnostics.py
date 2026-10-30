from fastapi import APIRouter
import json
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import zipfile
from fastapi.responses import FileResponse
from fastapi import HTTPException
from datetime import datetime
from services.paths import get_downloads_dir, get_log_dir
from services.stores import history_manager

router = APIRouter()


@router.get("/diagnostics/export")
async def export_diagnostics():
    """
    Compresses engine logs, telemetry.jsonl, system metadata, and diagnostics into a timestamped zip archive.
    Saves a copy directly to the user's Downloads directory and returns the zip FileResponse.
    """
    zip_name = f"Dicty_Diagnostics_{datetime.now().strftime('%Y%m%d_%H%M%S')}.zip"
    temp_zip_path = os.path.join(tempfile.gettempdir(), zip_name)

    # Gather candidate log directories across OSes
    log_dirs = [get_log_dir()]
    if platform.system() == "Darwin":
        alt_log = os.path.expanduser("~/Library/Logs/Dicty")
        if alt_log not in log_dirs:
            log_dirs.append(alt_log)
    elif platform.system() == "Windows":
        alt_log = os.path.expanduser("~/.dicty/logs")
        if alt_log not in log_dirs:
            log_dirs.append(alt_log)
        alt_win = os.path.expanduser("~/Library/Logs/Dicty")
        if os.path.exists(alt_win) and alt_win not in log_dirs:
            log_dirs.append(alt_win)

    # Generate system_info.json
    try:
        from model_manager import MODELS_DIR
        installed_models = os.listdir(MODELS_DIR) if os.path.exists(MODELS_DIR) else []
    except Exception:
        installed_models = []

    sys_info = {
        "timestamp": datetime.now().isoformat(),
        "platform": platform.system(),
        "platform_release": platform.release(),
        "platform_version": platform.version(),
        "architecture": platform.machine(),
        "python_version": sys.version,
        "active_model": active_model_id,
        "installed_models": installed_models,
        "server_port": 8075,
    }

    try:
        with zipfile.ZipFile(temp_zip_path, 'w', zipfile.ZIP_DEFLATED) as zipf:
            # Write system_info.json
            zipf.writestr("system_info.json", json.dumps(sys_info, indent=2))

            # Add all log files from candidate log dirs
            added_files = set()
            for ldir in log_dirs:
                if os.path.exists(ldir):
                    for root, _, files in os.walk(ldir):
                        for file in files:
                            file_path = os.path.join(root, file)
                            arcname = os.path.relpath(file_path, ldir)
                            if arcname not in added_files:
                                zipf.write(file_path, arcname=f"logs/{arcname}")
                                added_files.add(arcname)

            # Check for history database / summary
            try:
                hist_records = history_manager.get_all()
                hist_summary = {
                    "total_records": len(hist_records),
                    "retention_settings": history_manager.get_retention_settings()
                }
                zipf.writestr("history_summary.json", json.dumps(hist_summary, indent=2))
            except Exception:
                pass
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to create diagnostic zip: {e}")

    # Copy directly to Downloads folder on user machine
    try:
        downloads_dir = get_downloads_dir()
        if os.path.exists(downloads_dir):
            dest_file = os.path.join(downloads_dir, zip_name)
            shutil.copyfile(temp_zip_path, dest_file)
            print(f"[*] Diagnostics successfully exported to Downloads: {dest_file}")
            # Try revealing in Explorer / Finder
            try:
                if platform.system() == "Windows":
                    subprocess.Popen(["explorer", f'/select,{os.path.normpath(dest_file)}'])
                elif platform.system() == "Darwin":
                    subprocess.Popen(["open", "-R", dest_file])
            except Exception:
                pass
    except Exception as copy_err:
        print(f"[!] Warning: Could not save direct copy to Downloads: {copy_err}")

    return FileResponse(
        temp_zip_path,
        media_type="application/zip",
        filename=zip_name,
        headers={
            "Content-Disposition": f'attachment; filename="{zip_name}"',
            "Access-Control-Expose-Headers": "Content-Disposition"
        }
    )
