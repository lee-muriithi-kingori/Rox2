#!/system/bin/sh
# Rox2 - uninstall
# Cleanly remove everything we put down.

MODPATH="${0%/*}"
LOG_FILE=/data/local/tmp/Rox2.log

log_msg() {
    level="$1"; shift
    stamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 1970-01-01)
    echo "[$stamp] [$level] Rox2: $*" >> "$LOG_FILE" 2>/dev/null
}

log_msg "INFO" "Uninstalling"

# State files
for s in "$MODPATH"/.state_* "$MODPATH"/.flag_*; do
    [ -f "$s" ] && rm -f "$s" 2>/dev/null
done

# Allowlist — keep it if the user re-installs (modular uninstall should
# not destroy state). Only wipe on explicit cleanup.
[ -n "${ROX2_PURGE:-}" ] && rm -f "$MODPATH/allowlist.json" 2>/dev/null

log_msg "INFO" "Uninstall complete"
exit 0
