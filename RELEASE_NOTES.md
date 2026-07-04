# Rox2 v1.0

First cut of Rox2, the root-hider I rewrote after the v1.4 of the previous project got roasted on Telegram. The full story is in the README; this file is the short list of what to do.

## Install

1. Download `Rox2-v1.0.zip` below.
2. Install via Magisk, KernelSU, or APatch.
3. Reboot.
4. Open the WebUI:
   - **Magisk**: tap the play button.
   - **KernelSU**: tap the Rox2 module card.
   - **APatch**: tap the Rox2 module card.

## First-run

The WebUI opens with an empty allowlist. **Every app is hidden from root by default.** The root managers themselves (Magisk, KernelSU, APatch) are auto-allowed so they keep working.

Add packages to the allowlist if you want them to see root. The list lives at `/data/adb/modules/Rox2/allowlist.json` on the device. You can edit it by hand or through the WebUI.

## What I did not include (and why)

I deliberately did not ship:

- **Fake Play Integrity attestation chains.** If you need **STRONG** Play Integrity, get a keybox from your own device via TrickyStore and point Rox2 at it. I am not your source for stolen Google intermediate CAs.
- **A "passmark" percentage.** I cannot measure this; I will not invent it. The README has the actual list of what Rox2 does.

The module passes **Play Integrity BASIC and DEVICE** reliably. If your bank app demands STRONG, see above.

## After install

If you want a clean unspoof (re-running the prop spoof without rebooting):

```bash
adb shell sh /data/adb/modules/Rox2/hide_root.sh
```

If the WebUI behaves oddly:

```bash
adb shell sh /data/adb/modules/Rox2/uninstall.sh
adb shell sh /data/adb/modules/Rox2/customize.sh
```

## Community

Telegram: [@lestramk](https://t.me/lestramk). I am the only person maintaining this, so replies take time. Be specific when you file an issue — device model, root manager and version, target app, log line.

— lee-muriithi-kingori
