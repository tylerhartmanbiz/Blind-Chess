//
//  ChessComBridge.swift
//  Blind Chess
//
//  Swift side of `Resources/chesscom-bridge.js` (see Tools/BridgeLab/INTEGRATION.md): typed calls into
//  `window.BlindChess` and typed events from its `blindChess` message handler.
//

import Foundation
import WebKit

enum GamePhase: String {
    case setup, playing, over
}

struct GameOverInfo: Equatable {
    let result: String
    let reason: String
    /// nil for a draw.
    let winner: PieceColor?
    let userWon: Bool?

    init(_ dict: [String: Any]) {
        result = dict["result"] as? String ?? ""
        reason = dict["reason"] as? String ?? "unknown"
        winner = PieceColor(bridgeLetter: dict["winner"] as? String)
        userWon = dict["userWon"] as? Bool
    }
}

struct BridgeState: Equatable {
    let phase: GamePhase
    let fen: String?
    let playingAs: PieceColor?
    let ply: Int
    let gameOver: GameOverInfo?

    init?(_ dict: [String: Any]) {
        guard let phase = GamePhase(rawValue: dict["phase"] as? String ?? "") else { return nil }
        self.phase = phase
        fen = dict["fen"] as? String
        playingAs = PieceColor(bridgeLetter: dict["playingAs"] as? String)
        ply = dict["ply"] as? Int ?? 0
        gameOver = (dict["gameOver"] as? [String: Any]).map(GameOverInfo.init)
    }
}

struct BridgeMove {
    let ply: Int
    let san: String
    let uci: String?
    let fen: String?
    let byUser: Bool
}

enum BridgeEvent {
    case move(BridgeMove)
    case gameOver(GameOverInfo)
    case newGame(playingAs: PieceColor?)
    case takeback(fen: String?)
    case state(BridgeState)
    case setupFailed(String)
    /// Sent by the web view, not the script: chess.com could not be loaded.
    case loadFailed(String)

    init?(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "move":
            guard let san = dict["san"] as? String else { return nil }
            self = .move(BridgeMove(ply: dict["ply"] as? Int ?? 0, san: san, uci: dict["uci"] as? String,
                                    fen: dict["fen"] as? String, byUser: dict["by"] as? String == "user"))
        case "gameOver": self = .gameOver(GameOverInfo(dict))
        case "newGame": self = .newGame(playingAs: PieceColor(bridgeLetter: dict["playingAs"] as? String))
        case "takeback": self = .takeback(fen: dict["fen"] as? String)
        case "state":
            guard let state = (dict["state"] as? [String: Any]).flatMap(BridgeState.init) else { return nil }
            self = .state(state)
        case "setupFailed": self = .setupFailed(dict["error"] as? String ?? "unknown")
        default: return nil
        }
    }
}

/// Result of `BlindChess.move(uci)`: the new FEN, or chess.com's reason for refusing.
enum BridgeMoveResult {
    case played(fen: String?)
    case failed(String)
}

@MainActor
final class ChessComBridge {
    static let handlerName = "blindChess"

    static let script: String = {
        guard let url = Bundle.main.url(forResource: "chesscom-bridge", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            Log.error("chesscom-bridge.js missing from the bundle")
            return ""
        }
        return source
    }()

    weak var webView: WKWebView?
    var onEvent: ((BridgeEvent) -> Void)?

    func receive(_ body: Any) {
        guard let event = BridgeEvent(body) else { return }
        onEvent?(event)
    }

    func move(_ uci: String) async -> BridgeMoveResult {
        let reply = await call("return window.BlindChess ? BlindChess.move(uci) : {ok: false, error: 'no-bridge'}",
                               ["uci": uci])
        if reply["ok"] as? Bool == true { return .played(fen: reply["fen"] as? String) }
        return .failed(reply["error"] as? String ?? "no-bridge")
    }

    func state() async -> BridgeState? {
        BridgeState(await call("return window.BlindChess ? BlindChess.state() : {}"))
    }

    /// `color` is "white", "black" or "random"; `force` resigns a game in progress first.
    @discardableResult
    func startNewGame(color: String, force: Bool) async -> Bool {
        let reply = await call("return window.BlindChess ? BlindChess.startNewGame({color: color, force: force}) : {ok: false}",
                               ["color": color, "force": force])
        if reply["ok"] as? Bool != true { Log.error("startNewGame failed: \(reply)") }
        return reply["ok"] as? Bool == true
    }

    @discardableResult
    func resign() async -> Bool { await simpleCall("resign") }

    @discardableResult
    func takeback() async -> Bool { await simpleCall("takeback") }

    private func simpleCall(_ name: String) async -> Bool {
        let reply = await call("return window.BlindChess ? BlindChess.\(name)() : {ok: false}")
        if reply["ok"] as? Bool != true { Log.error("\(name) failed: \(reply)") }
        return reply["ok"] as? Bool == true
    }

    private func call(_ body: String, _ arguments: [String: Any] = [:]) async -> [String: Any] {
        guard let webView else { return [:] }
        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: value as? [String: Any] ?? [:])
                case .failure(let error):
                    Log.error("bridge call failed: \(error.localizedDescription)")
                    continuation.resume(returning: [:])
                }
            }
        }
    }
}

/// Holds the message receiver weakly so WKUserContentController does not keep it alive.
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var bridge: ChessComBridge?

    init(_ bridge: ChessComBridge) {
        self.bridge = bridge
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        bridge?.receive(message.body)
    }
}

extension PieceColor {
    /// The bridge's "w" / "b".
    init?(bridgeLetter: String?) {
        switch bridgeLetter {
        case "w": self = .white
        case "b": self = .black
        default: return nil
        }
    }
}
