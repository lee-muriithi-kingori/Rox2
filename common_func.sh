#!/system/bin/sh
# Rox2 - shared functions
# I keep these POSIX-compatible so they run on bash, ash, mksh — whatever Android gives me.

MODPATH="${0%/*}"
[ -z "$MODPATH" ] && MODPATH=/data/adb/modules/Rox2

LOG_FILE=/data/local/tmp/Rox2.log

# ---------------------------------------------------------------------------
# Logging — append-and-mirror to logcat where possible.
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
# Detect which root manager owns us. Read-only — no harness probing.
# ---------------------------------------------------------------------------
detect_root_manager() {
    if [ -n "${KSU:-}" ] && [ "$KSU" = "true" ]; then echo "kernelsu"
    elif [ -n "${APATCH:-}" ] && [ "$APATCH" = "true" ]; then echo "apatch"
    elif [ -n "${MAGISK_VER_CODE:-}" ]; then echo "magisk"
    else echo "unknown"
    fi
}

# ---------------------------------------------------------------------------
# Always-running boot flags. Written atomically so the WebUI never sees
# a torn file.
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
# resetprop with retry — Magisk's resetprop returns non-zero if the
# system property service is locked during early boot.
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
    [ -z "$current" ] && current=$(resetprop "$target" 2>/dev/null || true)
    [ -n "$current" ] && resetprop --delete "$target" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Booleans on disk. Default 1 (enabled) where missing.
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

# ---------------------------------------------------------------------------
# Allowlist — apps that get to see root.
# File format: $MODPATH/allowlist.json — { "allow": ["pkg1","pkg2"], "deny_root_manager": true }
# We keep it simple JSON so the WebUI and the shell scripts agree on format.
# ---------------------------------------------------------------------------
ALLOWLIST_FILE="$MODPATH/allowlist.json"

allowlist_init() {
    [ -f "$ALLOWLIST_FILE" ] || echo '{"allow":[],"deny_root_manager":true,"version":1}' > "$ALLOWLIST_FILE"
    chmod 644 "$ALLOWLIST_FILE" 2>/dev/null
}

# Print "1" if $1 is on the allowlist, "0" otherwise.
# Root manager packages are always allowed (they need root to do their job).
is_allowlisted() {
    pkg="$1"
    [ -z "$pkg" ] && { echo "0"; return; }
    case "$pkg" in
        com.topjohnwu.magisk|me.weishu.kernelsu|me.bmax.apatch)
            echo "1"; return ;;
    esac
    allowlist_init
    # Very small JSON parser: look for "pkg" anywhere in the allow array.
    # Good enough — no nested objects.
    if grep -q "\"$pkg\"" "$ALLOWLIST_FILE" 2>/dev/null; then
        echo "1"
    else
        echo "0"
    fi
}

# Add a package to the allowlist.
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

# Remove a package from the allowlist.
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
# Boot-time property cleanup — applied in post-fs-data so the props are
# set before any app starts. This is what makes apps see "stock" before
# they even get a chance to query root.
# ---------------------------------------------------------------------------
spoof_boot_state() {
    log_info "Spoofing boot/locked state"
    for key in \
        ro.boot.flash.locked ro.boot.verifiedbootstate ro.boot.veritymode \
        ro.boot.vbmeta.device_state ro.secureboot.lockstate \
        sys.oem_unlock_allowed ro.boot.mode ro.bootmode \
        ro.debuggable ro.secure ro.adb.secure \
        ro.boot.selinux ro.boot.secureboot \
        vendor.boot.flash.locked vendor.boot.verifiedbootstate \
        vendor.boot.vbmeta.device_state; do
        val=$(grep "^$key=" "$MODPATH/system.prop" 2>/dev/null | cut -d= -f2- | head -1)
        [ -n "$val" ] && resetprop_safe "$key" "$val"
    done
    # .build.tags and .build.type are device-prefixed — reset all variants
    for prop in $(resetprop 2>/dev/null | grep -oE 'ro\..*\.build\.tags' 2>/dev/null); do
        resetprop_safe "$prop" "release-keys"
    done
    for prop in $(resetprop 2>/dev/null | grep -oE 'ro\..*\.build\.type' 2>/dev/null); do
        resetprop_safe "$prop" "user"
    done
    # Boot mode recovery → boot
    resetprop_if_match ro.boot.mode recovery boot
    resetprop_if_match ro.bootmode recovery boot
    resetprop_if_match vendor.boot.mode recovery boot
    # Verified boot error markers — strip
    delprop_if_exists ro.boot.verifiedbooterror
    delprop_if_exists ro.boot.verifyerrorpart
    delprop_if_exists ro.boot.verifyerrorcode
    delprop_if_exists ro.build.selinux
    log_info "Boot state spoofed"
}

hide_keystore_leaks() {
    log_info "Stripping keystore/root-solution property leaks"
    # Magisk, KSU, APatch all leave telltale properties somewhere.
    # Strip them quietly — apps that check for keystore injection
    # look at exactly this list.
    for leak in \
        ro.magisk.keystore ro.magisk.hide ro.ksu.keystore \
        ro.ksu.selinux ro.apatch.keystore ro.apatch.recovery \
        ro.su_bit ro.debuggable.secure persist.magisk.hide; do
        delprop_if_exists "$leak"
    done
    log_info "Keystore leaks stripped"
}

# ---------------------------------------------------------------------------
# Per-app hiding: just before the app process gets to do init work, do
# mount namespace + env cleanup. This is the shell-side analogue of
# what the Zygisk native module does in C++.
# ---------------------------------------------------------------------------
hide_for_app_shell() {
    pkg="$1"
    if [ "$(is_allowlisted "$pkg")" = "1" ]; then
        log_info "Allowlist hit, skipping: $pkg"
        return 0
    fi

    # Only the per-app process has these mounted — if we're called outside
    # an app context, skip silently.
    # Most safely we just rely on the Zygisk module for namespace work;
    # this shell path handles cases where Zygisk is unavailable.

    # Strip env we inherit
    unsetenv_ro() {
        for var in MAGISK_VER MAGISK_VER_CODE MAGISK_DEBUG \
                   KSU KSU_VER KSU_VER_CODE \
                   APATCH APATCH_VER APATCH_VER_CODE; do
            # POSIX sh has no `unsetenv`. Best-effort: empty it.
            eval "export $var=" 2>/dev/null || true
        done
    }
    unsetenv_ro
    log_info "Shell-side hide applied for $pkg"
}

is_boot_completed() { [ "$(resetprop sys.boot_completed 2>/dev/null)" = "1" ]; }

boot_summary() {
    rm=$(detect_root_manager)
    log_info "Manager: $rm | Boot: $(is_boot_completed && echo done || echo booting) | Allowlist file: $ALLOWLIST_FILE"
}
