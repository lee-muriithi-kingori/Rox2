#!/system/bin/sh
# Rox2 - shared functions
# I keep these POSIX-compatible so they run on bash, ash, mksh — whatever Android gives me.

MODPATH="${0%/*}"
[ -z "$MODPATH" ] && MODPATH=/data/adb/modules/Rox2

LOG_FILE=/data/local/tmp/Rox2.log

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log_msg() {
    level="$1"; shift
    stamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 1970-01-01)
    safe=$(printf '%s' "$*" | tr -cd '[:print:]\n ')
    echo "[$stamp] [$level] Rox2: $safe" >> "$LOG_FILE" 2>/dev/null
    log -t Rox2 "[$level] $*" 2>/dev/null || true
}
log_info()  { log_msg INFO  "$@"; }
log_warn()  { log_msg WARN  "$@"; }
log_error() { log_msg ERROR "$@"; }

# ---------------------------------------------------------------------------
# Root manager detection
# ---------------------------------------------------------------------------
detect_root_manager() {
    if [ -n "${KSU:-}" ] && [ "$KSU" = "true" ]; then echo "kernelsu"
    elif [ -n "${APATCH:-}" ] && [ "$APATCH}" = "true" ]; then echo "apatch"
    elif [ -n "${MAGISK_VER_CODE:-}" ]; then echo "magisk"
    else echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Boolean state flags (read by both shell and Zygisk module)
# ---------------------------------------------------------------------------
write_state() {
    key="$1"; value="$2"
    file="$MODPATH/.state_$key"
    tmp="$file.tmp.$$"
    echo "$value" > "$tmp" 2>/dev/null || return 1
    mv "$tmp" "$file" 2>/dev/null || { cat "$tmp" > "$file" && rm -f "$tmp"; }
    chmod 644 "$file" 2>/dev/null
    return 0
}
read_state() {
    key="$1"; default="${2:-}"
    file="$MODPATH/.state_$key"
    [ -r "$file" ] && { cat "$file" 2>/dev/null || echo "$default"; } || echo "$default"
}

# ---------------------------------------------------------------------------
# resetprop helpers
# ---------------------------------------------------------------------------
resetprop_safe() {
    target="$1"; value="$2"
    tries=0
    while [ $tries -lt 5 ]; do
        if resetprop -n "$target" "$value" 2>/dev/null; then return 0; fi
        tries=$((tries + 1))
        sleep 0.2
    done
    log_warn "Could not resetprop $target=$value"
    return 1
}

resetprop_if_diff() {
    target="$1"; value="$2"
    current=$(resetprop "$target" 2>/dev/null || true)
    if [ "$current" != "$value" ]; then
        resetprop_safe "$target" "$value"
    fi
}

resetprop_if_match() {
    target="$1"; contains="$2"; value="$3"
    current=$(resetprop "$target" 2>/dev/null || true)
    if [ -n "$current" ] && printf '%s' "$current" | grep -q "$contains"; then
        resetprop_safe "$target" "$value"
    fi
}

delprop_if_exists() {
    target="$1"
    current=$(resetprop "$target" 2>/dev/null || true)
    [ -n "$current" ] && resetprop --delete "$target" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Feature flags driven by .flag_* files (WebUI toggles them)
#   .flag_spoof       - boot/property spoofing on/off   (default 1)
#   .flag_keystore    - keystore leak scrub            (default 1)
#   .flag_zygisk      - Zygisk mount-namespace hide    (default 1)
#   .flag_hide_mgr    - hide root-manager app from pm  (default 1)
#   .flag_hide_xposed - strip Xposed/LSPosed callbacks (default 1)
# ---------------------------------------------------------------------------
ensure_flag() {
    key="$1"; default="${2:-1}"
    file="$MODPATH/.flag_$key"
    [ -f "$file" ] || echo "$default" > "$file"
    chmod 644 "$file" 2>/dev/null
}
is_flag_enabled() {
    key="$1"
    val=$(read_state "flag_$key" "1")
    [ "$val" = "1" ]
}
set_flag() {
    key="$1"; value="$2"
    echo "$value" > "$MODPATH/.flag_$key"
    chmod 644 "$MODPATH/.flag_$key" 2>/dev/null
}
ensure_all_flags() {
    ensure_flag spoof        "1"
    ensure_flag keystore     "1"
    ensure_flag zygisk       "1"
    ensure_flag hide_mgr     "1"
    ensure_flag hide_xposed  "1"
}

# ---------------------------------------------------------------------------
# Allowlist (default-deny) + manager-toggle
# ---------------------------------------------------------------------------
ALLOWLIST_FILE="$MODPATH/allowlist.json"
HIDE_MGR_DEFAULT_PKGS="com.topjohnwu.magisk me.weishu.kernelsu me.bmax.apatch org.lsposed.manager de.robv.android.xposed.installer"

allowlist_init() {
    [ -f "$ALLOWLIST_FILE" ] || echo '{"allow":[],"deny_root_manager":true,"version":1}' > "$ALLOWLIST_FILE"
    chmod 644 "$ALLOWLIST_FILE" 2>/dev/null
}

# Returns "1" if the package is on the allowlist, "0" otherwise. Manager
# packages are auto-allowed only when the user has not toggled
# `deny_root_manager` in the file.
is_allowlisted() {
    pkg="$1"
    [ -z "$pkg" ] && { echo "0"; return; }
    allowlist_init
    if grep -q "\"$pkg\"" "$ALLOWLIST_FILE" 2>/dev/null; then
        echo "1"; return
    fi
    # Check the "deny_root_manager" flag. If false, root manager packages
    # stay auto-allowed so the manager can run.
    deny=$(grep -o '"deny_root_manager":[ ]*\(true\|false\)' "$ALLOWLIST_FILE" 2>/dev/null | cut -d: -f2 | tr -d ' ')
    if [ "$deny" = "false" ]; then
        for mp in $HIDE_MGR_DEFAULT_PKGS; do
            [ "$pkg" = "$mp" ] && { echo "1"; return; }
        done
    fi
    echo "0"
}

# True if the manager-hide flag is on. When on, the Zygisk module also
# filters these packages from `pm list packages` regardless of allowlist.
is_manager_hidden() {
    is_flag_enabled hide_mgr
}

# True if Xposed-hide is on. When on, the Zygisk module scrubs known
# injection callbacks from Looper / Method dispatch.
is_xposed_hidden() {
    is_flag_enabled hide_xposed
}

allowlist_add() {
    pkg="$1"
    [ -z "$pkg" ] && return 1
    is_on=$(is_allowlisted "$pkg")
    [ "$is_on" = "1" ] && return 0
    allowlist_init
    tmp="$ALLOWLIST_FILE.tmp.$$"
    awk -v pkg="$pkg" '
        BEGIN { saw=0 }
        /"allow":\s*\[/ {
            print
            saw=1
            next
        }
        /\][^]]*$/ && saw==1 {
            sub(/\][^]]*$/, ",\"" pkg "\"]")
            saw=0
            print
            next
        }
        { print }
    ' "$ALLOWLIST_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$ALLOWLIST_FILE" 2>/dev/null
    chmod 644 "$ALLOWLIST_FILE" 2>/dev/null
    log_info "Allowlist add: $pkg"
}

