@echo off
setlocal enabledelayedexpansion

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"
set "VENV_DIR=%REPO_ROOT%\.venv"
set "VENV_PYTHON=%VENV_DIR%\Scripts\python.exe"
set "VENV_PIP=%VENV_DIR%\Scripts\pip.exe"
set "REQ_FILE=%REPO_ROOT%\requirements-windows.txt"
set "TAURI_DIR=%REPO_ROOT%\DictyClientTauri"

echo =======================================================
echo          Dicty Windows Environment Setup Script
echo =======================================================
echo [*] Repository root: %REPO_ROOT%
echo.

:: 1. Locate compatible Python (3.10 - 3.13 recommended)
set "PYTHON_EXE="

:: Check Python Launcher (py) for 3.12, 3.11, 3.10
py -3.12 --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PYTHON_EXE=py -3.12"
    goto :PYTHON_FOUND
)
py -3.11 --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PYTHON_EXE=py -3.11"
    goto :PYTHON_FOUND
)
py -3.10 --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PYTHON_EXE=py -3.10"
    goto :PYTHON_FOUND
)

:: Check default python in PATH
python --version >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set "PYTHON_EXE=python"
    goto :PYTHON_FOUND
)

echo [-] ERROR: Python 3.10 - 3.13 was not found!
echo     Please install Python 3.10, 3.11, or 3.12 from https://www.python.org/downloads/
echo     (Make sure to check "Add python.exe to PATH" during installation)
exit /b 1

:PYTHON_FOUND
echo [*] Using Python interpreter: %PYTHON_EXE%
%PYTHON_EXE% --version

:: 2. Setup Python Virtual Environment (.venv)
if not exist "%VENV_PYTHON%" goto :CREATE_VENV

"%VENV_PYTHON%" -c "import sys; sys.exit(0 if sys.version_info >= (3, 10) and sys.version_info < (3, 14) else 1)" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [*] Compatible virtual environment found at %VENV_DIR%.
    goto :VENV_READY
)

echo [!] Existing .venv is incompatible with required ML packages. Recreating with %PYTHON_EXE% ...
rmdir /s /q "%VENV_DIR%"

:CREATE_VENV
echo [*] Creating virtual environment at %VENV_DIR% ...
%PYTHON_EXE% -m venv "%VENV_DIR%"
if %ERRORLEVEL% NEQ 0 (
    echo [-] Failed to create virtual environment!
    exit /b 1
)
echo [+] Virtual environment created successfully.

:VENV_READY

:: 3. Upgrade pip and build tooling
echo [*] Upgrading pip, setuptools, and wheel...
"%VENV_PYTHON%" -m pip install --upgrade pip setuptools wheel --quiet

:: 4. Install backend dependencies
echo [*] Installing Windows backend dependencies from %REQ_FILE%...
"%VENV_PIP%" install -r "%REQ_FILE%"
if %ERRORLEVEL% NEQ 0 (
    echo [-] Failed to install Python dependencies! Please check error output above.
    exit /b 1
)
echo [+] Python dependencies installed successfully.

:: 5. Setup Node.js & npm for Frontend
echo.
echo [*] Checking Node.js environment...
if exist "C:\Program Files\nodejs" (
    set "PATH=C:\Program Files\nodejs;%PATH%"
)
where node >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] WARNING: Node.js was not found in PATH.
    echo     To run or develop the frontend UI, please install Node.js from https://nodejs.org/
) else (
    node --version
    echo [*] Installing frontend dependencies in %TAURI_DIR%...
    cd /d "%TAURI_DIR%"
    call npm install
    if %ERRORLEVEL% NEQ 0 (
        echo [-] npm install encountered errors!
    ) else (
        echo [+] Frontend dependencies installed successfully.
    )
    cd /d "%REPO_ROOT%"
)

:: 6. Validate Installation and GPU Acceleration
echo.
echo [*] Validating engine environment and GPU acceleration...
"%VENV_PYTHON%" -c "import ctranslate2; devs = ctranslate2.get_cuda_device_count(); print(f'[+] ctranslate2 CUDA acceleration: {\"ENABLED (Devices: \" + str(devs) + \")\" if devs > 0 else \"CPU Only (No CUDA detected)\"}'); import fastapi, faster_whisper, onnxruntime; print('[+] Core modules loaded: FastAPI, Faster-Whisper, ONNXRuntime OK')"
if %ERRORLEVEL% NEQ 0 (
    echo [!] Validation warning: some modules reported issues.
)

echo.
echo =======================================================
echo          [+] Dicty Setup Completed Successfully!
echo =======================================================
echo Next steps:
echo   1. Run in development mode (Native Window):
echo      scripts\windows\run_dev.bat (or run_dev.bat)
echo.
echo   2. Run in development mode (Browser UI, no Rust required):
echo      scripts\windows\run_dev_web.bat (or run_dev_web.bat)
echo.
echo   3. Build standalone production installer:
echo      scripts\windows\package_windows.bat (or package_windows.bat)
echo =======================================================
