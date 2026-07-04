#!/system/bin/sh
# Rox2 - action
# Triggered by the "play" button in Magisk / tap in KernelSU.
# Opens the WebUI cleanly.

MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

echo "================================"
echo "  Rox2 v1.0"
echo "  Root: $(detect_root_manager)"
echo "  Boot: $(read_state post_fs_data_done 0) (1=done)"
echo "  Allowlist: $(wc -l < "$ALLOWLIST_FILE" 2>/dev/null || echo 0) lines"
echo "================================"
echo ""

# Locate the WebUI
webui=""
for p in \
    "/data/adb/modules_update/Rox2/webroot/index.html" \
    "$MODPATH/webroot/index.html" \
    "/data/adb/modules/Rox2/webroot/index.html"; do
    [ -f "$p" ] && webui="$p" && break
done

[ -z "$webui" ] && { echo "[!] WebUI not found"; exit 1; }

url="file://${webui}"
opened=0

# KernelSU WebUI host
if [ "${KSU:-}" = "true" ] && command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$url" \
        -n me.weishu.kernelsu/.ui.webui.WebUIActivity 2>/dev/null && opened=1
fi

# APatch WebUI host
if [ "$opened" = 0 ] && [ "${APATCH:-}" = "true" ] && command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$url" \
        -n me.bmax.apatch/.ui.webui.WebUIActivity 2>/dev/null && opened=1
fi

# Last resort — plain VIEW intent
if [ "$opened" = 0 ] && command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$url" 2>/dev/null && opened=1
fi

[ "$opened" = 1 ] && echo "[ok] WebUI opened" || {
    echo "[!] Could not open WebUI"
    echo "    Open: $url"
}

# Print the Telegram community line for adb-shell users.
echo ""
echo "Community: https://t.me/lestramk"
exit 0
