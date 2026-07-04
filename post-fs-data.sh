#!/system/bin/sh
# Rox2 - post-fs-data
# Runs after filesystem mount, before Zygote. The cleanest place to
# set boot props because every app inherits them.
MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_info "=== post-fs-data v1.1 start ==="

if [ "$(resetprop ro.boot.safe_mode 2>/dev/null)" = "1" ]; then
    log_warn "Safe mode — minimal run only"
    write_state post_fs_data_done 1
    exit 0
fi
if [ "$(resetprop ro.boot.mode 2>/dev/null)" = "recovery" ]; then
    log_warn "Recovery mode — skipping"
    write_state post_fs_data_done 1
    exit 0
fi

[ -f "$MODPATH/disable" ] && { log_warn "Module disabled via flag"; exit 0; }

# Feature flags are first so the WebUI can flip them mid-flight and have
# the next post-fs-data see them.
ensure_all_flags
allowlist_init

if is_flag_enabled spoof;   then spoof_boot_state;   else log_info "spoof disabled by flag"; fi
if is_flag_enabled keystore; then hide_keystore_leaks; else log_info "keystore scrub disabled by flag"; fi
if is_flag_enabled zygisk;   then scrub_root_paths;    else log_info "zygisk mount-scrub disabled by flag"; fi

boot_summary
write_state post_fs_data_done 1

log_info "=== post-fs-data v1.1 complete ==="
exit 0
