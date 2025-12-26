# NL Devices Setup - Mikrotik Switch Optimization
# For CRS series switches (RouterOS 7.x)
# Optimizes for Dante/AES67 low-latency audio
# Usage: /import file-name=switch-optimize.rsc

:local configName "nldevicessetup"
:local issuesFound 0
:local issuesFixed 0

:log info "$configName - Starting switch optimization and audit..."

# ===========================================
# System Information
# ===========================================
:local identity [/system identity get name]
:local version [/system resource get version]
:local board [/system resource get board-name]
:log info "$configName - Device: $identity ($board) running $version"

# ===========================================
# Flow Control (DISABLE for low-latency)
# ===========================================
:log info "$configName - Disabling flow control..."

/interface ethernet {
    :foreach i in=[find] do={
        :local ifname [get $i name]
        :local rxfc [get $i rx-flow-control]
        :local txfc [get $i tx-flow-control]
        :if ($rxfc != "off" || $txfc != "off") do={
            :log info "$configName - Disabling flow control on $ifname"
            set $i rx-flow-control=off tx-flow-control=off
        }
    }
}
:log info "$configName - Flow control disabled on all ports"

# ===========================================
# Bridge IGMP Fast Leave (for multicast)
# ===========================================
:log info "$configName - Configuring IGMP fast-leave..."

/interface bridge port {
    :foreach i in=[find] do={
        :local fl [get $i fast-leave]
        :if ($fl != true) do={
            :local ifname [get $i interface]
            :log info "$configName - Enabling fast-leave on $ifname"
            set $i fast-leave=yes
        }
    }
}
:log info "$configName - IGMP fast-leave configured"

# ===========================================
# Dante QoS Profiles
# ===========================================
:log info "$configName - Configuring Dante QoS profiles..."

/interface ethernet switch qos profile {
    # PTP Clock Sync - highest priority (DSCP 56 = CS7)
    :if ([:len [find where name="dante-ptp"]] = 0) do={
        add name=dante-ptp dscp=56 pcp=7 traffic-class=7
        :log info "$configName - Created dante-ptp profile (DSCP 56, TC 7)"
    }

    # Audio Streams - high priority (DSCP 46 = EF)
    :if ([:len [find where name="dante-audio"]] = 0) do={
        add name=dante-audio dscp=46 pcp=5 traffic-class=5
        :log info "$configName - Created dante-audio profile (DSCP 46, TC 5)"
    }

    # Control/Discovery - low priority (DSCP 8 = CS1)
    :if ([:len [find where name="dante-low"]] = 0) do={
        add name=dante-low dscp=8 pcp=1 traffic-class=0
        :log info "$configName - Created dante-low profile (DSCP 8, TC 0)"
    }
}

# ===========================================
# DSCP to Profile Mapping
# ===========================================
:log info "$configName - Configuring DSCP mappings..."

/interface ethernet switch qos map ip {
    :if ([:len [find where dscp=56]] = 0) do={
        add dscp=56 profile=dante-ptp
        :log info "$configName - Mapped DSCP 56 -> dante-ptp"
    }

    :if ([:len [find where dscp=46]] = 0) do={
        add dscp=46 profile=dante-audio
        :log info "$configName - Mapped DSCP 46 -> dante-audio"
    }

    :if ([:len [find where dscp=8]] = 0) do={
        add dscp=8 profile=dante-low
        :log info "$configName - Mapped DSCP 8 -> dante-low"
    }
}

# ===========================================
# Queue Scheduling
# ===========================================
:log info "$configName - Configuring queue scheduling..."

/interface ethernet switch qos tx-manager queue {
    # Strict priority for traffic-class >= 2 (audio, PTP)
    :foreach i in=[find where traffic-class>=2] do={
        :local sched [get $i schedule]
        :if ($sched != "strict-priority") do={
            set $i schedule=strict-priority
        }
    }

    # Weighted round-robin for traffic-class < 2 (control, best-effort)
    :foreach i in=[find where traffic-class<2] do={
        :local sched [get $i schedule]
        :if ($sched != "low-priority-group") do={
            set $i schedule=low-priority-group weight=1
        }
    }
}
:log info "$configName - Queue scheduling configured (strict priority for TC >= 2)"

# ===========================================
# Port QoS Trust Settings
# ===========================================
:log info "$configName - Configuring port trust..."

/interface ethernet switch qos port {
    :foreach i in=[find] do={
        :local trust [get $i trust-l3]
        :if ($trust != "keep") do={
            set $i trust-l3=keep
        }
    }
}
:log info "$configName - Ports set to trust L3 DSCP markings"

# ===========================================
# Hardware QoS Offloading
# ===========================================
:log info "$configName - Enabling hardware QoS offloading..."

/interface ethernet switch {
    :foreach i in=[find] do={
        :do {
            :local qos [get $i qos-hw-offloading]
            :if ($qos != true) do={
                set $i qos-hw-offloading=yes
                :log info "$configName - Enabled QoS HW offloading"
            }
        } on-error={
            :log warning "$configName - QoS HW offloading not supported on this switch"
        }
    }
}

# ===========================================
# Bridge Settings (IGMP Snooping, HW Offload)
# ===========================================
:log info "$configName - Checking bridge settings..."

