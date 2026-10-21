# Integrating `chesscom-bridge.js` into the app

The bridge replaces `Chess/ChessJSBridge.swift` (DOM class scraping + simulated taps). It talks to the
game object chess.com attaches to its board element (`document.querySelector('wc-chess-board').game`), so
moves, the FEN, whose turn it is, the move list and the result all come from chess.com's own state.
It was tested live on chess.com/play/computer as a guest (WebKit + iPhone 13 emulation). See `Tools/BridgeLab/`
and the `bridge-lab` workflow.

## 1. Ship the file

`Blind Chess/Resources/chesscom-bridge.js` is inside the file-system-synchronized `Blind Chess` group, so
Xcode copies it into the app bundle (Copy Bundle Resources). Check that it shows up under the target's
Build Phases. Load it once:

```swift
let bridgeJS = try! String(contentsOf: Bundle.main.url(forResource: "chesscom-bridge", withExtension: "js")!, encoding: .utf8)
```

## 2. Inject it (WebView.makeUIView)

```swift
let ucc = config.userContentController
ucc.addUserScript(WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
ucc.add(WeakScriptHandler(context.coordinator), name: "blindChess")   // page content world (the default)
```

- Use the **page** content world, which is the default for `WKUserScript` and `add(_:name:)`. `element.game` is
  a JS property set by chess.com's scripts, so an isolated `WKContentWorld` cannot see it.
- `.atDocumentStart` is fine because the bridge waits for the board to appear (tested). Injecting again with
  `evaluateJavaScript(bridgeJS)` in `didFinish` is also safe: a second injection is a no-op that returns
  `"BlindChess:already"`. The bridge keeps working across chess.com's in-page navigation (setup screen, game,
  game over, New Bot, Rematch) and re-attaches when the board element is replaced.
- Remove the old `ChessJSBridge.injectionScript()` CSS that forces the board to 98vw. chess.com sizes the board
  itself (384px on a 390pt-wide iPhone 13), and forcing the size can misplace taps. The bridge adds its own small
  stylesheet that only hides ads and banners.
- Keep the default WKWebView user agent. Do not set a desktop or "bot-like" UA (see bot detection below).
- `WeakScriptHandler` is a tiny `NSObject, WKScriptMessageHandler` that holds the coordinator weakly, which
  avoids the WKUserContentController retain cycle.

## 3. Calling it

Use `callAsyncJavaScript`, which takes arguments, so you never build JS strings by hand. It returns
`[String: Any]`:

```swift
webView.callAsyncJavaScript("return window.BlindChess ? BlindChess.move(uci) : {ok:false, error:'no-bridge'}",
                            arguments: ["uci": "e7e8n"], in: nil, in: .page) { result in ... }
webView.callAsyncJavaScript("return BlindChess.state()", arguments: [:], in: nil, in: .page) { ... }
```