allowlist_remove() {
    pkg="$1"
    [ -z "$pkg" ] && return 1
    [ ! -f "$ALLOWLIST_FILE" ] && return 0
    tmp="$ALLOWLIST_FILE.tmp.$$"
    awk -v pkg="$pkg" '
        { gsub("\"" pkg "\"", ""); gsub(/,,/, ","); print }
    ' "$ALLOWLIST_FILE" > "$tmp" 2>/dev/null && mv "$tmp" "$ALLOWLIST_FILE" 2>/dev/null
    chmod 644 "$ALLOWLIST_FILE" 2>/dev/null
    log_info "Allowlist remove: $pkg"
}

# ---------------------------------------------------------------------------
# Boot-time property cleanup. v1.1: also populate the full vbmeta chain.
# ---------------------------------------------------------------------------
spoof_boot_state() {
    log_info "Spoofing boot/locked state"
    for key in \
        ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.veritymode \
        ro.boot.vbmeta.device_state ro.boot.vbmeta.size ro.boot.vbmeta.avb_version \
        ro.boot.vbmeta.hash_alg ro.boot.vbmeta.digest \
        ro.secureboot.lockstate \
        sys.oem_unlock_allowed ro.boot.mode ro.bootmode \
        ro.debuggable ro.secure ro.adb.secure \
        ro.boot.selinux ro.boot.secureboot \
        vendor.boot.flash.locked vendor.boot.verifiedbootstate \
        vendor.boot.vbmeta.device_state vendor.boot.vbmeta.size \
        ro.boot.hardware.platform ro.boot.hardware; do
        val=$(grep "^$key=" "$MODPATH/system.prop" 2>/dev/null | cut -d= -f2- | head -1)
        [ -n "$val" ] && resetprop_safe "$key" "$val"
    done
    for prop in $(resetprop 2>/dev/null | grep -oE 'ro\..*\.build\.tags' 2>/dev/null); do
        resetprop_safe "$prop" "release-keys"
    done
    for prop in $(resetprop 2>/dev/null | grep -oE 'ro\..*\.build\.type' 2>/dev/null); do
        resetprop_safe "$prop" "user"
    done
    resetprop_if_match ro.boot.mode recovery boot
    resetprop_if_match ro.bootmode recovery boot
    resetprop_if_match vendor.boot.mode recovery boot
    delprop_if_exists ro.boot.verifiedbooterror
    delprop_if_exists ro.boot.verifyerrorpart
    delprop_if_exists ro.boot.verifyerrorcode
    delprop_if_exists ro.build.selinux
    log_info "Boot state spoofed"
}

