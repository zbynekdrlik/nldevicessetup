#!/usr/bin/env bash
# NL Devices Setup - Linux Production Setup Script
# Low-latency optimization for audio/video production (Dante, NDI, VBAN)
# Usage: curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/linux/setup.sh | sudo bash

set -euo pipefail

#region Configuration
SCRIPT_VERSION="1.1.0"
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
    sysctl -p "$SYSCTL_CONF" 2>/dev/null || true
    log_success "Network sysctl settings applied and persisted"

    # Apply optional scheduler settings (may not exist on all kernels)
    for param in "kernel.sched_min_granularity_ns=1000000" \
                 "kernel.sched_wakeup_granularity_ns=500000" \
                 "kernel.sched_migration_cost_ns=50000"; do
        sysctl -w "$param" 2>/dev/null && log_success "Set $param" || true
    done

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

    # NOTE: Do NOT restart systemd-logind here - it kills the active desktop session.
    # The logind config takes effect on next login or reboot.

    log_success "Power buttons configured to do nothing (takes effect on next login/reboot)"
    log_info "  - Power key: ignore"
    log_info "  - Suspend key: ignore"
    log_info "  - Lid switch: ignore"
}
#endregion

#region Disable Screen Timeout
disable_screen_timeout() {
    log_info "Disabling screen timeout and screensaver..."

    # GNOME settings (requires running as the desktop user, not just root)
    # We'll create a script that runs on user login
    local autostart_dir="/etc/xdg/autostart"
    mkdir -p "$autostart_dir"

    cat > "$autostart_dir/nldevicessetup-screen.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=NL Devices Setup - Disable Screen Timeout
Exec=/etc/nldevicessetup/disable-screen-timeout.sh
Hidden=false
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF

    local screen_script="/etc/nldevicessetup/disable-screen-timeout.sh"
    mkdir -p "$(dirname "$screen_script")"

    cat > "$screen_script" << 'EOF'
#!/bin/bash
# Disable screen timeout for GNOME/X11

# GNOME settings
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.session idle-delay 0 2>/dev/null || true
    gsettings set org.gnome.desktop.screensaver lock-enabled false 2>/dev/null || true
    gsettings set org.gnome.desktop.screensaver idle-activation-enabled false 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type 'nothing' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type 'nothing' 2>/dev/null || true
    gsettings set org.gnome.settings-daemon.plugins.power idle-dim false 2>/dev/null || true
fi

# X11 settings
if command -v xset &>/dev/null; then
    xset s off 2>/dev/null || true
    xset -dpms 2>/dev/null || true
    xset s noblank 2>/dev/null || true
fi
EOF

    chmod +x "$screen_script"

    # Disable systemd sleep/suspend targets
    systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true

    # Try to run immediately if we have DISPLAY
    if [[ -n "${DISPLAY:-}" ]]; then
        "$screen_script" 2>/dev/null || true
    fi

    log_success "Screen timeout disabled"
    log_info "  - GNOME idle-delay: 0"
    log_info "  - Screensaver: disabled"
    log_info "  - Sleep targets: masked"
}
#endregion

#region Configure Auto Login
configure_auto_login() {
    local target_user="${1:-}"

    # Try to detect the user
    if [[ -z "$target_user" ]]; then
        target_user="${SUDO_USER:-}"
    fi
    if [[ -z "$target_user" ]]; then
        target_user=$(logname 2>/dev/null || true)
    fi
    if [[ -z "$target_user" ]] || [[ "$target_user" == "root" ]]; then
        # Try to find a non-root user with UID >= 1000
        target_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
    fi

    if [[ -z "$target_user" ]]; then
        log_warn "Could not determine user for auto-login - skipping"
        return 1
    fi

    log_info "Configuring auto-login for user: $target_user"

    # GDM3 (GNOME Display Manager)
    local gdm_conf="/etc/gdm3/custom.conf"
    if [[ -f "$gdm_conf" ]]; then
        # Backup
        cp "$gdm_conf" "${gdm_conf}.bak" 2>/dev/null || true

        # Check if [daemon] section exists
        if grep -q '^\[daemon\]' "$gdm_conf"; then
            # Remove existing auto-login settings
            sed -i '/^AutomaticLoginEnable=/d' "$gdm_conf"
            sed -i '/^AutomaticLogin=/d' "$gdm_conf"
            # Add after [daemon]
            sed -i "/^\[daemon\]/a AutomaticLoginEnable=True\nAutomaticLogin=$target_user" "$gdm_conf"
        else
            # Add [daemon] section
            echo -e "\n[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=$target_user" >> "$gdm_conf"
        fi
        log_success "GDM3 auto-login configured for $target_user"
    fi

    # LightDM
    if command_exists lightdm; then
        local lightdm_conf="/etc/lightdm/lightdm.conf.d/99-nldevicessetup.conf"
        mkdir -p "$(dirname "$lightdm_conf")"

        cat > "$lightdm_conf" << EOF
[Seat:*]
autologin-user=$target_user
autologin-user-timeout=0
EOF
        log_success "LightDM auto-login configured for $target_user"
    fi

    # SDDM (KDE)
    local sddm_conf="/etc/sddm.conf.d/99-nldevicessetup.conf"
    if command_exists sddm; then
        mkdir -p "$(dirname "$sddm_conf")"

        cat > "$sddm_conf" << EOF
[Autologin]
User=$target_user
Session=
EOF
        log_success "SDDM auto-login configured for $target_user"
    fi

    log_info "Auto-login will take effect on next reboot"
}
#endregion

