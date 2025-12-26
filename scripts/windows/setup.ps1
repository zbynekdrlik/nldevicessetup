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
        $null = Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -ErrorAction Stop
    }
    catch {
        Write-LogWarn "Failed to set $Path\$Name : $_"
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
function Ensure-MicrosoftStore {
    Write-LogInfo "Ensuring Microsoft Store is installed..."

    # Check if Store exists
    $store = Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
    if ($store) {
        Write-LogSuccess "Microsoft Store already installed"
        return $true
    }

    # Method 1: Register by family name
    Write-LogInfo "Registering Microsoft Store..."
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.WindowsStore_8wekyb3d8bbwe -ErrorAction Stop
        Start-Sleep -Seconds 2
        if (Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue) {
            Write-LogSuccess "Microsoft Store registered"
            return $true
        }
    }
    catch {
        Write-LogWarn "Store registration failed: $_"
    }

    # Method 2: wsreset -i (reinstalls Store)
    Write-LogInfo "Reinstalling Microsoft Store via wsreset..."
    try {
        $process = Start-Process -FilePath "wsreset.exe" -ArgumentList "-i" -Wait -PassThru -NoNewWindow -ErrorAction Stop
        Start-Sleep -Seconds 5
        if (Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue) {
            Write-LogSuccess "Microsoft Store reinstalled"
            return $true
        }
    }
    catch {
        Write-LogWarn "wsreset -i failed: $_"
    }

    Write-LogWarn "Could not ensure Microsoft Store - winget may have issues"
    return $false
}

