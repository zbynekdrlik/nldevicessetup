# Description: Windows service optimization for low latency
# Module: services

function Apply-Services {
    Write-LogInfo "=== Services Module ==="

    # Disable unnecessary services that can cause latency spikes

    $servicesToDisable = @(
        'SysMain',           # Superfetch - causes disk I/O
        'DiagTrack',         # Diagnostics Tracking
        'dmwappushservice',  # WAP Push Message Routing
        'WSearch'            # Windows Search (if not needed)
    )

    foreach ($service in $servicesToDisable) {
        try {
            $svc = Get-Service -Name $service -ErrorAction SilentlyContinue
            if ($svc -and $svc.StartType -ne 'Disabled') {
                Write-LogInfo "Disabling service: $service"
                Set-Service -Name $service -StartupType Disabled -ErrorAction SilentlyContinue
                Stop-Service -Name $service -Force -ErrorAction SilentlyContinue
            }
        }
        catch {
            Write-LogWarn "Could not disable service: $service"
        }
    }

    # Ensure audio services are running and set to automatic
    $audioServices = @(
        'Audiosrv',     # Windows Audio
        'AudioEndpointBuilder'  # Windows Audio Endpoint Builder
    )

    foreach ($service in $audioServices) {
        try {
            Set-Service -Name $service -StartupType Automatic
            Start-Service -Name $service -ErrorAction SilentlyContinue
            Write-LogSuccess "Ensured $service is running"
        }
        catch {
            Write-LogWarn "Could not configure service: $service"
        }
    }

    Write-LogSuccess "Services module complete"
}
