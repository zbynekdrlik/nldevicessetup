#!/usr/bin/env bash
# NL Devices Setup - Linux Bootstrap Installer
# Usage: curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.sh | sudo bash
#    or: curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.sh | sudo bash -s -- --help

set -euo pipefail

REPO_URL="https://github.com/zbynekdrlik/nldevicessetup"
RAW_URL="https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main"
INSTALL_DIR="${NLDEVICESSETUP_DIR:-/opt/nldevicessetup}"
VERSION="${NLDEVICESSETUP_VERSION:-latest}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

show_help() {
    cat << EOF
NL Devices Setup - Linux Bootstrap Installer

Usage:
    curl -sSL ${RAW_URL}/scripts/bootstrap/install.sh | sudo bash
    curl -sSL ${RAW_URL}/scripts/bootstrap/install.sh | sudo bash -s -- [OPTIONS]

Options:
    --help          Show this help message
    --version VER   Install specific version (default: latest)
    --dir DIR       Installation directory (default: /opt/nldevicessetup)
    --dry-run       Show what would be done without making changes
    --setup         Run full production setup after installation (recommended)
    --modules MOD   Comma-separated list of modules to apply (default: all)

Examples:
    # Install and run full setup (recommended)
    curl -sSL ... | sudo bash -s -- --setup

    # Install only (run setup later with: sudo nldevicessetup)
    curl -sSL ... | sudo bash

    # Install specific version
    curl -sSL ... | sudo bash -s -- --version v1.0.0

EOF
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root. Use:"
        log_error "  curl -sSL ${RAW_URL}/scripts/bootstrap/install.sh | sudo bash"
        exit 1
    fi
}

install_requirements() {
    # Auto-install git and curl if missing
    local missing=()

    for cmd in curl git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        return 0
    fi

    log_info "Installing missing requirements: ${missing[*]}"

    # Detect package manager and install
    if command -v apt-get &>/dev/null; then
        apt-get update -qq 2>/dev/null || true
        apt-get install -y -qq "${missing[@]}" 2>/dev/null
    elif command -v dnf &>/dev/null; then
        dnf install -y -q "${missing[@]}" 2>/dev/null
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm "${missing[@]}" 2>/dev/null
    else
        log_error "Could not auto-install: ${missing[*]}"
        log_error "Please install them manually and re-run."
        exit 1
    fi

    # Verify installation
    for cmd in "${missing[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Failed to install $cmd"
            exit 1
        fi
    done

    log_success "Requirements installed: ${missing[*]}"
}

get_latest_version() {
    curl -sSL "https://api.github.com/repos/zbynekdrlik/nldevicessetup/releases/latest" 2>/dev/null | \
        grep '"tag_name"' | \
        sed -E 's/.*"tag_name": "([^"]+)".*/\1/' || echo "main"
}

install_nldevicessetup() {
    local version="$1"
    local install_dir="$2"

    log_info "Installing nldevicessetup ${version} to ${install_dir}"

    if [[ -d "$install_dir" ]]; then
        log_warn "Installation directory exists, updating..."
        cd "$install_dir"
        git fetch --all --tags
        if [[ "$version" == "latest" || "$version" == "main" ]]; then
            git checkout main
            git pull origin main
        else
            git checkout "$version"
        fi
    else
        if [[ "$version" == "latest" || "$version" == "main" ]]; then
            git clone "$REPO_URL" "$install_dir"
        else
            git clone --branch "$version" "$REPO_URL" "$install_dir"
        fi
    fi

    # Make scripts executable
    find "$install_dir/scripts" -name "*.sh" -exec chmod +x {} \;

    # Create symlink for easy access (points to full setup script)
    if [[ -d /usr/local/bin ]]; then
        ln -sf "$install_dir/scripts/linux/setup.sh" /usr/local/bin/nldevicessetup 2>/dev/null || true
    fi

    log_success "Installation complete!"
}

run_setup() {
    local install_dir="$1"

    log_info "Running full production setup..."

    local setup_script="$install_dir/scripts/linux/setup.sh"

    if [[ ! -x "$setup_script" ]]; then
        log_error "Setup script not found: $setup_script"
        exit 1
    fi

    "$setup_script"
}

main() {
    local version="$VERSION"
    local install_dir="$INSTALL_DIR"
    local dry_run="false"
    local run_setup_flag="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --version|-v)
                version="$2"
                shift 2
                ;;
            --dir|-d)
                install_dir="$2"
                shift 2
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            --setup|-s|--optimize|-o)
                run_setup_flag="true"
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo ""
    echo "  _   _ _     ____             _                 ____       _               "
    echo " | \\ | | |   |  _ \\  _____   _(_) ___ ___  ___  / ___|  ___| |_ _   _ _ __  "
    echo " |  \\| | |   | | | |/ _ \\ \\ / / |/ __/ _ \\/ __| \\___ \\ / _ \\ __| | | | '_ \\ "
    echo " | |\\  | |___| |_| |  __/\\ V /| | (_|  __/\\__ \\  ___) |  __/ |_| |_| | |_) |"
    echo " |_| \\_|_____|____/ \\___| \\_/ |_|\\___\\___||___/ |____/ \\___|\\__|\\__,_| .__/ "
    echo "                                                                     |_|    "
    echo ""

    require_root
    install_requirements

    if [[ "$version" == "latest" ]]; then
        version=$(get_latest_version)
        log_info "Latest version: $version"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would install to: $install_dir"
        log_info "[DRY-RUN] Version: $version"
        [[ "$run_setup_flag" == "true" ]] && log_info "[DRY-RUN] Would run full setup"
        exit 0
    fi

    install_nldevicessetup "$version" "$install_dir"

    if [[ "$run_setup_flag" == "true" ]]; then
        run_setup "$install_dir"
    else
        log_info ""
        log_info "To run full production setup:"
        log_info "  sudo nldevicessetup"
        log_info ""
        log_info "Or directly:"
        log_info "  sudo $install_dir/scripts/linux/setup.sh"
    fi
}

main "$@"
