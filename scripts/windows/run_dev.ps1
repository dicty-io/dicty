# Dicty Development Launcher (PowerShell)

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$venvPython = Join-Path $RepoRoot ".venv\Scripts\python.exe"
$tauriDir = Join-Path $RepoRoot "DictyClientTauri"
$tauriModules = Join-Path $tauriDir "node_modules"

if (Test-Path "$env:USERPROFILE\.cargo\bin") {
    $env:PATH = "$env:USERPROFILE\.cargo\bin;" + $env:PATH
}
if (Test-Path "C:\Program Files\nodejs") {
    $env:PATH = "C:\Program Files\nodejs;" + $env:PATH
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "           Dicty Local Development Launcher            " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "[*] Repository root: $RepoRoot" -ForegroundColor Gray

# Check if environment is set up
if (-not (Test-Path $venvPython)) {
    Write-Host "[!] Virtual environment not found. Running automated setup..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "setup_windows.ps1")
}

if (-not (Test-Path $tauriModules)) {
    Write-Host "[!] Frontend dependencies not found. Installing..." -ForegroundColor Yellow
    Push-Location $tauriDir
    npm install
    Pop-Location
}

# 1. Check if backend is running on 8075
$backendRunning = $false
try {
    $res = Invoke-RestMethod -Uri "http://127.0.0.1:8075/recording/status" -TimeoutSec 1 -ErrorAction SilentlyContinue
    if ($res) { $backendRunning = $true }
} catch {}

if (-not $backendRunning) {
    Write-Host "[*] Launching Python backend engine on port 8075 in separate window..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "Set-Location '$RepoRoot'; `$env:PYTHONIOENCODING='utf-8'; .\.venv\Scripts\python.exe dicty_engine.py"
    Start-Sleep -Seconds 3
} else {
    Write-Host "[*] Python backend is already active on http://127.0.0.1:8075." -ForegroundColor Green
}

# 2. Launch Tauri Desktop Dev Server
Write-Host "[*] Launching Tauri Desktop Client (Hot-Reloading)..." -ForegroundColor Green
Set-Location $tauriDir
npm run tauri dev