/interface bridge {
    :foreach i in=[find] do={
        :local brname [get $i name]

        # Log IGMP snooping status (not changed - user preference)
        :local igmp [get $i igmp-snooping]
        :log info "$configName - Bridge $brname IGMP snooping: $igmp"

        # Check hardware offloading
        :do {
            :local hwoff [get $i hw-offload]
            :if ($hwoff != true) do={
                :log info "$configName - Enabling HW offload on bridge $brname"
                set $i hw-offload=yes
                :set issuesFixed ($issuesFixed + 1)
            }
        } on-error={}

        # Check protocol mode (should be rstp or mstp for fast convergence)
        :local proto [get $i protocol-mode]
        :if ($proto = "none") do={
            :log warning "$configName - Bridge $brname has no STP - consider enabling rstp"
            :set issuesFound ($issuesFound + 1)
        }

        # Check multicast router (should be set for proper Dante multicast)
        :local mcrouter [get $i multicast-router]
        :if ($mcrouter != "permanent") do={
            :log info "$configName - Setting multicast-router=permanent on $brname"
            set $i multicast-router=permanent
            :set issuesFixed ($issuesFixed + 1)
        }
    }
}
:log info "$configName - Bridge settings configured"

# ===========================================
# EEE (Energy Efficient Ethernet) - DISABLE
# ===========================================
:log info "$configName - Checking EEE (should be disabled for low-latency)..."

/interface ethernet {
    :foreach i in=[find] do={
        :local ifname [get $i name]
        :do {
            :local eee [get $i eee]
            :if ($eee != "disabled") do={
                :log info "$configName - Disabling EEE on $ifname"
                set $i eee=disabled
                :set issuesFixed ($issuesFixed + 1)
            }
        } on-error={}
    }
}
:log info "$configName - EEE check complete"

# ===========================================
# Loop Protection
# ===========================================
:log info "$configName - Checking loop protection..."

/interface ethernet {
    :foreach i in=[find] do={
        :local ifname [get $i name]
        :local lp [get $i loop-protect]
        :if ($lp = "off") do={
            :log warning "$configName - Loop protection disabled on $ifname (consider enabling)"
            :set issuesFound ($issuesFound + 1)
        }
    }
}

# ===========================================
# Port Speed/Duplex Verification
# ===========================================
:log info "$configName - Checking port link status..."

/interface ethernet {
    :foreach i in=[find where running=yes] do={
        :local ifname [get $i name]
        :local speed [get $i speed]
        :local duplex [get $i full-duplex]
        :if ($duplex != true) do={
            :log warning "$configName - $ifname is running HALF-DUPLEX (bad for audio!)"
            :set issuesFound ($issuesFound + 1)
        }
        :log info "$configName - $ifname: $speed, full-duplex=$duplex"
    }
}

# ===========================================
# L2MTU Check
# ===========================================
:log info "$configName - Checking L2MTU..."

/interface ethernet {
    :foreach i in=[find] do={
        :local ifname [get $i name]
        :local l2mtu [get $i l2mtu]
        :if ($l2mtu < 1592) do={
            :log warning "$configName - $ifname L2MTU=$l2mtu (should be >= 1592)"
            :set issuesFound ($issuesFound + 1)
        }
    }
}

# ===========================================
# MAC Table Aging
# ===========================================
:log info "$configName - Checking MAC aging time..."

/interface bridge {
    :foreach i in=[find] do={
        :local brname [get $i name]
        :local aging [get $i auto-mac]
        # Just log current setting
        :local ageTime [get $i mac-age]
        :log info "$configName - Bridge $brname MAC aging: $ageTime"
    }
}

# ===========================================
# Switch Chip Verification
# ===========================================
:log info "$configName - Verifying switch chip settings..."

/interface ethernet switch {
    :foreach i in=[find] do={
        :local swname [get $i name]
        :local swtype [get $i type]
        :local l3off [get $i l3-hw-offloading]
        :local qosoff [get $i qos-hw-offloading]
        :log info "$configName - Switch: $swname ($swtype)"
        :log info "$configName -   L3 HW offload: $l3off"
        :log info "$configName -   QoS HW offload: $qosoff"

        :if ($qosoff != true) do={
            :log warning "$configName - QoS HW offloading is DISABLED!"
            :set issuesFound ($issuesFound + 1)
        }
    }
}

# ===========================================
# Final Audit Summary
# ===========================================
:log info "==========================================="
:log info "$configName - OPTIMIZATION COMPLETE"
:log info "==========================================="
:log info "$configName - Issues found: $issuesFound"
:log info "$configName - Issues fixed: $issuesFixed"
:log info ""
:log info "$configName - Dante QoS Configuration:"
:log info "  - PTP/Clock (DSCP 56): Traffic Class 7 (highest)"
:log info "  - Audio (DSCP 46): Traffic Class 5 (high)"
:log info "  - Control (DSCP 8): Traffic Class 0 (low)"
:log info ""
:log info "$configName - Optimizations Applied:"
:log info "  - Flow control: DISABLED"
:log info "  - IGMP fast-leave: ENABLED"
:log info "  - HW offloading: ENABLED"
:log info "  - EEE: DISABLED"
:log info "  - Multicast router: PERMANENT"
:log info ""
:if ($issuesFound > 0) do={
    :log warning "$configName - Review warnings above for potential issues"
} else={
    :log info "$configName - All checks passed!"
}
