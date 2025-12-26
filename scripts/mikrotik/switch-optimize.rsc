# NL Devices Setup - Mikrotik Switch Optimization
# For CRS series switches (RouterOS 7.x)
# Optimizes for Dante/AES67 low-latency audio
# Usage: /import file-name=switch-optimize.rsc

:local configName "nldevicessetup"
:log info "$configName - Starting switch optimization..."

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
# Summary
# ===========================================
:log info "$configName - Switch optimization complete!"
:log info "$configName - Dante QoS: PTP(TC7) > Audio(TC5) > Control(TC0)"
:log info "$configName - Flow control: DISABLED"
:log info "$configName - IGMP fast-leave: ENABLED"