function Install-Winget {
    Write-LogInfo "Checking winget..."

    if (Test-CommandExists 'winget') {
        Write-LogSuccess "winget already installed"
        $script:Results.AlreadyInstalled += 'winget'
        return $true
    }

    # Method 1: Try winget.pro installer
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
        Write-LogWarn "winget.pro method failed: $_"
    }

    # Method 2: Register App Installer by family name (works on most Windows 10/11)
    Write-LogInfo "Trying App Installer registration method..."
    try {
        Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop
        Start-Sleep -Seconds 2

        if (Test-CommandExists 'winget') {
            Write-LogSuccess "winget installed via App Installer registration"
            $script:Results.Installed += 'winget'
            return $true
        }
    }
    catch {
        Write-LogWarn "App Installer registration failed: $_"
    }

    # Method 3: Direct MSIX download from GitHub
    Write-LogInfo "Trying direct MSIX download..."
    try {
        $tempDir = "$env:TEMP\winget-install"
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

        # Get latest release URL
        $releaseUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseUrl -ErrorAction Stop
        $msixUrl = ($release.assets | Where-Object { $_.name -match '\.msixbundle$' }).browser_download_url

        if ($msixUrl) {
            $msixPath = "$tempDir\winget.msixbundle"
            Invoke-WebRequest -Uri $msixUrl -OutFile $msixPath -ErrorAction Stop
            Add-AppxPackage -Path $msixPath -ErrorAction Stop

            if (Test-CommandExists 'winget') {
                Write-LogSuccess "winget installed via direct download"
                $script:Results.Installed += 'winget'
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                return $true
            }
        }
    }
    catch {
        Write-LogWarn "Direct download method failed: $_"
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
    Write-LogInfo "Optimizing network adapters (registry-based, applies after reboot)..."
    Write-LogWarn "NOTE: Some NIC settings apply after reboot to avoid disconnection"

    # Global TCP/IP settings first (these are safe, no disconnect)
    $tcpParams = 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters'
    Set-RegistryValue -Path $tcpParams -Name 'TcpAckFrequency' -Value 1
    Set-RegistryValue -Path $tcpParams -Name 'TCPNoDelay' -Value 1
    Set-RegistryValue -Path $tcpParams -Name 'TcpDelAckTicks' -Value 0

    # Disable network throttling (safe)
    $mmcssPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
    Set-RegistryValue -Path $mmcssPath -Name 'NetworkThrottlingIndex' -Value 0xFFFFFFFF

    # Per-adapter settings via registry (doesn't cause immediate disconnect)
    $adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disconnected' }

    foreach ($adapter in $adapters) {
        Write-LogInfo "  Configuring: $($adapter.Name)"

        # Get adapter registry path
        try {
            $adapterGuid = $adapter.InterfaceGuid
            $regBasePath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"

            # Find the adapter's registry key
            Get-ChildItem $regBasePath -ErrorAction SilentlyContinue | ForEach-Object {
                $props = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
                if ($props.NetCfgInstanceId -eq $adapterGuid) {
                    $adapterRegPath = $_.PSPath

                    # Disable EEE (Energy Efficient Ethernet) - value 0
                    Set-RegistryValue -Path $adapterRegPath -Name '*EEE' -Value '0' -Type 'String'

                    # Disable Flow Control - value 0
                    Set-RegistryValue -Path $adapterRegPath -Name '*FlowControl' -Value '0' -Type 'String'

                    # Disable Interrupt Moderation - value 0
                    Set-RegistryValue -Path $adapterRegPath -Name '*InterruptModeration' -Value '0' -Type 'String'

                    # Disable Power Saving - value 0
                    Set-RegistryValue -Path $adapterRegPath -Name '*PowerSavingMode' -Value '0' -Type 'String'
                    Set-RegistryValue -Path $adapterRegPath -Name 'EnablePME' -Value '0' -Type 'String'
                    Set-RegistryValue -Path $adapterRegPath -Name 'WakeOnMagicPacket' -Value '0' -Type 'String'
                    Set-RegistryValue -Path $adapterRegPath -Name 'WakeOnPattern' -Value '0' -Type 'String'

                    # Disable Green Ethernet
                    Set-RegistryValue -Path $adapterRegPath -Name 'GreenEthernet' -Value '0' -Type 'String'
                    Set-RegistryValue -Path $adapterRegPath -Name 'EnableGreenEthernet' -Value '0' -Type 'String'

                    # Disable Large Send Offload
                    Set-RegistryValue -Path $adapterRegPath -Name '*LsoV2IPv4' -Value '0' -Type 'String'
                    Set-RegistryValue -Path $adapterRegPath -Name '*LsoV2IPv6' -Value '0' -Type 'String'
                }
            }
        }
        catch {
            Write-LogWarn "  Could not configure adapter via registry: $($adapter.Name)"
        }

        # Disable adapter power management via PnP
        try {
            $pnpDevice = Get-PnpDevice | Where-Object { $_.FriendlyName -eq $adapter.InterfaceDescription }
            if ($pnpDevice) {
                $instanceId = $pnpDevice.InstanceId
                $regPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\$instanceId\Device Parameters"
                Set-RegistryValue -Path $regPath -Name 'PnPCapabilities' -Value 24
            }
        }
        catch {}
    }

    Write-LogSuccess "Network adapter settings configured (some require reboot)"
    $script:Results.Optimizations += 'Network: EEE, Flow Control, Interrupt Mod, LSO disabled (reboot for NIC changes)'
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
        $null = New-NetQosPolicy -Name 'VBAN Audio' -IPProtocol UDP -IPDstPortStart 6980 -IPDstPortEnd 6989 -DSCPAction 46 -NetworkProfile All -ErrorAction Stop
        Write-LogSuccess "QoS policy created for VBAN (DSCP 46)"

        # Dante policy (ensure it exists)
        $null = New-NetQosPolicy -Name 'Dante Audio' -IPProtocol UDP -IPDstPortStart 14336 -IPDstPortEnd 14600 -DSCPAction 46 -NetworkProfile All -ErrorAction SilentlyContinue

        $script:Results.Optimizations += 'QoS: VBAN + Dante DSCP 46 (EF)'
    }
    catch {
        Write-LogWarn "QoS policy creation failed (may require reboot): $_"

        # Alternative: Use registry-based QoS
        $qosPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\QoS\VBAN Audio'
        $null = Set-RegistryValue -Path $qosPath -Name 'Version' -Value '1.0' -Type 'String'
        $null = Set-RegistryValue -Path $qosPath -Name 'Protocol' -Value 'UDP' -Type 'String'
        $null = Set-RegistryValue -Path $qosPath -Name 'Local Port' -Value '*' -Type 'String'
        $null = Set-RegistryValue -Path $qosPath -Name 'Remote Port' -Value '6980:6989' -Type 'String'
        $null = Set-RegistryValue -Path $qosPath -Name 'DSCP Value' -Value '46' -Type 'String'

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

function Optimize-DisableStartupItems {
    Write-LogInfo "Disabling unnecessary startup items..."

    $disabledItems = @()

    # 1. Disable Microsoft Edge startup (multiple locations)
    # Registry Run keys
    $edgeRunPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($path in $edgeRunPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            $items.PSObject.Properties | Where-Object { $_.Name -like '*Edge*' -or $_.Name -like '*MicrosoftEdge*' } | ForEach-Object {
                Remove-ItemProperty -Path $path -Name $_.Name -ErrorAction SilentlyContinue
                Write-LogInfo "  Removed: $($_.Name) from $path"
                $disabledItems += "Edge ($($_.Name))"
            }
        } catch {}
    }

    # Disable Edge startup boost via registry
    $edgePrefsPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    if (-not (Test-Path $edgePrefsPath)) { $null = New-Item -Path $edgePrefsPath -Force }
    Set-RegistryValue -Path $edgePrefsPath -Name 'StartupBoostEnabled' -Value 0
    Set-RegistryValue -Path $edgePrefsPath -Name 'BackgroundModeEnabled' -Value 0
    $disabledItems += 'Edge Startup Boost'

    # Disable Edge scheduled tasks
    $edgeTasks = @(
        '\Microsoft\Edge\MicrosoftEdgeUpdateTaskMachineCore',
        '\Microsoft\Edge\MicrosoftEdgeUpdateTaskMachineUA',
        '\MicrosoftEdgeUpdateTaskMachineCore',
        '\MicrosoftEdgeUpdateTaskMachineUA'
    )
    foreach ($task in $edgeTasks) {
        try {
            Disable-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }

    # 2. Disable Windows Security Health Systray (SecurityHealth)
    $securityHealthPaths = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($path in $securityHealthPaths) {
        try {
            Remove-ItemProperty -Path $path -Name 'SecurityHealth' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $path -Name 'WindowsDefender' -ErrorAction SilentlyContinue
        } catch {}
    }

    # Disable via Explorer startup approved
    $startupApprovedPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    if (Test-Path $startupApprovedPath) {
        try {
            # Setting to disabled (first byte = 03 means disabled)
            $disabledValue = [byte[]](0x03,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00)
            Set-ItemProperty -Path $startupApprovedPath -Name 'SecurityHealth' -Value $disabledValue -Type Binary -ErrorAction SilentlyContinue
        } catch {}
    }
    $disabledItems += 'SecurityHealth Systray'

    # 3. Disable Logitech Download Assistant (LogiLDA)
    $logitechPaths = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
    )

    foreach ($path in $logitechPaths) {
        try {
            Remove-ItemProperty -Path $path -Name 'Logitech Download Assistant' -ErrorAction SilentlyContinue
            Remove-ItemProperty -Path $path -Name 'LogiLDA' -ErrorAction SilentlyContinue
        } catch {}
    }

    # Disable Logitech scheduled tasks
    $logiTasks = Get-ScheduledTask -TaskName '*Logitech*' -ErrorAction SilentlyContinue
    foreach ($task in $logiTasks) {
        try {
            Disable-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue | Out-Null
        } catch {}
    }
    $disabledItems += 'Logitech Download Assistant'

    # 4. Disable other common bloatware startup items
    $bloatwareItems = @(
        'OneDrive',
        'OneDriveSetup',
        'Cortana',
        'GameBar',
        'Teams',
        'Spotify'
    )

    foreach ($item in $bloatwareItems) {
        foreach ($path in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run')) {
            try {
                $existing = Get-ItemProperty -Path $path -Name $item -ErrorAction SilentlyContinue
                if ($existing) {
                    Remove-ItemProperty -Path $path -Name $item -ErrorAction SilentlyContinue
                    $disabledItems += $item
                }
            } catch {}
        }
    }

    Write-LogSuccess "Startup items disabled: Edge, SecurityHealth, LogiLDA"
    $script:Results.Optimizations += 'Startup: Edge, SecurityHealth, LogiLDA disabled'
}

