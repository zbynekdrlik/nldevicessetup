# NL Devices Setup - Windows Production Setup Script
# Run as Administrator: irm https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/windows/setup.ps1 | iex
#
# This script:
# 1. Installs required software (winget, apps, npm packages)
# 2. Configures system for low-latency audio/video production
# 3. Optimizes power, network, and system settings
#
# Compatible with Windows 10 and Windows 11

#Requires -RunAsAdministrator

$ErrorActionPreference = 'Continue'
Set-StrictMode -Version Latest

$script:Version = '1.0.0'
$script:LogFile = "$env:LOCALAPPDATA\nldevicessetup\setup.log"
$script:Results = @{
    Installed = @()
    AlreadyInstalled = @()
    Failed = @()
    Optimizations = @()
}

#region Logging Functions
function Write-LogInfo {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
    Add-Content -Path $script:LogFile -Value "[$timestamp] [INFO] $Message" -ErrorAction SilentlyContinue
}

function Write-LogSuccess {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[OK] $Message" -ForegroundColor Green
    Add-Content -Path $script:LogFile -Value "[$timestamp] [OK] $Message" -ErrorAction SilentlyContinue
}

function Write-LogWarn {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
    Add-Content -Path $script:LogFile -Value "[$timestamp] [WARN] $Message" -ErrorAction SilentlyContinue
}

