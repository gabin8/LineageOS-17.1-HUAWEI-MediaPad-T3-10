#!/usr/bin/env bash
# Stage A2 (handoff 5): make the prebuilt 15.1 v2 vendor partition run under an Android 10 system.
# Run after stage-a-android10.sh, from a RAM-booted root recovery (the 15.1 LineageOS recovery
# ramdisk with adb root works), with the 17.1 build done:
#   usage: stage-a2-android10.sh <lineage-17.1 source root>
# Each item was a boot blocker on the first 17.1 boots (2026-11-03). Undo: flash the vendor backup.
#  1. Swap AOSP HIDL wrappers that 15.1 built against Oreo libs for the Android 10 builds of the
#     same modules (SWAP below, from scripts/vendor-abi-audit.py): sensors, keymaster
#     (+ libkeymaster3device), audio + effects, wifi service + libwifi-hal, omx, minijail helpers.
#     The Oreo ones fail to link (android::base::LogMessage ctor, libkeymaster_staging, HidlUtils).
#  2. vndservicemanager -> the Q one. The Oreo C one rejects every call from Q's libbinder (Q's
#     writeInterfaceToken adds a work-source int32 before the interface name), so display.qservice
#     never registers and the HWC fails to open: no display, surfaceflinger/zygote restart loop.
#  3. Park /vendor/lib{,64}/libnative{loader,bridge}.so (EMUI copies of Oreo system libs). Q moved
#     them into the runtime APEX, and the legacy linker searches /vendor before following its APEX
#     link, so zygote linked the Oreo libnativeloader and died. On 15.1 /system shadowed them.
#  4. configstore@1.0 seccomp policy -> AOSP Q's configstore@1.1-arm64.policy (adds getdents64,
#     getpid, sched_setscheduler). The Oreo policy SIGSYS-killed the service under Q libs, and Q
#     libEGL's eglInitialize waits for ISurfaceFlingerConfigs: system_server hung at the first
#     screen-off, PowerManager blocked, touch looked dead, watchdog restart.
#     libshim_icu58 (device libshims): ICU 58 names for Huawei's audio.primary; the system linker
#     attaches it (TARGET_LD_SHIM_LIBS), the library itself lives on the vendor partition.
#     libshim_hwlog: liblog's logprint API for Huawei's libhwlog (camera daemon could not link).
#  5. Park the 15.1 livedisplay@1.0 sdm service rc (interface dropped in 17.1; cannot link).
#  8. camera.msm8937.so: sendSingleParam() patched to return 0 (Oreo-sized stack Parcel overflow).
#  7. media_codecs_performance.xml: two update entries rewritten to the form Q's parser accepts
#     (else no codecs at all); debug.sf.latch_unsignaled=0 (Q client composition showed garbage).
#  9. Power HAL: the Android 10 one (vendor/qcom/opensource/power + frameworks/
#     vendor_qcom_power-explicit-touch-boost.patch) under the 15.1 binary name, so the 15.1 rc
#     (service power-hal-1-0) runs it. Huawei's perfd client has no perf_hint(): the touch and
#     launch boosts were no-ops; the patched HAL takes explicit single-cluster perf locks (CPU
#     floor, GPU level, HMP sched_boost).
# 10. LiveDisplay: the device's livedisplay@2.0 service (adaptive backlight = the panel's CABC,
#     device series 0024) and its rc. vendor.lineage.livedisplay@2.0.so comes with system.img.
# 11. USB modes: init.ags_w09.usb.rc (device series 0026) in /vendor/etc/init. Android 10's
#     init.usb.rc only knows none/adb/accessory/audio_source for the legacy android_usb gadget, so
#     File transfer (MTP), PTP, USB tethering and MIDI timed out and fell back to adb.
# 12. Bluetooth: the Android 10 bluetooth@1.0 HAL (in SWAP; with frameworks/hardware_interfaces-
#     bluetooth-fw-cfg-deadlock.patch: the vendor libbt-vendor holds its lock across the FW_CFG
#     callback, the stock AOSP HAL re-entered it and deadlocked), init.ags_w09.bt.rc (device series
#     0027: hciattach + bluetooth.status) and the bluetooth_loader label for hci_qcomm_init.
#  6. BRING-UP ONLY: adb on at boot without authorization (LineageOS 17.1 userdebug ships
#     persist.sys.usb.config=none and /data is fresh). Vendor props override prop.default on Q.
#     Remove these two lines from /vendor/default.prop before any release.
set -euo pipefail
ROOT=$(realpath "${1:?lineage-17.1 source root}")
OUT=$ROOT/out/target/product/ags_w09/vendor
POLICY=$ROOT/hardware/interfaces/configstore/1.1/default/seccomp_policy/configstore@1.1-arm64.policy
SWAP="bin/hw/android.hardware.media.omx@1.0-service bin/hw/android.hardware.wifi@1.0-service
bin/vndservicemanager lib/libavservices_minijail_vendor.so lib/libkeymaster3device.so
lib/hw/android.hardware.audio@2.0-impl.so lib/hw/android.hardware.audio.effect@2.0-impl.so
lib/hw/android.hardware.keymaster@3.0-impl.so lib/hw/android.hardware.sensors@1.0-impl.so
lib64/libhwminijail.so lib64/libkeymaster3device.so lib64/libwifi-hal.so
lib64/hw/android.hardware.audio@2.0-impl.so lib64/hw/android.hardware.audio.effect@2.0-impl.so
lib64/hw/android.hardware.keymaster@3.0-impl.so lib64/hw/android.hardware.sensors@1.0-impl.so
lib/libshim_icu58.so lib64/libshim_icu58.so lib/libshim_hwlog.so lib64/libshim_hwlog.so
bin/hw/android.hardware.bluetooth@1.0-service lib/hw/android.hardware.bluetooth@1.0-impl.so
lib64/hw/android.hardware.bluetooth@1.0-impl.so"
S=$(mktemp -d); trap 'rm -rf "${S:?}"' EXIT
for f in $SWAP; do mkdir -p "$S/${f%/*}"; cp "$OUT/$f" "$S/$f"; done
cp "$OUT/bin/hw/android.hardware.power@1.2-service-qti" "$S/bin/hw/android.hardware.power@1.0-service-qti"
LD=vendor.lineage.livedisplay@2.0-service.ags_w09
mkdir -p "$S/etc/init"; cp "$OUT/bin/hw/$LD" "$S/bin/hw/$LD"; cp "$OUT/etc/init/$LD.rc" "$S/etc/init/$LD.rc"
cp "$OUT/etc/init/init.ags_w09.usb.rc" "$OUT/etc/init/init.ags_w09.bt.rc" "$S/etc/init/"
mkdir -p "$S/etc/seccomp_policy"; cp "$POLICY" "$S/etc/seccomp_policy/configstore@1.0.policy"
[ "$(adb shell getprop ro.build.version.release | tr -d '\r')" = 8.1.0 ] && \
    adb shell test -x /sbin/recovery || { echo "not in the 15.1 recovery" >&2; exit 1; }
