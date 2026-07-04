#!/system/bin/sh
# Rox2 - service.sh
# Late-start, after boot is mostly done. We:
#   1. Tighten property state once more
#   2. Start the per-app monitor loop

MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_info "=== service.sh v1.1 start ==="

boot_summary
allowlist_init
ensure_all_flags

if is_flag_enabled spoof;   then spoof_boot_state;   fi
if is_flag_enabled keystore; then hide_keystore_leaks; fi
if is_flag_enabled zygisk;   then scrub_root_paths;    fi

start_monitor() {
    monitor_pid_file="$MODPATH/.state_monitor_pid"
    rm -f "$monitor_pid_file"
    POLL_INTERVAL_S="${ROX2_POLL_INTERVAL:-3}"

    (
        while :; do
            sleep "$POLL_INTERVAL_S" 2>/dev/null || sleep 3
            [ -f "$MODPATH/disable" ] && exit 0
            # Re-read flags every cycle so WebUI toggle changes kick in.
            ensure_all_flags

            for line in $(pm list packages 2>/dev/null | sed 's/^package://'); do
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
log_info "=== service.sh v1.1 complete ==="
exit 0