function Write-LogError {
    param([string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    Add-Content -Path $script:LogFile -Value "[$timestamp] [ERROR] $Message" -ErrorAction SilentlyContinue
}

function Write-LogSection {
    param([string]$Title)
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host " $Title" -ForegroundColor Magenta
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Magenta
    Write-Host ""
}
#endregion

#region Helper Functions
function Test-Administrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type = 'DWord'
    )
    try {
        if (-not (Test-Path $Path)) {
            $null = New-Item -Path $Path -Force
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
        return $true
    }
    catch {
        Write-LogWarn "Failed to set $Path\$Name : $_"
        return $false
    }
}

function Test-CommandExists {
    param([string]$Command)
    $null -ne (Get-Command $Command -ErrorAction SilentlyContinue)
}

function Test-WingetPackageInstalled {
    param([string]$PackageId)
    try {
        $result = winget list --id $PackageId --accept-source-agreements 2>$null
        return $result -match $PackageId
    }
    catch {
        return $false
    }
}

function Test-NpmPackageInstalled {
    param([string]$Package)
    try {
        $result = npm list -g $Package 2>$null
        return -not ($result -match 'empty')
    }
    catch {
        return $false
    }
}
#endregion

#region Installation Functions
function Install-Winget {
    Write-LogInfo "Checking winget..."

    if (Test-CommandExists 'winget') {
        Write-LogSuccess "winget already installed"
        $script:Results.AlreadyInstalled += 'winget'
        return $true
    }

    Write-LogInfo "Installing winget via winget.pro..."
    try {
        Invoke-Expression (Invoke-RestMethod -Uri 'https://winget.pro')
        Start-Sleep -Seconds 3

        if (Test-CommandExists 'winget') {
            Write-LogSuccess "winget installed successfully"
            $script:Results.Installed += 'winget'
            return $true
        }
    }
    catch {
        Write-LogError "Failed to install winget: $_"
    }

    $script:Results.Failed += 'winget'
    return $false
}

function Install-WingetPackage {
    param(
        [string]$PackageId,
        [string]$DisplayName
    )

    Write-LogInfo "Checking $DisplayName..."

    if (Test-WingetPackageInstalled $PackageId) {
        Write-LogSuccess "$DisplayName already installed"
        $script:Results.AlreadyInstalled += $DisplayName
        return $true
    }

    Write-LogInfo "Installing $DisplayName..."
    try {
        $result = winget install $PackageId --accept-package-agreements --accept-source-agreements --silent 2>&1

        if ($LASTEXITCODE -eq 0 -or $result -match 'successfully installed') {
            Write-LogSuccess "$DisplayName installed successfully"
            $script:Results.Installed += $DisplayName
            return $true
        }
    }
    catch {
        Write-LogError "Failed to install $DisplayName : $_"
    }

    $script:Results.Failed += $DisplayName
    return $false
}

function Install-OpenSSH {
    Write-LogInfo "Checking OpenSSH..."

    $sshClient = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Client*'
    $sshServer = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

    $needsInstall = $false

    if ($sshClient.State -ne 'Installed') {
        Write-LogInfo "Installing OpenSSH Client..."
        try {
            Add-WindowsCapability -Online -Name $sshClient.Name
            $needsInstall = $true
        }
        catch {
            Write-LogWarn "Failed to install OpenSSH Client: $_"
        }
    }

    if ($sshServer.State -ne 'Installed') {
        Write-LogInfo "Installing OpenSSH Server..."
        try {
            Add-WindowsCapability -Online -Name $sshServer.Name
            $needsInstall = $true
        }
        catch {
            Write-LogWarn "Failed to install OpenSSH Server: $_"
        }
    }

    # Configure SSH Server
    try {
        Start-Service sshd -ErrorAction SilentlyContinue
        Set-Service -Name sshd -StartupType 'Automatic' -ErrorAction SilentlyContinue

        # Firewall rule
        $rule = Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue
        if (-not $rule) {
            New-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort 22
        }
    }
    catch {
        Write-LogWarn "Failed to configure SSH Server: $_"
    }

    if ($needsInstall) {
        Write-LogSuccess "OpenSSH installed and configured"
        $script:Results.Installed += 'OpenSSH'
    }
    else {
        Write-LogSuccess "OpenSSH already installed"
        $script:Results.AlreadyInstalled += 'OpenSSH'
    }

    return $true
}

function Install-NpmPackage {
    param(
        [string]$Package,
        [string]$DisplayName
    )

    if (-not (Test-CommandExists 'npm')) {
        Write-LogWarn "npm not found, skipping $DisplayName"
        $script:Results.Failed += $DisplayName
        return $false
    }

    Write-LogInfo "Checking $DisplayName..."

    if (Test-NpmPackageInstalled $Package) {
        Write-LogSuccess "$DisplayName already installed"
        $script:Results.AlreadyInstalled += $DisplayName
        return $true
    }

    Write-LogInfo "Installing $DisplayName..."
    try {
        npm install -g $Package 2>&1 | Out-Null

        if ($LASTEXITCODE -eq 0) {
            Write-LogSuccess "$DisplayName installed successfully"
            $script:Results.Installed += $DisplayName
            return $true
        }
    }
    catch {
        Write-LogError "Failed to install $DisplayName : $_"
    }

    $script:Results.Failed += $DisplayName
    return $false
}

function Install-DanteTimeSync {
    Write-LogInfo "Installing DanteTimeSync..."
    try {
        Invoke-Expression (Invoke-RestMethod -Uri 'https://raw.githubusercontent.com/zbynekdrlik/dantetimesync/master/install.ps1')
        Write-LogSuccess "DanteTimeSync installed"
        $script:Results.Installed += 'DanteTimeSync'
        return $true
    }
    catch {
        Write-LogWarn "DanteTimeSync installation issue: $_"
        $script:Results.Failed += 'DanteTimeSync'
        return $false
    }
}

function Configure-ProcessLasso {
    Write-LogInfo "Configuring Process Lasso..."

    # Check if Process Lasso is installed
    $plPath = "${env:ProgramFiles}\Process Lasso\ProcessLasso.exe"
    if (-not (Test-Path $plPath)) {
        $plPath = "${env:ProgramFiles(x86)}\Process Lasso\ProcessLasso.exe"
    }

    if (-not (Test-Path $plPath)) {
        Write-LogWarn "Process Lasso not found, skipping configuration"
        return $false
    }

    # Process Lasso settings via registry
    $plRegPath = 'HKCU:\Software\ProcessLasso'

    # Enable Performance Mode
    Set-RegistryValue -Path $plRegPath -Name 'PerformanceMode' -Value 1

    # Keep computer awake (prevent sleep)
    Set-RegistryValue -Path $plRegPath -Name 'PreventSleep' -Value 1

    Write-LogSuccess "Process Lasso configured"
    $script:Results.Optimizations += 'Process Lasso: Performance Mode + Keep Awake'
    return $true
}
#endregion

#region Optimization Functions
function Optimize-PowerButtons {
    Write-LogInfo "Configuring power buttons and lid to do nothing..."

    # Power button action: 0 = Do nothing
    # Lid close action: 0 = Do nothing

    # AC (plugged in)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0
    powercfg /setacvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0

    # DC (battery)
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS PBUTTONACTION 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS SBUTTONACTION 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_BUTTONS LIDACTION 0

    powercfg /setactive SCHEME_CURRENT

    Write-LogSuccess "Power buttons and lid set to do nothing"
    $script:Results.Optimizations += 'Power buttons/lid: Do nothing'
}

function Optimize-VisualEffects {
    Write-LogInfo "Optimizing visual effects for best performance..."

    # Visual Effects settings
    # 0 = Let Windows choose
    # 1 = Adjust for best appearance
    # 2 = Adjust for best performance
    # 3 = Custom

    $vfxPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
    Set-RegistryValue -Path $vfxPath -Name 'VisualFXSetting' -Value 3

    # Disable all visual effects except thumbnails
    $advPath = 'HKCU:\Control Panel\Desktop'
    Set-RegistryValue -Path $advPath -Name 'UserPreferencesMask' -Value ([byte[]](0x90,0x12,0x03,0x80,0x10,0x00,0x00,0x00)) -Type 'Binary'

    # Keep thumbnails enabled
    $explorerPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    Set-RegistryValue -Path $explorerPath -Name 'IconsOnly' -Value 0

    # Disable animations
    Set-RegistryValue -Path 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name 'MinAnimate' -Value '0' -Type 'String'

    # Disable Aero Peek
    $dwmPath = 'HKCU:\Software\Microsoft\Windows\DWM'
    Set-RegistryValue -Path $dwmPath -Name 'EnableAeroPeek' -Value 0

    Write-LogSuccess "Visual effects optimized (thumbnails kept)"
    $script:Results.Optimizations += 'Visual effects: Best performance + thumbnails'
}

function Optimize-DarkMode {
    Write-LogInfo "Enabling dark mode..."

    $themePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'

    # Apps dark mode
    Set-RegistryValue -Path $themePath -Name 'AppsUseLightTheme' -Value 0

    # System dark mode
    Set-RegistryValue -Path $themePath -Name 'SystemUsesLightTheme' -Value 0

    Write-LogSuccess "Dark mode enabled"
    $script:Results.Optimizations += 'Dark mode: Enabled'
}

function Optimize-DisableTransparency {
    Write-LogInfo "Disabling transparency effects..."

    $themePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    Set-RegistryValue -Path $themePath -Name 'EnableTransparency' -Value 0

    Write-LogSuccess "Transparency effects disabled"
    $script:Results.Optimizations += 'Transparency: Disabled'
}

function Optimize-NetworkAdapters {
    Write-LogInfo "Optimizing network adapters..."

    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected' }

    foreach ($adapter in $adapters) {
        Write-LogInfo "  Configuring: $($adapter.Name)"

        # Disable Energy Efficient Ethernet (Green Ethernet)
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*EEE' -RegistryValue 0 -ErrorAction SilentlyContinue
        } catch {}

        # Disable Energy Efficient Ethernet (alternate key)
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'EEE' -RegistryValue 0 -ErrorAction SilentlyContinue
        } catch {}

        # Disable Green Ethernet
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword 'GreenEthernet' -RegistryValue 0 -ErrorAction SilentlyContinue
        } catch {}

        # Disable Power Saving Mode
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*PowerSavingMode' -RegistryValue 0 -ErrorAction SilentlyContinue
        } catch {}

        # Disable Flow Control
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*FlowControl' -RegistryValue 0 -ErrorAction SilentlyContinue
        } catch {}

        # Disable Interrupt Moderation (lower latency)
        try {
            Set-NetAdapterAdvancedProperty -Name $adapter.Name -RegistryKeyword '*InterruptModeration' -RegistryValue 0 -ErrorAction SilentlyContinue
        } catch {}

        # Disable Large Send Offload v2
        try {
            Disable-NetAdapterLso -Name $adapter.Name -ErrorAction SilentlyContinue
        } catch {}

        # Disable adapter power management
        try {
            $pnpDevice = Get-PnpDevice | Where-Object { $_.FriendlyName -eq $adapter.InterfaceDescription }
            if ($pnpDevice) {
                $instanceId = $pnpDevice.InstanceId
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
                Set-RegistryValue -Path $regPath -Name 'PnPCapabilities' -Value 24
            }
        } catch {}
    }

    # Disable Nagle's Algorithm globally
    $tcpParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-RegistryValue -Path $tcpParams -Name 'TcpAckFrequency' -Value 1
    Set-RegistryValue -Path $tcpParams -Name 'TCPNoDelay' -Value 1
    Set-RegistryValue -Path $tcpParams -Name 'TcpDelAckTicks' -Value 0

    # Disable network throttling
    $mmcssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-RegistryValue -Path $mmcssPath -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF

    Write-LogSuccess "Network adapters optimized"
    $script:Results.Optimizations += 'Network: Green Ethernet, Flow Control, Power Saving disabled'
}

