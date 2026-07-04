#!/system/bin/sh
# Rox2 - Magisk module installer
# Runs inside the recovery / module-installer context.

ui_print "============================================"
ui_print "  Rox2 - Root Hider v1.0"
ui_print "  by lee-muriithi-kingori"
ui_print "============================================"
ui_print ""
ui_print "I built Rox2 because I got tired of useless modules that either"
ui_print "claim things they can't do, or break under the most basic checks."
ui_print ""
ui_print "What this module does:"
ui_print "  - Spoofs boot/verified-boot properties at post-fs-data"
ui_print "  - Hides Magisk/KSU/APatch traces in shell environment"
ui_print "  - Adds a Zygisk layer that switches mount namespace per app"
ui_print "  - Default-deny with WebUI allowlist (only listed apps see root)"
ui_print ""
ui_print "What it does NOT do:"
ui_print "  - It does not fake attestation certificates. If you need"
ui_print "    Play Integrity STRONG, point Rox2 at a TrickyStore keybox"
ui_print "    from your own device. Don't ship fake certs in modules."
ui_print ""

[ "$(id -u)" != "0" ] && abort "! Root required"

# Root manager hint
if [ "${KSU:-}" = "true" ]; then
    ui_print "  Detected: KernelSU"
elif [ "${APATCH:-}" = "true" ]; then
    ui_print "  Detected: APatch"
elif [ -n "${MAGISK_VER_CODE:-}" ]; then
    ui_print "  Detected: Magisk ${MAGISK_VER}"
else
    ui_print "  Detected: unknown root manager"
fi

ui_print ""
ui_print "  Installing ..."

# File permissions
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh"       0 0 0755
set_perm "$MODPATH/service.sh"            0 0 0755
set_perm "$MODPATH/customize.sh"          0 0 0755
set_perm "$MODPATH/uninstall.sh"          0 0 0755
set_perm "$MODPATH/action.sh"             0 0 0755
set_perm "$MODPATH/hide_root.sh"          0 0 0755
set_perm "$MODPATH/allowlist_manager.sh"  0 0 0755
set_perm "$MODPATH/build.sh"              0 0 0755
set_perm "$MODPATH/common_func.sh"        0 0 0644
set_perm "$MODPATH/system.prop"           0 0 0644
set_perm "$MODPATH/module.prop"           0 0 0644
set_perm "$MODPATH/allowlist.json"        0 0 0644
[ -d "$MODPATH/webroot" ] && set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
[ -d "$MODPATH/zygisk" ]  && set_perm_recursive "$MODPATH/zygisk"  0 0 0755 0644

# Init allowlist with sane defaults. Touch the manager packages so
# Rox2 itself can be managed even though we deny the world by default.
ui_print "  Initializing allowlist ..."
mkdir -p "$MODPATH" 2>/dev/null
if [ ! -f "$MODPATH/allowlist.json" ]; then
    cat > "$MODPATH/allowlist.json" <<'JSON'
{"allow":["com.topjohnwu.magisk","me.weishu.kernelsu","me.bmax.apatch"],"deny_root_manager":false,"version":1}
JSON
    chmod 644 "$MODPATH/allowlist.json"
fi

# Touch log file so the WebUI can read it without perms failures.
touch /data/local/tmp/Rox2.log 2>/dev/null
chmod 644 /data/local/tmp/Rox2.log 2>/dev/null

ui_print ""
ui_print "============================================"
ui_print "  Rox2 installed."
ui_print "  REBOOT required for hide to apply."
ui_print "  After reboot, open the WebUI to manage allowlist."
ui_print "  Support: https://t.me/lestramk"
ui_print "============================================"

exit 0
