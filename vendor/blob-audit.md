# Vendor blob audit (AGS-W09, LineageOS 17.1, 2026-11-06)

The vendor partition is Huawei's (EMUI 5/8 era, shared with other Huawei MSM8917/8937 devices), so
it carries a lot that this tablet never uses. This audit asks, for each of the 3,574 ELF files on
`/vendor`: does anything load it, link to it or name it?

## Method

1. **Loaded now**: every `/proc/<pid>/maps` on the running tablet (323 vendor files).
2. **Reachable**: starting from every system/APEX binary, every vendor program an init script
   starts, and every hardware module whose id a binary asks for, follow `NEEDED` links, library
   names inside reachable binaries (`dlopen`), `printf`-style name patterns (`libmmcamera_%s.so`),
   and names in vendor config files. 1,232 files are reachable.
3. **Second pass on the rest**: library names and `System.loadLibrary()` stems in every app and
   framework jar (system, product, vendor dex and APK native code), and names in vendor shell
   scripts and init files.
4. **Camera**: the camera stack loads `camera_config_<product>.xml` (here
   `camera_config_Agassi.xml`, falling back to `camera_config.xml` only if it is missing) and then
   only the sensor, actuator, EEPROM and tuning (chromatix) libraries named for those sensors.
   `camera_config_Agassi.xml` lists four sensor modules, two per camera (alternative suppliers):
   rear `s5k5e8_holitech_8579m_pad` or `gc5035_kingcome_g9m5_pad`, front
   `sp2509v_holitech_sp2565m_pad` or `gc2375h_kingcome_g7p2_pad`. This unit has the s5k5e8 and the
   sp2509v (their libraries are the ones loaded). Everything named for those four, their two
   actuators and the gc5035 EEPROM stays (93 files).
5. **Link check**: each vendor ELF against Android 10's libraries (see the last section for its
   limits).

A file is parked only if it is unused by all of the above **and** nothing that stays on the tablet
links to it or names it (21 files were kept back by that rule).

## Parked: 1,913 files, 124 MB (`park-unused-blobs.txt`, stage A2 item 19)

| What | Files | Notes |
|---|---|---|
| Camera files of other devices' sensors | 1,696 | tuning, sensor driver, actuator and EEPROM libraries for sensors of Atomu, Kobe, London, Moscow, Yangon and Qualcomm reference boards (not in `camera_config_Agassi.xml`). None was loaded. |
| Factory, MMI and diagnostics tests | 65 | Huawei `libhw_diag_*`, `lib_factory_interface`, touch/sensor/display/I²C test libraries, Bluetooth aging tools; their factory apps are not on the tablet. |
| Mobile network, IMS/RCS, data path | 45 | IMS/RCS libraries, `qmuxd`, `ipacm`, `rmnetcli`, `dun-server`, `ATFWD-daemon`, `wdsdaemon`, SIM lock: the Wi-Fi model has no telephony. |
| Clients of unused TrustZone apps | 43 | FIDO, anti-theft, secure UI, keybox, eSE power manager, Trustonic loader and GP TEE client (this tablet uses QSEE). |
| Cannot link on Android 10, unreferenced | 30 | e.g. `lib-imsvt`, `libavenhancements`, `libmm-qdcm`, display/camera HIDL leftovers, a 15.1-era `libshim_camera` and `vendor.lineage.power@1.0`. They could not load anyway. |
| Stock-kernel modules | 24 | `/vendor/lib/modules/*.ko`: test and Huawei debug modules and the WiGig driver, built for Huawei's kernel (version check fails on this one); no script loads them. |
| Already renamed `*.disabled` | 10 | `libsdm-*`, `libdisplay_ext`. |

**Checked on the tablet after parking** (same kernel and system): all 79 init services in the
same state as before, no new library-loading error at boot, rear and front camera open and stream
preview (same frame processing, 0 camera libraries failing to load), Wi-Fi connected and
validated, Bluetooth on, sensors listed, audio HAL, audioserver and media codecs running, modem
online, GPS tracking.

## Kept although nothing refers to them (303 files, 82 MB)

Unused today, but not removed: either the feature has not been tested yet, or a mistake would be
costly and the gain small.

