#!/bin/bash
# Pre-flash check of a 17.1 system.img (Q: system-as-root layout, the root dir is in the image).
#   verify-system-img.sh <system.img> [device root listing from `adb shell ls -la /`]
# Needs simg2img (export ANDROID_HOST_OUT=<lineage>/out/host/linux-x86) and debugfs (e2fsprogs).
# Reads the image itself (unsparsed, debugfs), not the target-files listing: on 2026-11-03 a
# stale /cache -> /data/cache symlink passed a name-only check and the boot stalled in mount_all.
set -euo pipefail
IMG=${1:?system.img}; REF=${2:-}
[ -z "${ANDROID_HOST_OUT:-}" ] || PATH=$PATH:$ANDROID_HOST_OUT/bin
T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
simg2img "$IMG" "$T/raw.img" 2>/dev/null || cp "$IMG" "$T/raw.img"
# debugfs "ls -l": inode  mode(octal)  (?)  uid gid size date time name
debugfs -R 'ls -l /' "$T/raw.img" 2>/dev/null | awk 'NF>=8 && $NF!="." && $NF!=".." {print $2, $NF}' > "$T/root"
fail=0
for d in cache data dev proc sys system vendor firmware persist mnt apex acct config storage odm oem; do
    m=$(awk -v n="$d" '$2==n {print $1}' "$T/root")
    case "$m" in 40*) ;; *) echo "FAIL: /$d is not a directory (mode '${m:-missing}')"; fail=1;; esac
done
for f in fstab.qcom init.qcom.rc ueventd.qcom.rc init.rc sepolicy file_contexts.bin; do
    m=$(awk -v n="$f" '$2==n {print $1}' "$T/root")
    case "$m" in 100*) ;; *) echo "FAIL: /$f is not a regular file (mode '${m:-missing}')"; fail=1;; esac
done
echo "/cache: mode $(awk '$2=="cache"{print $1}' "$T/root"); $(wc -l < "$T/root") root entries"
if [ -n "$REF" ]; then
    # device listing: "<perms> ... <name> [-> target]"; compare names + type letter (d/l/-)
    awk '$1 ~ /^[dl-]/ {n=$NF; if ($(NF-1)=="->") n=$(NF-2); t=substr($1,1,1); if (n!="." && n!="..") print n, t}' "$REF" | sort > "$T/dev"
    awk '{t="-"; if ($1 ~ /^40/) t="d"; else if ($1 ~ /^120/) t="l"; print $2, t}' "$T/root" | sort > "$T/new"
    echo "root entries that differ from the running image (< device, > new image):"
    diff "$T/dev" "$T/new" || true
fi
[ $fail = 0 ] && echo "system.img root: OK" || { echo "system.img root: NOT OK"; exit 1; }
