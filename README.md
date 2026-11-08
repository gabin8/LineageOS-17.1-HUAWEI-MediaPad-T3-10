# LineageOS 17.1 for HUAWEI MediaPad T3 10 (AGS-W09, codename "agassi")

**Status: first test build (2026-11-08).** Wi-Fi, Bluetooth, GPS, audio, both cameras, hardware
video, sensors, USB (including OTG host), microSD and opt-in encryption are tested on the tablet;
there is no FM radio (see the hardware table). This is the Android 10 follow-up to the
[LineageOS 15.1 port](https://github.com/gabin8/LineageOS-15.1-HUAWEI-MediaPad-T3-10).

**Download (test build):** [v17.1-20261108](https://github.com/gabin8/LineageOS-17.1-HUAWEI-MediaPad-T3-10/releases/tag/v17.1-20261108):
one zip with the RAM-boot image, system and vendor images, kernel source and `INSTALL.txt`. Needs
the engineering bootloader; read `INSTALL.txt` first. The boot image is only ever `fastboot boot`ed.

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
  `kernel/modem-board-info-smem-vendor2.patch` does what Huawei's stock bootloader does before
  the modem starts and the engineering bootloader on this tablet does not: it puts the board's
  modem id (from the device tree) and product name in shared memory, where the modem looks up its
  board configuration. Without it the GPS engine ran but never saw a satellite.
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
  0033 boots the modem, which hosts the GNSS engine on MSM8917 even on this Wi-Fi model (Huawei
  lists GPS/GLONASS/BeiDou, without A-GPS on AGS-W09). Neither port had started it, so GPS could
  not work. The stock helpers run again (rmt_storage serves the modem's file system on
  modemst1/2, fsg and fsc; tftp_server), and a small holder keeps the modem up, as stock's pm-proxy
  did: that one crashes on Android 10 (Huawei's Android 8 peripheral-manager client overflows the
  larger binder Parcel). A modem crash restarts the modem alone. The modem reaches ONLINE at boot
  and offers its location service. The location stack already on the vendor partition (Qualcomm's
  `gps.default.so`) drives it; with the kernel's modem board info it tracks GPS, QZSS and SBAS
  satellites (10 indoors within 5 minutes). Outdoors, from a cold start with no assistance data, the
  first fix came after 89 s and held at 1 Hz for the rest of a 20-minute run: up to 39 satellites
  (GPS, GLONASS, BeiDou, SBAS, QZSS), up to 28 used in the fix, reported accuracy 4.6 m.
  Apps get it through Android's location service: in Organic Maps (F-Droid) the first fix came
  14 s after the app asked (warm start), and the position on the map was confirmed correct.
  The satellite counts and fix times come from 0035's bench tool `gnss_probe` (not installed by
  the product; it reports satellites, fix and accuracy but never the position).
  Raw GNSS measurements (Android's GnssMeasurement API, used by tools like GnssLogger) are not
  available: the modem rejects the measurement-report setup with a general failure, which is the
  "Set GNSS constellation failed" line in the log when the GPS service starts. Huawei's stock
  modem firmware (AGS-W09 8.0.0.161) rejects it the same way, and stock's location library sends
  the same request, so stock had no raw measurements on this tablet either.
  XTRA (Qualcomm's satellite orbit predictions, the assistance a Wi-Fi tablet can get) was never
  used: the location stack found its own "XTRA Client 2.0" and therefore turned off the HAL's
  IGnssXtra, but that client only starts inside system_server, where Android 7 ran the HAL. Stage
  A2 item 18 patches one byte in `liblbs_core.so` so the check fails; Android then downloads XTRA
  itself and the HAL injects it (checked: 21,817 bytes from izatcloud.net, all 22 parts accepted
  by the modem). `frameworks/location-gps-debug-xtra-servers.patch` gives Android the servers
  (system image). Android downloads XTRA at every boot once Wi-Fi is up, and on demand; the
  modem's own refresh request still goes to the unused client, so after about a week without a
  reboot the data expires until the next boot.
  Widevine (protected video) is software L3, as on stock: neither the stock EMUI 8 nor the
  original Android 7 vendor image has Qualcomm's `liboemcrypto.so`, the bridge to the hardware
  level. Before stage A2 item 20 it did not work at all, for three reasons. The vendor manifest
  declared a "widevine" DRM service this vendor never had, and Android 10 waits for every
  declared instance, so any app touching DRM hung. Both Widevine engines on hand were built
  against Android 8's protobuf. And the DRM HAL was not allowed into `/data/mediadrm`, where
  pre-Treble Widevine keeps its files (stock's policy allowed it; device 0036). Item 20 drops the
  declaration and installs stock EMUI 8's engine (CDM 5.0.0, 2017) on an Android 8.1 protobuf
  under its own name. Checked end to end in a WebView: provisioning with Google's server, a
  licence from the Shaka demo's proxy, and the encrypted "Angel One" stream (VP9 + AAC) playing.
  Two limits: L3 streaming apps usually cap at SD, and LineageOS 17.1's browser (Jelly) never
  answers the WebView's protected-media permission request, so web pages cannot use Widevine
  there (an app that grants it, as Chrome does, works).
  **No TrustZone keystore or gatekeeper, and no `qseecomd`, on purpose.** For two days this port
  ran them (`qseecomd`, Qualcomm's helper that lets TrustZone apps reach the eMMC's
  replay-protected block, RPMB, plus Huawei's `keystore.msm8937.so`/`gatekeeper.msm8937.so`;
  stage A2 items 21-22, device 0037/0039): keys in TrustZone and a TrustZone-checked PIN worked.
  But this unit runs the *engineering* TrustZone from the engineering bootloader package, and
  its keymaster writes its records into the RPMB area the stock keymaster uses. Measured with a
  read-only RPMB probe (`tools/rpmb_probe` in the device tree: RPMB write counter and contents):
  an engineering bootloader boot and a full Android boot write nothing; one keystore key
  generated, used and deleted wrote 4 RPMB blocks, all in the keymaster record. Afterwards stock
  EMUI 5.1, restored byte-for-byte to every partition from the original backup (retail
  bootloader included, verified boot green), could not get its file-encryption key at any boot
  (`vold: file cryption: failed to get the key` → system_server crash → eRecovery), even after a
  factory reset: the way back to stock was gone, and RPMB cannot be rolled back by any tool.
  Stage A2 item 26 (device 0046) therefore parks `qseecomd`'s rc and the gatekeeper HAL and keeps
  the TrustZone modules set aside: keys use AOSP's software keymaster and the lock screen AOSP's
  software gatekeeper, as in the 15.1 port, with 0 RPMB writes (keystore operations and PIN
  set/verify/clear re-measured). The 15.1 release never ran `qseecomd`; no build with the
  TrustZone keystore was published. On a tablet that did run it, the lock settings sealed by the
  TrustZone gatekeeper must be cleared once (`/data/system_de/0/spblob/*` and the `sp-handle`
  row of `/data/system/locksettings.db`), else no PIN can be set.
  The PIN check could not be tried at first because Android 10 offered no secure lock screen at
  all: the vendor kept Android 8's `handheld_core_hardware.xml`, which lacks
  `android.software.secure_lock_screen`, so Settings had no PIN, pattern or password and
  `locksettings` answered "The device does not support lock screen". Stage A2 item 23 installs
  the build's Android 10 copy.
  **Encryption is off by default**, a deliberate choice for speed (LineageOS asks devices whose
  stock firmware forced encryption, as EMUI 8 did with file-based encryption, to default to it;
  this port does not). Settings → Security → Encryption & credentials → Encrypt tablet is the
  opt-in: vold's full-disk encryption in software (dm-crypt, `aes-cbc-essiv:sha256`, the key
  wrapped with scrypt and the keymaster; tested first with the TrustZone keymaster and again with
  the software one item 26 brings back, which left the RPMB write counter unchanged).
  Like every full-disk encryption it is one-way: only a factory reset makes the tablet
  unencrypted again. It needed four fixes: device 0041 drops
  `TARGET_HW_DISK_ENCRYPTION` (stock Android 7's Qualcomm hardware disk encryption; vold asked for
  a `cryptfshw` HAL this port does not have and refused), and 0042 sets
  `vold.post_fs_data_done` at the end of post-fs-data (AOSP leaves it to the device; without it
  encryption, and every boot of an encrypted tablet, hung on the boot animation); 0048 loads the
  persistent properties a second time after decryption (the boot that encrypts carries on without
  a reboot, and init skipped the one load that counted, so time zone, locale and the Bluetooth
  address were missing and Bluetooth crashed on that boot); 0049 takes Bluetooth's
  `hci_qcomm_init` service out of class `late_start` (encryption's framework restart resets that
  class and left the never-run service marked "stopped", so Bluetooth was reported ready before
  the core was set up and crashed once on every encrypted boot). Checked on this
  tablet: the in-place encryption of a 3.4 GB `/data` took about 2 minutes, the data survived,
  boots unlock it without a PIN, and with "Secure start-up" the PIN is asked before Android
  starts (wrong PIN rejected; this screen stays portrait, the panel's natural orientation). Cost,
  same partition, 256 MB uncached: writes 64 → 61 MB/s with three times the CPU, reads 185 → 60
  MB/s. The first boot after "Encrypt tablet" logs a few one-off SELinux denials (programs
  inheriting vold's handle to the data partition); later boots have none. Without a PIN the
  tablet unlocks itself, so encryption protects little; and since this bootloader starts any
  image over USB, unencrypted data is open to anyone with a cable. File-based encryption, as on
  stock, would cost less on reads (about −24% in a test) but needs a kernel change first: Huawei's
  fscrypt only accepts 32-byte master keys and Android 10's vold uses 64.
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
  - `location-gps-debug-xtra-servers.patch` — Qualcomm's XTRA servers (as in the vendor gps.conf)
    in `gps_debug.conf`, the only GPS configuration a Wi-Fi tablet has on Android 10 (no carrier
    config): without them Android cannot download XTRA for the GNSS HAL.
  - `Recorder-last-item-refresh.patch` — after a first recording (or after deleting the last
    one) the play icon did not appear until Recorder was reopened: the app saves the last item
    after its screen refresh and only refreshed on recording-status changes.
  - `hardware_interfaces-audio-legacy-hal-layout.patch` — `dumpsys media.audio_flinger` (and any
    bug report) crashed the audio HAL and stopped all sound. Android 9 inserted a member in the
    middle of `struct audio_hw_device`; Huawei's Android 8 audio HAL has the old layout, so the
    Android 10 wrapper called the wrong hooks (its `dump` was the HAL's empty `set_master_mute`
    slot; master mute and the audio port hooks were also off by one). The 2.0 wrapper now reads
    such HALs through the Android 8 layout, as Huawei's stock wrapper did. Installed by stage A2.
  - `vendor_qcom_audio-policy-reroute-idle-primary.patch` — with a Bluetooth headset in a call,
    an app that only recorded (no sound playing) got the tablet's built-in microphone. Qualcomm's
    audio policy reroutes only playing outputs when the call audio moves to the headset (AOSP
    reroutes all of them), so the idle primary output stayed on the speaker, and Huawei's audio HAL
    takes the device of its VoIP path from that output while no VoIP playback is open. The
    primary output is now rerouted too: calls record from the headset microphone in every phase.
  - `av-drm-legacy-factory-security-level.patch` — Android 10 only answers "is this DRM scheme
    supported at security level X?" for DRM HALs 1.2 and newer; for this vendor's 1.0 HAL it threw,
    and the WebView, which always asks with a level, treated Widevine as missing (Shaka error
    6001). It now answers like a software (L3) plugin does through 1.2: the software levels only.
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
- [`vendor/blob-audit.md`](vendor/blob-audit.md) — what on `/vendor` is used, what was parked
  (`vendor/park-unused-blobs.txt`, stage A2 item 19) and what is kept although unused, with notes.
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
| 2. Vendor ABI audit (Oreo vendor blobs against Android 10 system libs) | boot blockers fixed (stage A2); full audit in [`vendor/blob-audit.md`](vendor/blob-audit.md): 1,913 unused files parked (124 MB, stage A2 item 19, device 0034), the rest annotated |
| 3. Hardware bring-up: display/GPU, touch, WiFi, sensors, audio, video, camera, charging | in progress: display, touch, sensors/auto-rotate, charging, Wi-Fi (factory MAC + calibration), storage, audio (speaker, mic recording, agassi ACDB), video (HW H.264/HEVC/VP8; SW VP9 up to 1080p30 — 1080p60 VP9 is beyond software decode on 4×A53, as there is no VP9 hardware), camera (rear 5 MP + front: preview, photo, 1080p video with sound) OK; notification shade at 60 fps over the launcher; LiveDisplay adaptive backlight (panel CABC); USB modes: File transfer (MTP, checked both ways), PTP, MIDI and the USB tethering adapter (device series 0026); Bluetooth on with the factory address, discoverable and scanning (0027 + the HAL patch); Bluetooth headphones: music (A2DP) and hands-free connect without crashes (0028); Bluetooth call audio (SCO, as calling apps use it): headset speaker and microphone in both directions, call volume from the tablet keys (policy patch above; the tested headset supports only narrowband HFP 1.5); GPU features as the Adreno 308 really has them: OpenGL ES 3.0, no Vulkan (0029); Wi-Fi hotspot (0030 + the Wi-Fi HAL stop patch; PC client at 38 Mbit/s, Wi-Fi returns after it); USB and Bluetooth tethering share the Wi-Fi internet (kernel: IPv6 rpfilter, conntrack template fix); 3.5 mm headset: music, headset-with-mic detection, play/pause and volume buttons; microSD read/write (FAT32, 20 MB/s read); USB OTG host, with no change needed: a 128 GB exFAT flash drive is detected, checked and mounted, opens in Files and keeps its data across an unmount (about 15 MB/s read and 4 MB/s write on that stick over the USB 2.0 port), wireless mouse and keyboard receivers work (pointer, hover, typing), the tablet powers them from the charger's boost and returns to PC mode and charging when the cable goes back in; keystore and lock screen PIN/pattern/password in software (AOSP keymaster and gatekeeper; the TrustZone ones are off on purpose because the engineering TrustZone's keymaster overwrote stock's RPMB records, stage A2 items 23 and 26); opt-in full-disk encryption from Settings (off by default; device 0041/0042); Widevine L3 protected video (stage A2 item 20 + device 0036 + the av patch; checked with a Widevine-encrypted stream in a WebView); GPS: outdoor fix in 89 s from a cold start, GPS + GLONASS + BeiDou, 4.6 m, position confirmed in a map app (0033 + kernel patch 13; no raw GNSS measurements, as on stock); no IR blaster declared any more (the tree's first template shipped the consumer IR HAL and feature; stage A2 item 24, device 0044); clean shutdown: the light HAL stays up for init's blank_screen, which used to abort with DEAD_OBJECT (0045); a quiet kernel log: the touch controller's empty read after each once-a-second ESD watchdog ping (stock's own setup) is no longer logged as an error (kernel patch 14) |
| 4. SELinux enforcing | done: enforcing boot with 0 denials (device 0038 quiets SystemUI's harmless lookup of the Bluetooth app's data folder when it draws that app's notifications, 0040 vold's daily fstrim of `/persist`); Wi-Fi, audio play/record, both cameras (photo + 1080p video), sensors, HW video, browser and apps pass with 0 denials (device series 0022/0023) |
| 5. Reproducible vendor + release | open: booting without a PC (today the system is RAM-booted from fastboot, and anything that restarts the tablet itself, such as "Encrypt tablet", lands in download mode until it is RAM-booted again); a recovery that can be installed (LineageOS 17.1 Recovery from this build works RAM-booted with `fastboot boot`: menu, adb, partition table and, with device 0043, the `misc` command block; the stage scripts still expect the 15.1 one); the bring-up adb settings out of the vendor; the vendor rebuilt reproducibly. Known gaps: no FM radio (the WCN3660B's FM core powers up, calibrates and tunes, but reports no signal on any channel on this board, also with Huawei's own stock FM module, a headset on either antenna setting and the 2020 WCNSS firmware; device 0050 leaves FMRadio out, and the bring-up is kept on the `fm-radio` branch until stock's handling of FM is understood); Wi-Fi always uses the factory MAC (Android's per-network private MAC is not applied: `config_wifi_connected_mac_randomization_supported` is off, as on AOSP; the Wi-Fi HAL built from this tree already offers `setMacAddress` (it serves IWifi 1.3 although the vendor manifest declares 1.1), but turning it on needs a prima change first: prima gives the firmware its MAC only when the station session is opened, so changing wlan0's address later doesn't reach the air; scans send the random-MAC OUI request, `gEnableMacAddrSpoof=1`); file-based encryption needs the fscrypt key-size change |

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
