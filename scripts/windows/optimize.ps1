# NL Devices Setup - Windows Optimization Script
# Applies low-latency and network optimizations

[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$DryRun,
    [string]$Modules = 'all',
    [switch]$ListModules,
    [switch]$Rollback
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibDir = Join-Path (Split-Path -Parent $ScriptDir) 'lib'
$ModulesDir = Join-Path $ScriptDir 'modules'

# Import common functions
. (Join-Path $LibDir 'common.ps1')

function Show-Help {
    @"
NL Devices Setup - Windows Optimization

Usage: .\optimize.ps1 [OPTIONS]

Options:
    -Help           Show this help message
    -DryRun         Show what would be done without making changes
    -Modules MOD    Comma-separated list of modules (default: all)
    -ListModules    List available modules
    -Rollback       Rollback to pre-optimization state

Available Modules:
    network     Network adapter and TCP/IP optimizations
    latency     Timer resolution and MMCSS tuning
    power       Power plan optimization
    services    Service optimization
    all         Apply all modules

Examples:
    .\optimize.ps1                       # Apply all optimizations
    .\optimize.ps1 -Modules network,latency  # Apply specific modules
    .\optimize.ps1 -DryRun               # Preview changes
"@
}

function Get-AvailableModules {
    Get-ChildItem -Path $ModulesDir -Filter '*.ps1' -ErrorAction SilentlyContinue | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $desc = if ($content -match '# Description:\s*(.+)') { $Matches[1] } else { 'No description' }
        [PSCustomObject]@{
            Name = $_.BaseName
            Description = $desc
        }
    }
}

function Apply-NetworkOptimizations {
    Write-LogInfo "Applying network optimizations..."

    # Disable Nagle's Algorithm for all interfaces
    $tcpParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-RegistryValueIdempotent -Path $tcpParams -Name 'TcpAckFrequency' -Value 1 -Type DWord
    Set-RegistryValueIdempotent -Path $tcpParams -Name 'TCPNoDelay' -Value 1 -Type DWord

    # Optimize TCP settings
    Set-RegistryValueIdempotent -Path $tcpParams -Name 'TcpDelAckTicks' -Value 0 -Type DWord
    Set-RegistryValueIdempotent -Path $tcpParams -Name 'DefaultTTL' -Value 64 -Type DWord

    # Network adapter optimizations
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }

    foreach ($adapter in $adapters) {
        Write-LogInfo "Configuring adapter: $($adapter.Name)"

        # Disable interrupt moderation where supported
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*InterruptModeration' -RegistryValue 0 -ErrorAction SilentlyContinue
        }
        catch {
            Write-LogWarn "Could not disable interrupt moderation on $($adapter.Name)"
        }

        # Disable Large Send Offload (can increase latency)
        try {
            Disable-NetAdapterLso -Name $adapter.Name -ErrorAction SilentlyContinue
        }
        catch {
            Write-LogWarn "Could not disable LSO on $($adapter.Name)"
        }
    }

    Write-LogSuccess "Network optimizations applied"
}