function Optimize-DisableWindowsUpdate {
    Write-LogInfo "Disabling Windows Update (pause for 35 days)..."

    # Pause updates for maximum time (35 days)
    $pauseDate = (Get-Date).AddDays(35).ToString('yyyy-MM-ddTHH:mm:ssZ')

    $wuPath = 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    Set-RegistryValue -Path $wuPath -Name 'PauseFeatureUpdatesStartTime' -Value $pauseDate -Type 'String'
    Set-RegistryValue -Path $wuPath -Name 'PauseQualityUpdatesStartTime' -Value $pauseDate -Type 'String'
    Set-RegistryValue -Path $wuPath -Name 'PauseUpdatesExpiryTime' -Value $pauseDate -Type 'String'
    Set-RegistryValue -Path $wuPath -Name 'PauseFeatureUpdatesEndTime' -Value $pauseDate -Type 'String'
    Set-RegistryValue -Path $wuPath -Name 'PauseQualityUpdatesEndTime' -Value $pauseDate -Type 'String'

    # Disable automatic updates
    $auPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    Set-RegistryValue -Path $auPath -Name 'NoAutoUpdate' -Value 1
    Set-RegistryValue -Path $auPath -Name 'AUOptions' -Value 2  # Notify for download

    # Stop Windows Update service temporarily
    try {
        Stop-Service -Name wuauserv -Force -ErrorAction SilentlyContinue
        Set-Service -Name wuauserv -StartupType Manual -ErrorAction SilentlyContinue
    } catch {}

    Write-LogSuccess "Windows Update paused for 35 days"
    $script:Results.Optimizations += 'Windows Update: Paused 35 days'
}

