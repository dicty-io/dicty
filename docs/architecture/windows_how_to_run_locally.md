# How to Install and Run Dicty on Windows

There are two primary ways to run Dicty on Windows:
1. **As an End-User** (Standalone packaged installer — zero setup required)
2. **As a Developer** (Running from source with live reload)

---

## 1. End-User Installation (Standalone Installer)

If you just want to use Dicty on your Windows PC:
- Download the official setup executable `Dicty_<version>_x64-setup.exe` from [Releases](https://github.com/dicty-io/dicty/releases).
- Run the installer. It installs Dicty to your local user directory (`%LOCALAPPDATA%\Programs\Dicty`).
- **Zero prerequisites**: The installer bundles the standalone Python backend engine (`dicty_engine.exe`), faster-whisper, and NVIDIA GPU CUDA acceleration libraries. You do **not** need Python, Node.js, or Rust installed.
- Launch Dicty via the Desktop shortcut or Start Menu.

---

## 2. Developer / Running from Source

If you cloned this repository and want to run or modify Dicty locally:

### Step 1: Automatic Environment Setup (One-Click)
Run the automated setup script to configure Python virtual environment, install backend dependencies, and install frontend packages:

**Using Command Prompt:**
```cmd
setup_windows.bat
:: or from scripts directory:
scripts\windows\setup_windows.bat
```
*Or using PowerShell:*
```powershell
.\setup_windows.ps1
# or from scripts directory:
.\scripts\windows\setup_windows.ps1
```

This script:
1. Detects compatible Python (3.10 - 3.13).
2. Creates `.venv` at repository root and upgrades pip tooling.
3. Installs backend dependencies from `requirements-windows.txt`.
4. Installs frontend dependencies in `DictyClientTauri` via `npm install`.
5. Checks NVIDIA GPU CUDA acceleration status.

---

### Step 2: Run in Development Mode

You have two workflows to run Dicty in development:

#### Option A: Native Desktop App (Requires Rust Toolchain)
Runs the desktop window with hot-module reloading (HMR):
```cmd
run_dev.bat
:: or
scripts\windows\run_dev.bat
```
*Or in PowerShell:*
```powershell
.\run_dev.ps1
# or
.\scripts\windows\run_dev.ps1
```
*(If `.venv` or `node_modules` is missing, it will automatically run setup first).*

#### Option B: Browser Web UI (No Rust Required!)
If you do not have Rust or Cargo installed, you can develop and use the entire UI in your web browser:
```cmd
run_dev_web.bat
:: or
scripts\windows\run_dev_web.bat
```
*Or in PowerShell:*
```powershell
.\run_dev_web.ps1
# or
.\scripts\windows\run_dev_web.ps1
```
- Starts the Python backend engine on `http://127.0.0.1:8075`.
- Starts the Vite frontend on `http://localhost:1420` and opens it in your default browser.

---

## 3. Building the Production Installer Locally

To package a standalone Windows installer (`.exe`) identical to release builds:
```cmd
package_windows.bat
:: or
scripts\windows\package_windows.bat
```
The output installer will be created at:
`DictyClientTauri\src-tauri\target\release\bundle\nsis\Dicty_<version>_x64-setup.exe`
