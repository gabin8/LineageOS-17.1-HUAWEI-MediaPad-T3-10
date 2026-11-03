#!/usr/bin/env bash
# Package a signed boot.img for the AGS-W09 engineering aboot.
#   usage: STOCK_BOOT=<stock boot.bin> make_signed_boot.sh <kernelblob> <ramdisk> <out.img> "<cmdline>"
# kernelblob = Image.gz + ONE appended DTB whose qcom,board-id = 0x1000b (so the eng
# aboot's libfdt selector picks it) and msm-id triple 0x12f/0x134/0x135.
# Appends the GENUINE stock /boot signature at the image's image_actual so the locked
# eng aboot authenticates (RSA fails -> orange -> boots). Pads to the 80 MiB boot part.
set -euo pipefail
KBLOB="${1:?kernelblob}"; RD="${2:?ramdisk}"; OUT="${3:?out.img}"
CMDLINE="${4:-androidboot.hardware=qcom androidboot.selinux=permissive console=tty0 earlycon ignore_loglevel}"
STOCK="${STOCK_BOOT:?set STOCK_BOOT to your dump of the stock boot partition}"
MKBOOT=$(command -v mkbootimg || echo /usr/bin/mkbootimg)

"$MKBOOT" --kernel "$KBLOB" --ramdisk "$RD" \
  --base 0x80000000 --kernel_offset 0x00080000 --ramdisk_offset 0x03600000 \
  --tags_offset 0x03400000 --pagesize 2048 --cmdline "$CMDLINE" \
  -o "$OUT.unsigned"

python3 -I - "$OUT.unsigned" "$STOCK" "$OUT" <<'PY'
import struct,sys
rup=lambda x,p:(x+p-1)//p*p
img=open(sys.argv[1],'rb').read()
ks,ka,rs,ra,ss,sa,ta,ps,dt=struct.unpack_from('<9I',img,8)
ia=ps+rup(ks,ps)+rup(rs,ps)+rup(ss,ps)+rup(dt,ps)
st=open(sys.argv[2],'rb'); st.seek(0x360c000); sig=st.read(0x528)
assert sig[0]==0x30 and b'/boot' in sig, "genuine /boot signature not found in stock boot.bin"
out=bytearray(img)
if len(out)<ia: out+=b'\0'*(ia-len(out))
out=out[:ia]                     # trim to exactly image_actual
out+=sig+b'\0'*(0x800-len(sig))  # genuine sig, pad sig region to 2048
TARGET=83886080
assert len(out)<=TARGET, "image exceeds 80 MiB: %d"%len(out)
out+=b'\0'*(TARGET-len(out))
open(sys.argv[3],'wb').write(out)
print("signed boot: kernel=%d ramdisk=%d image_actual=0x%x total=%d"%(ks,rs,ia,len(out)))
PY
rm -f "$OUT.unsigned"
sha256sum "$OUT"
