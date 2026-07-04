#!/system/bin/sh
# Rox-Boot - uninstall
MODPATH="${0%/*}"
rm -f "$MODPATH"/.state_* "$MODPATH"/.flag_* 2>/dev/null
exit 0