#region Optimize Docker
optimize_docker() {
    log_info "Optimizing Docker daemon..."

    if ! command_exists docker; then
        log_warn "Docker not installed - skipping Docker optimization"
        return 0
    fi

    local docker_conf="/etc/docker/daemon.json"
    mkdir -p "$(dirname "$docker_conf")"

    # Backup existing config
    if [[ -f "$docker_conf" ]]; then
        cp "$docker_conf" "${docker_conf}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Backed up existing Docker config"
    fi

    cat > "$docker_conf" << 'EOF'
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "live-restore": true,
    "default-ulimits": {
        "nofile": {
            "Name": "nofile",
            "Hard": 65536,
            "Soft": 65536
        },
        "memlock": {
            "Name": "memlock",
            "Hard": -1,
            "Soft": -1
        }
    },
    "default-shm-size": "256M"
}
EOF

    # Restart Docker to apply (only if it was running)
    if systemctl is-active docker &>/dev/null; then
        log_info "Restarting Docker daemon..."
        systemctl restart docker 2>/dev/null || true
    fi

    log_success "Docker daemon optimized"
    log_info "  - Log rotation: 10MB x 3 files"
    log_info "  - Storage driver: overlay2"
    log_info "  - Live restore: enabled (containers survive daemon restart)"
    log_info "  - ulimits: nofile=65536, memlock=unlimited"
    log_info "  - Default SHM size: 256MB"
}
#endregion

