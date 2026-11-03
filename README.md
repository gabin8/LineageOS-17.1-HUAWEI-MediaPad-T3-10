# LineageOS 17.1 for HUAWEI MediaPad T3 10 (AGS-W09, codename "agassi")

**Status: work in progress — not bootable yet.** This is the Android 10 follow-up to the
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
  `device/device-tree.patch`, ported to lineage-17.1 (legacy, non-Treble build like 15.1).
- **Vendor:** first the proven 15.1 v2 vendor image unchanged; later a vendor rebuilt reproducibly
  from the stock EMUI 8 (Oreo) image with the 15.1 vendor fixes folded in at build time.
- **Boot:** same as 15.1 — signed image, **RAM-booted with `fastboot boot` only**.

The fix numbers used in commits and notes (e.g. "fix 33") refer to the 15.1 fix chain, kept here as
[`docs/lineage-15.1-README.md`](docs/lineage-15.1-README.md) (snapshot at v15.1-20261102).

## Progress
| Phase | State |
|---|---|
| 0. Prep: lineage-17.1 sync, kernel config audit, backups | in progress |
| 1. First boot to adb (Android 10 init, first-stage mount, permissive) | — |
| 2. Vendor ABI audit (Oreo vendor blobs against Android 10 system libs) | — |
| 3. Hardware bring-up: display/GPU, touch, WiFi, sensors, audio, video, camera, charging | — |
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
