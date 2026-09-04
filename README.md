# Blind Chess

An iOS app for playing chess against the computer on chess.com — without looking at the board. Speak your moves out loud like "knight to f3" or "queen takes e5", or use an on-screen button pad, while the board stays hidden. Built for practicing blindfold chess, or just as a "hide the board" mode for anyone who wants to play by move names instead of dragging pieces around.

## How it works

- A hidden `WKWebView` loads [chess.com/play/computer](https://www.chess.com/play/computer) and drives the actual game — chess.com's own engine, board state, and computer opponent are used as-is.
- A small JS bridge ([`Chess/ChessJSBridge.swift`](Chess/ChessJSBridge.swift)) is injected into the page to enlarge the board, scrape the current position/orientation, and programmatically execute moves by simulating drag-and-drop on the DOM.
- A native SwiftUI layer sits on top of (or in place of) that web view and is the only thing you actually interact with:
  - **Voice mode** ([`Speech/SpeechRecognizer.swift`](Speech/SpeechRecognizer.swift), [`Speech/ChessMoveParser.swift`](Speech/ChessMoveParser.swift)) uses Apple's on-device Speech framework to transcribe what you say, then fuzzy-parses it into a piece + destination square (it tolerates a lot of mis-hearings — "knight" → "night"/"nite", "for" → rank 4, NATO alphabet for files, etc.), plus spoken castling ("castle kingside/queenside").
  - **Button mode** lets you tap a piece type, then a file (A–H) and rank (1–8) instead of speaking.
  - Either mode goes through the same move-resolution logic ([`Chess/ChessMoveValidator.swift`](Chess/ChessMoveValidator.swift)): it reads the live board state from chess.com, works out every legal piece that could reach the target square, and if more than one piece qualifies, asks you to disambiguate (by file/rank, spoken or tapped) before committing to a move.
- A toggle in the control bar lets you show or hide the chess board itself at any time:
  - **Board hidden** → true blindfold chess, you track the position in your head and only hear/see move confirmations.
  - **Board visible** → you can still watch the game, but make moves by voice/buttons instead of touch, if you just prefer that.

## Requirements

- Xcode 15+, iOS 16+
- A physical device is recommended (microphone + on-device speech recognition)
- Internet access (the board itself is chess.com, loaded live in-app)

## Getting started

```bash
open "Blind Chess.xcodeproj"
```

Build and run, grant microphone and speech recognition permissions when prompted, then just start talking: "pawn to e4."

## Project structure

- `Blind Chess/Blind_ChessApp.swift` — app entry point
- `Blind Chess/ContentView.swift` — main screen: board window, control bar (mode/TTS/board-visibility toggles), voice mode UI, and button mode UI
- `Blind Chess/WebView.swift` — `WKWebView` wrapper that loads chess.com and injects the JS bridge on load
- `Chess/ChessJSBridge.swift` — JavaScript injected into the chess.com page to resize the board, read board state/orientation, and execute moves
- `Chess/ChessMoveValidator.swift` — parses scraped board state and figures out which piece(s) can legally reach a target square, including disambiguation between multiple candidates
- `Speech/SpeechRecognizer.swift` — on-device speech-to-text using `SFSpeechRecognizer`, with silence detection to reset the transcript
- `Speech/ChessMoveParser.swift` — turns a spoken transcript into a piece/file/rank move, tolerant of common mis-transcriptions and castling phrases
