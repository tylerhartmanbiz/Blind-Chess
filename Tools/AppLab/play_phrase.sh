#!/bin/bash
# Speak a phrase (or play an audio file) into the Mac's default OUTPUT device.
# With a loopback driver (BlackHole 2ch) set as default output AND input, the iOS
# Simulator's microphone hears it.
#
#   Tools/AppLab/play_phrase.sh "pawn to e4"            # macOS TTS (say) -> afplay
#   Tools/AppLab/play_phrase.sh --file move.wav         # play a recorded file
#   VOICE=Samantha RATE=170 Tools/AppLab/play_phrase.sh "knight to f3"
set -euo pipefail
tmp="${TMPDIR:-/tmp}/applab_phrase_$$"
if [[ "${1:-}" == "--file" ]]; then
  file="$2"
else
  phrase="$*"
  [[ -n "$phrase" ]] || { echo "usage: $0 \"phrase\" | --file audio.wav" >&2; exit 2; }
  file="$tmp.aiff"
  args=()
  [[ -n "${VOICE:-}" ]] && args+=(-v "$VOICE")
  [[ -n "${RATE:-}" ]] && args+=(-r "$RATE")
  if ! say ${args[@]+"${args[@]}"} -o "$file" "$phrase" 2>/dev/null; then
    say -o "$file" "$phrase"   # fall back to the default voice
  fi
fi
dur=$(afinfo "$file" 2>/dev/null | awk '/estimated duration/ {print $3}')
echo "[play_phrase $(date +%T)] playing '${phrase:-$file}' (${dur:-?}s) on output: $(SwitchAudioSource -c -t output 2>/dev/null || echo default)"
afplay -v "${VOLUME:-1}" "$file"
rm -f "$tmp.aiff"