function Apply-LatencyOptimizations {
    Write-LogInfo "Applying latency optimizations..."

    # MMCSS (Multimedia Class Scheduler Service) optimization
    $mmcssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-RegistryValueIdempotent -Path $mmcssPath -Name 'SystemResponsiveness' -Value 0 -Type DWord
    Set-RegistryValueIdempotent -Path $mmcssPath -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF -Type DWord

    # Audio priority
    $audioPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Audio'
    if (-not (Test-Path $audioPath)) {
        $null = New-Item -Path $audioPath -Force
    }
    Set-RegistryValueIdempotent -Path $audioPath -Name 'Affinity' -Value 0 -Type DWord
    Set-RegistryValueIdempotent -Path $audioPath -Name 'Background Only' -Value 'False' -Type String
    Set-RegistryValueIdempotent -Path $audioPath -Name 'Clock Rate' -Value 10000 -Type DWord
    Set-RegistryValueIdempotent -Path $audioPath -Name 'GPU Priority' -Value 8 -Type DWord
    Set-RegistryValueIdempotent -Path $audioPath -Name 'Priority' -Value 6 -Type DWord
    Set-RegistryValueIdempotent -Path $audioPath -Name 'Scheduling Category' -Value 'High' -Type String
    Set-RegistryValueIdempotent -Path $audioPath -Name 'SFIO Priority' -Value 'High' -Type String

    # Pro Audio task
    $proAudioPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile\Tasks\Pro Audio'
    if (-not (Test-Path $proAudioPath)) {
        $null = New-Item -Path $proAudioPath -Force
    }
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'Affinity' -Value 0 -Type DWord
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'Background Only' -Value 'False' -Type String
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'Clock Rate' -Value 10000 -Type DWord
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'GPU Priority' -Value 8 -Type DWord
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'Priority' -Value 6 -Type DWord
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'Scheduling Category' -Value 'High' -Type String
    Set-RegistryValueIdempotent -Path $proAudioPath -Name 'SFIO Priority' -Value 'High' -Type String

    # Disable dynamic tick (improves timer consistency)
    try {
        bcdedit /set disabledynamictick yes 2>$null
        Write-LogInfo "Disabled dynamic tick"
    }
    catch {
        Write-LogWarn "Could not disable dynamic tick"
    }

    # Set timer resolution to 1ms (requires reboot)
    $timerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
    Set-RegistryValueIdempotent -Path $timerPath -Name 'GlobalTimerResolutionRequests' -Value 1 -Type DWord

    Write-LogSuccess "Latency optimizations applied"
}

function Apply-PowerOptimizations {
    Write-LogInfo "Applying power optimizations..."

    # Set power plan to High Performance
    try {
        $highPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
        powercfg /setactive $highPerfGuid
        Write-LogSuccess "Power plan set to High Performance"
    }
    catch {
        Write-LogWarn "Could not set power plan"
    }

    # Disable USB selective suspend
    $usbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USB'
    Set-RegistryValueIdempotent -Path $usbPath -Name 'DisableSelectiveSuspend' -Value 1 -Type DWord

    # Disable PCI Express Link State Power Management
    $pciePath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerSettings\501a4d13-42af-4429-9fd1-a8218c268e20\ee12f906-d277-404b-b6da-e5fa1a576df5'
    Set-RegistryValueIdempotent -Path $pciePath -Name 'Attributes' -Value 2 -Type DWord

    Write-LogSuccess "Power optimizations applied"
}

function Show-Summary {
    Write-Host ""
    Write-LogSuccess "=== Optimization Complete ==="
    Write-Host ""
    Write-LogInfo "Most settings are applied immediately."
    Write-LogInfo "Some settings require a system restart to take effect."
    Write-Host ""
    Write-LogInfo "Recommended: Restart your computer for all changes to take effect."
    Write-Host ""
}

function Main {
    if ($Help) {
        Show-Help
        return
    }

    if ($ListModules) {
        Write-LogInfo "Available modules:"
        Get-AvailableModules | ForEach-Object {
            Write-Host ("  {0,-15} {1}" -f $_.Name, $_.Description)
        }
        return
    }

    if ($Rollback) {
        Write-LogError "Rollback not yet implemented"
        return
    }

    # Require Administrator
    Require-Administrator

    Write-LogInfo "NL Devices Setup - Windows Optimizer v$NLDEVICESSETUP_VERSION"
    Write-LogInfo "Mode: $(if ($DryRun) { 'DRY-RUN' } else { 'LIVE' })"
    Write-Host ""

    if ($DryRun) {
        $script:DRY_RUN = $true
    }

    # Backup registry before changes
    $backupDir = "$env:LOCALAPPDATA\nldevicessetup\backups"
    $null = New-Item -Path $backupDir -ItemType Directory -Force

    # Apply optimizations
    if ($Modules -eq 'all') {
        Apply-NetworkOptimizations
        Apply-LatencyOptimizations
        Apply-PowerOptimizations
    }
    else {
        $moduleList = $Modules -split ','
        foreach ($module in $moduleList) {
            switch ($module.Trim()) {
                'network' { Apply-NetworkOptimizations }
                'latency' { Apply-LatencyOptimizations }
                'power' { Apply-PowerOptimizations }
                default { Write-LogWarn "Unknown module: $module" }
            }
        }
    }

    if (-not $DryRun) {
        Show-Summary
    }
}

Main
