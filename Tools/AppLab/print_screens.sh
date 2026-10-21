#!/bin/bash
# Print downscaled JPEGs of the lab screenshots as base64 blocks in the job log, so an
# agent that can read job logs but not download artifacts can still look at them.
# Decode with: python3 Tools/AppLab/extract_screens.py <job log> <out dir>
# Usage: print_screens.sh <lab-out dir> [max width px]   (SCREENS="glob ..." to choose)
set -uo pipefail
out="$1"; width="${2:-300}"
tmp="$(mktemp -d)"
shopt -s nullglob
files=( ${SCREENS:-"$out"/screens/simctl_35s.png "$out"/lab/screens/smoke_03_web_32s.png "$out"/lab/screens/toggle_02_input_mode_switched.png "$out"/lab/screens/toggle_03_board_toggled.png "$out"/lab/screens/voice_*.png} )
for f in "${files[@]}"; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f" .png)"
  sips -s format jpeg -s formatOptions 45 -Z "$width" "$f" --out "$tmp/$name.jpg" >/dev/null 2>&1 || continue
  echo "=====APPLAB_JPEG_BEGIN $name====="
  base64 -i "$tmp/$name.jpg" | fold -w 160
  echo "=====APPLAB_JPEG_END====="
done
rm -rf "$tmp"
