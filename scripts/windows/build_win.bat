@echo off
REM scripts\windows\build_win.bat
REM Packages the Dicty backend into a standalone Windows executable directory using PyInstaller.

setlocal enabledelayedexpansion

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"
cd /d "%REPO_ROOT%"

echo [*] Installing PyInstaller in virtual environment...
.venv\Scripts\pip install pyinstaller

echo [*] Checking for whisper.cpp native binaries...
if exist "%~dp0compile_whisper.bat" (
    call "%~dp0compile_whisper.bat"
)

echo [*] Cleaning previous build artifacts...
if exist build rmdir /s /q build
if exist dist rmdir /s /q dist

echo [*] Generating telemetry_config.json if not present...
if not exist telemetry_config.json (
    echo {} > telemetry_config.json
)

echo [*] Running PyInstaller packaging with dicty_engine.spec...
.venv\Scripts\pyinstaller --noconfirm dicty_engine.spec

if %ERRORLEVEL% NEQ 0 (
    echo [-] PyInstaller build failed!
    exit /b 1
)

echo [*] Staging backend bundle into DictyClientTauri resources...
if exist DictyClientTauri\src-tauri\resources\dicty_engine (
    rmdir /s /q DictyClientTauri\src-tauri\resources\dicty_engine
)
mkdir DictyClientTauri\src-tauri\resources\dicty_engine
xcopy /E /I /Y dist\dicty_engine DictyClientTauri\src-tauri\resources\dicty_engine >nul

if not exist DictyClientTauri\src-tauri\resources\dicty_engine\dicty_engine.exe (
    echo [-] Error: DictyClientTauri\src-tauri\resources\dicty_engine\dicty_engine.exe was not staged successfully!
    exit /b 1
)

echo [+] Build complete! Standalone Windows engine is located at: dist\dicty_engine\dicty_engine.exe
