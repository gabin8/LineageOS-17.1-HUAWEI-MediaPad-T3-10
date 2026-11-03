#!/bin/sh
# Apply the lineage-17.1 device tree on top of the 15.1 v2 state.
#   apply.sh <android_device_huawei_ags_w09 checkout at the 15.1 v2 state>
# (15.1 v2 state = clienthax lineage-15.1 + ../device-tree.patch + this repo's device files, see README).
# Patch 0006 drops the QCamera2 source HAL; its 120k deleted lines are left out of the patch and the
# directory is removed here instead.
set -e
D=$(cd "$(dirname "$0")" && pwd)
cd "${1:?device tree}"
for p in $(cat "$D/series"); do
    git am -q "$D/$p"
    case $p in 0006-*) git rm -r -q camera && git commit -q --amend --no-edit ;; esac
done
git log --oneline -1
