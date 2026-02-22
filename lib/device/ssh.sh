#!/usr/bin/env bash
# SSH wrapper functions for nldevicessetup
# Provides consistent SSH access to remote devices

set -euo pipefail

# Default SSH options for automation
SSH_OPTS="-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o BatchMode=yes"

# SSH to a device and run a command
# Usage: ssh_run <host> <user> [command]
ssh_run() {
    local host="$1"
    local user="${2:-newlevel}"
    shift 2
    local command="$*"

    # shellcheck disable=SC2086
    ssh $SSH_OPTS "${user}@${host}" "$command"
}

# SCP file to a device
# Usage: scp_to <host> <user> <local_path> <remote_path>
scp_to() {
    local host="$1"
    local user="${2:-newlevel}"
    local local_path="$3"
    local remote_path="$4"

    # shellcheck disable=SC2086
    scp $SSH_OPTS "$local_path" "${user}@${host}:${remote_path}"
}

# SCP file from a device
# Usage: scp_from <host> <user> <remote_path> <local_path>
scp_from() {
    local host="$1"
    local user="${2:-newlevel}"
    local remote_path="$3"
    local local_path="$4"

    # shellcheck disable=SC2086
    scp $SSH_OPTS "${user}@${host}:${remote_path}" "$local_path"
}

# Check if device is reachable via SSH
# Usage: ssh_check <host> <user>
ssh_check() {
    local host="$1"
    local user="${2:-newlevel}"

    # shellcheck disable=SC2086
    if ssh $SSH_OPTS -o ConnectTimeout=5 "${user}@${host}" "echo ok" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Detect OS type on remote device
# Usage: detect_os <host> <user>
# Returns: "windows", "linux", or "unknown"
detect_os() {
    local host="$1"
    local user="${2:-newlevel}"

    local uname_output
    uname_output=$(ssh_run "$host" "$user" "uname -s 2>/dev/null || echo WINDOWS" 2>/dev/null || echo "UNKNOWN")

    case "$uname_output" in
        Linux*)
            echo "linux"
            ;;
        Darwin*)
            echo "macos"
            ;;
        CYGWIN*|MINGW*|MSYS*|WINDOWS*)
            echo "windows"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Get remote system info (Linux)
# Usage: get_linux_info <host> <user>
get_linux_info() {
    local host="$1"
    local user="${2:-newlevel}"

    ssh_run "$host" "$user" '
        echo "hostname: $(hostname)"
        if [ -f /etc/os-release ]; then
            source /etc/os-release
            echo "os_version: \"$PRETTY_NAME\""
        fi
        echo "kernel: $(uname -r)"
        echo "cpu: \"$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs)\""
        echo "memory_gb: $(free -g | awk "/^Mem:/{print \$2}")"
        echo "nics:"
        ip -o link show | grep -v "lo:" | awk -F": " "{print \"  - \" \$2}"
    '
}

# Get remote system info (Windows via PowerShell)
# Usage: get_windows_info <host> <user>
get_windows_info() {
    local host="$1"
    local user="${2:-newlevel}"

    ssh_run "$host" "$user" 'powershell -NoProfile -Command "
        $os = Get-CimInstance Win32_OperatingSystem
        $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
        $mem = [math]::Round($os.TotalVisibleMemorySize / 1MB, 0)
        $nics = Get-NetAdapter | Where-Object { $_.Status -eq \"Up\" } | Select-Object -ExpandProperty Name

        Write-Host \"hostname: $env:COMPUTERNAME\"
        Write-Host \"os_version: `\"$($os.Caption) $($os.Version)`\"\"
        Write-Host \"cpu: `\"$($cpu.Name)`\"\"
        Write-Host \"memory_gb: $mem\"
        Write-Host \"nics:\"
        foreach ($nic in $nics) {
            Write-Host \"  - $nic\"
        }
    "'
}