# The 15.1 recovery has no /dev/block/bootdevice and its fstab maps /vendor to by-name/cust:
# mount the real vendor partition and check the backing device before writing anything.
adb shell sh -s <<'EOF'
set -e
B=/dev/block/platform/soc/7824900.sdhci/by-name
while grep -q ' /vendor ' /proc/mounts; do umount /vendor; done
mkdir -p /vendor
mount -t ext4 -o rw $B/vendor /vendor
[ "$(readlink -f "$(awk '$2=="/vendor"{print $1}' /proc/mounts)")" = "$(readlink -f $B/vendor)" ] \
    || { echo "/vendor is not the vendor partition"; exit 1; }
EOF
# media_codecs_performance.xml: Q's MediaCodecsXmlParser rejects an update="true" entry whose type
# is given as a nested <Type> instead of a type= attribute ("cannot update codec without type
# specified"); the BAD_VALUE empties the whole OMX store and MediaCodecList, so no audio or video
# codec at all (not even Codec2). Rewrite those entries to the attribute form; limits unchanged.
adb pull /vendor/etc/media_codecs_performance.xml "$S/perf.xml" >/dev/null
python3 - "$S/perf.xml" "$S/etc/media_codecs_performance.xml" <<'EOF'
import re, sys
s = open(sys.argv[1]).read()
pat = re.compile(r'<MediaCodec name="([^"]+)" update="true">\s*<Type name="([^"]+)">(.*?)</Type>\s*'
                 r'</MediaCodec>', re.S)
def rep(m):
    lines = ''.join('\n            ' + l.strip() for l in m.group(3).strip().splitlines() if l.strip())
    return f'<MediaCodec name="{m.group(1)}" type="{m.group(2)}" update="true">{lines}\n        </MediaCodec>'