| Group | Files | Size | Notes |
|---|---|---|---|
| Camera features | 79 | 30.7 MB | Qualcomm computer vision (`libscve*`), Huawei algorithms (`libmrc_cg_*`, beauty, best shot, HDR helpers, scene detection), flash and OIS drivers, `mm-qcamera-app`. Snap does not use them; Huawei's camera app did. Candidates after a camera feature test. |
| Graphics | 6 | 28.8 MB | `libllvm-qgl` (Adreno LLVM compiler), `libsc-a2xx` (Adreno 2xx compiler), `libc2d30-a5xx` (Adreno 5xx C2D): not this GPU (Adreno 308), but graphics failures are severe. |
| Casting / streaming | 43 | 5.1 MB | Qualcomm Wi-Fi Display (Miracast) stack and RTP/HTTP streaming. Several cannot link on Android 10; decide after the screen casting test. |
| Plugin directories | 20 | 5.4 MB | Loaded by scanning their directory, not by name: `mediadrm/`, `mediacas/`, `qcdrm/` (Widevine, PlayReady, ClearKey CAS; several cannot link: protected video may not play) and `rfsa/adsp/` (code for the audio DSP, loaded by the DSP). |
| Audio extras | 21 | 2.7 MB | Voice wake-up (`liblisten*`), `audiod`, ALSA/device-arbitration helpers. |
| Debugging tools | 27 | 2.2 MB | `diag_*` loggers, `iw`, `iperf`, `athdiag`, `inotifywait`, ramdump tools. |
| Location extras | 8 | 0.5 MB | Wi-Fi positioning client libraries (`libxt*`, `libizat_client_api`); their daemons are not started. |
| Display extras | 6 | 0.2 MB | HDCP manager, colour converter, Huawei display effect. |
| Hardware modules | 4 | 0.1 MB | FM radio HAL, Huawei I/O flow meter. |
| Other | 89 | 6.2 MB | ebtables and its extensions (an init script names the binary), MDTP crypto (MdtpService is installed), vendor copies of `android.hidl.manager@1.0`/`libminijail`, recovery updater, Qualcomm FastRPC client, and the 21 files kept back because a remaining file still names them. |

49 more files are named by Java code (`System.loadLibrary`) in installed apps or framework jars
(e.g. `libTimeService` for Qualcomm's TimeService, the FIDO and MDTP services) and stay.

## Link problems on Android 10

`scripts/vendor-abi-audit.py` (legacy linker order: system, APEX, then vendor; `audio.primary` with
its ICU shim) finds 142 files still on `/vendor` with missing libraries or symbols: 49 that nothing
refers to (kept, see above: casting, camera features, DRM plugins) and 93 whose name appears
somewhere (25 more were among the parked files). The 93:

- **Oreo builds of system components that EMUI keeps on `/vendor`**: `bootstat`, `debuggerd`,
  `e2fsck`, `gatekeeperd`, `keystore`, `logcat`, `logd`, `netd`, `vold`, `toolbox`,
  `make_ext4fs`, `tzdatacheck`, `libssl`, `libcurl`/`curl`, `libutils`, `libbinderwrapper`,
  `libkeymaster1`, `libkeystore*`, `libext4_utils`, `libbacktrace`, `libpixelflinger`,
  `libstagefright_soft_flacdec`. Android 10 runs its own copies from `/system`; their names occur
  in system code, which is why they count as referenced.
- **Old ICU** (`*_56`): `chargemonitor`, `hs20-osu-client` (Hotspot 2.0 sign-up), `libxml2`,
  `libskia`.
- **Missing libraries**: `libperfhub_client.so` (fingerprint HAL and perfhub: no fingerprint sensor
  on this tablet), `libllvd_smore.so` (camera low-light video denoise, `libmmcamera_llvd`),
  `libtinyxml2_1.so` (`libsdm-color`), `libmmsw_*` (video post-processing `libOmxVpp`/
  `libvpplibrary`), the WFD libraries of `libOmxVideoDSMode`, and two unused Adreno EGL
  sub-drivers. `audio.r_submix.default.so` misses `libnbaio.so`: remote submix carries the audio of
  screen casting and some screen recorders, so check it with the casting test.
- **protobuf**: `libcne`, `libcneapiclient`, `libsettings`, `libkeystore_binder` and the legacy
  `bluetooth.default.so` module (Bluetooth runs on the Android 10 `bluetooth@1.0` HAL).
- **Not used here**: `rild`/`libreference-ril` (telephony), `slim_daemon`, secure display
  (`lib-sec-disp`), MMI (`libmmi`), touch HBTP (`libhbtpfrmwk`), `fingerprint.qcom`, WFD helpers,
  and `libgnss`, the 15.1 source-built GNSS stack that the GNSS service does not load (it uses
  `gps.default.so`).
