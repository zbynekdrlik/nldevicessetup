#!/usr/bin/env bash
# NL Devices Setup - Linux Bootstrap Installer
# Usage: curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.sh | bash
#    or: curl -sSL https://raw.githubusercontent.com/zbynekdrlik/nldevicessetup/main/scripts/bootstrap/install.sh | bash -s -- --help

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
    curl -sSL ${RAW_URL}/scripts/bootstrap/install.sh | bash
    curl -sSL ${RAW_URL}/scripts/bootstrap/install.sh | bash -s -- [OPTIONS]

Options:
    --help          Show this help message
    --version VER   Install specific version (default: latest)
    --dir DIR       Installation directory (default: /opt/nldevicessetup)
    --dry-run       Show what would be done without making changes
    --optimize      Run optimization after installation
    --modules MOD   Comma-separated list of modules to apply (default: all)

Modules:
    network         Network stack optimizations
    latency         Low-latency kernel parameters
    filesystem      Filesystem tuning
    realtime        Realtime scheduling setup
    all             All modules (default)

Examples:
    # Install and optimize
    curl -sSL ... | bash -s -- --optimize

    # Install specific version
    curl -sSL ... | bash -s -- --version v1.0.0

    # Only apply network tuning
    curl -sSL ... | bash -s -- --optimize --modules network

EOF
}

check_requirements() {
    local missing=()

    for cmd in curl git; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required commands: ${missing[*]}"
        log_info "Install them with your package manager:"
        log_info "  apt install ${missing[*]}    # Debian/Ubuntu"
        log_info "  dnf install ${missing[*]}    # Fedora/RHEL"
        log_info "  pacman -S ${missing[*]}      # Arch"
        exit 1
    fi
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

    # Create symlink for easy access
    if [[ -d /usr/local/bin ]]; then
        ln -sf "$install_dir/scripts/linux/optimize.sh" /usr/local/bin/nldevicessetup 2>/dev/null || true
    fi

    log_success "Installation complete!"
}

run_optimization() {
    local install_dir="$1"
    local modules="$2"
    local dry_run="$3"

    log_info "Running optimization (modules: $modules, dry-run: $dry_run)"

    local optimize_script="$install_dir/scripts/linux/optimize.sh"

    if [[ ! -x "$optimize_script" ]]; then
        log_error "Optimization script not found: $optimize_script"
        exit 1
    fi

    local args=()
    [[ "$dry_run" == "true" ]] && args+=("--dry-run")
    [[ "$modules" != "all" ]] && args+=("--modules" "$modules")

    # Need root for optimization
    if [[ $EUID -ne 0 ]]; then
        log_warn "Optimization requires root privileges"
        sudo "$optimize_script" "${args[@]}"
    else
        "$optimize_script" "${args[@]}"
    fi
}

main() {
    local version="$VERSION"
    local install_dir="$INSTALL_DIR"
    local dry_run="false"
    local optimize="false"
    local modules="all"

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
            --optimize|-o)
                optimize="true"
                shift
                ;;
            --modules|-m)
                modules="$2"
                shift 2
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

    check_requirements

    if [[ "$version" == "latest" ]]; then
        version=$(get_latest_version)
        log_info "Latest version: $version"
    fi

    if [[ "$dry_run" == "true" ]]; then
        log_info "[DRY-RUN] Would install to: $install_dir"
        log_info "[DRY-RUN] Version: $version"
        [[ "$optimize" == "true" ]] && log_info "[DRY-RUN] Would run optimization with modules: $modules"
        exit 0
    fi

    install_nldevicessetup "$version" "$install_dir"

    if [[ "$optimize" == "true" ]]; then
        run_optimization "$install_dir" "$modules" "$dry_run"
    else
        log_info ""
        log_info "To run optimization:"
        log_info "  sudo $install_dir/scripts/linux/optimize.sh"
        log_info ""
        log_info "Or simply:"
        log_info "  sudo nldevicessetup"
    fi
}

main "$@"
