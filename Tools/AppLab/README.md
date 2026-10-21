# AppLab: iOS Simulator lab for Blind Chess

CI: `.github/workflows/ios-app.yml` (runs on `macos-26`, Xcode 26.6, iPhone 17 / iOS 26.5 simulator).
Triggered by pushes touching the project, `Blind ChessUITests/`, `Tools/AppLab/` or the workflow, or manually
(`workflow_dispatch` with `phrases` = `"pawn to e4|knight to f3|h8"`). Everything lands in the artifact
`ios-app-lab-<run id>` (`lab-out/`): `screens/*.png`, `launch.mp4`, `uitests.mp4`, `app_stdout_*.log`,
`sim_log_stream.txt`, `lab/voice/result-*.txt`, `lab/chesscom_web_texts.txt`, `UITests.xcresult.zip`.

## Pieces

| File | What it does |
| --- | --- |
| `setup_audio.sh` | `brew install --cask blackhole-2ch` + `switchaudio-osx`, restarts `coreaudiod`, sets BlackHole 2ch as default input AND output |
| `play_phrase.sh "knight to f3"` | `say -o` a phrase to AIFF and `afplay` it to the default output (or `--file x.wav`) |
| `mic_level.swift` | host check: records the default input and prints peak level (SIGNAL / SILENCE) |
| `sim_prepare.sh NAME OS BUNDLE` | finds/boots the simulator, grants microphone (`simctl privacy`) and speech recognition (copies the TCC row to `kTCCServiceSpeechRecognition`) |
| `voice_driver.sh DIR [secs]` | host half of the voice handshake: speaks each `DIR/voice/req-N.txt`, then writes `done-N` |
| `Blind ChessUITests/` | XCUITests: `SmokeUITests` (launch, alerts, chess.com load, toggles), `VoiceE2EUITests` (taps mic, requests phrases, records every native UI text seen) |
| `Blind Chess/Testing/LabStdoutRedirect.c` | app hook: if env `BLINDCHESS_LOG_FILE` is set, the app's stdout/stderr (print) go to that file |

## Voice E2E recipe (on CI or any Mac)

```bash
bash Tools/AppLab/setup_audio.sh                       # loopback device as default in+out
eval "$(Tools/AppLab/sim_prepare.sh 'iPhone 17' 26.5 Blind-Chess.Blind-Chess)"
xcodebuild build-for-testing -project "Blind Chess.xcodeproj" -scheme "Blind Chess" \
  -destination "generic/platform=iOS Simulator" -derivedDataPath DD CODE_SIGNING_ALLOWED=NO
Tools/AppLab/voice_driver.sh /tmp/lab 900 &
TEST_RUNNER_APPLAB_DIR=/tmp/lab TEST_RUNNER_APPLAB_PHRASES="pawn to e4|knight to f3|h8" \
  xcodebuild test-without-building -xctestrun DD/Build/Products/*.xctestrun -destination "id=$UDID" \
  "-only-testing:Blind ChessUITests/VoiceE2EUITests"
cat /tmp/lab/voice/summary.txt                          # what the app showed for each phrase
```

Handshake: the test writes `voice/req-N.txt` -> host speaks it -> host writes `voice/done-N` -> test samples
the native UI (snapshot, web view excluded) for 5 more seconds -> `voice/result-N.txt` + screenshot.
To write a new scenario, copy `VoiceE2EUITests`, set `APPLAB_PHRASES`, and assert on the texts you expect.

UI lookups prefer accessibility identifiers `micButton`, `inputModeToggle`, `boardVisibilityToggle`
(falling back to label keywords "speak"/"listening", "mode", "board"), so the app should keep those.

See the bottom of this file for findings from actual runs.

## Findings

(filled in from CI runs)