function Optimize-QoSForVBAN {
    Write-LogInfo "Configuring QoS for VBAN (same priority as Dante)..."

    # VBAN uses UDP ports 6980-6989
    # Dante uses UDP ports 14336-14600 with DSCP 46 (EF - Expedited Forwarding)

    # Remove existing policies if they exist
    try {
        Remove-NetQosPolicy -Name 'VBAN Audio' -Confirm:$false -ErrorAction SilentlyContinue
        Remove-NetQosPolicy -Name 'Dante Audio' -Confirm:$false -ErrorAction SilentlyContinue
    } catch {}

    # Create QoS policies with DSCP 46 (Expedited Forwarding - same as Dante)
    try {
        # VBAN policy
        New-NetQosPolicy -Name 'VBAN Audio' -IPProtocol UDP -IPDstPortStart 6980 -IPDstPortEnd 6989 -DSCPAction 46 -NetworkProfile All -ErrorAction Stop
        Write-LogSuccess "QoS policy created for VBAN (DSCP 46)"

        # Dante policy (ensure it exists)
        New-NetQosPolicy -Name 'Dante Audio' -IPProtocol UDP -IPDstPortStart 14336 -IPDstPortEnd 14600 -DSCPAction 46 -NetworkProfile All -ErrorAction SilentlyContinue

        $script:Results.Optimizations += 'QoS: VBAN + Dante DSCP 46 (EF)'
    }
    catch {
        Write-LogWarn "QoS policy creation failed (may require reboot): $_"

        # Alternative: Use registry-based QoS
        $qosPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS\VBAN Audio'
        Set-RegistryValue -Path $qosPath -Name 'Version' -Value '1.0' -Type 'String'
        Set-RegistryValue -Path $qosPath -Name 'Protocol' -Value 'UDP' -Type 'String'
        Set-RegistryValue -Path $qosPath -Name 'Local Port' -Value '*' -Type 'String'
        Set-RegistryValue -Path $qosPath -Name 'Remote Port' -Value '6980:6989' -Type 'String'
        Set-RegistryValue -Path $qosPath -Name 'DSCP Value' -Value '46' -Type 'String'

        $script:Results.Optimizations += 'QoS: VBAN via registry (reboot may be needed)'
    }
}

