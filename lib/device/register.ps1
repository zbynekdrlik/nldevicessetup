# Device registration script for nldevicessetup (Windows)
# Registers the local Windows machine

#Requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Profile = "base-workstation",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ""
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Resolve-Path "$ScriptDir/../..").Path

# Import common functions
. "$ProjectRoot/lib/common.ps1"

function Get-LocalSystemInfo {
    <#
    .SYNOPSIS
    Gather system information for the local machine
    #>

    $os = Get-CimInstance Win32_OperatingSystem
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $mem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 0)
    $nics = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' } | Select-Object -ExpandProperty Name

    return @{
        Hostname    = $env:COMPUTERNAME.ToLower()
        OS          = 'windows'
        OSVersion   = "$($os.Caption) $($os.Version)"
        CPU         = $cpu.Name
        MemoryGB    = $mem
        NICs        = $nics
    }
}

function Get-LocalIPAddress {
    <#
    .SYNOPSIS
    Get the primary local IP address
    #>

    $ip = Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.PrefixOrigin -ne 'WellKnown' } |
        Select-Object -First 1 -ExpandProperty IPAddress

    return $ip
}

function Register-LocalDevice {
    <#
    .SYNOPSIS
    Register the local Windows machine as a device
    #>
    param(
        [string]$DeviceProfile,
        [string]$OutputDirectory
    )

    Write-LogInfo "Registering local device..."

    # Gather system info
    $sysInfo = Get-LocalSystemInfo
    $hostname = $sysInfo.Hostname
    $ipAddress = Get-LocalIPAddress

    # Determine output directory
    if ([string]::IsNullOrEmpty($OutputDirectory)) {
        $deviceDir = Join-Path $ProjectRoot "devices" $hostname
    }
    else {
        $deviceDir = Join-Path $OutputDirectory $hostname
    }

    # Create directories
    $historyDir = Join-Path $deviceDir "history"
    $null = New-Item -ItemType Directory -Path $historyDir -Force

    # Generate timestamp
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    # Create device.yml content
    $deviceYaml = @"
# Device registration for $hostname
# Generated: $timestamp

hostname: $hostname
ip: $ipAddress
os: $($sysInfo.OS)
os_version: "$($sysInfo.OSVersion)"
profile: $DeviceProfile
tags:
  - production
  - local
ssh_user: $env:USERNAME
ssh_port: 22
registered: $timestamp
last_seen: $timestamp

hardware:
  cpu: "$($sysInfo.CPU)"
  memory_gb: $($sysInfo.MemoryGB)
  nics:
"@

    foreach ($nic in $sysInfo.NICs) {
        $deviceYaml += "`n    - $nic"
    }

    # Write device.yml
    $deviceFile = Join-Path $deviceDir "device.yml"
    Set-Content -Path $deviceFile -Value $deviceYaml -Encoding UTF8
    Write-LogSuccess "Created $deviceFile"

    # Create initial state.yml
    $stateYaml = @"
# Current state for $hostname
# Last updated: $timestamp

last_updated: $timestamp

software: {}

optimizations:
  network: {}
  power: {}
  audio: {}

applied_recipes: []
"@

    $stateFile = Join-Path $deviceDir "state.yml"
    Set-Content -Path $stateFile -Value $stateYaml -Encoding UTF8
    Write-LogSuccess "Created $stateFile"

    Write-LogSuccess "Device $hostname registered successfully"
    Write-LogInfo "  Device directory: $deviceDir"
    Write-LogInfo "  Profile: $DeviceProfile"
    Write-LogInfo "  OS: $($sysInfo.OS) ($($sysInfo.OSVersion))"

    return $deviceDir
}

function Get-RegisteredDevices {
    <#
    .SYNOPSIS
    List all registered devices
    #>

    $devicesDir = Join-Path $ProjectRoot "devices"

    if (-not (Test-Path $devicesDir)) {
        Write-LogWarn "No devices directory found"
        return @()
    }

    $devices = @()
    Get-ChildItem -Path $devicesDir -Directory | ForEach-Object {
        $deviceFile = Join-Path $_.FullName "device.yml"
        if (Test-Path $deviceFile) {
            $content = Get-Content $deviceFile -Raw
            $hostname = $_.Name
            $os = if ($content -match 'os:\s*(\w+)') { $Matches[1] } else { 'unknown' }
            $profile = if ($content -match 'profile:\s*(\S+)') { $Matches[1] } else { 'unknown' }

            $devices += [PSCustomObject]@{
                Hostname = $hostname
                OS       = $os
                Profile  = $profile
            }
        }
    }

    return $devices
}

# Main execution
if ($MyInvocation.InvocationName -ne '.') {
    $result = Register-LocalDevice -DeviceProfile $Profile -OutputDirectory $OutputPath
    Write-Host "`nDevice directory: $result"
}
