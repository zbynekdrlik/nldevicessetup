# NL Devices Setup - Windows Bootstrap Installer
# Usage: irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1 | iex
#    or: & ([scriptblock]::Create((irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.ps1))) -Help

[CmdletBinding()]
param(
    [switch]$Help,
    [string]$Version = 'latest',
    [string]$InstallDir = "$env:ProgramFiles\nldevicessetup",
    [switch]$DryRun,
    [switch]$Optimize,
    [string]$Modules = 'all'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$RepoUrl = 'https://github.com/zbynekdrlik/nldevicessetup'
$RawUrl = 'https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main'

function Write-LogInfo { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-LogSuccess { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-LogWarn { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-LogError { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

function Show-Help {
    @"
NL Devices Setup - Windows Bootstrap Installer

Usage:
    irm $RawUrl/scripts/bootstrap/install.ps1 | iex
    & ([scriptblock]::Create((irm $RawUrl/scripts/bootstrap/install.ps1))) [OPTIONS]

Options:
    -Help           Show this help message
    -Version VER    Install specific version (default: latest)
    -InstallDir DIR Installation directory (default: %ProgramFiles%\nldevicessetup)
    -DryRun         Show what would be done without making changes
    -Optimize       Run optimization after installation
    -Modules MOD    Comma-separated list of modules to apply (default: all)

Modules:
    network         Network adapter and TCP/IP optimizations
    latency         Timer resolution and MMCSS tuning
    power           Power plan optimization
    services        Service optimization
    all             All modules (default)

Examples:
    # Install and optimize (run as Administrator)
    irm ... | iex; & "$env:ProgramFiles\nldevicessetup\scripts\windows\optimize.ps1"

    # Install with options
    & ([scriptblock]::Create((irm ...))) -Optimize -Modules network,latency

"@
}

function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LatestVersion {
    try {
        $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/zbynekdrlik/nldevicessetup/releases/latest' -UseBasicParsing
        return $release.tag_name
    }
    catch {
        return 'main'
    }
}

function Install-NLDevicesSetup {
    param(
        [string]$Version,
        [string]$InstallDir
    )

    Write-LogInfo "Installing nldevicessetup $Version to $InstallDir"

    # Check for git
    $gitPath = Get-Command git -ErrorAction SilentlyContinue

    if ($gitPath) {
        # Use git for installation
        if (Test-Path $InstallDir) {
            Write-LogWarn "Installation directory exists, updating..."
            Push-Location $InstallDir
            try {
                git fetch --all --tags
                if ($Version -eq 'latest' -or $Version -eq 'main') {
                    git checkout main
                    git pull origin main
                }
                else {
                    git checkout $Version
                }
            }
            finally {
                Pop-Location
            }
        }
        else {
            $null = New-Item -Path $InstallDir -ItemType Directory -Force
            if ($Version -eq 'latest' -or $Version -eq 'main') {
                git clone $RepoUrl $InstallDir
            }
            else {
                git clone --branch $Version $RepoUrl $InstallDir
            }
        }
    }
    else {
        # Download as ZIP
        Write-LogInfo "Git not found, downloading as ZIP archive..."

        $branch = if ($Version -eq 'latest' -or $Version -eq 'main') { 'main' } else { $Version }
        $zipUrl = "$RepoUrl/archive/refs/heads/$branch.zip"
        $tempZip = Join-Path $env:TEMP 'nldevicessetup.zip'
        $tempExtract = Join-Path $env:TEMP 'nldevicessetup-extract'

        try {
            Invoke-WebRequest -Uri $zipUrl -OutFile $tempZip -UseBasicParsing

            if (Test-Path $tempExtract) {
                Remove-Item $tempExtract -Recurse -Force
            }

            Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

            # Find extracted folder
            $extractedFolder = Get-ChildItem $tempExtract -Directory | Select-Object -First 1

            if (Test-Path $InstallDir) {
                Remove-Item $InstallDir -Recurse -Force
            }

            Move-Item $extractedFolder.FullName $InstallDir
        }
        finally {
            Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
            Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Add to PATH if not already there
    $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $scriptsPath = Join-Path $InstallDir 'scripts\windows'

    if ($machinePath -notlike "*$scriptsPath*") {
        if (Test-Administrator) {
            [Environment]::SetEnvironmentVariable('Path', "$machinePath;$scriptsPath", 'Machine')
            Write-LogInfo "Added $scriptsPath to system PATH"
        }
        else {
            Write-LogWarn "Run as Administrator to add to system PATH"
        }
    }

    Write-LogSuccess "Installation complete!"
}

function Invoke-Optimization {
    param(
        [string]$InstallDir,
        [string]$Modules,
        [bool]$DryRun
    )

    Write-LogInfo "Running optimization (modules: $Modules, dry-run: $DryRun)"

    $optimizeScript = Join-Path $InstallDir 'scripts\windows\optimize.ps1'

    if (-not (Test-Path $optimizeScript)) {
        Write-LogError "Optimization script not found: $optimizeScript"
        exit 1
    }

    if (-not (Test-Administrator)) {
        Write-LogError "Optimization requires Administrator privileges"
        Write-LogInfo "Please run this script as Administrator"
        exit 1
    }

    $params = @{}
    if ($DryRun) { $params['DryRun'] = $true }
    if ($Modules -ne 'all') { $params['Modules'] = $Modules }

    & $optimizeScript @params
}

function Main {
    Write-Host ""
    Write-Host "  _   _ _     ____             _                 ____       _               " -ForegroundColor Cyan
    Write-Host " | \ | | |   |  _ \  _____   _(_) ___ ___  ___  / ___|  ___| |_ _   _ _ __  " -ForegroundColor Cyan
    Write-Host " |  \| | |   | | | |/ _ \ \ / / |/ __/ _ \/ __| \___ \ / _ \ __| | | | '_ \ " -ForegroundColor Cyan
    Write-Host " | |\  | |___| |_| |  __/\ V /| | (_|  __/\__ \  ___) |  __/ |_| |_| | |_) |" -ForegroundColor Cyan
    Write-Host " |_| \_|_____|____/ \___| \_/ |_|\___\___||___/ |____/ \___|\__|\__,_| .__/ " -ForegroundColor Cyan
    Write-Host "                                                                     |_|    " -ForegroundColor Cyan
    Write-Host ""

    if ($Help) {
        Show-Help
        return
    }

    if ($Version -eq 'latest') {
        $Version = Get-LatestVersion
        Write-LogInfo "Latest version: $Version"
    }

    if ($DryRun) {
        Write-LogInfo "[DRY-RUN] Would install to: $InstallDir"
        Write-LogInfo "[DRY-RUN] Version: $Version"
        if ($Optimize) {
            Write-LogInfo "[DRY-RUN] Would run optimization with modules: $Modules"
        }
        return
    }

    Install-NLDevicesSetup -Version $Version -InstallDir $InstallDir

    if ($Optimize) {
        Invoke-Optimization -InstallDir $InstallDir -Modules $Modules -DryRun $DryRun
    }
    else {
        Write-LogInfo ""
        Write-LogInfo "To run optimization (as Administrator):"
        Write-LogInfo "  & '$InstallDir\scripts\windows\optimize.ps1'"
        Write-LogInfo ""
    }
}

Main