function Optimize-DisableUSBPowerSaving {
    Write-LogInfo "Disabling USB power saving..."

    # Disable USB selective suspend via power scheme
    powercfg /setacvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setdcvalueindex SCHEME_CURRENT 2a737441-1930-4402-8d77-b2bebba308a3 48e6b7a6-50f5-4782-a5d4-53bb8f07e226 0
    powercfg /setactive SCHEME_CURRENT

    # Disable USB selective suspend via registry
    $usbPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\USB'
    Set-RegistryValue -Path $usbPath -Name 'DisableSelectiveSuspend' -Value 1

    # Disable power management for USB hubs
    Get-PnpDevice -Class 'USB' | ForEach-Object {
        try {
            $instanceId = $_.InstanceId
            $powerPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
            Set-RegistryValue -Path $powerPath -Name 'EnhancedPowerManagementEnabled' -Value 0
            Set-RegistryValue -Path $powerPath -Name 'AllowIdleIrpInD3' -Value 0
            Set-RegistryValue -Path $powerPath -Name 'SelectiveSuspendEnabled' -Value 0
        } catch {}
    }

    Write-LogSuccess "USB power saving disabled"
    $script:Results.Optimizations += 'USB: Power saving disabled'
}

function Optimize-HighPerformancePower {
    Write-LogInfo "Setting High Performance power plan..."

    # Activate High Performance power plan
    $highPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    powercfg /setactive $highPerfGuid 2>$null

    if ($LASTEXITCODE -ne 0) {
        # Create High Performance plan if it doesn't exist
        Write-LogInfo "Creating High Performance power plan..."
        powercfg /duplicatescheme $highPerfGuid
        powercfg /setactive $highPerfGuid
    }

    # Disable hard disk turn off
    powercfg /setacvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_DISK DISKIDLE 0

    # Disable sleep
    powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP STANDBYIDLE 0

    # Disable hibernate
    powercfg /hibernate off 2>$null

    # Set CPU to 100% minimum
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100

    # Disable display turn off (set to 0 = never)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_VIDEO VIDEOIDLE 0

    # Disable PCI Express Link State Power Management
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0
    powercfg /setdcvalueindex SCHEME_CURRENT SUB_PCIEXPRESS ASPM 0

    powercfg /setactive SCHEME_CURRENT

    Write-LogSuccess "High Performance power plan configured"
    $script:Results.Optimizations += 'Power: High Performance, no sleep/hibernate, CPU 100%'
}