function Optimize-DisableFirewallAndRansomware {
    Write-LogInfo "Disabling Windows Firewall (all profiles)..."

    # Disable Windows Firewall on all profiles
    try {
        Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled False -ErrorAction Stop
        Write-LogSuccess "Windows Firewall disabled on all profiles"
    }
    catch {
        # Fallback to netsh
        try {
            netsh advfirewall set allprofiles state off 2>$null | Out-Null
            Write-LogSuccess "Windows Firewall disabled via netsh"
        }
        catch {
            Write-LogWarn "Could not disable Windows Firewall: $_"
        }
    }

    # Also disable via registry (persists)
    $fwProfiles = @(
        'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\DomainProfile',
        'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\PublicProfile',
        'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\StandardProfile'
    )

    foreach ($profile in $fwProfiles) {
        Set-RegistryValue -Path $profile -Name 'EnableFirewall' -Value 0
    }

    Write-LogInfo "Disabling Ransomware Protection (Controlled Folder Access)..."

    # Disable Controlled Folder Access (Ransomware Protection)
    try {
        Set-MpPreference -EnableControlledFolderAccess Disabled -ErrorAction Stop
        Write-LogSuccess "Controlled Folder Access disabled"
    }
    catch {
        # Fallback to registry
        $defenderPath = 'HKLM:\SOFTWARE\Microsoft\Windows Defender\Windows Defender Exploit Guard\Controlled Folder Access'
        if (-not (Test-Path $defenderPath)) { $null = New-Item -Path $defenderPath -Force }
        Set-RegistryValue -Path $defenderPath -Name 'EnableControlledFolderAccess' -Value 0
        Write-LogSuccess "Controlled Folder Access disabled via registry"
    }

    $script:Results.Optimizations += 'Firewall: Disabled on all profiles'
    $script:Results.Optimizations += 'Ransomware Protection: Disabled'
}

