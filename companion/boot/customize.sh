#!/system/bin/sh
# Rox-Boot - customize
MODPATH="${0%/*}"

[ "$(id -u)" != "0" ] && abort "Rox-Boot: not root"

ui_print "============================================"
ui_print "  Rox-Boot v1.0 - Bootloader Hide Companion"
ui_print "  Author: lee-muriithi-kingori"
ui_print "============================================"
ui_print ""
ui_print "I built Rox-Boot as a companion to Rox2. It goes one level"
ui_print "deeper on bootloader-state signals at boot time:"
ui_print "  - Sets the same verified-boot chain as Rox2"
ui_print "  - Strips verified-boot error markers"
ui_print "  - Bind-mounts a clean /proc/cmdline so apps reading it"
ui_print "    directly do not see androidboot.unlocked=1"
ui_print ""
ui_print "  What this module cannot do:"
ui_print "    * It does not defeat hardware-backed Play Integrity"
ui_print "      attestation. STRONG integrity requires a real keybox"
ui_print "      from your own device. Use TrickyStore."
ui_print ""

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh"      0 0 0755
set_perm "$MODPATH/customize.sh"    0 0 0755
set_perm "$MODPATH/uninstall.sh"    0 0 0755
set_perm "$MODPATH/action.sh"       0 0 0755
set_perm "$MODPATH/system.prop"     0 0 0644
set_perm "$MODPATH/module.prop"     0 0 0644
set_perm "$MODPATH/common_func.sh"  0 0 0644

touch /data/local/tmp/RoxBoot.log 2>/dev/null
chmod 644 /data/local/tmp/RoxBoot.log 2>/dev/null

ui_print ""
ui_print "Rox-Boot installed. Reboot for changes to apply."
ui_print "If used alongside Rox2, install Rox-Boot second so its"
ui_print "post-fs-data runs after Rox2's and inherits the cleaned props."
ui_print ""
ui_print "Community: https://t.me/lestramk"
exit 0
