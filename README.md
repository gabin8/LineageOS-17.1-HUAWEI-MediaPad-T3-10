# LineageOS 17.1 for HUAWEI MediaPad T3 10 (AGS-W09, codename "agassi")

**Status: work in progress — boots to the home screen (first boot 2026-11-03); hardware bring-up
ongoing.** This is the Android 10 follow-up to the
[LineageOS 15.1 port](https://github.com/gabin8/LineageOS-15.1-HUAWEI-MediaPad-T3-10), which is
daily-usable. **If you want a working ROM today, use 15.1.**

- **Device:** Huawei MediaPad T3 10, model **AGS-W09** (Wi‑Fi only), codename **agassi / ags_w09**
- **SoC:** Qualcomm Snapdragon 425 / MSM8917 (msm8937 family), 4 cores, 2 GB RAM
- **Target:** LineageOS 17.1 (Android 10), same 3.18 kernel as the 15.1 port
- ⚠️ **AGS-W09 (Snapdragon T3) is NOT AGS2-W09 (Kirin T5).** Do not cross-flash. Hard-brick risk.

## Why 17.1
- Android 10 app compatibility (API 29), current WebView builds, a later security patch level.
- The 3.18 kernel has no eBPF, so LineageOS 18.1 (Android 11) is the ceiling for this device;
  17.1 is the lighter of the two on 2 GB RAM.

## Approach
A forward-port of the 15.1 port, not a new port. This repository starts from the 15.1 history.
- **Kernel:** unchanged — clienthax's Huawei 3.18 kernel with the patches in `kernel/`.
  Ambient capabilities (`kernel/ambient-caps-3.18.patch`) become required on Android 10.
- **Device tree:** clienthax's `android_device_huawei_ags_w09` (lineage-15.1) with
  `device/device-tree.patch` (the 15.1 v2 state), then the lineage-17.1 port on top:
  [`device/lineage-17.1/`](device/lineage-17.1/) — a `git am` series, one commit per Android 10
  change, applied with `device/lineage-17.1/apply.sh` (legacy, non-Treble build like 15.1).
- **Frameworks:** `frameworks/*.patch` (the 15.1 ones apply where still needed). Android 10 ones:
  - `system_core-sdcard-fuse-fallback.patch` — Android 10 dropped the FUSE sdcard daemon and needs
    AOSP sdcardfs or esdfs; this kernel's sdcardfs is the older Samsung one (as on stock EMUI and
    15.1, storage runs over FUSE). Oreo's FUSE code, plus Q's 4th `full` view, forking for vold.
  - `av-swcodec-ldconfig-legacy-sphal.patch` — the software codecs' APEX could not load the vendor
    gralloc mapper on a non-VNDK build (`gralloc-mapper is missing`, VP9 crashed the player).
  - `SetupWizard-no-emergency-call-without-voice.patch` — no "Emergency call" on a Wi-Fi tablet.
  - `lineage-sdk-lockscreen-rotation-default.patch` — overlayable "Rotate lock screen" default
    (15.1 needed a manual toggle, fix 41).
- **Vendor:** first the proven 15.1 v2 vendor image unchanged; later a vendor rebuilt reproducibly
  from the stock EMUI 8 (Oreo) image with the 15.1 vendor fixes folded in at build time.
- **Boot:** same as 15.1 — signed image, **RAM-booted with `fastboot boot` only**.

### Running Android 10 on the Oreo vendor (stage A)
The device keeps the 15.1 v2 vendor partition; two scripts adapt it, each step documented inline:
- [`vendor/stage-a-android10.sh`](vendor/stage-a-android10.sh) — before the first flash: neutralise
  the vendor `init.qcom.rc` (Android 10 now imports it), match the vendor fingerprint, and install the
  vendor half of the split SELinux policy (Android 10 always loads split policy).
- [`vendor/stage-a2-android10.sh`](vendor/stage-a2-android10.sh) — from a root recovery: the Oreo
  `vndservicemanager` cannot talk to Android 10's libbinder (no display), the vendor's Oreo
  `libnativeloader` shadows Android 10's APEX copy (no zygote), Oreo-built HIDL wrappers do not link,
  configstore's Oreo seccomp policy kills it (system_server hang at screen-off).
- [`scripts/vendor-abi-audit.py`](scripts/vendor-abi-audit.py) finds such breaks offline (legacy
  linker order: `/system`, then `/vendor`, then the APEX link);
  [`scripts/verify-system-img.sh`](scripts/verify-system-img.sh) checks the root directory inside
  `system.img` before flashing (Android 10 builds it system-as-root on every device).

The fix numbers used in commits and notes (e.g. "fix 33") refer to the 15.1 fix chain, kept here as
[`docs/lineage-15.1-README.md`](docs/lineage-15.1-README.md) (snapshot at v15.1-20261102).

## Progress
| Phase | State |
|---|---|
| 0. Prep: lineage-17.1 sync, kernel config audit, backups | done |
| 1. First boot to adb (Android 10 init, first-stage mount, permissive) | done: boots unassisted in ~40 s, setup wizard, launcher |
| 2. Vendor ABI audit (Oreo vendor blobs against Android 10 system libs) | boot blockers fixed (stage A2); 75 non-boot blobs left |
| 3. Hardware bring-up: display/GPU, touch, WiFi, sensors, audio, video, camera, charging | in progress: display, touch, sensors/auto-rotate, charging, Wi-Fi (factory MAC + calibration), storage, audio (speaker, agassi ACDB), video (HW H.264/HEVC/VP8, SW VP9) OK; camera next |
| 4. SELinux enforcing | — |
| 5. Reproducible vendor + release | — |

## ⚠️ This unit runs a flashed engineering QRD bootloader

Not Huawei's stock bootloader (from earlier unlock work). It reports board-id **0x1000b** (QRD SKU5),
authenticates boot images against the genuine stock `/boot` signature (so a custom image is packed
with that signature appended → RSA fails → orange "unlocked" warning → boots anyway), and passes
`androidboot.mode=charger` on USB power.

- **Only `fastboot boot <img>` works — do NOT `fastboot flash boot`.** `fastboot boot` bypasses the
  signature check; booting from the partition enforces it, rejects our bad-sig image, and drops the
  SoC into Qualcomm emergency download mode (`05c6:900e`, black screen). Keep the stock `boot.bin`
  on the boot partition for safety and RAM-boot the custom image every time.

## Credits & license
Built on the GPLv2 Linux kernel and the clienthax and LineageOS sources; the ambient-caps patch is
upstream (Andy Lutomirski, v4.3); the Oreo camera driver comes from Huawei's GPL release as published
in [adeii/huawei-london-kernel](https://github.com/adeii/huawei-london-kernel) (commit d6d5b83).
Makefile and flag changes for Android 10 are cribbed from MacTavishAO's msm8917 lineage-17.1 trees.
Shared in the same spirit — use at your own risk, no warranty. Flashing firmware can brick your device.
