#!/system/bin/sh
# +6 dB recording boost for MIC-source recordings on the built-in mic (README item 61).
# Usage (as root): sh apply-recording-boost.sh [--revert]   D=<dir> runs against copies.
D=${D:-/product/etc/acdbdata/agassi}
M=$D/mixer_paths_mtp.xml
A=$D/audio_platform_info.xml
T=${REC_BOOST_TMP:-/data/local/tmp}/rec-boost.$$
case "$D" in /product/*) LIVE=1 ;; *) LIVE=0 ;; esac

finish() {
    chmod 0644 "$M" "$A"
    if [ $LIVE = 1 ]; then
        chown root:root "$M" "$A"
        restorecon "$M" "$A"; sync; mount -o ro,remount /product
        kill $(pidof android.hardware.audio@2.0-service) 2>/dev/null
    fi
}

if [ "$1" = "--revert" ]; then
    [ -f "$M.bak-stock" ] && [ -f "$A.bak-stock" ] || { echo "no stock backups in $D"; exit 1; }
    [ $LIVE = 1 ] && { mount -o rw,remount /product || exit 1; }
    mv "$M.bak-stock" "$M"; mv "$A.bak-stock" "$A"; finish; echo "reverted"; exit 0
fi

grep -q "rec-boost" "$M" "$A" && { echo "already applied"; exit 0; }
grep -q "^</mixer>$" "$M" && grep -q "^</audio_platform_info>$" "$A" || { echo "unexpected file layout"; exit 1; }

insert_before() {
    { while IFS= read -r l || [ -n "$l" ]; do
        [ "$l" = "$2" ] && cat "$3"
        printf '%s\n' "$l"
      done < "$1"; } > "$1.new"
}

mkdir -p $T || exit 1
cat > $T/paths <<'EOF'
    <path name="audio-record rec-boost">
        <path name="audio-record" />
        <ctl name="DEC1 Volume" value="90" />
    </path>
    <path name="low-latency-record rec-boost">
        <path name="low-latency-record" />
        <ctl name="DEC1 Volume" value="90" />
    </path>
    <path name="audio-record-compress rec-boost">
        <path name="audio-record-compress" />
        <ctl name="DEC1 Volume" value="90" />
    </path>
EOF
cat > $T/backends <<'EOF'
    <backend_names>
        <device name="SND_DEVICE_IN_SPEAKER_MIC" backend="rec-boost"/>
        <device name="SND_DEVICE_IN_SPEAKER_STEREO_DMIC" backend="rec-boost"/>
    </backend_names>
EOF

[ $LIVE = 1 ] && { mount -o rw,remount /product || { rm -rf $T; exit 1; }; }
cp -p "$M" "$M.bak-stock"; cp -p "$A" "$A.bak-stock"
insert_before "$M" "</mixer>" $T/paths && insert_before "$A" "</audio_platform_info>" $T/backends &&
    mv "$M.new" "$M" && mv "$A.new" "$A"
rm -rf $T
finish
echo "applied"
