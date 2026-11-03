#!/usr/bin/env bash
# Stage A (handoff 5): adapt the prebuilt 15.1 v2 vendor partition to an Android 10 system.
#   usage: stage-a-android10.sh <system fingerprint>     (run on the host, device on adb as root)
# The fingerprint is ro.system.build.fingerprint of the system image being flashed
# (META/ or SYSTEM/build.prop of the signed target-files).
#
# 1. With first-stage mount, Android 10 init imports /vendor/etc/init/hw/init.qcom.rc (8.1 never
#    did: /vendor was mounted later). The vendor copy starts modem daemons and duplicates the
#    services the boot ramdisk init.qcom.rc defines, and it imports the vendor init.target.rc,
#    init.qcom.power.rc and a 1600-line Huawei init.qcom.usb.rc. Move it to init-disabled/ and
#    leave a stub, so boot matches 15.1.
# 2. Build.isBuildConsistent() compares ro.system.build.fingerprint with
#    ro.vendor.build.fingerprint; set the vendor one to the system's (decision 5).
# Undo: flash the vendor image from the pre-17.1 backup.
set -euo pipefail
FP="${1:?system fingerprint}"
case "$FP" in */*:*/*/*:*/*) ;; *) echo "not a fingerprint: $FP" >&2; exit 1 ;; esac
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { adb root >/dev/null; adb wait-for-device; }
adb shell sh -s -- "$FP" <<'EOF'
set -e
FP="$1"
mount -o rw,remount /vendor
RC=/vendor/etc/init/hw/init.qcom.rc
if ! grep -q 'stage A stub' $RC; then
    mkdir -p /vendor/etc/init-disabled
    cp -p $RC /vendor/etc/init-disabled/hw-init.qcom.rc
    printf '%s\n' '# stage A stub (handoff 5): the AGS-W09 device services live in the boot ramdisk' \
        '# /init.qcom.rc. The EMUI vendor original is /vendor/etc/init-disabled/hw-init.qcom.rc.' > $RC
fi
sed -i "s|^ro.vendor.build.fingerprint=.*|ro.vendor.build.fingerprint=$FP|" /vendor/build.prop
restorecon $RC /vendor/etc/init-disabled/hw-init.qcom.rc /vendor/build.prop
sync
mount -o ro,remount /vendor
grep '^ro.vendor.build.fingerprint=' /vendor/build.prop
head -1 $RC
EOF
