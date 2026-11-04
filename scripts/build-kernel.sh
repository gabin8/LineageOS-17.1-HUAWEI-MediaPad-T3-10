#!/usr/bin/env bash
# Build the AGS-W09 kernel blob (Image.gz + the board-id-patched AGS-W09 DTB with ramoops) in
# the build container, with the tree's own aarch64 GCC 4.9.
#   usage: build-kernel.sh <lineage tree> <out dir>
#   output: <out dir>/kernel_blob   (input for make_signed_boot.sh)
# The source is mounted at /src/kernel and the builder identity and timestamp are fixed, so no
# host paths, user or host names end up in the binary (__FILE__ strings, version banner).
set -euo pipefail
TREE=$(realpath "${1:?lineage tree}"); OUT=$(realpath -m "${2:?out dir}")
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=${BUILD_IMAGE:-localhost/los15-build}
STAMP=${KBUILD_BUILD_TIMESTAMP:-$(LC_ALL=C date -u '+%a %b %-d 12:00:00 UTC %Y')}  # C locale: no host language in the banner
# The repo checkout's .git points outside the mounted source, so pass the commit in.
K="$TREE/kernel/huawei/ags_w09"
LV=-g$(git -C "$K" rev-parse --short=8 HEAD)
git -C "$K" diff-index --quiet HEAD -- || LV=$LV-dirty
mkdir -p "$OUT"
podman run --rm --userns=keep-id \
  -v "$TREE/kernel/huawei/ags_w09":/src/kernel \
  -v "$TREE/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9":/src/gcc:ro \
  -v "$OUT":/src/out \
  -e KBUILD_BUILD_USER=builder -e KBUILD_BUILD_HOST=lineageos -e KBUILD_BUILD_TIMESTAMP="$STAMP" -e LOCALVERSION="$LV" \
  "$IMAGE" bash -c '
    set -e; cd /src/kernel
    make O=/src/out ARCH=arm64 merge_msm8937_64_defconfig
    make O=/src/out ARCH=arm64 CROSS_COMPILE=/src/gcc/bin/aarch64-linux-android- \
      HOSTCFLAGS="-O2 -fcommon -Wno-error" -j"$(nproc)" Image.gz-dtb'
python3 -I "$HERE/patch_dtb.py" "$OUT/arch/arm64/boot/dts/qcom/huawei_msm8917_ags_w09_va.dtb" \
  "$OUT/ags_w09.dtb" --ramoops
cat "$OUT/arch/arm64/boot/Image.gz" "$OUT/ags_w09.dtb" > "$OUT/kernel_blob"
strings "$OUT/vmlinux" | awk '/^Linux version/ && !f {print; f=1}'
sha256sum "$OUT/kernel_blob"
