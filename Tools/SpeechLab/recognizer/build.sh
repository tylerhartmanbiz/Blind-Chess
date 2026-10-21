#!/bin/bash
# Builds the recognizer CLI (Info.plist embedded so TCC accepts it) and a SpeechLab.app wrapper.
# usage: build.sh OUTDIR [macos|iossim]
# Optional feature files that fail to type-check on this SDK are replaced by their *Stub.swift.
set -u
cd "$(dirname "$0")"
OUT=${1:-build}; PLATFORM=${2:-macos}
mkdir -p "$OUT"
if [ "$PLATFORM" = iossim ]; then
  SDKARGS=(-sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -target arm64-apple-ios26.0-simulator)
else
  SDKARGS=()
fi
FLAGS=(-O -parse-as-library -swift-version 5 "${SDKARGS[@]}" -framework Speech -framework AVFoundation)
OPT=(LM Analyzer Reserve)
stubs() { for o in "${OPT[@]}"; do echo "${o}Stub.swift"; done; }
FILES=(main.swift)
for o in "${OPT[@]}"; do
  others=$(for x in "${OPT[@]}"; do [ "$x" != "$o" ] && echo "${x}Stub.swift"; done)
  if xcrun swiftc -typecheck "${FLAGS[@]}" main.swift "$o.swift" $others 2> "$OUT/typecheck-$o.txt"; then
    FILES+=("$o.swift"); echo "feature $o: OK"
  else
    FILES+=("${o}Stub.swift"); echo "feature $o: STUBBED"; head -30 "$OUT/typecheck-$o.txt"
  fi
done
xcrun swiftc "${FLAGS[@]}" "${FILES[@]}" -o "$OUT/speechlab" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist || { echo "BUILD FAILED"; exit 1; }
echo "BUILT_WITH: ${FILES[*]}" | tee "$OUT/built-with.txt"
codesign --force -s - --identifier com.blindchess.speechlab "$OUT/speechlab"
if [ "$PLATFORM" = macos ]; then
  APP="$OUT/SpeechLab.app"; rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
  cp Info.plist "$APP/Contents/Info.plist"; cp "$OUT/speechlab" "$APP/Contents/MacOS/speechlab"
  codesign --force -s - "$APP"
fi
