# Rox-Boot - Bootloader Hide Companion to Rox2

I built this as a focused companion to Rox2 because reviewers (rightly) pushed back on me filling `system.prop` with placeholder values for things I had no real answer for. Rox-Boot does less. I think it does it honestly.

## What Rox-Boot does

Rox-Boot is a stand-alone Magisk/KernelSU/APatch module that lives alongside Rox2 (or alone). At `post-fs-data`:

1. Sets the same `ro.boot.flash.locked=1`, `ro.boot.verifiedbootstate=green`, `ro.boot.vbmeta.device_state=locked`, `ro.secureboot.lockstate=locked`, `sys.oem_unlock_allowed=0` chain that a stock locked-phone has.
2. Strips the `ro.boot.verifiedbooterror*` markers some kernel builds set when a Magisk/KSU patch happens.
3. Bind-mounts a clean `/proc/cmdline` over the upstream one — strips `androidboot.unlocked=1`, `androidboot.verifier=disabled`, and re-sets `androidboot.verifiedbootstate=green`. **If the kernel refuses the bind-mount, Rox-Boot logs the failure rather than silently keep the dirty cmdline.**

## What Rox-Boot does NOT do (and where the line is)

- **It does not defeat hardware-backed attestation.** `ro.boot.flash.locked=1` and friends are software properties. The actual `KM_VERIFIED_BOOT_UNVERIFIED` state inside the kernel — what Google's ATS validates against `keymaster.blob` — is independent of these. Play Integrity Server-side querying `https://playintegrity.googleapis.com/v1/...` checks the TEE-attested blob, not the userspace prop.
- **It does not put back your vbmeta digest.** Stock firmware sets that from the actual vbmeta image. If I faked it, every Rox-Boot user would share the same value, which is itself a fingerprint — the problem I solved by deleting the placeholder does not exist as a different problem if I fill it with a different constant.
- **It does not touch `keymaster.blob` or the TEE.** Those are out of userspace reach on a non-debug device.

## Use this with TrickyStore for STRONG integrity

For `MEETS_STRONG_INTEGRITY` verdicts from Play Integrity the only legal path I know is:

1. Run TrickyStore with a keybox extracted from your own device while that device was in a locked-bootloader state
2. Rox-Boot keeps the software surface aligned with what a locked phone looks like
3. Google ATS verifies your TEE-attested blob against the rotated real-device keys
4. STRONG verdict returned

I do not bundle a keybox. I will not bundle a keybox.

## Install

```
adb shell sh /data/adb/modules/RoxBoot/uninstall.sh
adb install RoxBoot-v1.0.zip   # via Magisk / KernelSU / APatch Manager
adb reboot
```

Or just install it from your root manager's Local Install menu.

## Source of truth

| Claim | Where |
| --- | --- |
| Sets locked verified-boot chain | `system.prop` + `post-fs-data.sh` |
| Strips `ro.boot.verifiedbooterror*` | `common_func.sh` `known_blu_leaks` |
| Bind-mounts clean `/proc/cmdline` | `post-fs-data.sh` `make_clean_cmdline` |
| Refuses to fake vbmeta digest | `system.prop` (deliberately absent) |
| Refuses to claim a keymaster passmark | `module.prop` (no `passmark=` line) |

If a future commit breaks one of these, I will revert it before tagging.

## License

MIT. See [LICENSE](LICENSE).
