#!/system/bin/sh
# Rox-Boot - companion module functions
# Smaller surface than Rox2: only what touches bootloader-state signals.

MODPATH="${0%/*}"
[ -z "$MODPATH" ] && MODPATH=/data/adb/modules/RoxBoot

LOG_FILE=/data/local/tmp/RoxBoot.log

log_msg() {
    level="$1"; shift
    stamp=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo 1970-01-01)
    echo "[$stamp] [$level] RoxBoot: $*" >> "$LOG_FILE" 2>/dev/null
    log -t RoxBoot "[$level] $*" 2>/dev/null
}

resetprop_safe() {
    target="$1"; value="$2"
    tries=0
    while [ $tries -lt 5 ]; do
        if resetprop -n "$target" "$value" 2>/dev/null; then return 0; fi
        tries=$((tries + 1)); sleep 0.2
    done
    return 1
}

resetprop_if_diff() {
    target="$1"; value="$2"
    current=$(resetprop "$target" 2>/dev/null || true)
    [ "$current" != "$value" ] && resetprop_safe "$target" "$value"
}

delprop_if_exists() {
    target="$1"
    current=$(resetprop "$target" 2>/dev/null || true)
    [ -n "$current" ] && resetprop --delete "$target" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Boot-state prop scrub. The list is REAL properties — the names I cannot
# back with evidence I leave out.
# ---------------------------------------------------------------------------
known_blu_leaks() {
    # Verified-boot error markers. If ANY of these exist, the kernel has
    # already signaled an unverified boot to user space — we strip them.
    for leak in \
        ro.boot.verifiedbooterror \
        ro.boot.verifyerrorpart \
        ro.boot.verifyerrorcode; do
        delprop_if_exists "$leak"
    done

    # Boot mode — recovery / bootloader modes leak the unlocked state.
    resetprop_if_diff ro.boot.mode     boot
    resetprop_if_diff ro.bootmode      boot
    resetprop_if_diff vendor.boot.mode boot
}

# ---------------------------------------------------------------------------
# Kernel cmdline sanitization. Magisk/KSU leave "androidboot.unlocked=1"
# and "androidboot.verifier=disabled" in /proc/cmdline. Apps that read
# this directly (some banking apps do, before they call Play Integrity)
# will flag the device. We bind-mount a clean version.
# ---------------------------------------------------------------------------
make_clean_cmdline() {
    # Read original cmdline once, save the bits we want to keep
    src=$(cat /proc/cmdline 2>/dev/null || echo "")
    [ -z "$src" ] && return 1

    # Strip root-manager-flagged tokens. We keep everything else.
    cleaned=$(echo "$src" | tr ' ' '\n' | grep -vE '^(androidboot\.)?(unlocked|verifiedbootstate|veritymode|verifier|dtbo|vbmeta)(=|$)' | tr '\n' ' ')
    cleaned=$(echo "$cleaned" | sed 's/  */ /g; s/^ //; s/ $//')
    [ -z "$cleaned" ] && return 1

    tmp=/data/local/tmp/roxboot_cmdline_$$
    umask 022
    printf '%s\n' "$cleaned androidboot.verifiedbootstate=green androidboot.verifier=locked" > "$tmp"

    # Hide /proc/cmdline in this mount namespace and replace with our clean copy.
    # Mounting a single file is supported on all Android kernel versions I care about.
    if mount --bind "$tmp" /proc/cmdline 2>/dev/null; then
        log_msg "INFO" "Bound clean cmdline"
    else
        # Some kernels forbid bind-mounting proc files. Fall back: write
        # the cleaned content to a path the WebUI can read; the upstream
        # cmdline remains visible to userspace.
        log_msg "WARN" "Could not bind-mount /proc/cmdline"
        cp "$tmp" /data/local/tmp/cmdline_visible 2>/dev/null
    fi

    rm -f "$tmp"
    return 0
}

# ---------------------------------------------------------------------------
# /proc/version is a smaller leak. Some fingerprint scripts read the
# Linux version string and match the kernel build. We cannot hide it
# without mounting proc, but at minimum we can strip "magisk" / "ksu"
# or similar tokens that may appear in a custom-built kernel config.
# ---------------------------------------------------------------------------
scrub_proc_version() {
    # No good way to do this from a shell script. doc.
    : # no-op
}
