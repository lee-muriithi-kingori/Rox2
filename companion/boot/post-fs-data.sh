#!/system/bin/sh
# Rox-Boot - post-fs-data
# Runs after filesystem mount, before Zygote.
MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

log_msg "=== Rox-Boot post-fs-data v1.0 ==="

[ "$(resetprop ro.boot.safe_mode 2>/dev/null)" = "1" ] && { log_msg "WARN" "safe mode"; exit 0; }
[ -f "$MODPATH/disable" ]                       && { log_msg "WARN" "module disabled"; exit 0; }

# 1. Boot-state properties (consistent with Rox2 but standalone usable).
for key in \
    ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.veritymode \
    ro.boot.vbmeta.device_state ro.boot.vbmeta.avb_version \
    ro.boot.vbmeta.hash_alg \
    ro.secureboot.lockstate \
    sys.oem_unlock_allowed ro.boot.mode ro.bootmode \
    ro.debuggable ro.secure ro.adb.secure \
    ro.boot.selinux ro.boot.secureboot \
    vendor.boot.flash.locked vendor.boot.verifiedbootstate \
    vendor.boot.vbmeta.device_state vendor.boot.vbmeta.avb_version \
    vendor.boot.vbmeta.hash_alg; do
    val=$(grep "^$key=" "$MODPATH/system.prop" 2>/dev/null | cut -d= -f2- | head -1)
    [ -n "$val" ] && resetprop_if_diff "$key" "$val"
done

for prop in $(resetprop 2>/dev/null | grep -oE 'ro\..*\.build\.tags' 2>/dev/null); do
    resetprop_safe "$prop" "release-keys"
done
for prop in $(resetprop 2>/dev/null | grep -oE 'ro\..*\.build\.type' 2>/dev/null); do
    resetprop_safe "$prop" "user"
done

# 2. Strip verified-boot error / mode-recovery leaks.
known_blu_leaks

# 3. Mount a clean /proc/cmdline if the kernel allows.
make_clean_cmdline

log_msg "INFO" "post-fs-data complete"
exit 0
