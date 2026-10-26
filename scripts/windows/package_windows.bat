@echo off
setlocal enabledelayedexpansion

echo =======================================================
echo        Dicty Windows Production Installer Packager
echo =======================================================

:: 1. Verify Node.js, Rust/Cargo, and Python are available
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [-] Node.js not found in PATH. Please install Node.js.
    exit /b 1
)

where cargo >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [-] Cargo/Rust not found in PATH. Please install Rust.
    exit /b 1
)

if not exist ".venv\Scripts\python.exe" (
    echo [-] Python virtual environment .venv not found at .\.venv\
    exit /b 1
)

:: 2. Package standalone Python backend via PyInstaller
echo [*] Step 1/3: Building standalone Python engine (PyInstaller)...
call scripts\windows\build_win.bat
if %ERRORLEVEL% NEQ 0 (
    echo [-] Backend packaging failed!
    exit /b 1
)

:: 3. Stage standalone Python backend into Tauri resources
echo [*] Staging standalone engine into Tauri resources...
if not exist "%~dp0DictyClientTauri\src-tauri\resources" mkdir "%~dp0DictyClientTauri\src-tauri\resources"
if exist "%~dp0DictyClientTauri\src-tauri\resources\dicty_engine" rmdir /s /q "%~dp0DictyClientTauri\src-tauri\resources\dicty_engine"
xcopy /E /I /Y "%~dp0dist\dicty_engine" "%~dp0DictyClientTauri\src-tauri\resources\dicty_engine"

:: 4. Build frontend web bundle
echo [*] Step 2/3: Building frontend web assets...
cd /d "%~dp0DictyClientTauri"
call npm run build
if %ERRORLEVEL% NEQ 0 (
    echo [-] Frontend build failed!
    cd /d "%~dp0"
    exit /b 1
)

:: 4. Build native desktop installer via Tauri
echo [*] Step 3/3: Packaging Windows Native Installer (Tauri NSIS)...
call npm run tauri build
if %ERRORLEVEL% NEQ 0 (
    echo [-] Tauri release build failed!
    cd /d "%~dp0"
    exit /b 1
)

cd /d "%~dp0"
echo =======================================================
echo  [+] Windows Production Installer Packaging Complete!
echo  Installer output located in:
echo  DictyClientTauri\src-tauri\target\release\bundle\
echo =======================================================
