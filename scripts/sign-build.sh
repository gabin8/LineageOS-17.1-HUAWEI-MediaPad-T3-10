#!/usr/bin/env bash
# Sign a LineageOS target-files package with your own release keys and build the images.
#   usage: sign-build.sh <lineage source root> [keys dir, default ~/.android-certs]
# Keys: releasekey, platform, shared, media, networkstack (.pk8 + .x509.pem) made once with AOSP's
#   development/tools/make_key <name> '/C=../O=../CN=..'   (keep them OUT of any git repo, back them up)
#   networkstack is new in Android 10 (NetworkStack, NetworkPermissionConfig, CaptivePortalLogin);
#   `-d` maps it, so signing fails without it. Do not reuse another key for it: its apps hold
#   signature permissions that every app signed with that key would then get too.
# The keys are mounted read-only and copied into a RAM-only tmpfs inside the container (the signer
# chmods its inputs), so no copy ever touches the disk. Output: <root>/out/signed/.
set -euo pipefail
ROOT=$(realpath "${1:?lineage root}"); KEYS=$(realpath "${2:-$HOME/.android-certs}")
for k in releasekey platform shared media networkstack; do [ -f "$KEYS/$k.pk8" ] && [ -f "$KEYS/$k.x509.pem" ] || { echo "missing $KEYS/$k.*" >&2; exit 1; }; done
podman run --rm --userns=keep-id -v "$ROOT:/src" -v "$KEYS:/keys:ro" \
    --mount type=tmpfs,destination=/rkeys,tmpfs-mode=1777 localhost/los15-build:latest bash -lc '
set -e; umask 077; mkdir /rkeys/k && cp /keys/*.pk8 /keys/*.x509.pem /rkeys/k/
cd /src && source build/envsetup.sh >/dev/null 2>&1
# Android 10 lunch runs commands that return non-zero internally: keep errexit off inside it
lunch lineage_ags_w09-userdebug >/dev/null 2>&1 || { echo "lunch failed" >&2; exit 1; }
TF=$(ls -t out/target/product/ags_w09/obj/PACKAGING/target_files_intermediates/lineage_ags_w09-target_files-*.zip | head -1)
mkdir -p out/signed && rm -f out/signed/signed-*.zip
./build/tools/releasetools/sign_target_files_apks -o -d /rkeys/k "$TF" out/signed/signed-target_files.zip > out/signed/sign.log 2>&1
./build/tools/releasetools/img_from_target_files out/signed/signed-target_files.zip out/signed/signed-img.zip
ls -la out/signed/'
