@echo off
REM scripts\windows\compile_whisper.bat
REM Compiles whisper.cpp for Windows using CMake and MSVC with AVX2/CUDA support.

setlocal enabledelayedexpansion

for %%I in ("%~dp0..\..") do set "REPO_ROOT=%%~fI"
cd /d "%REPO_ROOT%"

REM 1. Resolve persistent runner cache directory
set "CACHE_DIR="
if defined RUNNER_CACHE_DIR (
    set "CACHE_DIR=%RUNNER_CACHE_DIR%\whisper"
) else if defined RUNNER_WORKSPACE (
    for %%I in ("%RUNNER_WORKSPACE%\..\..") do set "CACHE_DIR=%%~fI\_cache\whisper"
) else if exist "%USERPROFILE%\actions-runner" (
    set "CACHE_DIR=%USERPROFILE%\actions-runner\_cache\whisper"
) else (
    set "CACHE_DIR=%USERPROFILE%\.dicty_cache\whisper"
)

set "TARGET_RELEASE_DIR=bin\whisper.cpp\build\bin\Release"

REM 2. Check if pre-compiled binaries are already cached
if exist "%CACHE_DIR%\whisper-cli.exe" if exist "%CACHE_DIR%\whisper-server.exe" (
    echo [+] Reusing cached whisper.cpp binaries from: %CACHE_DIR%
    if not exist "%TARGET_RELEASE_DIR%" mkdir "%TARGET_RELEASE_DIR%"
    copy /Y "%CACHE_DIR%\whisper-cli.exe" "%TARGET_RELEASE_DIR%\" >nul
    copy /Y "%CACHE_DIR%\whisper-server.exe" "%TARGET_RELEASE_DIR%\" >nul
    echo [+] Restored whisper binaries from runner cache successfully!
    exit /b 0
)

echo [*] Precompiled whisper binaries not found in cache (%CACHE_DIR%). Starting compilation...
echo [*] Checking for CMake...
where cmake >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo [!] CMake not found in PATH. Checking virtual environment...
    if exist "%cd%\.venv\Scripts\cmake.exe" (
        set "CMAKE_BIN=%cd%\.venv\Scripts\cmake.exe"
    ) else (
        echo [!] Installing cmake via pip in .venv...
        "%cd%\.venv\Scripts\pip" install cmake
        set "CMAKE_BIN=%cd%\.venv\Scripts\cmake.exe"
    )
) else (
    set CMAKE_BIN=cmake
)

set WHISPER_DIR=bin\whisper.cpp

if not exist "%WHISPER_DIR%" (
    echo [*] Cloning whisper.cpp repository...
    if not exist bin mkdir bin
    git clone https://github.com/ggerganov/whisper.cpp "%WHISPER_DIR%"
)

set "ROOT_DIR=%cd%"
cd "%WHISPER_DIR%"
if exist build rmdir /s /q build

REM Detect CUDA Toolkit
where nvcc >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [+] NVIDIA CUDA compiler detected! Enabling CUDA GPU acceleration...
    "%CMAKE_BIN%" -B build -A x64 -DGGML_CUDA=ON -DWHISPER_BUILD_TESTS=OFF
) else (
    echo [*] CUDA not found. Compiling for CPU with AVX2 optimizations...
    "%CMAKE_BIN%" -B build -A x64 -DGGML_AVX2=ON -DWHISPER_BUILD_TESTS=OFF
)

echo [*] Building targets (whisper-cli, whisper-server) with Release configuration...
"%CMAKE_BIN%" --build build --config Release -j %NUMBER_OF_PROCESSORS%

if %ERRORLEVEL% NEQ 0 (
    echo [-] Error: Build failed!
    cd /d "%ROOT_DIR%"
    exit /b 1
)

echo [+] Compilation successful!
echo     Binaries are in: %WHISPER_DIR%\build\bin\Release\

REM Save to persistent runner cache
if not exist "%CACHE_DIR%" mkdir "%CACHE_DIR%"
copy /Y "build\bin\Release\whisper-cli.exe" "%CACHE_DIR%\" >nul
copy /Y "build\bin\Release\whisper-server.exe" "%CACHE_DIR%\" >nul
echo [+] Saved compiled whisper.cpp binaries to runner cache (%CACHE_DIR%)!

cd /d "%ROOT_DIR%"
