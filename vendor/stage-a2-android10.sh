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
#  5. Park the 15.1 livedisplay@1.0 sdm service rc (interface dropped in 17.1; cannot link).
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
lib64/hw/android.hardware.keymaster@3.0-impl.so lib64/hw/android.hardware.sensors@1.0-impl.so"
S=$(mktemp -d); trap 'rm -rf "${S:?}"' EXIT
for f in $SWAP; do mkdir -p "$S/${f%/*}"; cp "$OUT/$f" "$S/$f"; done
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
    fi
    [ "$(sha256sum < "$f")" = "$(sha256sum < "$d")" ] || { echo "verify failed: $d"; exit 1; }
    echo "ok $d"
done
for f in lib/libnativeloader.so lib/libnativebridge.so lib64/libnativeloader.so lib64/libnativebridge.so; do
    mkdir -p /vendor/stage-a-parked/${f%/*}
    [ ! -e /vendor/$f ] || mv /vendor/$f /vendor/stage-a-parked/$f
done
mkdir -p /vendor/etc/init-disabled
R=/vendor/etc/init/vendor.lineage.livedisplay@1.0-service-sdm.rc
[ ! -e $R ] || mv $R /vendor/etc/init-disabled/
P=/vendor/default.prop
grep -q '^persist.sys.usb.config=adb' $P || printf '%s\n' \
    '# stage A2 bring-up: adb on at boot without authorization (remove before release)' \
    'persist.sys.usb.config=adb' 'ro.adb.secure=0' >> $P
sync; umount /vendor; rm -rf /tmp/a2files
EOF