| Call | Returns (synchronously) |
|---|---|
| `state()` | `{ok, api, phase:'setup'|'playing'|'over', fen, playingAs:'w'|'b', turn:'w'|'b', sanHistory:[...], ply, lastMove:{from,to,san,uci,by}, gameOver:{result:'1-0'|'0-1'|'1/2-1/2', reason, winner:'w'|'b'|'draw', userWon}|null, inCheck, mode}` |
| `move(uci)` | `{ok:true, uci, san, fen, promotion, autoQueen}` or `{ok:false, error}` where `error` is `bad-uci`, `illegal`, `not-your-turn`, `not-playing`, `game-over`, or `rejected` |
| `legalMoves()` | `["e2e4", ..., "e7e8q","e7e8r","e7e8b","e7e8n"]` (UCI, chess.com's own move generator) |
| `startNewGame({color:'white'|'black'|'random', bot?:'Martinfoot', rematch?:bool})` | `{ok, pending}`; completion arrives as events (`newGame`/`state`; `setupFailed` on error) |
| `resign()` / `takeback()` | `{ok, pending}`; they press chess.com's Resign (and its confirmation) or Undo buttons |
| `hint()` | `{ok, pending}`; then a `hint` event (see below) |
| `closeModal()` | `true` if it closed the onboarding or game-over modal |
| `events` / `eventsSince(seq)` | in-page event log (last 1000), for debugging and tests |

- `move()` is synchronous and validated against chess.com's legal moves. The move counts only if chess.com's
  history actually grew by one ply. Two calls in a row cannot both play: the second returns `not-your-turn`.
- **Promotion:** pass the piece letter (`e7e8q`, `e7e8n`, ...). If it is missing, the bridge promotes to a queen
  and returns `autoQueen:true`. The app should ask for the piece instead ("pawn to e8, promote to knight").
  Moves made through the game API never open chess.com's promotion picker. This was tested with all four pieces.
- Castling is the king's move (`e1g1`, `e1c1`, `e8g8`, `e8c8`). En passant is the pawn's diagonal move.
- `move(uci, {forceDom:true})` uses the synthetic-pointer fallback instead (also used automatically if the
  game API is ever missing). It returns `{ok:true, pending:true}`. Confirm it through the `move` event.

## 4. Events (`message.body` is a dictionary; switch on `type`)

| type | fields |
|---|---|
| `move` | `ply, san, uci, from, to, fen, color, by:'user'|'opponent', check, mate`. Sent exactly once per ply, including your own moves. A move made through the website also counts. |
| `gameOver` | `result, reason ('checkmate'|'stalemate'|'resignation'|'insufficient material'|'threefold repetition'|'50-move rule'|...), winner, userWon, fen, sanHistory`. Sent once per game, up to about 2.5 s late while chess.com publishes the reason. |
| `newGame` | `playingAs, fen`: history reset (Rematch / New Bot / Play) |
| `takeback` | `ply, fen, sanHistory`: one event per removed ply (Undo in a bot game removes 2) |
| `state` | `state` (same shape as `state()`), sent when phase, FEN, side or ply changes |
| `hint` | `uci` + `from`/`to` if an arrow is shown; otherwise `square` + `note:'piece-highlight-only'`. chess.com's "Show Hint" in bot games **only highlights the piece to move**, so expect `square`. |
| `boardChanged`, `setupDone`, `setupFailed` | navigation and setup diagnostics |

The blindfold loop: on `move` with `by == "opponent"`, speak `MoveAnnouncer(san)`. On `gameOver`, speak the
result. Feed `state().fen` to the Swift `Position` for disambiguation, and send the resolved UCI to
`BlindChess.move`. All of `ChessJSBridge.scrapeScript/findPieceScript/moveScript/touchScript` can go.

## 5. chess.com behaviour you will see (measured on the runner, guest, no login)

- On the first visit there is either an onboarding modal followed by a game that has already started (you are
  White vs the default bot "Martinfoot"), or the bot-selection screen with **Play**. `state().phase` tells them
  apart: `setup` means the selection screen (the `.bot-selection-cta` "Play" button is visible). In that case
  call `startNewGame({color})`. If a game has auto-started on the wrong side with no moves yet,
  `startNewGame({color})` resigns it and goes through New Bot for you.
- The colour picker is the three `.play-side-selector-option` tiles (white, random, black). Bots are
  `li.bot-component[data-bot-selection-name]`. "Options" holds time controls (default: no timer).
- **Reload mid-game:** the page comes back on the setup screen (`phase:'setup'`, ply 0). Pressing Play with the
  **same colour** (`startNewGame({color})`) resumes the unfinished game with its full history. Choosing the other
  colour also resumes that position, but with the sides swapped, so always pass the user's colour.
- After the game ends, `getPlayingAs()` returns undefined. The bridge remembers the side for that game.
- Game over shows a modal with "New Bot" and "Rematch". `startNewGame()` waits for that modal.

## 6. Bot detection

- WebKit (the engine WKWebView uses) with the iPhone 13 profile: **no challenge** in any run, headless, on
  both ubuntu-latest and macos-latest runners (about 12 page loads, including reloads).
- Chromium headless: Cloudflare "Just a moment..." (HTTP 403) on the first request (1 of 1 runs).
  Chromium headed under xvfb: loaded normally in 2 of 3 runs and was challenged in 1. This only matters for CI.
  Use WebKit, which is also what the app runs.
- No login was needed for anything above.

## 7. Re-running the lab

`.github/workflows/bridge-lab.yml` runs on pushes to the bridge or `Tools/BridgeLab/**`, or on manual dispatch
(`mode=test|explore`). `test.mjs` plays full games through the bridge (chess.js in the harness picks the moves).
It prints `RESULT PASS/FAIL ...`, `GAME ...`, `COVERAGE` and `SUMMARY` lines in the job log. `explore.mjs`
dumps setup-screen DOM.
