@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo            Starting Dicty in Dev Mode
echo ===================================================

:: Ensure user tools are in PATH
if exist "%USERPROFILE%\.cargo\bin" set "PATH=%USERPROFILE%\.cargo\bin;%PATH%"
if exist "C:\Program Files\nodejs" set "PATH=C:\Program Files\nodejs;%PATH%"

:: Check if environment is set up
if not exist "%~dp0.venv\Scripts\python.exe" (
    echo [!] Python virtual environment not found. Running automated setup...
    call "%~dp0setup_windows.bat"
    if %ERRORLEVEL% NEQ 0 (
        echo [-] Setup failed! Please resolve errors above.
        pause
        exit /b 1
    )
)

if not exist "%~dp0DictyClientTauri\node_modules" (
    echo [!] Node modules not found. Installing frontend dependencies...
    cd /d "%~dp0DictyClientTauri"
    call npm install
    cd /d "%~dp0"
)

echo [*] Cleaning up any previous Dicty background instances...
taskkill /F /IM "dicty_engine.exe" >nul 2>&1
taskkill /F /IM "dicty-client-tauri.exe" >nul 2>&1

echo [*] Starting Python Backend Engine (GPU CUDA) in dedicated window...
start "Dicty Backend Engine" cmd /k "cd /d "%~dp0" && chcp 65001 >nul && set PYTHONIOENCODING=utf-8 && .\.venv\Scripts\python.exe dicty_engine.py"

echo [*] Waiting 3 seconds for Python backend engine to bind port 8075...
timeout /t 3 /nobreak >nul

echo [*] Starting Tauri Client (Vite + Desktop App)...
cd /d "%~dp0DictyClientTauri"
call npm run tauri dev
