# Dicty Windows Environment Setup Script (PowerShell)
$ErrorActionPreference = "Stop"

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "          Dicty Windows Environment Setup Script        " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Detect Python (3.10 - 3.13)
$pythonCmd = $null

$candidates = @("py -3.12", "py -3.11", "py -3.10", "python")
foreach ($cand in $candidates) {
    try {
        $parts = $cand -split " "
        $exe = $parts[0]
        $args = if ($parts.Length -gt 1) { $parts[1..($parts.Length - 1)] + @("--version") } else { @("--version") }
        $ver = & $exe $args 2>$null
        if ($LASTEXITCODE -eq 0 -and $ver) {
            $pythonCmd = $cand
            break
        }
    } catch {}
}

if (-not $pythonCmd) {
    Write-Host "[-] ERROR: Python 3.10 - 3.13 was not found!" -ForegroundColor Red
    Write-Host "    Please install Python from https://www.python.org/downloads/" -ForegroundColor Red
    exit 1
}

Write-Host "[*] Using Python interpreter: $pythonCmd" -ForegroundColor Green
$parts = $pythonCmd -split " "
$exe = $parts[0]
$args = if ($parts.Length -gt 1) { $parts[1..($parts.Length - 1)] + @("--version") } else { @("--version") }
& $exe $args

# 2. Setup .venv
$venvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
$venvPip = Join-Path $PSScriptRoot ".venv\Scripts\pip.exe"

$recreateVenv = $false
if (Test-Path $venvPython) {
    try {
        & $venvPython -c "import sys; sys.exit(0 if (3, 10) <= sys.version_info[:2] < (3, 14) else 1)"
        if ($LASTEXITCODE -ne 0) { $recreateVenv = $true }
    } catch {
        $recreateVenv = $true
    }
} else {
    $recreateVenv = $true
}

if ($recreateVenv) {
    if (Test-Path (Join-Path $PSScriptRoot ".venv")) {
        Write-Host "[!] Existing .venv has an incompatible Python version. Recreating with $pythonCmd..." -ForegroundColor Yellow
        Remove-Item -Recurse -Force (Join-Path $PSScriptRoot ".venv")
    }
    Write-Host "[*] Creating virtual environment at .\.venv ..." -ForegroundColor Yellow
    $args = if ($parts.Length -gt 1) { $parts[1..($parts.Length - 1)] + @("-m", "venv", ".venv") } else { @("-m", "venv", ".venv") }
    & $exe $args
    Write-Host "[+] Virtual environment created." -ForegroundColor Green
} else {
    Write-Host "[*] Compatible virtual environment found at .\.venv." -ForegroundColor Green
}

# 3. Upgrade pip & tools
Write-Host "[*] Upgrading pip, setuptools, and wheel..." -ForegroundColor Yellow
& $venvPython -m pip install --upgrade pip setuptools wheel --quiet

# 4. Install backend dependencies
Write-Host "[*] Installing dependencies from requirements-windows.txt..." -ForegroundColor Yellow
& $venvPip install -r (Join-Path $PSScriptRoot "requirements-windows.txt")
Write-Host "[+] Python dependencies installed." -ForegroundColor Green

# 5. Node.js & npm
if (Test-Path "C:\Program Files\nodejs") {
    $env:PATH = "C:\Program Files\nodejs;" + $env:PATH
}
if (Test-Path "$env:USERPROFILE\.cargo\bin") {
    $env:PATH = "$env:USERPROFILE\.cargo\bin;" + $env:PATH
}

if (Get-Command node -ErrorAction SilentlyContinue) {
    Write-Host "[*] Node.js version: $(node -v)" -ForegroundColor Green
    Write-Host "[*] Installing frontend dependencies in DictyClientTauri..." -ForegroundColor Yellow
    Push-Location (Join-Path $PSScriptRoot "DictyClientTauri")
    npm install
    Pop-Location
    Write-Host "[+] Frontend dependencies installed." -ForegroundColor Green
} else {
    Write-Host "[!] Node.js not found in PATH. To run frontend or build app, install Node.js: https://nodejs.org/" -ForegroundColor Yellow
}

# 6. Validate GPU acceleration
Write-Host ""
Write-Host "[*] Validating engine environment and GPU acceleration..." -ForegroundColor Yellow
& $venvPython -c @"
import ctranslate2
devs = ctranslate2.get_cuda_device_count()
status = f'ENABLED (Devices: {devs})' if devs > 0 else 'CPU Only (No CUDA detected)'
print(f'[+] ctranslate2 CUDA acceleration: {status}')
import fastapi, faster_whisper, onnxruntime
print('[+] Core modules loaded: FastAPI, Faster-Whisper, ONNXRuntime OK')
"@

Write-Host ""
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "          [+] Dicty Setup Completed Successfully!       " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Next steps:"
Write-Host "  1. Run native desktop app: .\run_dev.ps1"
Write-Host "  2. Run browser UI (no Rust needed): .\run_dev_web.ps1"
Write-Host "  3. Build standalone installer: .\package_windows.bat"
Write-Host "=======================================================" -ForegroundColor Cyan
