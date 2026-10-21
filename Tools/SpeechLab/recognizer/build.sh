#!/bin/bash
# Builds the recognizer CLI (with embedded Info.plist) and a SpeechLab.app wrapper.
# Tries the full feature set first, then falls back to stubs for code that does not compile on this SDK.
set -u
cd "$(dirname "$0")"
OUT=${1:-build}
mkdir -p "$OUT"
FLAGS=(-O -parse-as-library -swift-version 5 -framework Speech -framework AVFoundation
       -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker Info.plist)
built=""
for combo in "LM.swift Analyzer.swift" "LMStub.swift Analyzer.swift" "LM.swift AnalyzerStub.swift" "LMStub.swift AnalyzerStub.swift"; do
  echo "== trying: main.swift $combo"
  if xcrun swiftc "${FLAGS[@]}" main.swift $combo -o "$OUT/speechlab" 2> "$OUT/build-errors.txt"; then
    built="$combo"; break
  fi
  head -60 "$OUT/build-errors.txt"
done
[ -n "$built" ] || { echo "BUILD FAILED"; exit 1; }
echo "BUILT_WITH: $built" | tee "$OUT/built-with.txt"
APP="$OUT/SpeechLab.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
cp "$OUT/speechlab" "$APP/Contents/MacOS/speechlab"
codesign --force -s - --identifier com.blindchess.speechlab "$OUT/speechlab"
codesign --force -s - "$APP"
codesign -dv "$APP" 2>&1 | head -5
