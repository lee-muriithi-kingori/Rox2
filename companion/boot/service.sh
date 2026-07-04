#!/system/bin/sh
# Rox-Boot - service / monitor
MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_msg "=== Rox-Boot service v1.0 ==="

# Re-apply boot-state props after boot shifts the namespace, and
# scrub verified-boot error markers that some ROMs re-set under us.
for key in \
    ro.boot.flash.locked ro.boot.verifiedbootstate \
    ro.secureboot.lockstate ro.boot.vbmeta.device_state \
    sys.oem_unlock_allowed ro.boot.mode ro.bootmode; do
    val=$(grep "^$key=" "$MODPATH/system.prop" 2>/dev/null | cut -d= -f2- | head -1)
    [ -n "$val" ] && resetprop_if_diff "$key" "$val"
done
known_blu_leaks

log_msg "INFO" "service done"
exit 0
