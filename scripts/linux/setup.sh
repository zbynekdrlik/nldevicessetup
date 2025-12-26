#!/usr/bin/env bash
# NL Devices Setup - Linux Production Setup Script
# Low-latency optimization for audio/video production (Dante, NDI, VBAN)
# Usage: curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/linux/setup.sh | sudo bash

set -euo pipefail

#region Configuration
SCRIPT_VERSION="1.0.0"
SYSCTL_CONF="/etc/sysctl.d/99-nldevicessetup.conf"
LIMITS_CONF="/etc/security/limits.d/99-nldevicessetup.conf"
UDEV_CONF="/etc/udev/rules.d/99-nldevicessetup.rules"
LOG_DIR="/var/log/nldevicessetup"
LOG_FILE="$LOG_DIR/setup.log"
#endregion

#region Colors and Logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*" | tee -a "$LOG_FILE"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
log_section() { echo -e "\n${CYAN}═══════════════════════════════════════════════════════${NC}" | tee -a "$LOG_FILE"; echo -e "${CYAN} $*${NC}" | tee -a "$LOG_FILE"; echo -e "${CYAN}═══════════════════════════════════════════════════════${NC}\n" | tee -a "$LOG_FILE"; }
#endregion

#region Helper Functions
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

command_exists() {
    command -v "$1" &>/dev/null
}

set_sysctl() {
    local key="$1"
    local value="$2"

    if sysctl -w "${key}=${value}" &>/dev/null; then
        log_success "Set $key=$value"
    else
        log_warn "Could not set $key (may not be supported)"
    fi
}

persist_sysctl() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "$SYSCTL_CONF" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$SYSCTL_CONF"
    else
        echo "${key}=${value}" >> "$SYSCTL_CONF"
    fi
}

get_network_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v '^lo$' | grep -v '@'
}
#endregion

#region Banner
show_banner() {
    echo -e "${CYAN}"
    cat << 'EOF'
  _   _ _     ____             _                 ____       _
 | \ | | |   |  _ \  _____   _(_) ___ ___  ___  / ___|  ___| |_ _   _ _ __
 |  \| | |   | | | |/ _ \ \ / / |/ __/ _ \/ __| \___ \ / _ \ __| | | | '_ \
 | |\  | |___| |_| |  __/\ V /| | (_|  __/\__ \  ___) |  __/ |_| |_| | |_) |
 |_| \_|_____|____/ \___| \_/ |_|\___\___||___/ |____/ \___|\__|\__,_| .__/
                                                                      |_|
EOF
    echo -e "${NC}"
    echo " Linux Production Setup Script v${SCRIPT_VERSION}"
    echo " Low-latency optimization for Dante, NDI, VBAN"
    echo ""
}
#endregion

#region System Info
show_system_info() {
    log_info "Hostname: $(hostname)"
    log_info "Kernel: $(uname -r)"
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        log_info "OS: ${PRETTY_NAME:-$ID}"
    fi
    echo ""
}
#endregion

#region CPU Governor (Performance Mode)
optimize_cpu_governor() {
    log_info "Setting CPU governor to performance..."

    local governor_set=0
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        if [[ -f "$cpu" ]]; then
            echo "performance" > "$cpu" 2>/dev/null && governor_set=1
        fi
    done

    if [[ $governor_set -eq 1 ]]; then
        log_success "CPU governor set to performance"
    else
        log_warn "Could not set CPU governor (may not be supported)"
    fi

    # Disable CPU idle states for lowest latency (optional, aggressive)
    for cpu in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
        if [[ -f "$cpu" ]]; then
            echo 1 > "$cpu" 2>/dev/null || true
        fi
    done

    # Persist via kernel parameter hint
    if command_exists tuned-adm; then
        tuned-adm profile latency-performance 2>/dev/null || true
        log_info "Applied tuned latency-performance profile"
    fi
}
#endregion