function Optimize-MMCSS {
    Write-LogInfo "Configuring MMCSS for audio priority..."

    $mmcssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'

    # System responsiveness - 0 means no CPU reserved for background tasks
    Set-RegistryValue -Path $mmcssPath -Name 'SystemResponsiveness' -Value 0

    # Audio priority
    $audioPath = "$mmcssPath\Tasks\Audio"
    if (-not (Test-Path $audioPath)) { New-Item -Path $audioPath -Force | Out-Null }

    Set-RegistryValue -Path $audioPath -Name 'Affinity' -Value 0
    Set-RegistryValue -Path $audioPath -Name 'Background Only' -Value 'False' -Type 'String'
    Set-RegistryValue -Path $audioPath -Name 'Clock Rate' -Value 10000
    Set-RegistryValue -Path $audioPath -Name 'GPU Priority' -Value 8
    Set-RegistryValue -Path $audioPath -Name 'Priority' -Value 6
    Set-RegistryValue -Path $audioPath -Name 'Scheduling Category' -Value 'High' -Type 'String'
    Set-RegistryValue -Path $audioPath -Name 'SFIO Priority' -Value 'High' -Type 'String'

    # Pro Audio priority
    $proAudioPath = "$mmcssPath\Tasks\Pro Audio"
    if (-not (Test-Path $proAudioPath)) { New-Item -Path $proAudioPath -Force | Out-Null }

    Set-RegistryValue -Path $proAudioPath -Name 'Affinity' -Value 0
    Set-RegistryValue -Path $proAudioPath -Name 'Background Only' -Value 'False' -Type 'String'
    Set-RegistryValue -Path $proAudioPath -Name 'Clock Rate' -Value 10000
    Set-RegistryValue -Path $proAudioPath -Name 'GPU Priority' -Value 8
    Set-RegistryValue -Path $proAudioPath -Name 'Priority' -Value 6
    Set-RegistryValue -Path $proAudioPath -Name 'Scheduling Category' -Value 'High' -Type 'String'
    Set-RegistryValue -Path $proAudioPath -Name 'SFIO Priority' -Value 'High' -Type 'String'

    Write-LogSuccess "MMCSS audio priority configured"
    $script:Results.Optimizations += 'MMCSS: Audio/Pro Audio high priority'
}

function Optimize-TimerResolution {
    Write-LogInfo "Configuring timer resolution..."

    # Enable global timer resolution requests
    $timerPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\kernel'
    Set-RegistryValue -Path $timerPath -Name 'GlobalTimerResolutionRequests' -Value 1

    # Disable dynamic tick (more consistent timer)
    try {
        bcdedit /set disabledynamictick yes 2>$null | Out-Null
        Write-LogSuccess "Dynamic tick disabled"
    }
    catch {
        Write-LogWarn "Could not disable dynamic tick"
    }

    $script:Results.Optimizations += 'Timer: 1ms resolution, dynamic tick disabled'
}

function Optimize-DisableServices {
    Write-LogInfo "Disabling unnecessary services..."

    $servicesToDisable = @(
        @{ Name = 'SysMain'; Desc = 'Superfetch (disk I/O)' },
        @{ Name = 'DiagTrack'; Desc = 'Diagnostics Tracking' },
        @{ Name = 'dmwappushservice'; Desc = 'WAP Push' }
    )

    foreach ($svc in $servicesToDisable) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service -and $service.StartType -ne 'Disabled') {
                Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
                Set-Service -Name $svc.Name -StartupType Disabled -ErrorAction SilentlyContinue
                Write-LogInfo "  Disabled: $($svc.Name) ($($svc.Desc))"
            }
        }
        catch {
            Write-LogWarn "  Could not disable: $($svc.Name)"
        }
    }

    $script:Results.Optimizations += 'Services: SysMain, DiagTrack, dmwappushservice disabled'
}
#endregion

#region Main
function Show-Banner {
    Write-Host ""
    Write-Host "  _   _ _     ____             _                 ____       _               " -ForegroundColor Cyan
    Write-Host " | \ | | |   |  _ \  _____   _(_) ___ ___  ___  / ___|  ___| |_ _   _ _ __  " -ForegroundColor Cyan
    Write-Host " |  \| | |   | | | |/ _ \ \ / / |/ __/ _ \/ __| \___ \ / _ \ __| | | | '_ \ " -ForegroundColor Cyan
    Write-Host " | |\  | |___| |_| |  __/\ V /| | (_|  __/\__ \  ___) |  __/ |_| |_| | |_) |" -ForegroundColor Cyan
    Write-Host " |_| \_|_____|____/ \___| \_/ |_|\___\___||___/ |____/ \___|\__|\__,_| .__/ " -ForegroundColor Cyan
    Write-Host "                                                                     |_|    " -ForegroundColor Cyan
    Write-Host ""
    Write-Host " Windows Production Setup Script v$script:Version" -ForegroundColor White
    Write-Host " Low-latency audio/video optimization for NDI, Dante, VBAN" -ForegroundColor Gray
    Write-Host ""
}

