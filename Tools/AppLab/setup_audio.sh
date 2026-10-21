#!/bin/bash
# Install a loopback audio device and make it the default input AND output, so that
# audio played on the host reaches the iOS Simulator's microphone.
# Works on GitHub-hosted macOS runners (passwordless sudo). On a dev Mac you can
# instead pick the device in System Settings > Sound (and Simulator > I/O > Audio Input).
set -uo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 HOMEBREW_NO_ENV_HINTS=1
DEVICE="${DEVICE:-BlackHole 2ch}"
if ! command -v SwitchAudioSource >/dev/null; then brew install switchaudio-osx; fi
if ! SwitchAudioSource -a 2>/dev/null | grep -q "$DEVICE"; then
  brew install --cask blackhole-2ch
  # Reload the HAL so the new driver shows up.
  sudo killall -9 coreaudiod 2>/dev/null || sudo launchctl kickstart -k system/com.apple.audio.coreaudiod || true
  for i in $(seq 1 20); do SwitchAudioSource -a 2>/dev/null | grep -q "$DEVICE" && break; sleep 1; done
fi
echo "== audio devices"; SwitchAudioSource -a -f cli 2>/dev/null || SwitchAudioSource -a
SwitchAudioSource -t input  -s "$DEVICE"
SwitchAudioSource -t output -s "$DEVICE"
SwitchAudioSource -t system -s "$DEVICE" || true
echo "default input:  $(SwitchAudioSource -c -t input)"
echo "default output: $(SwitchAudioSource -c -t output)"
# Max out volumes (BlackHole has no hardware volume, ignore errors).
osascript -e 'set volume output volume 100' -e 'set volume input volume 100' 2>/dev/null || true
