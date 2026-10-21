#!/bin/bash
# Speak a phrase (or play an audio file) into the Mac's default OUTPUT device.
# With a loopback driver (BlackHole 2ch) set as default output AND input, the iOS
# Simulator's microphone hears it.
#
#   Tools/AppLab/play_phrase.sh "pawn to e4"            # macOS TTS (say) -> afplay
#   Tools/AppLab/play_phrase.sh --file move.wav         # play a recorded file
#   Tools/AppLab/play_phrase.sh --render-only "h8"      # just render into the cache
#   VOICE=Samantha RATE=170 Tools/AppLab/play_phrase.sh "knight to f3"
# CACHE_DIR (default $TMPDIR/applab_tts) keeps rendered phrases: `say -o` can take 10-20 s
# on a busy CI VM, and the app's recognizer may give up during that silence.
set -euo pipefail
cache="${CACHE_DIR:-${TMPDIR:-/tmp}/applab_tts}"
mkdir -p "$cache"
render_only=0
if [[ "${1:-}" == "--render-only" ]]; then render_only=1; shift; fi
if [[ "${1:-}" == "--file" ]]; then
  file="$2"; label="$2"
else
  phrase="$*"; label="$phrase"
  [[ -n "$phrase" ]] || { echo "usage: $0 [--render-only] \"phrase\" | --file audio.wav" >&2; exit 2; }
  key=$(printf '%s|%s|%s' "${VOICE:-}" "${RATE:-}" "$phrase" | shasum | cut -c1-16)
  file="$cache/$key.aiff"
  if [[ ! -s "$file" ]]; then
    args=()
    [[ -n "${VOICE:-}" ]] && args+=(-v "$VOICE")
    [[ -n "${RATE:-}" ]] && args+=(-r "$RATE")
    if ! say ${args[@]+"${args[@]}"} -o "$file.tmp.aiff" "$phrase" 2>/dev/null; then
      say -o "$file.tmp.aiff" "$phrase"   # fall back to the default voice
    fi
    mv "$file.tmp.aiff" "$file"
  fi
fi
[[ $render_only == 1 ]] && { echo "[play_phrase] rendered '$label' -> $file"; exit 0; }
dur=$(afinfo "$file" 2>/dev/null | awk '/estimated duration/ {print $3}')
echo "[play_phrase $(date +%T)] playing '$label' (${dur:-?}s) on output: $(SwitchAudioSource -c -t output 2>/dev/null || echo default)"
afplay -v "${VOLUME:-1}" "$file"
