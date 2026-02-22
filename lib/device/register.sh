#!/usr/bin/env bash
# Device registration script for nldevicessetup
# Registers a device by gathering system info via SSH and creating YAML files

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/device/ssh.sh
source "$SCRIPT_DIR/ssh.sh"
# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"

# Register a device
# Usage: register_device <hostname> <profile> [ssh_user]
register_device() {
    local hostname="$1"
    local profile="${2:-base-workstation}"
    local ssh_user="${3:-newlevel}"

    local devices_dir="$PROJECT_ROOT/devices"
    local device_dir="$devices_dir/$hostname"

    log_info "Registering device: $hostname"

    # Check SSH connectivity
    log_info "Checking SSH connectivity..."
    if ! ssh_check "$hostname" "$ssh_user"; then
        log_error "Cannot reach $hostname via SSH as $ssh_user"
        return 1
    fi
    log_success "SSH connection successful"

    # Detect OS
    log_info "Detecting operating system..."
    local os_type
    os_type=$(detect_os "$hostname" "$ssh_user")
    log_info "Detected OS: $os_type"

    if [[ "$os_type" == "unknown" ]]; then
        log_error "Could not detect OS type for $hostname"
        return 1
    fi

    # Get IP address (resolve hostname)
    local ip_address
    ip_address=$(getent hosts "$hostname" 2>/dev/null | awk '{print $1}' | head -1 || echo "")
    if [[ -z "$ip_address" ]]; then
        # Try direct ping
        ip_address=$(ping -c1 "$hostname" 2>/dev/null | grep -oP '(?<=\()[\d.]+(?=\))' | head -1 || echo "")
    fi

    # Create device directory
    mkdir -p "$device_dir/history"

    # Get system info based on OS
    log_info "Gathering system information..."
    local system_info
    if [[ "$os_type" == "linux" ]]; then
        system_info=$(get_linux_info "$hostname" "$ssh_user")
    elif [[ "$os_type" == "windows" ]]; then
        system_info=$(get_windows_info "$hostname" "$ssh_user")
    fi

    # Extract info from gathered data
    local os_version cpu_info memory_gb
    os_version=$(echo "$system_info" | grep "^os_version:" | sed 's/os_version: //' | tr -d '"' || echo "unknown")
    cpu_info=$(echo "$system_info" | grep "^cpu:" | sed 's/cpu: //' | tr -d '"' || echo "unknown")
    memory_gb=$(echo "$system_info" | grep "^memory_gb:" | cut -d: -f2 | xargs || echo "0")

    # Generate timestamp
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Create device.yml
    log_info "Creating device.yml..."
    cat > "$device_dir/device.yml" << EOF
# Device registration for $hostname
# Generated: $timestamp

hostname: $hostname
ip: ${ip_address:-""}
os: $os_type
os_version: "$os_version"
profile: $profile
tags:
  - production
ssh_user: $ssh_user
ssh_port: 22
registered: $timestamp
last_seen: $timestamp

hardware:
  cpu: "$cpu_info"
  memory_gb: $memory_gb
EOF

    # Append NICs if available
    local nics_section
    nics_section=$(echo "$system_info" | sed -n '/^nics:/,$p')
    if [[ -n "$nics_section" ]]; then
        echo "  nics:" >> "$device_dir/device.yml"
        echo "$nics_section" | tail -n +2 >> "$device_dir/device.yml"
    fi

    # Create initial state.yml
    log_info "Creating initial state.yml..."
    cat > "$device_dir/state.yml" << EOF
# Current state for $hostname
# Last updated: $timestamp

last_updated: $timestamp

software: {}

optimizations:
  network: {}
  power: {}
  audio: {}

applied_recipes: []
EOF

    log_success "Device $hostname registered successfully"
    log_info "  Device directory: $device_dir"
    log_info "  Profile: $profile"
    log_info "  OS: $os_type ($os_version)"

    # Return device directory path
    echo "$device_dir"
}

# Update last_seen timestamp for a device
# Usage: update_last_seen <hostname>
update_last_seen() {
    local hostname="$1"
    local device_file="$PROJECT_ROOT/devices/$hostname/device.yml"

    if [[ ! -f "$device_file" ]]; then
        log_error "Device $hostname not found"
        return 1
    fi

    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update last_seen using sed
    sed -i "s/^last_seen:.*/last_seen: $timestamp/" "$device_file"
    log_info "Updated last_seen for $hostname to $timestamp"
}

# List all registered devices
# Usage: list_devices
list_devices() {
    local devices_dir="$PROJECT_ROOT/devices"

    if [[ ! -d "$devices_dir" ]]; then
        log_warn "No devices directory found"
        return 0
    fi

    echo "Registered devices:"
    echo "==================="

    for device_dir in "$devices_dir"/*/; do
        if [[ -f "${device_dir}device.yml" ]]; then
            local hostname os profile
            hostname=$(basename "$device_dir")
            os=$(grep "^os:" "${device_dir}device.yml" | cut -d: -f2 | xargs)
            profile=$(grep "^profile:" "${device_dir}device.yml" | cut -d: -f2 | xargs)
            printf "  %-20s %-10s %s\n" "$hostname" "$os" "$profile"
        fi
    done
}

# Main entry point for CLI usage
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        register)
            if [[ $# -lt 1 ]]; then
                echo "Usage: register.sh register <hostname> [profile] [ssh_user]"
                exit 1
            fi
            register_device "$@"
            ;;
        list)
            list_devices
            ;;
        update)
            if [[ $# -lt 1 ]]; then
                echo "Usage: register.sh update <hostname>"
                exit 1
            fi
            update_last_seen "$1"
            ;;
        help|--help|-h)
            echo "Device Registration Tool"
            echo ""
            echo "Usage: register.sh <command> [options]"
            echo ""
            echo "Commands:"
            echo "  register <hostname> [profile] [ssh_user]  Register a new device"
            echo "  list                                       List all registered devices"
            echo "  update <hostname>                          Update last_seen timestamp"
            echo "  help                                       Show this help"
            ;;
        *)
            log_error "Unknown command: $command"
            exit 1
            ;;
    esac
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
