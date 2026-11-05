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
  `kernel/mmput-async-3.18.patch` fixes a kernel panic that 15.1 had too: the binder driver
  backported in 15.1 (fix 3) had `mmput_async()` replaced by `mmput()`, which may sleep, and its
  memory shrinker calls it with a spinlock held. Under memory pressure (several apps open)
  `kswapd` hit it and the tablet rebooted into the Qualcomm crash-dump mode.
  Tethering needed two more: Android 10's netd adds an IPv6 `rpfilter` rule for every tethered
  interface and gives up when the kernel lacks the match, so USB and Bluetooth tethering
  connected but shared no internet (`kernel/defconfig-ipv6-rpfilter.patch`). With that fixed,
  ending a tethering session crashed the kernel: Qualcomm's SIP list in each conntrack was only
  set up for real connections, not for the templates netd's FTP/PPTP helper rules create
  (`kernel/conntrack-sip-segment-list-init.patch`). Both now share the tablet's Wi-Fi: USB at
  150 Mbit/s to the PC, Bluetooth at about 2 Mbit/s.
- **Device tree:** clienthax's `android_device_huawei_ags_w09` (lineage-15.1) with
  `device/device-tree.patch` (the 15.1 v2 state), then the lineage-17.1 port on top:
  [`device/lineage-17.1/`](device/lineage-17.1/) — a `git am` series, one commit per Android 10
  change, applied with `device/lineage-17.1/apply.sh` (legacy, non-Treble build like 15.1).
  It includes the SELinux policy for enforcing (0022/0023) and a small LiveDisplay 2.0 service
  (0024): "Reduce power consumption" (adaptive backlight) drives the panel's own CABC again; 15.1
  used the hardware class LineageOS 17.1 dropped (fix 50). 0026 adds the USB modes: Android 10's
  `init.usb.rc` only knows adb and accessory modes for this kernel's legacy `android_usb` gadget
  (15.1 had them from Qualcomm's `init.qcom.usb.rc`), so File transfer (MTP), PTP, USB tethering
  and MIDI fell back to adb. 0027 brings up Bluetooth (15.1 never had it): the `hciattach` power-up
  service stock EMUI kept in its vendor rc, its SELinux domain, and the factory Bluetooth address
  read from oeminfo (the same source as the Wi-Fi MAC). 0028 makes Bluetooth headphones work: the
  Huawei audio policy routed calls only to a combined "all SCO" device, which crashed Android 10's
  audio service in a loop as soon as a headset connected; and Huawei's A2DP audio module predates
  codec configuration, so music stayed on the speaker (stage A2 parks it; Android 10's is used).
  0029 stops claiming GPU features the Adreno 308 lacks: it is OpenGL ES 3.0 only, but the stock
  vendor declared Vulkan 1.0.3 and the OpenGL ES 3.1/3.2 extension pack. Its Vulkan driver fails on
  this GPU with a non-error return code, so game engines picked Vulkan and stopped with "No Vulkan
  driver found!" instead of falling back to OpenGL ES (stage A2 item 14 parks the driver and the
  feature files; Android's stub then reports zero Vulkan GPUs). Games built only for Vulkan, such
  as GTA: Vice City Definitive (Unreal's desktop-class Vulkan SM5 renderer), cannot run here.
  0030 turns on the Wi-Fi hotspot: Android 10 starts `hostapd` only through its HIDL interface,
  which the manifest did not declare, and the vendor still had Huawei's Oreo `hostapd` (stage A2
  item 15 installs the Android 10 one and its rc). Checked with a PC as the client: WPA2, an
  address by DHCP, 38 Mbit/s (2.4 GHz only, 802.11n). On this Wi-Fi-only tablet Android turns
  Wi-Fi off while the hotspot is on, so the hotspot has no internet to share: it is a local
  network. Wi-Fi comes back when the hotspot is turned off (with the Wi-Fi HAL patch below).
  0031/0032 declare only the sensors the tablet has: an accelerometer, plus Qualcomm's step counter
  computed from it. The stock vendor and the 15.1 tree also claimed light, proximity, compass,
  gyroscope and step detector sensors, so apps looked for sensors that are not there (stage A2
  item 16 parks those files; `ags_w09_unavailable_sensors.xml` takes back the compass that
  `handheld_core_hardware.xml` declares for every handheld). Adaptive brightness was already off.
- **Wi-Fi country** (reported on XDA for 15.1: routers rejected because no country code was set):
  a Wi-Fi-only tablet has no telephony to set one and LineageOS no EMUI region config, so prima
  stayed on the world domain (5 GHz and channels 12–13 passive-scan only). Stage A2 now enables
  802.11d in the driver's config (`WCNSS_qcom_cfg_ags.ini`, Qualcomm's default): the country comes
  from the access point's beacon.
- **Frameworks:** `frameworks/*.patch` (the 15.1 ones apply where still needed). Android 10 ones:
  - `system_core-sdcard-fuse-fallback.patch` — Android 10 dropped the FUSE sdcard daemon and needs
    AOSP sdcardfs or esdfs; this kernel's sdcardfs is the older Samsung one (as on stock EMUI and
    15.1, storage runs over FUSE). Oreo's FUSE code, plus Q's 4th `full` view, forking for vold.
  - `av-swcodec-ldconfig-legacy-sphal.patch` — the software codecs' APEX could not load the vendor
    gralloc mapper on a non-VNDK build (`gralloc-mapper is missing`, VP9 crashed the player).
  - `SetupWizard-no-emergency-call-without-voice.patch` — no "Emergency call" on a Wi-Fi tablet.
  - `lineage-sdk-lockscreen-rotation-default.patch` — overlayable "Rotate lock screen" default
    (15.1 needed a manual toggle, fix 41).
  - `SystemUI-wallpaper-redraw-on-rotation.patch` — the image wallpaper redraws after a rotation, so
    its buffer stays pre-rotated (the Adreno driver pre-rotates from the transform hint). A stale
    buffer made the MDP rotator run every frame; the rotator borrows the only DMA pipe, and four
    home-screen layers then no longer fit the 3 remaining pipes: SurfaceFlinger GPU-composed the
    notification shade (~320 dropped display frames per 8 pulls, now 0).
  - `vendor_qcom_power-explicit-touch-boost.patch` — touch and app-launch boosts. Huawei's perfd
    client library has no `perf_hint()`, so the power HAL's boosts were silent no-ops (also on 15.1)
    and drags started at the lowest CPU clock. The HAL now takes an explicit single-cluster perf
    lock while the finger moves: CPU at 1.4 GHz, GPU top level, and the HMP scheduler boost (the
    UI thread was waiting for a CPU while another core idled). Shade drags went from 49% to 14%
    janky frames; the scheduler boost then cut late render frames from 29–55 to 9–10 per five
    pulls. Installed on the vendor partition by stage A2 (below).
  - `SystemUI-qs-tile-logging-background.patch` — every quick-settings expansion wrote one usage
    log entry per tile (event log + statsd socket) on the UI thread, about a quarter of its CPU
    time in the first frames of a shade pull; the writes now run on SystemUI's background thread.
  - `Snap-tablet-shutter-offset.patch` — Snap's tablet (sw600dp) shutter margin put half the shutter
    off screen; the 15.1 fix used the phone value, which left it 23 px out of line with the
    mode-switch icon and thumbnail. Now on their row (within 1–4 px). Snap stays portrait-locked
    (its own manifest; the controls turn to the side when the tablet is held in landscape).
  - `hardware_interfaces-bluetooth-fw-cfg-deadlock.patch` — the Bluetooth HAL called back into
    Qualcomm's `libbt-vendor` from inside its firmware-configured callback; that library holds a
    lock across the callback, so the HAL deadlocked and Bluetooth stopped after 3 s ("Bluetooth
    keeps stopping"). Low power mode setup now waits until the library call has returned.
  - `hardware_interfaces-wifi-legacy-hal-stop-timeout.patch` — Wi-Fi stayed off after the hotspot
    was turned off. The prima driver drops its `p2p0` interface in hotspot mode and only a driver
    restart brings it back, but Android 10's Wi-Fi HAL skips that restart when Qualcomm's library
    takes longer than 100 ms to stop (75–115 ms on this tablet); `wpa_supplicant` then could not
    open `p2p0`. Huawei's stock HAL does not wait at all and always restarts the driver; the HAL
    now waits up to 1 s, so the restart always follows. Installed with the HAL by stage A2.
  - `Recorder-last-item-refresh.patch` — after a first recording (or after deleting the last
    one) the play icon did not appear until Recorder was reopened: the app saves the last item
    after its screen refresh and only refreshed on recording-status changes.
  - `hardware_interfaces-audio-legacy-hal-layout.patch` — `dumpsys media.audio_flinger` (and any
    bug report) crashed the audio HAL and stopped all sound. Android 9 inserted a member in the
    middle of `struct audio_hw_device`; Huawei's Android 8 audio HAL has the old layout, so the
    Android 10 wrapper called the wrong hooks (its `dump` was the HAL's empty `set_master_mute`
    slot; master mute and the audio port hooks were also off by one). The 2.0 wrapper now reads
    such HALs through the Android 8 layout, as Huawei's stock wrapper did. Installed by stage A2.
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
  configstore's Oreo seccomp policy kills it (system_server hang at screen-off); it also installs
  the patched Android 10 power HAL under the 15.1 binary name.
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
| 1. First boot to adb (Android 10 init, first-stage mount, permissive at first) | done: boots unassisted in ~40 s, setup wizard, launcher |
| 2. Vendor ABI audit (Oreo vendor blobs against Android 10 system libs) | boot blockers fixed (stage A2); 75 non-boot blobs left |
| 3. Hardware bring-up: display/GPU, touch, WiFi, sensors, audio, video, camera, charging | in progress: display, touch, sensors/auto-rotate, charging, Wi-Fi (factory MAC + calibration), storage, audio (speaker, mic recording, agassi ACDB), video (HW H.264/HEVC/VP8; SW VP9 up to 1080p30 — 1080p60 VP9 is beyond software decode on 4×A53, as there is no VP9 hardware), camera (rear 5 MP + front: preview, photo, 1080p video with sound) OK; notification shade at 60 fps over the launcher; LiveDisplay adaptive backlight (panel CABC); USB modes: File transfer (MTP, checked both ways), PTP, MIDI and the USB tethering adapter (device series 0026); Bluetooth on with the factory address, discoverable and scanning (0027 + the HAL patch); Bluetooth headphones: music (A2DP) and hands-free connect without crashes (0028); GPU features as the Adreno 308 really has them: OpenGL ES 3.0, no Vulkan (0029); Wi-Fi hotspot (0030 + the Wi-Fi HAL stop patch; PC client at 38 Mbit/s, Wi-Fi returns after it); USB and Bluetooth tethering share the Wi-Fi internet (kernel: IPv6 rpfilter, conntrack template fix); 3.5 mm headset: music, headset-with-mic detection, play/pause and volume buttons |
| 4. SELinux enforcing | done: enforcing boot with 0 denials; Wi-Fi, audio play/record, both cameras (photo + 1080p video), sensors, HW video, browser and apps pass with 0 denials (device series 0022/0023) |
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
