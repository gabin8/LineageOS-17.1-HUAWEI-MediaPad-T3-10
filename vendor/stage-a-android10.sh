#!/usr/bin/env bash
# Stage A (handoff 5): adapt the prebuilt 15.1 v2 vendor partition to an Android 10 system.
#   usage: stage-a-android10.sh <system fingerprint> <vendor selinux dir>
#          (run on the host, device on adb as root, still running 15.1)
# The fingerprint is ro.system.build.fingerprint of the system image being flashed
# (SYSTEM/build.prop of the signed target-files); the selinux dir is VENDOR/etc/selinux/ of the
# same signed target-files.
#
# 1. With first-stage mount, Android 10 init imports /vendor/etc/init/hw/init.qcom.rc (8.1 never
#    did: /vendor was mounted later). The vendor copy starts modem daemons and duplicates the
#    services the init.qcom.rc in the root defines, and it imports the vendor init.target.rc,
#    init.qcom.power.rc and a 1600-line Huawei init.qcom.usb.rc. Move it to init-disabled/ and
#    leave a stub, so boot matches 15.1.
# 2. Build.isBuildConsistent() compares ro.system.build.fingerprint with
#    ro.vendor.build.fingerprint; set the vendor one to the system's (decision 5).
# 3. Android 10 always installs /system/etc/selinux/plat_sepolicy.cil, and init then loads the
#    split policy: /vendor/etc/selinux/precompiled_sepolicy when its sha256 files match the
#    system's, else it compiles plat + vendor CIL. The 15.1 vendor has neither (15.1 used a
#    monolithic /sepolicy in the ramdisk), so init could not load any policy. Add the vendor half
#    of the policy (precompiled_sepolicy, vendor_*_contexts, ...) from the same build. 8.1 reads
#    none of these names, so rolling back to 15.1 is unaffected.
# Undo: flash the vendor image from the pre-17.1 backup.
set -euo pipefail
FP="${1:?system fingerprint}"
SEL="${2:?vendor selinux dir (VENDOR/etc/selinux of the signed target-files)}"
case "$FP" in */*:*/*/*:*/*) ;; *) echo "not a fingerprint: $FP" >&2; exit 1 ;; esac
for f in precompiled_sepolicy precompiled_sepolicy.plat_sepolicy_and_mapping.sha256 \
         plat_sepolicy_vers.txt vendor_file_contexts vendor_property_contexts; do
    [ -s "$SEL/$f" ] || { echo "$SEL/$f missing" >&2; exit 1; }
done
[ "$(adb shell id -u | tr -d '\r')" = 0 ] || { adb root >/dev/null; adb wait-for-device; }
adb shell rm -rf /data/local/tmp/stage-a-selinux
adb push "$SEL" /data/local/tmp/stage-a-selinux >/dev/null
adb shell sh -s -- "$FP" <<'EOF'
set -e
FP="$1"
mount -o rw,remount /vendor
RC=/vendor/etc/init/hw/init.qcom.rc
if ! grep -q 'stage A stub' $RC; then
    mkdir -p /vendor/etc/init-disabled
    cp -p $RC /vendor/etc/init-disabled/hw-init.qcom.rc
    printf '%s\n' '# stage A stub (handoff 5): the AGS-W09 device services live in /init.qcom.rc' \
        '# (system.img root). The EMUI vendor original is /vendor/etc/init-disabled/hw-init.qcom.rc.' > $RC
fi
sed -i "s|^ro.vendor.build.fingerprint=.*|ro.vendor.build.fingerprint=$FP|" /vendor/build.prop
for f in /data/local/tmp/stage-a-selinux/*; do
    cp "$f" /vendor/etc/selinux/
    chmod 644 "/vendor/etc/selinux/${f##*/}"
done
rm -rf /data/local/tmp/stage-a-selinux
restorecon -R $RC /vendor/etc/init-disabled /vendor/build.prop /vendor/etc/selinux
sync
mount -o ro,remount /vendor
grep '^ro.vendor.build.fingerprint=' /vendor/build.prop
head -1 $RC
ls /vendor/etc/selinux | tr '\n' ' '; echo
EOF
