# LineageOS 17.1 for HUAWEI MediaPad T3 10 (AGS-W09)

Unofficial LineageOS 17.1 (Android 10) for the Wi-Fi MediaPad T3 10: model **AGS-W09**,
Snapdragon 425 (MSM8917), 2 GB RAM, codename **agassi**. Follow-up to the
[LineageOS 15.1 port](https://github.com/gabin8/LineageOS-15.1-HUAWEI-MediaPad-T3-10).

> ⚠️ **AGS-W09 (MediaPad T3, Snapdragon) is not AGS2-W09 (MediaPad T5, Kirin).** Never cross-flash.

## Download
[v17.1-20261108](https://github.com/gabin8/LineageOS-17.1-HUAWEI-MediaPad-T3-10/releases/tag/v17.1-20261108)
(test build): boot, system and vendor images plus `INSTALL.txt`. Read `INSTALL.txt` first.

- Needs the engineering bootloader.
- The boot image is **RAM-booted only**: `fastboot boot boot_los17.img`. Never `fastboot flash boot`;
  that drops the tablet into Qualcomm download mode (`05c6:900e`, black screen).
- After every power-off or restart, boot it again from a PC.

## Status
**Works:** Wi-Fi and hotspot, Bluetooth (audio and calls), GPS, audio and 3.5 mm headset, both
cameras, hardware video decoding, accelerometer and auto-rotate, USB (MTP, PTP, tethering, OTG),
microSD, Widevine L3, opt-in encryption, SELinux enforcing.

**Limits:**
- No booting without a PC (see above).
- No FM radio: the board doesn't support it (stock has no FM app either).
- No Vulkan: the Adreno 308 is OpenGL ES 3.0 only.
- Keystore and lock screen run in software on purpose. The engineering TrustZone keymaster
  overwrites stock's RPMB records, which blocks any return to stock.
- Encryption is off by default and full-disk only (no file-based encryption).
- No Wi-Fi MAC randomization.
- AGS-L09 (LTE) is untested and has no telephony.

## Source
| Path | Contents |
|---|---|
| [`kernel/`](kernel/series) | Patch series for [clienthax's kernel](https://github.com/clienthax/android_kernel_huawei_AGS-W09) @ `b4cffd28` and [prima](https://github.com/clienthax/qcom_opensource_wlan_prima) @ `eed7cd6` |
| [`device/`](device/) | Device tree patch and the lineage-17.1 `git am` series (`device/lineage-17.1/apply.sh`) |
| [`frameworks/`](frameworks/) | Patches to LineageOS 17.1 sources |
| [`vendor/`](vendor/) | Stage A/A2 scripts that adapt the stock EMUI 8 vendor to Android 10, plus the [blob audit](vendor/blob-audit.md) |
| [`ramdisk/`](ramdisk/), [`scripts/`](scripts/) | Boot ramdisk files; build, signing and check tools |
| [`docs/`](docs/) | Detailed [porting notes](docs/lineage-17.1-notes.md) and the [15.1 fix chain](docs/lineage-15.1-README.md) |

## Credits
clienthax (kernel and device tree), the LineageOS project, MacTavishAO's msm8917 lineage-17.1 trees,
Huawei's GPL camera driver via [adeii/huawei-london-kernel](https://github.com/adeii/huawei-london-kernel),
and the upstream ambient-capabilities patch (Andy Lutomirski).

Use at your own risk, no warranty. Flashing firmware can brick your device.
