@echo off
setlocal enabledelayedexpansion

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"

:: Ensure Node.js is in PATH
if exist "C:\Program Files\nodejs" set "PATH=C:\Program Files\nodejs;%PATH%"

echo =======================================================
echo          Dicty Web Browser Development Launcher
echo =======================================================
echo [*] Repository root: %REPO_ROOT%

:: Check if environment is set up
if not exist "%REPO_ROOT%\.venv\Scripts\python.exe" (
    echo [!] Python virtual environment not found. Running automated setup...
    call "%~dp0setup_windows.bat"
    if %ERRORLEVEL% NEQ 0 (
        echo [-] Setup failed! Please resolve errors above.
        pause
        exit /b 1
    )
)

if not exist "%REPO_ROOT%\DictyClientTauri\node_modules" (
    echo [!] Node modules not found. Installing frontend dependencies...
    cd /d "%REPO_ROOT%\DictyClientTauri"
    call npm install
    cd /d "%REPO_ROOT%"
)

:: Check if Python backend is already running on port 8075
netstat -ano | findstr :8075 | findstr LISTENING >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [*] Starting Python backend engine on port 8075...
    start "Dicty Backend Engine (:8075)" cmd /k "cd /d "%REPO_ROOT%" && chcp 65001 >nul && set PYTHONIOENCODING=utf-8 && .\.venv\Scripts\python.exe dicty_engine.py"
    echo [*] Waiting 3 seconds for backend to initialize...
    timeout /t 3 /nobreak >nul
) else (
    echo [*] Python backend is already running on port 8075.
)

echo [*] Starting Vite Frontend Server (http://localhost:1420)...
cd /d "%REPO_ROOT%\DictyClientTauri"
start http://localhost:1420
call npm run dev
