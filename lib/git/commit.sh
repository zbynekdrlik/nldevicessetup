#!/usr/bin/env bash
# Git commit helpers for nldevicessetup
# Provides consistent git operations for device state tracking

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"

# Commit changes with a standardized message
# Usage: git_commit <message> [files...]
git_commit() {
    local message="$1"
    shift
    local files=("$@")

    cd "$PROJECT_ROOT"

    # Add specified files or all changes
    if [[ ${#files[@]} -gt 0 ]]; then
        for file in "${files[@]}"; do
            git add "$file" 2>/dev/null || true
        done
    else
        git add -A
    fi

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        log_info "No changes to commit"
        return 0
    fi

    # Commit with message
    git commit -m "$message" --no-gpg-sign 2>/dev/null || {
        log_warn "Git commit failed (may be normal if nothing to commit)"
        return 0
    }

    # Get commit SHA
    local sha
    sha=$(git rev-parse HEAD)
    log_success "Committed: $sha"
    echo "$sha"
}

# Commit execution plan before running
# Usage: commit_plan <hostname> <recipe> <session_id>
commit_plan() {
    local hostname="$1"
    local recipe="$2"
    local session_id="$3"

    local message="Plan: $recipe on $hostname [session: $session_id]"
    git_commit "$message" "devices/$hostname/"
}

# Commit execution results after running
# Usage: commit_result <hostname> <recipe> <session_id> <status>
commit_result() {
    local hostname="$1"
    local recipe="$2"
    local session_id="$3"
    local status="$4"

    local message
    case "$status" in
        success)
            message="Applied: $recipe to $hostname [session: $session_id]"
            ;;
        partial)
            message="Partial: $recipe on $hostname (some actions failed) [session: $session_id]"
            ;;
        failed)
            message="Failed: $recipe on $hostname [session: $session_id]"
            ;;
        *)
            message="Result: $recipe on $hostname ($status) [session: $session_id]"
            ;;
    esac

    git_commit "$message" "devices/$hostname/"
}

# Commit device registration
# Usage: commit_registration <hostname>
commit_registration() {
    local hostname="$1"

    local message="Register: $hostname"
    git_commit "$message" "devices/$hostname/"
}

# Get the last commit SHA for a device
# Usage: get_last_device_commit <hostname>
get_last_device_commit() {
    local hostname="$1"

    cd "$PROJECT_ROOT"
    git log -1 --format="%H" -- "devices/$hostname/" 2>/dev/null || echo ""
}

# Get commit history for a device
# Usage: get_device_history <hostname> [limit]
get_device_history() {
    local hostname="$1"
    local limit="${2:-10}"

    cd "$PROJECT_ROOT"
    git log --oneline -n "$limit" -- "devices/$hostname/" 2>/dev/null || echo "No history found"
}

# Generate a session ID
# Usage: generate_session_id
generate_session_id() {
    date +"%Y-%m-%d-%H%M%S"
}

# Main entry point for CLI usage
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        commit)
            git_commit "$@"
            ;;
        plan)
            commit_plan "$@"
            ;;
        result)
            commit_result "$@"
            ;;
        register)
            commit_registration "$@"
            ;;
        history)
            get_device_history "$@"
            ;;
        session-id)
            generate_session_id
            ;;
        help|--help|-h)
            echo "Git Commit Helper"
            echo ""
            echo "Usage: commit.sh <command> [options]"
            echo ""
            echo "Commands:"
            echo "  commit <message> [files...]     Commit changes"
            echo "  plan <host> <recipe> <session>  Commit execution plan"
            echo "  result <host> <recipe> <session> <status>  Commit results"
            echo "  register <hostname>             Commit device registration"
            echo "  history <hostname> [limit]      Show device commit history"
            echo "  session-id                      Generate a new session ID"
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