function Set-AutoLogin {
    Write-LogInfo "Configuring auto-login for current user..."

    $username = $env:USERNAME
    $password = 'newlevel'

    # Set auto-login via registry
    $winlogonPath = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'

    Set-RegistryValue -Path $winlogonPath -Name 'AutoAdminLogon' -Value '1' -Type 'String'
    Set-RegistryValue -Path $winlogonPath -Name 'DefaultUserName' -Value $username -Type 'String'
    Set-RegistryValue -Path $winlogonPath -Name 'DefaultPassword' -Value $password -Type 'String'
    Set-RegistryValue -Path $winlogonPath -Name 'DefaultDomainName' -Value $env:COMPUTERNAME -Type 'String'

    # Remove any auto-logon count limit
    try {
        Remove-ItemProperty -Path $winlogonPath -Name 'AutoLogonCount' -ErrorAction SilentlyContinue
    } catch {}

    # Set the user password
    try {
        $user = [ADSI]"WinNT://./$username,user"
        $user.SetPassword($password)
        $user.SetInfo()
        Write-LogSuccess "Password set for $username"
    }
    catch {
        # Try net user as fallback
        try {
            $null = net user $username $password 2>$null
            Write-LogSuccess "Password set for $username (via net user)"
        }
        catch {
            Write-LogWarn "Could not set password for $username : $_"
        }
    }

    Write-LogSuccess "Auto-login configured for $username"
    $script:Results.Optimizations += "Auto-login: Enabled for $username"
}

function Set-UACNeverNotify {
    Write-LogInfo "Setting UAC to never notify..."

    $uacPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'

    # EnableLUA = 0 completely disables UAC (not recommended, can break some apps)
    # Instead, we set notification level to "Never notify" while keeping UAC enabled
    # ConsentPromptBehaviorAdmin:
    #   0 = Elevate without prompting (silent elevation for admins)
    #   1 = Prompt for credentials on secure desktop
    #   2 = Prompt for consent on secure desktop
    #   3 = Prompt for credentials
    #   4 = Prompt for consent
    #   5 = Prompt for consent for non-Windows binaries (default)
    # PromptOnSecureDesktop:
    #   0 = Disabled (no secure desktop)
    #   1 = Enabled

    Set-RegistryValue -Path $uacPath -Name 'ConsentPromptBehaviorAdmin' -Value 0
    Set-RegistryValue -Path $uacPath -Name 'ConsentPromptBehaviorUser' -Value 0
    Set-RegistryValue -Path $uacPath -Name 'PromptOnSecureDesktop' -Value 0
    Set-RegistryValue -Path $uacPath -Name 'EnableInstallerDetection' -Value 0

    # Keep UAC enabled but silent
    Set-RegistryValue -Path $uacPath -Name 'EnableLUA' -Value 1

    Write-LogSuccess "UAC set to never notify (silent elevation)"
    $script:Results.Optimizations += 'UAC: Never notify (silent elevation)'
}

