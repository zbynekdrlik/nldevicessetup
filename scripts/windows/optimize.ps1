# NL Devices Setup - Windows Optimization Script
# DEPRECATED: This script redirects to setup.ps1 which includes all optimizations
#
# Use instead:
#   irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex

Write-Host "[INFO] This script has been merged into setup.ps1" -ForegroundColor Yellow
Write-Host "[INFO] Running setup.ps1 instead..." -ForegroundColor Cyan
Write-Host ""

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$SetupScript = Join-Path $ScriptDir 'setup.ps1'

if (Test-Path $SetupScript) {
    & $SetupScript @args
}
else {
    Write-Host "[ERROR] setup.ps1 not found at: $SetupScript" -ForegroundColor Red
    Write-Host "[INFO] Run instead: irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex" -ForegroundColor Cyan
    exit 1
}
