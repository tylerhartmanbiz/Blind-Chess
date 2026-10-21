# Blind Chess

An iOS app for playing chess against the computer on chess.com without looking at the board. Say your moves
("knight to f3", "e takes d5", "castle kingside") or tap them on a button pad. The app announces the opponent's
replies, answers questions about the position, and can hide the board completely for blindfold play.

## How it works

```
 microphone ─▶ SpeechRecognizer ─(n-best per utterance)─▶ GameController ◀─ ButtonPad / PromptView
                                                            │   ▲
                       MoveResolver / MoveAnnouncer (core) ◀┘   │ events: move, gameOver, newGame, takeback, state
                                                            │   │
                         Speaker (TTS) ◀── announcements ───┤   │
                                                            ▼   │
                               ChessComBridge ─ callAsyncJavaScript ─▶ chesscom-bridge.js in chess.com's page
```

- **chess.com runs the game.** `ChessWebView` loads [chess.com/play/computer](https://www.chess.com/play/computer)
  and injects [`chesscom-bridge.js`](Blind%20Chess/Resources/chesscom-bridge.js) at document start. The script
  talks to chess.com's own game object: it reports the FEN, the side you play, every move (yours and the bot's),
  takebacks, new games and the result, and plays moves in UCI (`e7e8n`), starts games, resigns and takes back.
  Details: [`Tools/BridgeLab/INTEGRATION.md`](Tools/BridgeLab/INTEGRATION.md).
- **A pure-Swift core understands speech and chess** (`Chess/Core`, `Speech/Core`, Foundation only, also built
  as the SwiftPM package `BlindChessCore`): `Position` (FEN, full legal move generation, SAN/UCI),
  `SpokenMoveParser` (tolerant of recognizer mistakes such as "night", "upon", "H A"), `MoveResolver` (picks
  the one legal move the n-best transcripts describe, or asks which piece, or explains why a move is illegal),
  `MoveAnnouncer` (speakable sentences like "Knight takes E 5, check").
- **`GameController`** (`Blind Chess/GameController.swift`) is the single source of truth for both input modes.
  It mirrors the bridge's state as a `Position`, resolves input, asks follow-up questions (which knight, did you
  mean, promotion piece, resign?, new game colour), plays moves and only reports success once chess.com
  confirms them. When chess.com shows its "Play the bots" setup screen (or reloads mid-game) it starts or
  resumes your game with your remembered colour.
- **`SpeechRecognizer`** (`Speech/`) listens continuously: on-device recognition with chess contextual strings
  and a custom language model when the device supports it (the speech lab's most accurate setup, see
  [`Tools/SpeechLab/REPORT.md`](Tools/SpeechLab/REPORT.md)). Partial results are only displayed; the top 5
  alternatives go to the resolver once the utterance ends (final result or 1 s without change), then a fresh
  request starts. Failed or expired tasks restart automatically. Listening pauses while the app speaks (so it
  does not hear itself), during audio interruptions and in the background.
- **`Speaker`** speaks opponent moves, confirmations, questions, results and errors. With speech turned off the
  text still appears on screen (and VoiceOver users get it as an announcement).

## Using it

- **Voice mode:** tap the microphone once; it keeps listening until you tap again or say "stop listening".
- **Button mode:** pick a piece (or Any), a file and a rank, then Play. Questions show up as buttons in both modes.
- **Board hidden:** the controls take the whole screen, with large shortcuts (last move, whose turn, my pieces,
  read board). The web view keeps running underneath and is hidden from VoiceOver.
- Settings (speech on/off, board visible, input mode, colour) are remembered.

### Voice commands

| Say | Does |
|---|---|
| "e4", "pawn to e4", "knight f3", "bishop takes c6", "e takes d5", "knight b d2", "castle kingside", "a8 queen" | plays the move |
| "the one on b1", "b", "kingside", "knight" | answers a "which piece?" or promotion question |
| "yes" / "no" | answers "Did you mean …?" and "Resign this game?" |
| "white" / "black" / "random" | answers the new-game colour question |
| "new game" | asks for a colour and starts a game (resigning a game in progress) |
| "resign", "undo" / "take back" | resign (after confirmation), take back your last move |
| "repeat", "what was the last move" | repeats the last moves |
| "where is my queen", "where are the black knights" | locates pieces |
| "what's on e4", "read the board", "list my pieces", "whose turn" | describes the position |
| "help", "cancel", "stop listening" | help text, cancel the open question, turn the microphone off |

## Requirements

- Xcode 26, iOS 26.5 (deployment target)
- A device is recommended (microphone; on-device recognition and the custom language model are not available
  in the simulator, which falls back to server recognition)
- Internet access (the game is chess.com)

## Building and testing

```bash
open "Blind Chess.xcodeproj"                     # build and run the "Blind Chess" scheme
swift test                                       # core unit tests (macOS or Linux)
docker run --rm -v "$PWD":/w -w /w swift:6.1-noble swift test   # same, in Docker
```

CI workflows (`.github/workflows/`):

| Workflow | What it covers |
|---|---|
| `core-tests.yml` | `swift test` on macOS, deep perft, and a type-check of the core with the app's compiler settings |
| `ios-app.yml` | builds the app for the iOS Simulator, launch screenshots, `SmokeUITests`, and the **voice end-to-end test**: the host speaks phrases into a BlackHole loopback that the simulator uses as its microphone, against the live chess.com page ([`Tools/AppLab/README.md`](Tools/AppLab/README.md)). Phrases are a `workflow_dispatch` input |
| `bridge-lab.yml` | plays full games on chess.com through the bridge in headless WebKit ([`Tools/BridgeLab/`](Tools/BridgeLab/)) |
| `speech-lab.yml` | measures Apple speech recognition on a synthetic and human chess corpus ([`Tools/SpeechLab/`](Tools/SpeechLab/)) |

## Project structure

- `Blind Chess/` — app: `Blind_ChessApp.swift`, `ContentView.swift` (layout, palette), `GameController.swift`,
  `WebView.swift` (`ChessWebView`), `Views/` (control panel, voice panel, button pad, question view),
  `Support/` (logging, settings keys), `Resources/chesscom-bridge.js`, `Testing/LabStdoutRedirect.c` (lab log hook)
- `Chess/ChessComBridge.swift` — typed calls into the bridge script and typed bridge events
- `Chess/Core/` — `Position`, move generation, SAN/UCI
- `Speech/` — `SpeechRecognizer`, `Speaker`, `ChessLanguageModel`; `Speech/Core/` — parser, resolver, announcer,
  recognition hints
- `Tests/BlindChessCoreTests/` — core unit tests; `Tests/SpeechCorpus/` — real recognizer transcripts
- `Blind ChessUITests/` — smoke and voice end-to-end UI tests; `Tools/` — the app, bridge and speech labs
