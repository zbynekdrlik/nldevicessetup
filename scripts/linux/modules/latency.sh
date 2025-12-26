#!/usr/bin/env bash
# Description: Low-latency kernel parameters for audio/video
# Module: latency

# This module is sourced by optimize.sh
# Requires: lib/common.sh to be loaded

apply_latency() {
    log_info "=== Latency Module ==="

    # Kernel preemption hints (if available)
    if [[ -f /sys/kernel/debug/sched_features ]]; then
        log_info "Checking scheduler features..."
    fi

    # Reduce dirty page writeback for more responsive I/O
    set_sysctl "vm.dirty_ratio" "10"
    persist_sysctl "vm.dirty_ratio" "10" "$SYSCTL_CONF"

    set_sysctl "vm.dirty_background_ratio" "5"
    persist_sysctl "vm.dirty_background_ratio" "5" "$SYSCTL_CONF"

    # Reduce dirty writeback centisecs
    set_sysctl "vm.dirty_writeback_centisecs" "100"
    persist_sysctl "vm.dirty_writeback_centisecs" "100" "$SYSCTL_CONF"

    # Optimize for low latency over throughput
    if [[ -f /proc/sys/kernel/sched_latency_ns ]]; then
        set_sysctl "kernel.sched_latency_ns" "1000000"
        persist_sysctl "kernel.sched_latency_ns" "1000000" "$SYSCTL_CONF"
    fi

    # Disable kernel watchdog for audio workloads (reduces latency spikes)
    if [[ -f /proc/sys/kernel/watchdog ]]; then
        log_info "Consider disabling watchdog for lowest latency:"
        log_info "  echo 0 > /proc/sys/kernel/watchdog"
    fi

    # Check for realtime kernel
    if uname -r | grep -q "rt"; then
        log_success "Realtime kernel detected"
    else
        log_info "Consider installing a realtime kernel for lowest latency"
    fi

    log_success "Latency module complete"
}
