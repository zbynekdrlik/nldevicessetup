#!/usr/bin/env bash
# Description: Network stack optimizations (TCP/UDP buffers, congestion)
# Module: network

# This module is sourced by optimize.sh
# Requires: lib/common.sh to be loaded

apply_network() {
    log_info "=== Network Module ==="

    # Additional network optimizations beyond core

    # Increase connection tracking limits
    if [[ -f /proc/sys/net/netfilter/nf_conntrack_max ]]; then
        set_sysctl "net.netfilter.nf_conntrack_max" "262144"
        persist_sysctl "net.netfilter.nf_conntrack_max" "262144" "$SYSCTL_CONF"
    fi

    # Reduce TIME_WAIT sockets
    set_sysctl "net.ipv4.tcp_tw_reuse" "1"
    persist_sysctl "net.ipv4.tcp_tw_reuse" "1" "$SYSCTL_CONF"

    # Increase local port range
    set_sysctl "net.ipv4.ip_local_port_range" "1024 65535"
    persist_sysctl "net.ipv4.ip_local_port_range" "1024 65535" "$SYSCTL_CONF"

    # Increase somaxconn for high connection servers
    set_sysctl "net.core.somaxconn" "65535"
    persist_sysctl "net.core.somaxconn" "65535" "$SYSCTL_CONF"

    # Increase netdev budget for high-throughput
    set_sysctl "net.core.netdev_budget" "600"
    persist_sysctl "net.core.netdev_budget" "600" "$SYSCTL_CONF"

    log_success "Network module complete"
}
