# Dicty Web Dev Launcher (PowerShell)

if (Test-Path "$env:USERPROFILE\.cargo\bin") {
    $env:PATH = "$env:USERPROFILE\.cargo\bin;" + $env:PATH
}
if (Test-Path "C:\Program Files\nodejs") {
    $env:PATH = "C:\Program Files\nodejs;" + $env:PATH
}

Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "          Dicty Web Browser Development Launcher       " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan

# Check if environment is set up
$venvPython = Join-Path $PSScriptRoot ".venv\Scripts\python.exe"
if (-not (Test-Path $venvPython)) {
    Write-Host "[!] Virtual environment not found. Running automated setup..." -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot "setup_windows.ps1")
}

$tauriModules = Join-Path $PSScriptRoot "DictyClientTauri\node_modules"
if (-not (Test-Path $tauriModules)) {
    Write-Host "[!] Frontend dependencies not found. Installing..." -ForegroundColor Yellow
    Push-Location (Join-Path $PSScriptRoot "DictyClientTauri")
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
    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "Set-Location '$PSScriptRoot'; `$env:PYTHONIOENCODING='utf-8'; .\.venv\Scripts\python.exe dicty_engine.py"
    Start-Sleep -Seconds 3
} else {
    Write-Host "[*] Python backend is already active on http://127.0.0.1:8075." -ForegroundColor Green
}

# 2. Launch Vite Dev Server and open browser
Write-Host "[*] Launching Vite Dev Server at http://localhost:1420..." -ForegroundColor Green
Set-Location "$PSScriptRoot\DictyClientTauri"
Start-Process "http://localhost:1420"
npm run dev
