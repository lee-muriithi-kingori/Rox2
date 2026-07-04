#!/system/bin/sh
# Rox2 - hide_root.sh
# Manual trigger. I run this from adb shell or from the WebUI when I want
# to refresh the spoofing without rebooting.
MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_info "=== Manual hide_root.sh ==="

spoof_boot_state
hide_keystore_traces_deep() {
    hide_keystore_leaks
    # Tighter pass: kernel-level hints if any leaked.
    for leak in ro.magisk.version ro.magisk.flash \
                ro.magisk.monitor ro.ksu.busybox ro.ksu.internal \
                persist.magisk.monitor; do
        delprop_if_exists "$leak"
    done
}
hide_keystore_traces_deep

# Re-apply bootloader mode props (most flagged property)
resetprop_if_match ro.boot.mode recovery boot
resetprop_if_match ro.bootmode recovery boot
resetprop_if_match vendor.boot.mode recovery boot

# Surface summary
log_info "Allowlist file currently includes:"
head -c 400 "$ALLOWLIST_FILE" 2>/dev/null

echo ""
echo "Rox2: hide_root.sh complete. Logs at /data/local/tmp/Rox2.log"
log_info "=== hide_root.sh complete ==="
exit 0
