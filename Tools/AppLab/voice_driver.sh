#!/bin/bash
# Host side of the voice E2E handshake (see Blind ChessUITests/VoiceE2EUITests.swift).
# Watches $1/voice for req-<n>.txt written by the UI test, speaks each phrase with
# play_phrase.sh, then writes done-<n>. Exits when the test writes "finished" or after
# $2 seconds (default 900).
#   Tools/AppLab/voice_driver.sh "$APPLAB_DIR" 900 &
set -uo pipefail
dir="$1/voice"; limit="${2:-900}"; here="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$dir"
end=$(( $(date +%s) + limit ))
echo "[voice_driver] watching $dir"
while [[ $(date +%s) -lt $end && ! -f "$dir/finished" ]]; do
  for req in "$dir"/req-*.txt; do
    [[ -f "$req" ]] || continue
    n="${req##*/req-}"; n="${n%.txt}"
    [[ -f "$dir/done-$n" ]] && continue
    sleep "${PRE_DELAY:-1.5}"   # let the recognizer settle before speaking
    "$here/play_phrase.sh" "$(cat "$req")" || echo "[voice_driver] play failed for $n"
    date +%s > "$dir/done-$n"
  done
  sleep 0.3
done
echo "[voice_driver] exiting (finished=$([[ -f $dir/finished ]] && echo yes || echo no))"
