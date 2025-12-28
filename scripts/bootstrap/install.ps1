# NL Devices Setup - Windows Bootstrap
# Usage: irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex
#
# This bootstrap script downloads and executes the full setup script.
# It handles execution policy and runs everything in one command.

# Bypass execution policy for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

$ErrorActionPreference = 'Stop'

$SetupUrl = 'https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/windows/setup.ps1'

# Check if running as Administrator
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "[ERROR] This script must be run as Administrator!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run PowerShell as Administrator and try again:" -ForegroundColor Yellow
    Write-Host "  1. Right-click PowerShell" -ForegroundColor Gray
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Gray
    Write-Host "  3. Run: irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex" -ForegroundColor Gray
    Write-Host ""
    exit 1
}

Write-Host ""
Write-Host "[INFO] NL Devices Setup - Downloading and running setup..." -ForegroundColor Cyan
Write-Host ""

try {
    # Download and execute setup.ps1 directly
    $setupScript = Invoke-RestMethod -Uri $SetupUrl -UseBasicParsing
    Invoke-Expression $setupScript
}
catch {
    Write-Host "[ERROR] Failed to download or run setup script: $_" -ForegroundColor Red
    Write-Host ""
    Write-Host "Alternative: Download manually from:" -ForegroundColor Yellow
    Write-Host "  $SetupUrl" -ForegroundColor Gray
    exit 1
}