#region Power Management (Disable)
disable_power_management() {
    log_info "Disabling power management..."

    # Disable USB autosuspend
    for usb in /sys/bus/usb/devices/*/power/autosuspend; do
        if [[ -f "$usb" ]]; then
            echo -1 > "$usb" 2>/dev/null || true
        fi
    done

    for usb in /sys/bus/usb/devices/*/power/control; do
        if [[ -f "$usb" ]]; then
            echo "on" > "$usb" 2>/dev/null || true
        fi
    done
    log_success "USB autosuspend disabled"

    # Disable PCI power management
    for pci in /sys/bus/pci/devices/*/power/control; do
        if [[ -f "$pci" ]]; then
            echo "on" > "$pci" 2>/dev/null || true
        fi
    done
    log_success "PCI power management disabled"

    # Disable ASPM (Active State Power Management)
    if [[ -f /sys/module/pcie_aspm/parameters/policy ]]; then
        echo "performance" > /sys/module/pcie_aspm/parameters/policy 2>/dev/null || true
        log_success "PCIe ASPM set to performance"
    fi

    # Persist USB autosuspend via udev
    cat > "$UDEV_CONF" << 'EOF'
# NL Devices Setup - Disable USB autosuspend
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/autosuspend}="-1"
ACTION=="add", SUBSYSTEM=="usb", ATTR{power/control}="on"
EOF
    log_info "Created udev rules for persistent USB settings"
}
#endregion

#region Network Optimization
optimize_network_sysctl() {
    log_info "Optimizing network stack..."

    # Create sysctl config
    cat > "$SYSCTL_CONF" << 'EOF'
# NL Devices Setup - Low-Latency Network Optimization
# Generated automatically - do not edit manually

# ===========================================
# Network Buffer Sizes
# ===========================================
net.core.rmem_max = 26214400
net.core.wmem_max = 26214400
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 65535

# ===========================================
# TCP Optimization
# ===========================================
net.ipv4.tcp_rmem = 4096 1048576 26214400
net.ipv4.tcp_wmem = 4096 1048576 26214400
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_fastopen = 3

# ===========================================
# UDP Optimization (for Dante/AES67)
# ===========================================
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# ===========================================
# Kernel Scheduling (Low Latency)
# ===========================================
kernel.sched_min_granularity_ns = 1000000
kernel.sched_wakeup_granularity_ns = 500000
kernel.sched_migration_cost_ns = 50000
kernel.sched_autogroup_enabled = 0

# ===========================================
# Memory Management
# ===========================================
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.dirty_writeback_centisecs = 100

# ===========================================
# Timer/Interrupt Optimization
# ===========================================
kernel.timer_migration = 0
EOF

    # Apply sysctl settings
    sysctl -p "$SYSCTL_CONF" &>/dev/null
    log_success "Network sysctl settings applied and persisted"

    # Enable BBR if available
    if [[ -f /proc/sys/net/ipv4/tcp_available_congestion_control ]]; then
        if grep -q bbr /proc/sys/net/ipv4/tcp_available_congestion_control; then
            echo "net.ipv4.tcp_congestion_control = bbr" >> "$SYSCTL_CONF"
            sysctl -w net.ipv4.tcp_congestion_control=bbr &>/dev/null
            log_success "TCP BBR congestion control enabled"
        fi
    fi
}

optimize_network_interfaces() {
    log_info "Optimizing network interfaces..."

    for iface in $(get_network_interfaces); do
        log_info "  Configuring: $iface"

        # Disable interrupt coalescing for lower latency (if ethtool available)
        if command_exists ethtool; then
            # Disable EEE (Energy Efficient Ethernet)
            ethtool --set-eee "$iface" eee off 2>/dev/null || true

            # Disable flow control
            ethtool -A "$iface" rx off tx off 2>/dev/null || true

            # Optimize interrupt coalescing (lower values = lower latency)
            ethtool -C "$iface" rx-usecs 0 tx-usecs 0 2>/dev/null || true

            # Disable offloading features that can add latency
            ethtool -K "$iface" tso off gso off gro off lro off 2>/dev/null || true

            log_success "    $iface: EEE=off, flow-ctrl=off, offload=off"
        else
            log_warn "    ethtool not found - skipping NIC tuning for $iface"
        fi

        # Set interface queue length
        ip link set "$iface" txqueuelen 10000 2>/dev/null || true
    done
}
#endregion

#region Realtime Limits
configure_realtime_limits() {
    log_info "Configuring realtime scheduling limits..."

    cat > "$LIMITS_CONF" << 'EOF'
# NL Devices Setup - Realtime Audio Limits
# Allow users in audio group to use realtime scheduling

@audio   -  rtprio     99
@audio   -  memlock    unlimited
@audio   -  nice       -20

# Also for root
root     -  rtprio     99
root     -  memlock    unlimited
EOF

    log_success "Realtime limits configured in $LIMITS_CONF"

    # Create audio group if it doesn't exist
    if ! getent group audio &>/dev/null; then
        groupadd audio
        log_info "Created 'audio' group"
    fi
}
#endregion

#region Timer Resolution
optimize_timer_resolution() {
    log_info "Optimizing timer resolution..."

    # Check current timer resolution
    if [[ -f /proc/timer_list ]]; then
        local resolution
        resolution=$(grep -m1 'resolution:' /proc/timer_list 2>/dev/null | awk '{print $2}')
        log_info "Current timer resolution: ${resolution:-unknown} ns"
    fi

    # Disable kernel watchdog for lowest latency (optional)
    if [[ -f /proc/sys/kernel/watchdog ]]; then
        log_info "Consider disabling watchdog for lowest latency:"
        log_info "  echo 0 > /proc/sys/kernel/watchdog"
    fi

    # Check for realtime kernel
    if uname -r | grep -qi 'rt\|preempt'; then
        log_success "Realtime/PREEMPT kernel detected"
    else
        log_info "Consider installing a PREEMPT_RT kernel for lowest latency"
    fi
}
#endregion

#region Disable Power Buttons
disable_power_buttons() {
    log_info "Configuring power buttons to do nothing..."

    local logind_conf="/etc/systemd/logind.conf.d/99-nldevicessetup.conf"
    mkdir -p "$(dirname "$logind_conf")"

    cat > "$logind_conf" << 'EOF'
# NL Devices Setup - Disable power buttons
# Prevent accidental shutdown/suspend during production

[Login]
HandlePowerKey=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
IdleAction=ignore
EOF

    # Restart logind to apply
    systemctl restart systemd-logind 2>/dev/null || true

    log_success "Power buttons configured to do nothing"
    log_info "  - Power key: ignore"
    log_info "  - Suspend key: ignore"
    log_info "  - Lid switch: ignore"
}
#endregion

#region Disable Unnecessary Services
disable_unnecessary_services() {
    log_info "Checking unnecessary services..."

    local services_to_disable=(
        "cups"              # Print spooler
        "avahi-daemon"      # mDNS (can conflict with Dante)
        "bluetooth"         # Bluetooth
        "ModemManager"      # Modem manager
    )

    for svc in "${services_to_disable[@]}"; do
        if systemctl is-active "$svc" &>/dev/null; then
            log_info "  Stopping $svc..."
            systemctl stop "$svc" 2>/dev/null || true
            systemctl disable "$svc" 2>/dev/null || true
            log_success "  $svc disabled"
        fi
    done
}
#endregion

#region Install DanteTimeSync
install_dante_timesync() {
    log_info "Installing DanteTimeSync..."

    if command_exists dantetimesync; then
        log_success "DanteTimeSync already installed"
        return 0
    fi

    if curl -sSL https://raw.githubusercontent.com/zbynekdrlik/dantetimesync/master/install.sh | bash; then
        log_success "DanteTimeSync installed"
    else
        log_warn "Failed to install DanteTimeSync"
    fi
}
#endregion

#region IRQ Affinity
optimize_irq_affinity() {
    log_info "Checking IRQ affinity..."

    # Get number of CPUs
    local num_cpus
    num_cpus=$(nproc)

    if [[ $num_cpus -ge 2 ]]; then
        log_info "System has $num_cpus CPUs - consider isolating CPU cores for audio"
        log_info "  Add 'isolcpus=1' to kernel parameters to isolate CPU 1"
    fi

    # If irqbalance is running, consider disabling for audio workloads
    if systemctl is-active irqbalance &>/dev/null; then
        log_info "irqbalance is running - consider disabling for lowest latency"
    fi
}
#endregion

#region Summary
show_summary() {
    log_section "SETUP COMPLETE"

    echo ""
    log_success "Optimizations Applied:"
    echo "  - CPU governor: performance"
    echo "  - USB/PCI power management: disabled"
    echo "  - Power buttons/lid: do nothing"
    echo "  - Network buffers: optimized for low latency"
    echo "  - TCP: BBR, no slow start, low latency mode"
    echo "  - NIC settings: EEE off, flow control off, offloading off"
    echo "  - Kernel scheduling: tuned for responsiveness"
    echo "  - Memory: low swappiness, fast writeback"
    echo "  - Realtime limits: configured for audio group"
    echo "  - DanteTimeSync: installed"
    echo ""
    log_info "Configuration files:"
    echo "  - $SYSCTL_CONF"
    echo "  - $LIMITS_CONF"
    echo "  - $UDEV_CONF"
    echo ""
    log_info "Log file: $LOG_FILE"
    echo ""
    log_warn "RECOMMENDED: Reboot your system for all changes to take effect"
    echo ""
}
#endregion

#region Main
main() {
    # Create log directory
    mkdir -p "$LOG_DIR"

    # Check root
    require_root

    # Show banner
    show_banner
    show_system_info

    # Apply optimizations
    log_section "POWER MANAGEMENT"
    optimize_cpu_governor
    disable_power_management

    log_section "NETWORK OPTIMIZATION"
    optimize_network_sysctl
    optimize_network_interfaces

    log_section "SYSTEM TUNING"
    configure_realtime_limits
    optimize_timer_resolution
    optimize_irq_affinity

    log_section "POWER BUTTONS"
    disable_power_buttons

    log_section "SERVICES"
    disable_unnecessary_services

    log_section "SOFTWARE INSTALLATION"
    install_dante_timesync

    # Show summary
    show_summary
}

main "$@"
#endregion
