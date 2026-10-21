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
the native UI (snapshot, web view excluded) for APPLAB_SETTLE (default 7) more seconds -> `voice/result-N.txt` + screenshot.
To write a new scenario, copy `VoiceE2EUITests`, set `APPLAB_PHRASES`, and assert on the texts you expect.

UI lookups prefer accessibility identifiers `micButton`, `inputModeToggle`, `boardVisibilityToggle`
(falling back to label keywords "speak"/"listening", "mode", "board"), so the app should keep those.

See the bottom of this file for findings from actual runs.

## Findings (GitHub-hosted runs 39545563001, 39546667438, 39548048665)

- Runner `macos-26` (arm64 VM, macOS 26 build 25G83), Xcode 26.6 (17F113), simulator iPhone 17 / iOS 26.5.
  The deployment target 26.5 is fine there, so it was not lowered. Job time is about 10-14 min: the first boot of
  the simulator (data migration) alone takes about 3 min.
- The build works with `CODE_SIGNING_ALLOWED=NO` after the dangling `Audio` synchronized group was removed.
- The VM already has "Apple Virtual Sound Device" plus "Null Audio Device". `brew install --cask blackhole-2ch`
  works without a reboot: `killall coreaudiod` is enough, though brew says a reboot is needed.
  `mic_level.swift` hears the loopback at about -13 dBFS (SIGNAL).
- Simulator microphone = host default input, so **real voice E2E works**. SFSpeechRecognizer in the simulator
  transcribed TTS audio as "Upon to E4" (pawn to e4), "Night to F3" (knight to f3) and "H8".
  The voice test sees no permission alerts, because both permissions are pre-granted:
  `simctl privacy grant microphone`, and a copied TCC row for `kTCCServiceSpeechRecognition`. The app logs
  "Speech recognition authorized".
- Pitfall: if the app's recognizer gets about 20 s of silence it fails with "Recognition error: Retry" and the
  current app never restarts it. For this reason phrases are pre-rendered and played within about 1 s of each request.
- Pitfall: phrases closer together than the app's 5 s silence reset merge into one transcript
  ("Upon to E4 9 to F3H8"). That is why `APPLAB_SETTLE` defaults to 7 s.
- chess.com loads in the simulator's WKWebView. There was no Cloudflare or bot challenge in 3 of 3 runs. The page
  shows the "Play the bots" setup dialog (Start button), so no game is running unless the bridge starts one.
  The app still printed "Moved to E4 / JS OK: Moving 52 to 54" while the dialog was up.
- Artifacts are on blob storage, which some agent sandboxes cannot reach. In that case read the job log
  (screenshots are printed by `print_screens.sh`) and decode it with `extract_screens.py`.
