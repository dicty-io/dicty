import sys
import json
import re
import os

def update_version(version_str: str):
    v = version_str.lstrip("vV").strip()
    if not v:
        print("[-] Error: Empty version string provided.")
        sys.exit(1)
        
    print(f"[*] Updating project version to: {v}")
    
    # 1. Update tauri.conf.json
    tauri_path = os.path.join("DictyClientTauri", "src-tauri", "tauri.conf.json")
    if os.path.exists(tauri_path):
        with open(tauri_path, "r", encoding="utf-8") as f:
            data = json.load(f)
        data["version"] = v
        with open(tauri_path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        print(f"[+] Successfully updated {tauri_path} (clean UTF-8 without BOM)")

    # 2. Update package.json
    pkg_path = os.path.join("DictyClientTauri", "package.json")
    if os.path.exists(pkg_path):
        with open(pkg_path, "r", encoding="utf-8") as f:
            pkg = json.load(f)
        pkg["version"] = v
        with open(pkg_path, "w", encoding="utf-8", newline="\n") as f:
            json.dump(pkg, f, indent=2)
            f.write("\n")
        print(f"[+] Successfully updated {pkg_path}")

    # 3. Update Cargo.toml
    cargo_path = os.path.join("DictyClientTauri", "src-tauri", "Cargo.toml")
    if os.path.exists(cargo_path):
        with open(cargo_path, "r", encoding="utf-8") as f:
            cargo = f.read()
        cargo_updated = re.sub(r'version = "[^"]+"', f'version = "{v}"', cargo, count=1)
        with open(cargo_path, "w", encoding="utf-8", newline="\n") as f:
            f.write(cargo_updated)
        print(f"[+] Successfully updated {cargo_path}")

if __name__ == "__main__":
    version = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("VERSION", "")
    update_version(version)
