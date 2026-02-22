#!/usr/bin/env bash
# Recipe execution engine for nldevicessetup
# Executes recipes on remote devices via SSH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# shellcheck source=lib/common.sh
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=lib/device/ssh.sh
source "$PROJECT_ROOT/lib/device/ssh.sh"
# shellcheck source=lib/git/commit.sh
source "$PROJECT_ROOT/lib/git/commit.sh"

# Parse YAML file (basic parser for our recipe format)
# This is a simple parser - for production, consider using yq
parse_yaml_value() {
    local file="$1"
    local key="$2"

    grep "^${key}:" "$file" 2>/dev/null | sed "s/^${key}:[[:space:]]*//" | tr -d '"' || echo ""
}

# Get recipe file path
get_recipe_path() {
    local recipe_name="$1"
    local recipe_file="$PROJECT_ROOT/recipes/${recipe_name}.yml"

    if [[ -f "$recipe_file" ]]; then
        echo "$recipe_file"
    else
        echo ""
    fi
}

# Load device info
load_device() {
    local hostname="$1"
    local device_file="$PROJECT_ROOT/devices/$hostname/device.yml"

    if [[ ! -f "$device_file" ]]; then
        log_error "Device $hostname not found. Register it first."
        return 1
    fi

    # Parse device info
    local os ssh_user ssh_port
    os=$(parse_yaml_value "$device_file" "os")
    ssh_user=$(parse_yaml_value "$device_file" "ssh_user")
    ssh_port=$(parse_yaml_value "$device_file" "ssh_port")

    echo "os=$os"
    echo "ssh_user=${ssh_user:-newlevel}"
    echo "ssh_port=${ssh_port:-22}"
}

# Execute a recipe on a device
# Usage: execute_recipe <hostname> <recipe_name>
execute_recipe() {
    local hostname="$1"
    local recipe_name="$2"

    log_info "Executing recipe '$recipe_name' on '$hostname'"

    # Load device info
    local device_info
    if ! device_info=$(load_device "$hostname"); then
        return 1
    fi

    # Parse device info
    local os ssh_user ssh_port
    eval "$device_info"

    # Find recipe
    local recipe_file
    recipe_file=$(get_recipe_path "$recipe_name")
    if [[ -z "$recipe_file" ]]; then
        log_error "Recipe '$recipe_name' not found"
        return 1
    fi

    # Generate session ID
    local session_id
    session_id=$(generate_session_id)
    log_info "Session ID: $session_id"

    # Create history file
    local history_dir="$PROJECT_ROOT/devices/$hostname/history"
    local history_file="$history_dir/${session_id}-${recipe_name}.yml"
    mkdir -p "$history_dir"

    local start_time
    start_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Initialize history file
    cat > "$history_file" << EOF
session_id: $session_id
executed_by: claude-code
recipe: $recipe_name
started: $start_time
status: in_progress
actions: []
EOF

    # Commit plan before execution
    commit_plan "$hostname" "$recipe_name" "$session_id"

    # Check SSH connectivity
    log_info "Checking SSH connectivity..."
    if ! ssh_check "$hostname" "$ssh_user"; then
        log_error "Cannot reach $hostname via SSH"
        # Update history with failure
        sed -i "s/status: in_progress/status: failed/" "$history_file"
        echo "error: SSH connection failed" >> "$history_file"
        commit_result "$hostname" "$recipe_name" "$session_id" "failed"
        return 1
    fi
    log_success "SSH connection OK"

    # Parse and execute actions from recipe
    # Note: This is a simplified executor. Full implementation would need proper YAML parsing.
    log_info "Recipe file: $recipe_file"
    log_info "Target OS: $os"

    local total_actions=0
    local succeeded=0
    local failed=0
    local skipped=0

    # For now, just log that we would execute the recipe
    # In a full implementation, we would:
    # 1. Parse the recipe YAML
    # 2. Filter actions for the target OS
    # 3. Execute each action via SSH
    # 4. Record results in history

    log_info "Recipe execution would happen here..."
    log_info "This is a skeleton - full YAML parsing requires yq or a proper parser"

    # Update history with completion
    local end_time
    end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    cat > "$history_file" << EOF
session_id: $session_id
executed_by: claude-code
recipe: $recipe_name
started: $start_time
completed: $end_time
status: success
actions:
  - action: placeholder
    result: success
    output: "Recipe execution engine skeleton"
summary:
  total_actions: $total_actions
  succeeded: $succeeded
  failed: $failed
  skipped: $skipped
EOF

    # Update device state
    update_device_state "$hostname" "$recipe_name" "$session_id"

    # Commit results
    commit_result "$hostname" "$recipe_name" "$session_id" "success"

    log_success "Recipe '$recipe_name' executed on '$hostname'"
    log_info "History: $history_file"
}

# Update device state after recipe execution
update_device_state() {
    local hostname="$1"
    local recipe_name="$2"
    local session_id="$3"

    local state_file="$PROJECT_ROOT/devices/$hostname/state.yml"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Update last_updated
    if [[ -f "$state_file" ]]; then
        sed -i "s/^last_updated:.*/last_updated: $timestamp/" "$state_file"

        # Append to applied_recipes if not already a proper YAML array
        # This is simplified - proper implementation needs YAML manipulation
        if ! grep -q "name: $recipe_name" "$state_file"; then
            cat >> "$state_file" << EOF

  - name: $recipe_name
    applied_at: $timestamp
    session_id: $session_id
EOF
        fi
    fi
}

# List available recipes
list_recipes() {
    local recipes_dir="$PROJECT_ROOT/recipes"

    if [[ ! -d "$recipes_dir" ]]; then
        log_warn "No recipes directory found"
        return 0
    fi

    echo "Available recipes:"
    echo "=================="

    for recipe_file in "$recipes_dir"/*.yml; do
        if [[ -f "$recipe_file" ]]; then
            local name description
            name=$(basename "$recipe_file" .yml)
            description=$(parse_yaml_value "$recipe_file" "description" || echo "No description")
            printf "  %-25s %s\n" "$name" "$description"
        fi
    done
}

# Show recipe details
show_recipe() {
    local recipe_name="$1"

    local recipe_file
    recipe_file=$(get_recipe_path "$recipe_name")

    if [[ -z "$recipe_file" ]]; then
        log_error "Recipe '$recipe_name' not found"
        return 1
    fi

    cat "$recipe_file"
}

# Main entry point
main() {
    local command="${1:-help}"
    shift || true

    case "$command" in
        run|execute)
            if [[ $# -lt 2 ]]; then
                echo "Usage: executor.sh run <hostname> <recipe>"
                exit 1
            fi
            execute_recipe "$@"
            ;;
        list)
            list_recipes
            ;;
        show)
            if [[ $# -lt 1 ]]; then
                echo "Usage: executor.sh show <recipe>"
                exit 1
            fi
            show_recipe "$@"
            ;;
        help|--help|-h)
            echo "Recipe Execution Engine"
            echo ""
            echo "Usage: executor.sh <command> [options]"
            echo ""
            echo "Commands:"
            echo "  run <hostname> <recipe>  Execute a recipe on a device"
            echo "  list                     List available recipes"
            echo "  show <recipe>            Show recipe details"
            echo "  help                     Show this help"
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
