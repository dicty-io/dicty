& (Join-Path $PSScriptRoot "scripts\windows\setup_windows.ps1") @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

