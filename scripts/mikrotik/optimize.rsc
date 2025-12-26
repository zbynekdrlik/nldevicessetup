# NL Devices Setup - Mikrotik Optimization Script
# RouterOS 7.x compatible
# Usage: Import via /import or paste in terminal

# Configuration
:local configName "nldevicessetup"

:log info "NL Devices Setup - Starting Mikrotik optimization..."

# ===========================================
# Connection Tracking Optimization
# ===========================================

# Increase connection tracking limits for high-throughput
/ip firewall connection tracking
set enabled=auto
set tcp-established-timeout=1d
set tcp-close-timeout=10s
set tcp-close-wait-timeout=10s
set tcp-fin-wait-timeout=10s
set tcp-last-ack-timeout=10s
set tcp-syn-received-timeout=5s
set tcp-syn-sent-timeout=5s
set tcp-time-wait-timeout=10s
set udp-stream-timeout=3m
set udp-timeout=10s
set icmp-timeout=10s
set generic-timeout=10m

:log info "Connection tracking optimized"

# ===========================================
# Firewall Fasttrack
# ===========================================

# Enable fasttrack for established connections (bypasses firewall for speed)
/ip firewall filter
:if ([:len [find where comment~"$configName-fasttrack"]] = 0) do={
    add chain=forward action=fasttrack-connection connection-state=established,related comment="$configName-fasttrack"
    add chain=forward action=accept connection-state=established,related comment="$configName-accept-established"
}

:log info "Fasttrack rules configured"

# ===========================================
# Queue Configuration (QoS)
# ===========================================

# Create queue tree for traffic prioritization
# Priority: 1=highest, 8=lowest

# Mark audio/video traffic
/ip firewall mangle
:if ([:len [find where comment~"$configName-audio"]] = 0) do={
    # Dante/AES67 audio (typically UDP 14336-14600)
    add chain=prerouting protocol=udp dst-port=14336-14600 action=mark-packet new-packet-mark=audio-traffic passthrough=no comment="$configName-audio"

    # RTP/RTSP video
    add chain=prerouting protocol=udp dst-port=5004-5005 action=mark-packet new-packet-mark=video-traffic passthrough=no comment="$configName-video"

    # VoIP SIP
    add chain=prerouting protocol=udp dst-port=5060-5061 action=mark-packet new-packet-mark=voip-traffic passthrough=no comment="$configName-voip"
}

# Create priority queues
/queue tree
:if ([:len [find where comment~"$configName-queue"]] = 0) do={
    add name="audio-priority" parent=global packet-mark=audio-traffic priority=1 comment="$configName-queue"
    add name="video-priority" parent=global packet-mark=video-traffic priority=2 comment="$configName-queue"
    add name="voip-priority" parent=global packet-mark=voip-traffic priority=1 comment="$configName-queue"
}

:log info "QoS queues configured"

# ===========================================
# Hardware Offloading
# ===========================================

# Enable hardware offloading where supported
/interface ethernet
:foreach i in=[find] do={
    :local name [get $i name]
    :do {
        set $i rx-flow-control=auto tx-flow-control=auto
    } on-error={}
}

:log info "Hardware settings optimized"

# ===========================================
# Final Summary
# ===========================================

:log info "NL Devices Setup - Mikrotik optimization complete!"
:log info "Reboot recommended for all changes to take effect"