open(sys.argv[2], 'w').write(pat.sub(rep, s))
EOF
rm -f "$S/perf.xml"
# camera.msm8937.so (32-bit, Huawei Oreo HAL): its static copy of qdutils' sendSingleParam() puts two
# android::Parcel on the stack with Oreo's size (52 bytes); Android 10's Parcel is larger, so the
# constructor overran into the stack canary -> "stack corruption detected" -> camera provider abort,
# "Can't connect to the camera". Its only use is setCameraLaunchStatus(), a bandwidth hint to the
# display service, so make it return 0 (movs r0,#0; bx lr). Only the known original is patched.
mkdir -p "$S/lib/hw"
adb pull /vendor/lib/hw/camera.msm8937.so "$S/cam.so" >/dev/null
python3 - "$S/cam.so" "$S/lib/hw/camera.msm8937.so" <<'EOF'
import hashlib, sys
d = bytearray(open(sys.argv[1], 'rb').read())
h = hashlib.sha256(d).hexdigest()
off = 0x60dec                          # vaddr 0x61dec, first PT_LOAD at vaddr 0x1000 / offset 0
if h.startswith('71f5a78f1ec86e96'):
    sys.exit(0)                        # already patched: nothing staged
assert h.startswith('880bf987e491cc50'), 'unknown camera.msm8937.so, not patching'
assert d[off:off + 4] == bytes.fromhex('f0b59db0')
d[off:off + 4] = bytes.fromhex('00207047')
open(sys.argv[2], 'wb').write(d)
EOF
rm -f "$S/cam.so"
adb shell rm -rf /tmp/a2files
adb push "$S" /tmp/a2files >/dev/null
adb shell sh -s <<'EOF'
set -e
cd /tmp/a2files
for f in $(find . -type f | sed 's#^\./##'); do
    d=/vendor/$f
    if [ -e "$d" ]; then
        cat "$f" > "$d"                    # in place: keeps owner, mode, SELinux label
    else
        cp "$f" "$d"; chown root:root "$d"; chmod 644 "$d"; chcon u:object_r:vendor_file:s0 "$d"
        case $f in    # new files: label as the Android 10 vendor policy expects
            bin/hw/vendor.lineage.livedisplay@2.0-service.ags_w09)
                chown root:shell "$d"; chmod 755 "$d"
                chcon u:object_r:hal_lineage_livedisplay_sysfs_exec:s0 "$d" ;;
            etc/init/*.rc) chcon u:object_r:vendor_configs_file:s0 "$d" ;;
        esac
    fi
    [ "$(sha256sum < "$f")" = "$(sha256sum < "$d")" ] || { echo "verify failed: $d"; exit 1; }
    echo "ok $d"
done
chcon u:object_r:bluetooth_loader_exec:s0 /vendor/bin/hci_qcomm_init   # Bluetooth power-up (item 12)
for f in lib/libnativeloader.so lib/libnativebridge.so lib64/libnativeloader.so lib64/libnativebridge.so; do
    mkdir -p /vendor/stage-a-parked/${f%/*}
    [ ! -e /vendor/$f ] || mv /vendor/$f /vendor/stage-a-parked/$f
done
mkdir -p /vendor/etc/init-disabled
W=/vendor/etc/init/android.hardware.wifi@1.0-service.rc   # Q HAL sets wlan0 up itself
grep -q '^    capabilities NET_ADMIN' $W || sed -i 's/^    class hal$/    class hal\n    capabilities NET_ADMIN NET_RAW SYS_MODULE/' $W
R=/vendor/etc/init/vendor.lineage.livedisplay@1.0-service-sdm.rc
[ ! -e $R ] || mv $R /vendor/etc/init-disabled/
# Q client (GPU) composition breaks with SurfaceFlinger latching unsignaled buffers (15.1/stock
# vendor build.prop set 1): volume panel and any GPU-fallback frame showed garbage on screen.
sed -i 's/^debug.sf.latch_unsignaled=1$/debug.sf.latch_unsignaled=0/' /vendor/build.prop
# Wi-Fi country (XDA thread #26): no telephony and no EMUI region config, so nothing sets a country
# code and prima stays on the world domain (5 GHz and channels 12-13 passive-scan only). 802.11d
# lets the driver take the country from the access point's beacon (Qualcomm's default; Huawei had
# turned it off). The driver reads this file (construct_configini_with_ini_type), not the copies.
sed -i 's/^g11dSupportEnabled=0$/g11dSupportEnabled=1/' /vendor/etc/wifi/WCNSS_qcom_cfg_ags.ini
P=/vendor/default.prop
grep -q '^persist.sys.usb.config=adb' $P || printf '%s\n' \
    '# stage A2 bring-up: adb on at boot without authorization (remove before release)' \
    'persist.sys.usb.config=adb' 'ro.adb.secure=0' >> $P
sync; umount /vendor; rm -rf /tmp/a2files
EOF
