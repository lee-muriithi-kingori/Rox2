# Rox2 changelog

All notable changes to Rox2 are documented here. I write the dates as I cut the release.

## v1.0 (2026-07-04)

Initial release under the new name. I rebuilt the module from scratch because the v1.4 of the previous project got hammered by reviewers for two specific things: a fake "Google Hardware Attestation Root CA" stored as zero bytes, and a `passmark: 99.9%` field I had no measurement for. Those two patterns are gone from this codebase.

### New

- **Rox2 identity and directory layout.** Renamed from the old project. New `id=Rox2` everywhere.
- **Zygisk native layer** in `zygisk_src/jni/module.cpp`. This is real per-process work: `unshare(CLONE_NEWNS)`, then `umount2(MNT_DETACH)` on the four module storage paths, then strip `MAGISK_VER`/`KSU`/`APATCH` envs. No fake hooks. No dlsym-no-op section.
- **Default-deny allowlist** in `webroot/index.html`. The WebUI starts empty; the user adds packages they trust. Magisk, KernelSU, APatch themselves are auto-allowed (manager has to keep working).
- **One-file root hider** for the common case: `sh hide_root.sh` re-applies props without rebooting.
- **MIT license file** with first-person disclaimer. I am not responsible if your bank app notices.
- **Build script** (`build.sh`) that handles missing-NDK gracefully — it ships a working ZIP without the native lib, and the shell-script layer still hides root in the meantime.
- **GitHub Actions workflow** that builds and uploads a release ZIP on tag.

### Removed

- `keybox.xml` and the entire `keybox_updater.sh` flow. There is no keybox subsystem in Rox2 by design.
- `keybox_hook.cpp` and `root_spoof.cpp` from the previous Zygisk tree. Replaced by `module.cpp`, which is small enough to read in one screen.
- All shell-side "passmark" calls and the `passmark=99.9` claim in `module.prop`. The README has the actual list of things Rox2 does.
- `target_apps.txt`. The allowlist replaces it. `shizuku_helper.sh`, `update_service_addon.sh` and similar auxiliary scripts are gone or refactored into `allowlist_manager.sh`.

### Migration from the old module

If you installed v1.4 of the old project:

1. Uninstall the old module. Reboot. Confirm `/data/adb/modules/<old>` is gone.
2. Install `Rox2-v1.0.zip`. Reboot.
3. Open the WebUI. The allowlist starts empty — re-add any apps you actually wanted to see root (e.g. `com.topjohnwu.magisk`, file managers, root checkers).

Your data is untouched. Only the module directory is replaced.

## Next

I have no public v1.1 yet. The v1.1 ideas I keep in my head:

- Bind-mount umount detection for non-Magisk root managers (KSU/APatch) so the Zygisk namespace switch covers more cases.
- A small C++ helper so the `hide_root.sh` shell code can ask the Zygisk module to flush its allowlist cache without restarting the monitor.
- Optional: a sign-build flow for users who want to distribute their own forks. I do not have a project signing key.

If you want any of these, file an issue. If none of you want them, they will not get built.
