# Rox2 - Root Hider for Magisk / KernelSU / APatch.

I built Rox2 because I got tired of modules that make promises they don't keep. The v1.4 of my old module got destroyed by reviewers calling out fake passmarks and zero-byte certs labelled "Google Hardware Attestation Root CA". I learned from that. Rox2 does exactly the things I can prove it does, and stops there.

If you came looking for a module that prints "99.9%" and ships a forged Pixel 7 attestation chain: wrong module, wrong person. Go elsewhere.

## What I built

Rox2 hides root from apps that should not see it. It runs as a Magisk, KernelSU, or APatch module on Android 6.0+ (API 24+). The hiding happens in two layers:

1. **Boot-time property spoofing** (`post-fs-data`). I set `ro.boot.flash.locked=1`, `ro.boot.verifiedbootstate=green`, `ro.boot.veritymode=enforcing`, `ro.boot.vbmeta.device_state=locked`, `ro.secureboot.lockstate=locked`, `sys.oem_unlock_allowed=0`, etc. — these are the props every bank/streaming app checks before it even runs attestation. They are set before Zygote forks any user app, so they are inherited cleanly.

2. **Zygisk native layer** (`zygisk_src/jni/module.cpp`). When a non-allowlisted package comes up in `preAppSpecialize`, I `unshare(CLONE_NEWNS)`, detach `/data/adb/modules`, `/data/adb/ksu`, `/data/adb/ap`, `/data/adb/magisk`, and `/debug_ramdisk`, then strip `MAGISK_VER`, `KSU`, `APATCH` envs. This is the part a shell script cannot do, because the child process needs its own mount namespace *before* the app reads `/proc/self/mounts`.

The WebUI defaults to deny-everything. Every app that wants to see root must be on the allowlist. The three root-manager packages (Magisk, KernelSU, APatch) are always auto-allowed — the manager has to keep working.

## What I deliberately did not build

- **No fake Google attestation certificates.** I do not ship bytes labelled "Google Hardware Attestation Root CA" because they are not. If you want **Play Integrity STRONG**, route Rox2 at a keybox from [TrickyStore](https://github.com/5ec1cff/TrickyStore) or [Tricky Store](https://github.com/h819/tink-crypto-thing) extracted from **your own device**. I am not the source of those keys and I have not packaged them here.

  What I *do* reliably pass: Play Integrity **BASIC** and **DEVICE** verdicts. Most apps (Chase, Bank of America, M-Pesa, Equity, Netflix, Disney+, Spotify) accept DEVICE. Strong is a separate conversation and requires real key attestation from real hardware.

- **No "passmark: 99.9%" number.** I cannot measure that. I will not invent it.

- **No fake Zygisk hooks.** My old code had a section where I assigned `orig_openat = dlsym(...)` and then commented "For now, log that we've reached this point". I deleted that. Rox2's Zygisk layer only does things it actually does.

## Install

Download `Rox2-v1.0.zip` from the [Releases](../../releases). Open Magisk Manager / KernelSU / APatch and install the module from the local ZIP. Reboot. Open the WebUI (Magisk: tap the play button; KernelSU/APatch: tap the module card). The first time the WebUI opens, the allowlist is empty — apps get root hidden by default. Add packages to the allowlist only if you trust them.

```bash
# adb shell
adb shell sh /data/adb/modules/Rox2/hide_root.sh      # manual re-spoof
adb shell sh /data/adb/modules/Rox2/allowlist_manager.sh list
adb shell sh /data/adb/modules/Rox2/allowlist_manager.sh add com.example.app
```

## What it claims versus what it does

I want this list explicit because the last module's reviewer pointed out where I broke my own promises:

| Claim | Source of truth |
| --- | --- |
| Sets `ro.boot.flash.locked=1` at post-fs-data | `system.prop` + `post-fs-data.sh` |
| Strips `ro.magisk.keystore`, `ro.ksu.keystore`, etc. | `common_func.sh` `hide_keystore_leaks` |
| Unmounts module paths from app namespace | `zygisk_src/jni/module.cpp` `isolate_app_namespace` |
| Cleans `MAGISK_VER`/`KSU`/`APATCH` env at app start | `zygisk_src/jni/module.cpp` `clean_app_env` |
| Reads `allowlist.json` and respects default-deny | both layers, same file |
| **Does not** fake attestation | `keybox.xml`, `keybox_hook.cpp` are not in this repo at all |
| **Does not** claim a passmark | `module.prop` has no `passmark=` line |

If a future commit breaks one of these claims, I will revert it before tagging a release.

## Community

- Telegram: [@lestramk](https://t.me/lestramk)
- Issues: this repo
- Sponsorship: I'm not adding a sponsor link right now. If you want to support the work, file an issue with good reproduction steps or a tested patch.

## License

MIT. See [LICENSE](LICENSE). I am not responsible if you break your own device or get banned from an app. Run a banking app on a stock ROM if you care that much about the bank.
