#!/usr/bin/env bash
# Common functions for nldevicessetup Linux scripts
# shellcheck disable=SC2034

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Check if running as root
require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check if running as non-root
require_non_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root"
        exit 1
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Backup file before modification
backup_file() {
    local file="$1"
    local backup_dir="${2:-/var/backup/nldevicessetup}"

    if [[ -f "$file" ]]; then
        mkdir -p "$backup_dir"
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup_name
        backup_name=$(basename "$file")
        cp "$file" "${backup_dir}/${backup_name}.${timestamp}.bak"
        log_info "Backed up $file to ${backup_dir}/${backup_name}.${timestamp}.bak"
    fi
}

# Set sysctl parameter idempotently
set_sysctl() {
    local key="$1"
    local value="$2"
    local current

    if current=$(sysctl -n "$key" 2>/dev/null); then
        if [[ "$current" == "$value" ]]; then
            log_info "sysctl $key already set to $value"
            return 0
        fi
    fi

    if sysctl -w "${key}=${value}" &>/dev/null; then
        log_success "Set sysctl $key=$value"
        return 0
    else
        log_error "Failed to set sysctl $key=$value"
        return 1
    fi
}

# Persist sysctl setting
persist_sysctl() {
    local key="$1"
    local value="$2"
    local conf_file="${3:-/etc/sysctl.d/99-nldevicessetup.conf}"

    mkdir -p "$(dirname "$conf_file")"

    if grep -q "^${key}=" "$conf_file" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=${value}|" "$conf_file"
    else
        echo "${key}=${value}" >> "$conf_file"
    fi

    log_info "Persisted $key=$value to $conf_file"
}

# Get OS information
get_os_info() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        echo "${ID:-unknown}"
    else
        echo "unknown"
    fi
}

# Check minimum kernel version
check_kernel_version() {
    local required="$1"
    local current
    current=$(uname -r | cut -d'-' -f1)

    if [[ "$(printf '%s\n' "$required" "$current" | sort -V | head -n1)" == "$required" ]]; then
        return 0
    else
        return 1
    fi
}

# Dry run mode support
DRY_RUN="${DRY_RUN:-false}"

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# Version
NLDEVICESSETUP_VERSION="${NLDEVICESSETUP_VERSION:-dev}"
