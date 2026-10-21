#!/bin/bash
# Host side of the voice E2E handshake (see Blind ChessUITests/VoiceE2EUITests.swift).
# Watches $1/voice for req-<n>.txt written by the UI test, speaks each phrase with
# play_phrase.sh, then writes done-<n>. Exits when the test writes "finished" or after
# $2 seconds (default 900). Phrases in $APPLAB_PHRASES ("a|b|c") are pre-rendered first.
#   APPLAB_PHRASES="pawn to e4|h8" Tools/AppLab/voice_driver.sh "$APPLAB_DIR" 900 &
set -uo pipefail
dir="$1/voice"; limit="${2:-900}"; here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir"
end=$(( $(date +%s) + limit ))
IFS='|' read -r -a pre <<< "${APPLAB_PHRASES:-}"
for p in ${pre[@]+"${pre[@]}"}; do "$here/play_phrase.sh" --render-only "$p"; done
echo "[voice_driver $(date +%T)] watching $dir"
while [[ $(date +%s) -lt $end && ! -f "$dir/finished" ]]; do
  for req in "$dir"/req-*.txt; do
    [[ -f "$req" ]] || continue
    n="${req##*/req-}"; n="${n%.txt}"
    [[ -f "$dir/done-$n" ]] && continue
    echo "[voice_driver $(date +%T)] request $n: $(cat "$req")"
    sleep "${PRE_DELAY:-0.5}"
    "$here/play_phrase.sh" "$(cat "$req")" || echo "[voice_driver] play failed for $n"
    date +%s > "$dir/done-$n"
  done
  sleep 0.2
done
echo "[voice_driver $(date +%T)] exiting (finished=$([[ -f $dir/finished ]] && echo yes || echo no))"