function Show-Summary {
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host " SETUP COMPLETE" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Green
    Write-Host ""

    if ($script:Results.Installed.Count -gt 0) {
        Write-Host "INSTALLED:" -ForegroundColor Green
        $script:Results.Installed | ForEach-Object { Write-Host "  + $_" -ForegroundColor Green }
        Write-Host ""
    }

    if ($script:Results.AlreadyInstalled.Count -gt 0) {
        Write-Host "ALREADY INSTALLED:" -ForegroundColor Cyan
        $script:Results.AlreadyInstalled | ForEach-Object { Write-Host "  = $_" -ForegroundColor Cyan }
        Write-Host ""
    }

    if ($script:Results.Failed.Count -gt 0) {
        Write-Host "FAILED:" -ForegroundColor Red
        $script:Results.Failed | ForEach-Object { Write-Host "  x $_" -ForegroundColor Red }
        Write-Host ""
    }

    if ($script:Results.Optimizations.Count -gt 0) {
        Write-Host "OPTIMIZATIONS APPLIED:" -ForegroundColor Magenta
        $script:Results.Optimizations | ForEach-Object { Write-Host "  * $_" -ForegroundColor Magenta }
        Write-Host ""
    }

    Write-Host "Log file: $script:LogFile" -ForegroundColor Gray
    Write-Host ""
    Write-Host "RECOMMENDED: Restart your computer for all changes to take effect." -ForegroundColor Yellow
    Write-Host ""
}

function Main {
    # Check admin
    if (-not (Test-Administrator)) {
        Write-LogError "This script must be run as Administrator!"
        Write-Host "Right-click PowerShell and select 'Run as Administrator'" -ForegroundColor Yellow
        return
    }

    # Create log directory
    $logDir = Split-Path $script:LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -Path $logDir -ItemType Directory -Force | Out-Null
    }

    Show-Banner

    Write-LogInfo "Starting setup on $env:COMPUTERNAME"
    Write-LogInfo "Windows Version: $([System.Environment]::OSVersion.Version)"
    Write-Host ""

    #region Software Installation
    Write-LogSection "SOFTWARE INSTALLATION"

    # 1. Install winget
    Install-Winget

    # Refresh PATH for winget
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 2. Install Process Lasso
    Install-WingetPackage -PackageId 'Bitsum.ProcessLasso' -DisplayName 'Process Lasso'
    Configure-ProcessLasso

    # 3. Install other apps
    Install-WingetPackage -PackageId 'Microsoft.WindowsTerminal' -DisplayName 'Windows Terminal'
    Install-WingetPackage -PackageId 'RustDesk.RustDesk' -DisplayName 'RustDesk'
    Install-WingetPackage -PackageId 'OpenJS.NodeJS.LTS' -DisplayName 'Node.js LTS'
    Install-WingetPackage -PackageId 'Skillbrains.Lightshot' -DisplayName 'Lightshot'

    # Refresh PATH for Node.js
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 4. Install npm packages
    Install-NpmPackage -Package '@anthropic-ai/claude-code' -DisplayName 'Claude Code'
    Install-NpmPackage -Package '@google/gemini-cli' -DisplayName 'Gemini CLI'

    # 5. Install SSH
    Install-OpenSSH

    # 6. Install DanteTimeSync
    Install-DanteTimeSync
    #endregion

    #region System Optimization
    Write-LogSection "SYSTEM OPTIMIZATION"

    # Power and responsiveness
    Optimize-HighPerformancePower
    Optimize-PowerButtons
    Optimize-DisableUSBPowerSaving

    # Visual
    Optimize-VisualEffects
    Optimize-DarkMode
    Optimize-DisableTransparency

    # Network
    Optimize-NetworkAdapters
    Optimize-QoSForVBAN

    # Audio/latency
    Optimize-MMCSS
    Optimize-TimerResolution

    # System
    Optimize-DisableWindowsUpdate
    Optimize-DisableServices
    #endregion

    Show-Summary
}

Main
#endregion
