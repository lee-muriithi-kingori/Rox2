#!/system/bin/sh
# Rox2 - post-fs-data
# Runs after filesystem mount, before Zygote. The cleanest place to
# set boot props because every app inherits them.
MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_info "=== post-fs-data start ==="

# Safety: bail in safe mode so a partial boot does not panic.
if [ "$(resetprop ro.boot.safe_mode 2>/dev/null)" = "1" ]; then
    log_warn "Safe mode — minimal run only"
    echo "1" > "$MODPATH/.state_post_fs_data_done"
    exit 0
fi
if [ "$(resetprop ro.boot.mode 2>/dev/null)" = "recovery" ]; then
    log_warn "Recovery mode — skipping"
    echo "1" > "$MODPATH/.state_post_fs_data_done"
    exit 0
fi

# If the user disabled us (touch /data/adb/modules/Rox2/disable), respect it.
[ -f "$MODPATH/disable" ] && { log_warn "Module disabled via flag"; exit 0; }

# Run the prop spoofing first. Properties propagate to every process
# forked from Zygote from this point on.
spoof_boot_state
hide_keystore_leaks

# Allowlist ready to read by both shell and the Zygisk module.
allowlist_init
log_info "Allowlist file: $(head -c 200 "$ALLOWLIST_FILE" 2>/dev/null)..."

# Stamps — these are the cheap signals the WebUI reads.
boot_summary
write_state post_fs_data_done 1

log_info "=== post-fs-data complete ==="
exit 0