hide_keystore_leaks() {
    log_info "Stripping keystore/root-solution property leaks"
    for leak in \
        ro.magisk.keystore ro.magisk.hide ro.magisk.flash ro.magisk.monitor \
        ro.ksu.keystore ro.ksu.selinux ro.ksu.internal ro.ksu.busybox \
        ro.apatch.keystore ro.apatch.recovery \
        ro.su_bit ro.debuggable.secure persist.magisk.hide \
        persist.magisk.monitor ro.magisk.version; do
        delprop_if_exists "$leak"
    done
    log_info "Keystore leaks stripped"
}

# ---------------------------------------------------------------------------
# Per-app hide (shell-side). The Zygisk module does the real namespace work.
# ---------------------------------------------------------------------------
hide_for_app_shell() {
    pkg="$1"
    [ "$(is_allowlisted "$pkg")" = "1" ] && { log_info "Allowlist hit: $pkg"; return 0; }
    # Best-effort env strip.
    for var in MAGISK_VER MAGISK_VER_CODE MAGISK_DEBUG \
               KSU KSU_VER KSU_VER_CODE \
               APATCH APATCH_VER APATCH_VER_CODE; do
        eval "export $var=" 2>/dev/null || true
    done
    log_info "Shell-side hide applied for $pkg"
}

is_boot_completed() { [ "$(resetprop sys.boot_completed 2>/dev/null)" = "1" ]; }

boot_summary() {
    rm=$(detect_root_manager)
    log_info "Manager: $rm | Boot: $(is_boot_completed && echo done || echo booting) | Allowlist: $ALLOWLIST_FILE | HideMgr: $(is_manager_hidden) | HideXposed: $(is_xposed_hidden)"
}

# ---------------------------------------------------------------------------
# File-system scrub used at boot. We make sure the module paths and the
# root-manager userland app data dirs are gone from the *parent* mount
# namespace so child processes inherit a clean view. The Zygisk layer
# further isolates each process.
# ---------------------------------------------------------------------------
scrub_root_paths() {
    log_info "Scrubbing root-manager storage paths"
    # These are best-effort; umount2 may fail if the path does not exist.
    for target in \
        /data/adb/modules \
        /data/adb/ksu \
        /data/adb/ap \
        /data/adb/magisk \
        /sbin/.magisk \
        /sbin/magisk \
        /data/adb/lspd \
        /data/adb/riru \
        /debug_ramdisk; do
        umount2 "$target" 2>/dev/null || true
    done
    log_info "Root storage paths scrubbed"
}
