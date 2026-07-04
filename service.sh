#!/system/bin/sh
# Rox2 - service.sh
# Late-start, after boot is mostly done. We:
#   1. Tighten property state once more (in case anything reset)
#   2. Start the per-app monitor loop that re-applies hiding when
#      target apps come into focus.

MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_info "=== service.sh start ==="

# Re-apply on late start — sometimes props flip back if early reset
# races with system services.
boot_summary
spoof_boot_state
hide_keystore_leaks

# ----- monitor loop -----
start_monitor() {
    monitor_pid_file="$MODPATH/.state_monitor_pid"
    rm -f "$monitor_pid_file"

    # Background loop. POLL_INTERVAL_S is the seconds between scans.
    POLL_INTERVAL_S="${ROX2_POLL_INTERVAL:-3}"

    (
        # Read fresh state every cycle so WebUI toggle changes take effect immediately.
        while :; do
            sleep "$POLL_INTERVAL_S" 2>/dev/null || sleep 3

            [ -f "$MODPATH/disable" ] && exit 0

            # If a target app surfaces, re-apply per-process hiding quickly.
            for line in $(pm list packages 2>/dev/null | sed 's/^package://'); do
                # Only check apps that are actually running.
                if pidof "$line" >/dev/null 2>&1; then
                    allowed=$(is_allowlisted "$line")
                    if [ "$allowed" = "0" ]; then
                        hide_for_app_shell "$line"
                    fi
                fi
            done
            echo "$$" > "$monitor_pid_file" 2>/dev/null
        done
    ) >/dev/null 2>&1 &
    monitor_pid=$!
    echo "$monitor_pid" > "$monitor_pid_file"
    log_info "Monitor spawned (PID: $monitor_pid, poll=${POLL_INTERVAL_S}s)"
}

start_monitor
log_info "=== service.sh complete ==="
exit 0
