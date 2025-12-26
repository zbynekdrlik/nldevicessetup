#!/usr/bin/env bats
# Unit tests for lib/common.sh

setup() {
    # Load the library
    source "$BATS_TEST_DIRNAME/../../lib/common.sh"

    # Set dry run mode for tests
    DRY_RUN="true"
}

@test "log_info outputs with INFO prefix" {
    run log_info "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"test message"* ]]
}

@test "log_success outputs with OK prefix" {
    run log_success "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[OK]"* ]]
}

@test "log_warn outputs with WARN prefix" {
    run log_warn "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[WARN]"* ]]
}

@test "log_error outputs with ERROR prefix" {
    run log_error "test message"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[ERROR]"* ]]
}

@test "command_exists returns 0 for bash" {
    run command_exists bash
    [ "$status" -eq 0 ]
}

@test "command_exists returns 1 for nonexistent command" {
    run command_exists nonexistent_command_xyz
    [ "$status" -eq 1 ]
}

@test "get_os_info returns a value" {
    run get_os_info
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "check_kernel_version passes for current kernel" {
    run check_kernel_version "1.0.0"
    [ "$status" -eq 0 ]
}

@test "run_cmd in dry run mode logs without executing" {
    DRY_RUN="true"
    run run_cmd echo "should not appear"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[DRY-RUN]"* ]]
}

@test "NLDEVICESSETUP_VERSION is set" {
    [ -n "$NLDEVICESSETUP_VERSION" ]
}
