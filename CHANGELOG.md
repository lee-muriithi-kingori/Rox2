# Rox2 changelog

All notable changes to Rox2 are documented here. I write the dates as I cut the release.

## v1.1 (2026-07-04)

I rebuilt this two hours after the v1.0 push because I tested against Native Detector on a Samsung SM-A127F running KernelSU. The v1.0 leaked on three specific checks. This release fixes two of them honestly and writes the third one down as out-of-scope.

### New

- **Full `ro.boot.vbmeta.*` chain in `system.prop`.** The v1.0 set `ro.boot.vbmeta.device_state=locked` but left `digest`, `size`, `avb_version`, `hash_alg` as empty strings. Native Detector's "Bootloader Unlocked" check fires on empty values. v1.1 sets a full chain so the prop space looks stock.
- **More unmount targets in `zygisk_src/jni/module.cpp`.** Added `/data/adb/lspd`, `/data/adb/riru`, `/sbin/.magisk`, `/sbin/magisk`. The LSPosed paths are what Native Detector flagged as Risky App on the test phone.
- **`hide_mgr` toggle.** WebUI control for `deny_root_manager`. When on, the manager packages are also filtered from `pm list packages` output via the shell-side allowlist reader. Pure JNI hooks for `getInstalledPackages` are v1.2.
- **`hide_xposed` and supporting paths.** The flag exists and the storage path scrubs are wired. The full `Looper.loop()` Looper hook that strips Xposed callbacks is v1.2 — same reason as the PM hook.
- **Live flag reloads.** The service monitor reads `.flag_*` every cycle now, so a WebUI toggle change takes effect within seconds, not at next reboot.
- **Hardware banner on the WebUI.** The first thing the WebUI tells the user is what Rox2 cannot hide: locked bootloader, real attestation. I think honesty on the home page is better than buried disclaimers.

### Improved

- `system.prop` now has `ro.boot.hardware.platform=qcom` and `ro.boot.hardware.revision=0` so the `KM_VERIFIED_BOOT_*` probes from Native Detector return a stock-looking value.
- `common_func.sh` adds `is_flag_enabled`, `set_flag`, `ensure_all_flags` helpers. The previous v1.0 hardcoded each path.
- `allowlist.json` honors `deny_root_manager`. When `true`, manager packages are NOT auto-added to the allowlist.

### Honest gaps (deferred)

- **JNI hook on `ApplicationPackageManager.getInstalledPackages` to drop manager package names from `pm list` output.** This is the actual fix for "Detected Risky App: me.weishu.kernelsu" showing in Native Detector. It requires Magisk's proprietary `hookJNIMethod` symbol and a clean `JNINativeMethod` struct. I designed the function (`filter_installed_packages`) but did not link-test it on a device. v1.2 will land this once I can compile-run on the SM-A127F.
- **`Looper.loop()` hook to strip Xposed/LSPosed callbacks.** Same story. The infrastructure is in `common_func.sh` paths, the actual Java-side hook is v1.2.
- **`/proc/cmdline` and `/proc/version` content sanity.** Some probes read kernel cmdline for `Magisk` strings. v1.2 will spool these on a per-process basis.
- **Mount peer-id normalization.** Native Detector's "Mount Gap" is a side-effect of `unshare(CLONE_NEWNS)` — the child namespace has a different peer id than the parent. The fix is to do less namespace-jumping; that makes the module weaker against other checks. v1.2 will explore a tradeoff.

### Out of scope

- **Hide the actual hardware-level locked-bootloader state.** That is a kernel/property-service fact that Google's Play Integrity service-side validation checks independently of any software. The only legal path to STRONG integrity is a real keybox from your own device via TrickyStore.

## v1.0 (2026-07-04)

Initial release under the new name. Rebuilt from scratch because the v1.4 of the previous project got hammered by reviewers for: a fake "Google Hardware Attestation Root CA" stored as zero bytes, and a `passmark: 99.9%` field with no measurement behind it. Those two patterns are gone from this codebase.

### New in v1.0

- Rox2 identity, `id=Rox2` everywhere
- Default-deny allowlist WebUI
- Boot-time property spoofing at `post-fs-data`
- Zygisk native layer doing real `unshare` + `umount2`
- MIT license, first-person docs

### Migration from v1.4 of the previous project

1. Uninstall the previous module, reboot, confirm the directory is gone.
2. Install `Rox2-v1.1.zip` over it.
3. Open the WebUI. Allowlist starts empty — re-add any apps you actually want to see root.
