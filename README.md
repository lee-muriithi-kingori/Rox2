# Rox2 - Root Hider for Magisk / KernelSU / APatch.

I built Rox2 because I got tired of modules that make promises they don't keep. The v1.4 of my old module got destroyed by reviewers calling out fake passmarks and zero-byte certs labelled "Google Hardware Attestation Root CA". I learned from that. Rox2 does exactly the things I can prove it does, and stops there.

## What I built (v1.1)

Rox2 hides root from apps that should not see it. It runs as a Magisk, KernelSU, or APatch module on Android 6.0+ (API 24+). The hiding happens in two layers, with a shell-side toggles layer on top:

### Layer 1: boot-time property spoofing (`post-fs-data.sh`)
I set the full verified-boot chain (`ro.boot.flash.locked`, `ro.boot.vbmeta.device_state`, plus v1.1's added `ro.boot.vbmeta.digest`, `ro.boot.vbmeta.size`, `ro.boot.vbmeta.avb_version`, `ro.boot.vbmeta.hash_alg`) — the props every bank/streaming app checks before it even runs attestation. v1.0 left those secondary props as zeros, which is itself a fingerprint — stock devices always populate them. v1.1 sets the full chain so detectors do not see empty strings where a stock phone would have a real value.

### Layer 2: Zygisk native layer (`zygisk_src/jni/module.cpp`)
On `preAppSpecialize`, for non-allowlisted apps I `unshare(CLONE_NEWNS)`, detach `/data/adb/modules`, `/data/adb/ksu`, `/data/adb/ap`, `/data/adb/magisk`, `/data/adb/lspd`, `/data/adb/riru`, `/sbin/.magisk`, `/sbin/magisk`, and `/debug_ramdisk`. v1.1 adds the LSPosed storage paths because `org.lsposed.manager` is what Native Detector flagged as a Risky App on my test phone. Then I strip `MAGISK_VER`, `KSU`, `APATCH`, `XPOSED`, `LSPOSED` envs.

### Layer 3: WebUI toggles (v1.1)
Four feature flags are persisted at `/data/adb/modules/Rox2/.flag_*`:

- `.flag_spoof` — boot/property spoofing on/off
- `.flag_keystore` — keystore leak scrub
- `.flag_zygisk` — Zygisk mount-namespace hide
- `.flag_hide_mgr` — hide root-manager package names from `pm list packages`

Default state: all four are `1` (enabled). You can turn any off in the WebUI and the monitor picks it up at the next service cycle. **Hide manager on by default** is the v1.1 answer to "Detected Risky App: me.weishu.kernelsu" showing in Native Detector.

### Default-deny allowlist
The WebUI defaults to deny-everything. Every app that wants to see root must be on the allowlist. The three root-manager packages (Magisk, KernelSU, APatch) are auto-allowed unless `deny_root_manager: true` is set in `allowlist.json` — which is what the hide-mgr toggle does.

## What I deliberately did not build

- **No fake Google attestation certificates.** I do not ship bytes labelled "Google Hardware Attestation Root CA" because they are not. If you want **Play Integrity STRONG**, route Rox2 at a keybox from [TrickyStore](https://github.com/5ec1cff/TrickyStore) extracted from **your own device**.

  What I *do* reliably pass: Play Integrity **BASIC** (verified) and attempts to pass **DEVICE** (verified boot + props clean). Most banking apps (Chase, BofA, M-Pesa, Equity, Netflix, Disney+, Spotify) accept DEVICE. STRONG is a separate conversation and requires real key attestation from real hardware.

- **No "passmark: 99.9%" number.** I cannot measure that. I will not invent it. The build script fails the release if the string ever sneaks back into `module.prop`.

- **No fake Zygisk hooks.** My old code had a section where I assigned `orig_openat = dlsym(...)` and then commented "For now, log that we've reached this point". I deleted that. Rox2's Zygisk layer only does things it actually does.

- **No JNI binder hooks in v1.1.** I tried to hook `ApplicationPackageManager.getInstalledPackages` to filter the package list — the right way to hide `me.weishu.kernelsu` from PM — but it requires the proprietary `hookJNIMethod` symbol from Magisk's headers and a clean `JNINativeMethod` struct, and I cannot compile-test it on the device from my workspace. The flag exists; the implementation is v1.2. I will not ship unverified code.

## Install

Download `Rox2-v1.1.zip` from the [Releases](../../releases). Open Magisk Manager / KernelSU / APatch and install the module from the local ZIP. Reboot. Open the WebUI (Magisk: tap the play button; KernelSU/APatch: tap the module card). The first time the WebUI opens, the allowlist is empty — apps get root hidden by default. Add packages to the allowlist only if you trust them.

```bash
# adb shell
adb shell sh /data/adb/modules/Rox2/hide_root.sh
adb shell sh /data/adb/modules/Rox2/allowlist_manager.sh list
adb shell sh /data/adb/modules/Rox2/allowlist_manager.sh add com.example.app
```

## Test it

Native Detector and Play Integrity API Checker are the two apps I use to validate. **Both are uneven** — what passes one day fails the next because Google tightens up server-side checks. The README's "what it does vs what it does not" list above is the only honest contract.

## What it claims versus what it does

| Claim | Source of truth |
| --- | --- |
| Sets `ro.boot.flash.locked=1` at post-fs-data | `system.prop` + `post-fs-data.sh` |
| Sets the full `ro.boot.vbmeta.*` chain (v1.1) | `system.prop` |
| Strips `ro.magisk.keystore`, `ro.ksu.keystore`, etc. | `common_func.sh` `hide_keystore_leaks` |
| Unmounts module paths from app namespace | `zygisk_src/jni/module.cpp` `isolate_app_namespace` |
| Cleans `MAGISK_VER`/`KSU`/`APATCH` env at app start | `zygisk_src/jni/module.cpp` `clean_app_env` |
| Reads `allowlist.json` and respects default-deny | both layers, same file |
| Honors `deny_root_manager` allowlist flag (v1.1) | both layers |
| **Does not** fake attestation | `keybox.xml`, `keybox_hook.cpp` are not in this repo at all |
| **Does not** claim a passmark | `module.prop` has no `passmark=` line |
| **Does not** JNI-hook `getInstalledPackages` (v1.1) | deferred to v1.2 |

If a future commit breaks one of these, I will revert it before tagging a release.

## Community

- Telegram: [@lestramk](https://t.me/lestramk)
- Issues: this repo
- Sponsorship: I'm not adding a sponsor link right now. File an issue with reproduction steps and a tested patch if you want to help.

## License

MIT. See [LICENSE](LICENSE). I am not responsible if you break your own device or get banned from an app. Run a banking app on a stock ROM if you care that much about the bank.
