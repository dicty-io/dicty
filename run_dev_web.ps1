& (Join-Path $PSScriptRoot "scripts\windows\run_dev_web.ps1") @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