#region Install Essential Software
install_essential_software() {
    log_info "Installing essential software packages..."

    # Update package lists
    apt-get update -qq 2>/dev/null || true

    # Core system tools
    local packages=(
        openssh-server          # SSH remote access
        git                     # Version control
        curl                    # HTTP client
        wget                    # HTTP client
        ethtool                 # NIC configuration
        net-tools               # ifconfig, netstat
        iptables                # Firewall/QoS
        build-essential         # Compiler toolchain
        htop                    # System monitor
        tmux                    # Terminal multiplexer
    )

    # Install packages (skip already installed)
    for pkg in "${packages[@]}"; do
        if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
            log_info "  Installing $pkg..."
            apt-get install -y -qq "$pkg" 2>/dev/null || log_warn "  Could not install $pkg"
        else
            log_info "  $pkg already installed"
        fi
    done

    # Enable and start SSH
    if systemctl is-enabled ssh &>/dev/null || systemctl is-enabled sshd &>/dev/null; then
        log_info "  SSH already enabled"
    else
        systemctl enable --now ssh 2>/dev/null || systemctl enable --now sshd 2>/dev/null || true
    fi
    log_success "SSH server enabled"

    # Install GitHub CLI if not present
    if ! command_exists gh; then
        log_info "  Installing GitHub CLI..."
        (type -p wget >/dev/null || apt-get install wget -y -qq) \
            && mkdir -p -m 755 /etc/apt/keyrings \
            && out=$(mktemp) \
            && wget -qO "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg \
            && cat "$out" | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
            && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
            && apt-get update -qq \
            && apt-get install gh -y -qq 2>/dev/null \
            && rm -f "$out" \
            || log_warn "  Could not install GitHub CLI"
    fi
    if command_exists gh; then
        log_success "GitHub CLI installed"
    fi

    # Install Claude Code CLI if not present
    if ! command_exists claude; then
        log_info "  Installing Claude Code CLI..."
        # Claude Code requires npm/node
        if ! command_exists npm; then
            log_info "  Installing Node.js first..."
            curl -fsSL https://deb.nodesource.com/setup_lts.x 2>/dev/null | bash - 2>/dev/null || true
            apt-get install -y -qq nodejs 2>/dev/null || true
        fi
        if command_exists npm; then
            npm install -g @anthropic-ai/claude-code 2>/dev/null || log_warn "  Could not install Claude Code CLI"
        else
            log_warn "  npm not available - skipping Claude Code CLI"
        fi
    fi
    if command_exists claude; then
        log_success "Claude Code CLI installed"
    fi

    log_success "Essential software installation complete"
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

#region Configure Passwordless Sudo
configure_passwordless_sudo() {
    local target_user="${1:-}"

    # Detect user same way as auto-login
    if [[ -z "$target_user" ]]; then
        target_user="${SUDO_USER:-}"
    fi
    if [[ -z "$target_user" ]]; then
        target_user=$(logname 2>/dev/null || true)
    fi
    if [[ -z "$target_user" ]] || [[ "$target_user" == "root" ]]; then
        target_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
    fi

    if [[ -z "$target_user" ]]; then
        log_warn "Could not determine user for passwordless sudo - skipping"
        return 1
    fi

    log_info "Configuring passwordless sudo for user: $target_user"

    local sudoers_file="/etc/sudoers.d/99-nldevicessetup-${target_user}"
    echo "$target_user ALL=(ALL) NOPASSWD: ALL" > "$sudoers_file"
    chmod 440 "$sudoers_file"

    # Validate sudoers syntax
    if visudo -cf "$sudoers_file" &>/dev/null; then
        log_success "Passwordless sudo configured for $target_user"
    else
        log_error "Invalid sudoers syntax - removing file"
        rm -f "$sudoers_file"
        return 1
    fi
}
#endregion

#region Install DanteTimeSync
install_dante_timesync() {
    log_info "Installing DanteTimeSync..."

    if command_exists dantetimesync; then
        log_success "DanteTimeSync already installed"
        return 0
    fi

    if curl -sSL https://raw.githubusercontent.com/zbynekdrlik/dantesync/master/install.sh | bash; then
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

#region QoS Configuration (Dante/VBAN)
configure_qos() {
    log_info "Configuring QoS for Dante and VBAN..."

    # Check if iptables is available
    if ! command_exists iptables; then
        log_warn "iptables not found - skipping QoS configuration"
        return 1
    fi

    # DSCP Values:
    # - DSCP 56 (CS7) = 0x38 = PTP/Clock sync (highest priority)
    # - DSCP 46 (EF)  = 0x2e = Audio streams (expedited forwarding)
    # - DSCP 8  (CS1) = 0x08 = Control/discovery (low priority)

    # Clear existing nldevicessetup QoS rules
    iptables -t mangle -F NLDEVICESSETUP_QOS 2>/dev/null || true
    iptables -t mangle -D OUTPUT -j NLDEVICESSETUP_QOS 2>/dev/null || true
    iptables -t mangle -X NLDEVICESSETUP_QOS 2>/dev/null || true

    # Create QoS chain
    iptables -t mangle -N NLDEVICESSETUP_QOS 2>/dev/null || true
    iptables -t mangle -A OUTPUT -j NLDEVICESSETUP_QOS

    # ===========================================
    # PTP (Precision Time Protocol) - DSCP 56 (CS7)
    # ===========================================
    # PTP Event messages (port 319)
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 319 -j DSCP --set-dscp 56
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 319 -j DSCP --set-dscp 56
    # PTP General messages (port 320)
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 320 -j DSCP --set-dscp 56
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 320 -j DSCP --set-dscp 56
    log_success "PTP traffic marked with DSCP 56 (CS7)"

    # ===========================================
    # Dante Audio Streams - DSCP 46 (EF)
    # ===========================================
    # Dante primary audio (ports 14336-14600)
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 14336:14600 -j DSCP --set-dscp 46
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 14336:14600 -j DSCP --set-dscp 46
    # Dante secondary audio (ports 4321, 4440)
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 4321 -j DSCP --set-dscp 46
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 4321 -j DSCP --set-dscp 46
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 4440 -j DSCP --set-dscp 46
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 4440 -j DSCP --set-dscp 46
    log_success "Dante audio traffic marked with DSCP 46 (EF)"

    # ===========================================
    # VBAN Audio Streams - DSCP 46 (EF)
    # ===========================================
    # VBAN uses UDP ports 6980-6989
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 6980:6989 -j DSCP --set-dscp 46
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 6980:6989 -j DSCP --set-dscp 46
    log_success "VBAN traffic marked with DSCP 46 (EF)"

    # ===========================================
    # Dante Control/Discovery - DSCP 8 (CS1)
    # ===========================================
    # Dante discovery/control (ports 8700-8708)
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 8700:8708 -j DSCP --set-dscp 8
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 8700:8708 -j DSCP --set-dscp 8
    # Dante Controller (port 4455)
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 4455 -j DSCP --set-dscp 8
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 4455 -j DSCP --set-dscp 8
    # mDNS for Dante discovery
    iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 5353 -j DSCP --set-dscp 8
    log_success "Dante control traffic marked with DSCP 8 (CS1)"

    # ===========================================
    # Persist QoS Rules
    # ===========================================
    local qos_script="/etc/nldevicessetup/qos-rules.sh"
    mkdir -p "$(dirname "$qos_script")"

    cat > "$qos_script" << 'EOFQOS'
#!/bin/bash
# NL Devices Setup - QoS Rules for Dante/VBAN
# Auto-generated - do not edit manually

# Clear existing rules
iptables -t mangle -F NLDEVICESSETUP_QOS 2>/dev/null || true
iptables -t mangle -D OUTPUT -j NLDEVICESSETUP_QOS 2>/dev/null || true
iptables -t mangle -X NLDEVICESSETUP_QOS 2>/dev/null || true

# Create chain
iptables -t mangle -N NLDEVICESSETUP_QOS
iptables -t mangle -A OUTPUT -j NLDEVICESSETUP_QOS

# PTP - DSCP 56 (CS7)
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 319 -j DSCP --set-dscp 56
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 319 -j DSCP --set-dscp 56
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 320 -j DSCP --set-dscp 56
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 320 -j DSCP --set-dscp 56

# Dante Audio - DSCP 46 (EF)
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 14336:14600 -j DSCP --set-dscp 46
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 14336:14600 -j DSCP --set-dscp 46
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 4321 -j DSCP --set-dscp 46
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 4321 -j DSCP --set-dscp 46
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 4440 -j DSCP --set-dscp 46
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 4440 -j DSCP --set-dscp 46

# VBAN - DSCP 46 (EF)
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 6980:6989 -j DSCP --set-dscp 46
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 6980:6989 -j DSCP --set-dscp 46

# Dante Control - DSCP 8 (CS1)
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 8700:8708 -j DSCP --set-dscp 8
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 8700:8708 -j DSCP --set-dscp 8
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 4455 -j DSCP --set-dscp 8
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --sport 4455 -j DSCP --set-dscp 8
iptables -t mangle -A NLDEVICESSETUP_QOS -p udp --dport 5353 -j DSCP --set-dscp 8
EOFQOS

    chmod +x "$qos_script"

    # Create systemd service for persistence
    cat > /etc/systemd/system/nldevicessetup-qos.service << EOF
[Unit]
Description=NL Devices Setup QoS Rules (Dante/VBAN)
After=network.target

[Service]
Type=oneshot
ExecStart=$qos_script
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nldevicessetup-qos.service 2>/dev/null || true
    log_success "QoS rules persisted via systemd service"

    log_info "QoS Configuration Summary:"
    log_info "  PTP (ports 319-320):        DSCP 56 (CS7) - highest priority"
    log_info "  Dante Audio (14336-14600):  DSCP 46 (EF)  - audio priority"
    log_info "  VBAN (ports 6980-6989):     DSCP 46 (EF)  - audio priority"
    log_info "  Dante Control (8700-8708):  DSCP 8  (CS1) - low priority"
}
#endregion

#region Summary
show_summary() {
    log_section "SETUP COMPLETE"

    echo ""
    log_success "Optimizations Applied:"
    echo "  - Essential software: SSH, git, gh, claude, ethtool, etc."
    echo "  - Passwordless sudo: configured"
    echo "  - CPU governor: performance"
    echo "  - USB/PCI power management: disabled"
    echo "  - Power buttons/lid: do nothing"
    echo "  - Screen timeout/screensaver: disabled"
    echo "  - Sleep/suspend/hibernate: masked"
    echo "  - Auto-login: configured"
    echo "  - Network buffers: optimized for low latency"
    echo "  - TCP: BBR, no slow start, low latency mode"
    echo "  - NIC settings: EEE off, flow control off, offloading off"
    echo "  - Kernel scheduling: tuned for responsiveness"
    echo "  - Memory: low swappiness, fast writeback"
    echo "  - Realtime limits: configured for audio group"
    echo "  - QoS: Dante/VBAN DSCP marking enabled"
    echo "  - Docker: log rotation, live-restore, ulimits"
    echo "  - DanteTimeSync: installed"
    echo ""
    log_info "QoS DSCP Markings:"
    echo "  - PTP (319-320):       DSCP 56 (CS7)"
    echo "  - Dante Audio:         DSCP 46 (EF)"
    echo "  - VBAN (6980-6989):    DSCP 46 (EF)"
    echo "  - Dante Control:       DSCP 8  (CS1)"
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

    # Install essential software first
    log_section "ESSENTIAL SOFTWARE"
    install_essential_software

    log_section "PASSWORDLESS SUDO"
    configure_passwordless_sudo

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

    log_section "POWER BUTTONS & SCREEN"
    disable_power_buttons
    disable_screen_timeout

    log_section "AUTO LOGIN"
    configure_auto_login

    log_section "SERVICES"
    disable_unnecessary_services

    log_section "DOCKER OPTIMIZATION"
    optimize_docker

    log_section "QOS CONFIGURATION"
    configure_qos

    log_section "SOFTWARE INSTALLATION"
    install_dante_timesync

    # Show summary
    show_summary
}

main "$@"
#endregion