function Install-NvidiaDrivers {
    Write-LogInfo "Checking for NVIDIA graphics card..."

    # Check for NVIDIA GPU
    $nvidiaGPU = Get-CimInstance -ClassName Win32_VideoController | Where-Object {
        $_.Name -match 'NVIDIA' -or $_.Description -match 'NVIDIA'
    }

    if (-not $nvidiaGPU) {
        Write-LogInfo "No NVIDIA graphics card detected - skipping driver installation"
        return $false
    }

    Write-LogSuccess "Found NVIDIA GPU: $($nvidiaGPU.Name)"
    Write-LogInfo "Installing NVIDIA App for Studio Drivers..."

    # Install NVIDIA App (replaces GeForce Experience, supports Studio Drivers)
    try {
        $installed = Install-WingetPackage -PackageId 'Nvidia.NvidiaApp' -DisplayName 'NVIDIA App'

        if ($installed) {
            Write-LogSuccess "NVIDIA App installed"
            Write-LogInfo "NVIDIA App will allow you to switch to Studio Drivers:"
            Write-LogInfo "  1. Open NVIDIA App"
            Write-LogInfo "  2. Go to Settings > Driver Type"
            Write-LogInfo "  3. Select 'Studio Driver' instead of 'Game Ready Driver'"
            Write-LogInfo "  4. Check for updates to download Studio Driver"

            $script:Results.Optimizations += "NVIDIA: App installed (switch to Studio Driver in settings)"
            return $true
        }
    }
    catch {
        Write-LogWarn "Failed to install NVIDIA App: $_"
    }

    # Fallback: Try to install via direct download
    Write-LogInfo "Attempting direct NVIDIA App download..."
    try {
        $downloadUrl = 'https://us.download.nvidia.com/nvapp/client/11.0.1.163/NVIDIA_app_v11.0.1.163.exe'
        $installerPath = "$env:TEMP\NVIDIA_app_installer.exe"

        Write-LogInfo "Downloading NVIDIA App..."
        Invoke-WebRequest -Uri $downloadUrl -OutFile $installerPath -UseBasicParsing

        Write-LogInfo "Running NVIDIA App installer (silent)..."
        $process = Start-Process -FilePath $installerPath -ArgumentList '-s', '-noreboot' -Wait -PassThru

        if ($process.ExitCode -eq 0) {
            Write-LogSuccess "NVIDIA App installed successfully"
            $script:Results.Optimizations += "NVIDIA: App installed (switch to Studio Driver in settings)"
            return $true
        }
        else {
            Write-LogWarn "NVIDIA App installer exited with code: $($process.ExitCode)"
        }
    }
    catch {
        Write-LogWarn "Failed to download/install NVIDIA App: $_"
    }

    $script:Results.Failed += 'NVIDIA App installation'
    return $false
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

    # 0. Ensure Microsoft Store is available (required for winget)
    $null = Ensure-MicrosoftStore

    # 1. Install winget
    $null = Install-Winget

    # Refresh PATH for winget
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 2. Install Process Lasso
    $null = Install-WingetPackage -PackageId 'Bitsum.ProcessLasso' -DisplayName 'Process Lasso'
    $null = Configure-ProcessLasso

    # 3. Install other apps
    $null = Install-WingetPackage -PackageId 'Microsoft.WindowsTerminal' -DisplayName 'Windows Terminal'
    $null = Install-WingetPackage -PackageId 'RustDesk.RustDesk' -DisplayName 'RustDesk'
    $null = Install-WingetPackage -PackageId 'OpenJS.NodeJS' -DisplayName 'Node.js'
    $null = Install-WingetPackage -PackageId 'Skillbrains.Lightshot' -DisplayName 'Lightshot'
    $null = Install-WingetPackage -PackageId 'Brave.Brave' -DisplayName 'Brave Browser'

    # Refresh PATH for Node.js
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")

    # 4. Install npm packages
    $null = Install-NpmPackage -Package '@anthropic-ai/claude-code' -DisplayName 'Claude Code'
    $null = Install-NpmPackage -Package '@google/gemini-cli' -DisplayName 'Gemini CLI'

    # 5. Install SSH
    $null = Install-OpenSSH

    # 6. Install DanteTimeSync
    $null = Install-DanteTimeSync
    #endregion

    #region System Optimization
    Write-LogSection "SYSTEM OPTIMIZATION"

    # Power and responsiveness (safe, no disconnect risk)
    Optimize-HighPerformancePower
    Optimize-PowerButtons
    Optimize-DisableUSBPowerSaving

    # Visual (safe)
    Optimize-VisualEffects
    Optimize-DarkMode
    Optimize-DisableTransparency

    # Audio/latency (safe)
    Optimize-MMCSS
    Optimize-TimerResolution

    # System (safe)
    Optimize-DisableWindowsUpdate
    Optimize-DisableServices
    Optimize-DisableStartupItems
    Optimize-DisableFirewallAndRansomware

    # Security/Login
    Set-UACNeverNotify
    Set-AutoLogin

    # QoS (safe)
    Optimize-QoSForVBAN

    # Network adapters LAST (registry-based, some changes need reboot)
    Optimize-NetworkAdapters

    # GPU Drivers (if NVIDIA detected)
    Install-NvidiaDrivers
    #endregion

    Show-Summary
}

Main
#endregion
