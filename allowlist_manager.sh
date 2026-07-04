#!/system/bin/sh
# Rox2 - allowlist manager
# Add/remove/list packages via simple shell interface used by the WebUI.
# I keep this small because anything more clever just adds bugs.

MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

usage() {
    cat <<EOF
Rox2 allowlist manager

Usage:
  sh allowlist_manager.sh list                 List current allowlist
  sh allowlist_manager.sh add <pkg>            Add a package
  sh allowlist_manager.sh remove <pkg>         Remove a package
  sh allowlist_manager.sh init                 Create empty allowlist if missing
  sh allowlist_manager.sh contains <pkg>       Print 1 if on allowlist, else 0

The WebUI calls these commands through Shizuku, KernelSU, APatch, or
the Magisk action button. They do not require a daemon.
EOF
}

case "${1:-}" in
    list)       allowlist_init; cat "$ALLOWLIST_FILE" ;;
    add)        shift; allowlist_add "$1" ;;
    remove)     shift; allowlist_remove "$1" ;;
    init)       allowlist_init ;;
    contains)   shift; is_allowlisted "$1" ;;
    help|-h|--help|"") usage ;;
    *) echo "unknown: $1" >&2; usage; exit 2 ;;
esac
exit $?
