#!/bin/bash
# Pick/boot an iPhone simulator and pre-grant microphone + speech-recognition permissions.
#   eval "$(Tools/AppLab/sim_prepare.sh "iPhone 17" 26.5 Blind-Chess.Blind-Chess)"   -> exports UDID
# Microphone: `simctl privacy grant microphone` (supported service).
# Speech recognition: not a simctl privacy service, so we copy the microphone row of the
# simulator's TCC.db to kTCCServiceSpeechRecognition (schema-agnostic SQL).
set -euo pipefail
NAME="${1:-iPhone 17}"; OS="${2:-26.5}"; BUNDLE="${3:-Blind-Chess.Blind-Chess}"
RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-${OS//./-}"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]; rt,name=sys.argv[1],sys.argv[2]
m=[x["udid"] for x in d.get(rt,[]) if x["name"]==name]
print(m[0] if m else "")' "$RUNTIME" "$NAME")
[[ -n "$UDID" ]] || UDID=$(xcrun simctl create "applab-$NAME" "$NAME" "$RUNTIME")
xcrun simctl boot "$UDID" >&2 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b >&2
xcrun simctl privacy "$UDID" grant microphone "$BUNDLE" >&2 || echo "mic grant failed" >&2
DB="$HOME/Library/Developer/CoreSimulator/Devices/$UDID/data/Library/TCC/TCC.db"
if [[ -f "$DB" ]]; then
  sqlite3 "$DB" "CREATE TEMP TABLE t AS SELECT * FROM access WHERE service='kTCCServiceMicrophone' AND client='$BUNDLE';
                 UPDATE t SET service='kTCCServiceSpeechRecognition';
                 INSERT OR REPLACE INTO access SELECT * FROM t;" >&2 || echo "speech TCC insert failed" >&2
  echo "TCC rows for $BUNDLE:" >&2
  sqlite3 "$DB" "SELECT service, client, auth_value FROM access WHERE client='$BUNDLE';" >&2 || true
  xcrun simctl spawn "$UDID" launchctl kill TERM system/com.apple.tccd >&2 2>/dev/null || true
else
  echo "no simulator TCC.db at $DB" >&2
fi
echo "export UDID=$UDID"
