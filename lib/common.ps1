# Common functions for nldevicessetup Windows scripts
# PowerShell 5.1+ compatible

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Version
$script:NLDEVICESSETUP_VERSION = $env:NLDEVICESSETUP_VERSION ?? 'dev'

# Logging functions
function Write-LogInfo {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-LogSuccess {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-LogWarn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-LogError {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# Check if running as Administrator
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Require-Administrator {
    if (-not (Test-Administrator)) {
        Write-LogError "This script must be run as Administrator"
        exit 1
    }
}

# Backup registry key before modification
function Backup-RegistryKey {
    param(
        [Parameter(Mandatory)]
        [string]$KeyPath,
        [string]$BackupDir = "$env:LOCALAPPDATA\nldevicessetup\backups"
    )

    if (Test-Path "Registry::$KeyPath") {
        $null = New-Item -Path $BackupDir -ItemType Directory -Force
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $safeName = $KeyPath -replace '[:\\]', '_'
        $backupFile = Join-Path $BackupDir "${safeName}_${timestamp}.reg"

        reg export $KeyPath $backupFile /y 2>$null
        Write-LogInfo "Backed up $KeyPath to $backupFile"
    }
}

# Set registry value idempotently
function Set-RegistryValueIdempotent {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Name,
        [Parameter(Mandatory)]
        $Value,
        [ValidateSet('String', 'ExpandString', 'Binary', 'DWord', 'QWord', 'MultiString')]
        [string]$Type = 'DWord'
    )

    # Ensure path exists
    if (-not (Test-Path $Path)) {
        $null = New-Item -Path $Path -Force
        Write-LogInfo "Created registry path: $Path"
    }

    # Check current value
    $current = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue

    if ($null -ne $current -and $current.$Name -eq $Value) {
        Write-LogInfo "Registry $Path\$Name already set to $Value"
        return $true
    }

    try {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
        Write-LogSuccess "Set registry $Path\$Name = $Value"
        return $true
    }
    catch {
        Write-LogError "Failed to set registry $Path\$Name : $_"
        return $false
    }
}

# Get Windows version info
function Get-WindowsVersionInfo {
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    return @{
        Version = $os.Version
        BuildNumber = $os.BuildNumber
        Caption = $os.Caption
    }
}

# Check if a Windows feature is enabled
function Test-WindowsFeature {
    param([string]$FeatureName)

    try {
        $feature = Get-WindowsOptionalFeature -Online -FeatureName $FeatureName -ErrorAction SilentlyContinue
        return $feature.State -eq 'Enabled'
    }
    catch {
        return $false
    }
}

# Dry run mode support
$script:DRY_RUN = $env:DRY_RUN -eq 'true'

function Invoke-CommandWithDryRun {
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,
        [string]$Description
    )

    if ($script:DRY_RUN) {
        Write-LogInfo "[DRY-RUN] Would execute: $Description"
        return $null
    }
    else {
        return & $ScriptBlock
    }
}

# Export functions only when running as a module (not when dot-sourced)
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    Export-ModuleMember -Function @(
        'Write-LogInfo',
        'Write-LogSuccess',
        'Write-LogWarn',
        'Write-LogError',
        'Test-Administrator',
        'Require-Administrator',
        'Backup-RegistryKey',
        'Set-RegistryValueIdempotent',
        'Get-WindowsVersionInfo',
        'Test-WindowsFeature',
        'Invoke-CommandWithDryRun'
    ) -Variable @(
        'NLDEVICESSETUP_VERSION',
        'DRY_RUN'
    )
}
