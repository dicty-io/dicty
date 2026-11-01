@echo off
setlocal enabledelayedexpansion

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"

echo =======================================================
echo        Dicty Windows Production Installer Packager
echo =======================================================
echo [*] Repository root: %REPO_ROOT%

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

if not exist "%REPO_ROOT%\.venv\Scripts\python.exe" (
    echo [-] Python virtual environment .venv not found at %REPO_ROOT%\.venv\
    exit /b 1
)

:: 2. Package standalone Python backend via PyInstaller
echo [*] Step 1/3: Building standalone Python engine (PyInstaller)...
cd /d "%REPO_ROOT%"
call "%~dp0build_win.bat"
if %ERRORLEVEL% NEQ 0 (
    echo [-] Backend packaging failed!
    exit /b 1
)

:: 3. Stage standalone Python backend into Tauri resources
echo [*] Staging standalone engine into Tauri resources...
if not exist "%REPO_ROOT%\DictyClientTauri\src-tauri\resources" mkdir "%REPO_ROOT%\DictyClientTauri\src-tauri\resources"
if exist "%REPO_ROOT%\DictyClientTauri\src-tauri\resources\dicty_engine" rmdir /s /q "%REPO_ROOT%\DictyClientTauri\src-tauri\resources\dicty_engine"
xcopy /E /I /Y "%REPO_ROOT%\dist\dicty_engine" "%REPO_ROOT%\DictyClientTauri\src-tauri\resources\dicty_engine"

:: 4. Build frontend web bundle
echo [*] Step 2/3: Building frontend web assets...
cd /d "%REPO_ROOT%\DictyClientTauri"
call npm run build
if %ERRORLEVEL% NEQ 0 (
    echo [-] Frontend build failed!
    cd /d "%REPO_ROOT%"
    exit /b 1
)

:: 5. Build native desktop installer via Tauri
echo [*] Step 3/3: Packaging Windows Native Installer (Tauri NSIS)...
call npm run tauri build
if %ERRORLEVEL% NEQ 0 (
    echo [-] Tauri release build failed!
    cd /d "%REPO_ROOT%"
    exit /b 1
)

cd /d "%REPO_ROOT%"
echo =======================================================
echo  [+] Windows Production Installer Packaging Complete!
echo  Installer output located in:
echo  DictyClientTauri\src-tauri\target\release\bundle\
echo =======================================================
