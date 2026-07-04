#!/system/bin/sh
# Rox2 - action (KSU/Magisk/APatch action button / play button)
# When you tap the play icon on a module card in KernelSU Manager, this
# script runs. v1.1 makes sure the WebUI opens on every root manager
# by trying multiple launch paths in order.
MODPATH="${0%/*}"
. "$MODPATH/common_func.sh"

VERSION="v1.1"
WEBUI_PATH=""

# Look for the WebUI index.html in the usual places.
for p in \
    "/data/adb/modules_update/Rox2/webroot/index.html" \
    "$MODPATH/webroot/index.html" \
    "/data/adb/modules/Rox2/webroot/index.html"; do
    [ -f "$p" ] && WEBUI_PATH="$p" && break
done

print_status() {
    echo ""
    echo "================================"
    echo "  Rox2 $VERSION"
    echo "  Root: $(detect_root_manager)"
    pfs=$(read_state post_fs_data_done 0)
    echo "  Boot: $pfs (1 = post-fs-data OK)"
    echo "  WebUI: ${WEBUI_PATH:-NOT FOUND}"
    echo "  Allowlist file: $ALLOWLIST_FILE"
    echo "================================"
    echo ""
}

print_status

if [ -z "$WEBUI_PATH" ]; then
    echo "[!] WebUI index.html missing."
    echo "    Expected at \$MODPATH/webroot/index.html"
    echo "    Reboot and reinstall if this persists."
    exit 1
fi

# Browser-friendly file:// URL. The user can copy this into a local
# browser if the manager-side WebView is broken for any reason.
file_url="file://${WEBUI_PATH}"
echo "Direct URL (also works in Chrome/DuckDuckGo if manager WebView fails):"
echo "  $file_url"
echo ""

opened=0

# 1) KernelSU WebUI activity. This is what KSU Manager passes WebUI
#    button clicks to when it does recognise the webroot field.
if [ "${KSU:-}" = "true" ] && command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$file_url" \
        -n me.weishu.kernelsu/.ui.webui.WebUIActivity \
        >/dev/null 2>&1 && opened=1 && echo "[ok] KernelSU WebUI launched"
fi

# 2) APatch WebUI activity. Same shape as KSU.
if [ "$opened" = 0 ] && [ "${APATCH:-}" = "true" ] && command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$file_url" \
        -n me.bmax.apatch/.ui.webui.WebUIActivity \
        >/dev/null 2>&1 && opened=1 && echo "[ok] APatch WebUI launched"
fi

# 3) Plain VIEW intent — works for Magisk Manager action and as a fallback.
if [ "$opened" = 0 ] && command -v am >/dev/null 2>&1; then
    am start -a android.intent.action.VIEW -d "$file_url" \
        >/dev/null 2>&1 && opened=1 && echo "[ok] Generic VIEW intent launched"
fi

# 4) Last-ditch: just echo the URL so the user can open it.
if [ "$opened" = 0 ]; then
    echo "[!] WebUI could not auto-open. Open this URL in your browser:"
    echo "    $file_url"
fi

echo ""
echo "If you do NOT see a globe/webui icon next to this module in"
echo "your root manager, that means the WebUI was launched via the"
echo "play (action) button you just tapped. Your manager does not"
echo "expose a separate WebUI entry, but this script is the same button."
echo ""
echo "Community: https://t.me/lestramk"
exit 0
