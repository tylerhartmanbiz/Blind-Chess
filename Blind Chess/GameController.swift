//
//  GameController.swift
//  Blind Chess
//
//  The single source of truth for the game the user plays on chess.com. It mirrors the bridge's state as a
//  core `Position`, turns voice transcripts and button input into moves or commands (MoveResolver), asks
//  follow-up questions (which piece, did you mean, promotion, resign, new game), plays moves through the bridge
//  and announces what happens. Voice and button modes share everything here.
//

import Combine
import SwiftUI

@MainActor
final class GameController: ObservableObject {
    struct Feedback: Equatable {
        enum Tone { case info, success, question, warning, error }
        let text: String
        let tone: Tone
    }

    struct Choice: Identifiable, Equatable {
        let id: String
        let title: String
    }

    /// A question waiting for an answer, by voice or by one of its choice buttons.
    struct Prompt: Equatable {
        enum Kind: Equatable {
            case moves([Move])
            case confirmMove(Move)
            case resign
            case newGame
        }
        let kind: Kind
        let question: String
        let choices: [Choice]
    }

    /// nil until the bridge reports in.
    @Published private(set) var phase: GamePhase?
    @Published private(set) var position = Position.start
    @Published private(set) var userColor: PieceColor?
    @Published private(set) var lastUserMove: String?
    @Published private(set) var lastOpponentMove: String?
    @Published private(set) var result: String?
    @Published private(set) var feedback: Feedback?
    @Published private(set) var prompt: Prompt?
    @Published private(set) var heard = ""
    @Published private(set) var loadError: String?

    let bridge = ChessComBridge()
    let speaker = Speaker()
    let listener = SpeechRecognizer()

    private var lastState: BridgeState?
    private var startRequested = false
    private var autoStartRetries = 0
    private var undoRequested = false

    static let helpText = """
        Say a move like "knight to f3", "e4", "bishop takes c6", or "castle kingside". \
        You can also say: repeat, where is my queen, what's on e4, read the board, list my pieces, whose turn, \
        undo, resign, new game, cancel, or stop listening.
        """

    init() {
        bridge.onEvent = { [weak self] event in self?.handle(event) }
        listener.onUtterance = { [weak self] transcripts in self?.hear(transcripts) }
        speaker.onSpeakingChanged = { [weak self] speaking in
            if speaking { self?.listener.pause(.speaking) } else { self?.listener.resume(.speaking) }
        }
    }

    // MARK: - Derived state

    var isMyTurn: Bool { phase == .playing && userColor == position.sideToMove }

    var statusLine: String {
        if loadError != nil { return "chess.com didn't load" }
        switch phase {
        case nil: return "Loading chess.com…"
        case .setup?: return "Starting a game…"
        case .over?: return result ?? "Game over"
        case .playing?:
            if isMyTurn { return position.isCheck ? "Your move — you're in check" : "Your move" }
            return "Opponent is thinking…"
        }
    }

    // MARK: - Input

    func toggleListening() {
        if listener.isOn {
            listener.stop()
        } else {
            Task { await listener.start() }
        }
    }

    /// One finished utterance: the recognizer's alternatives, best first.
    func hear(_ transcripts: [String]) {
        heard = transcripts.first ?? ""
        if let prompt {
            answer(prompt, transcripts)
        } else {
            handle(MoveResolver.resolve(transcripts, in: position))
        }
    }

    /// A move from the button pad.
    func submit(_ intent: MoveIntent) {
        prompt = nil
        handle(MoveResolver.resolve(intent, in: position))
    }

    func choose(_ choice: Choice) {
        guard let prompt else { return }
        switch prompt.kind {
        case .moves(let candidates):
            if let move = candidates.first(where: { $0.uci == choice.id }) { play(move) }
        case .confirmMove(let move):
            if choice.id == "yes" { play(move) } else { cancelPrompt("Okay, say your move again.") }
        case .resign:
            if choice.id == "yes" { resign() } else { cancelPrompt("Okay, keep playing.") }
        case .newGame:
            startNewGame(color: choice.id)
        }
    }

    func cancelPrompt(_ message: String = "Cancelled.") {
        prompt = nil
        tell(message, .info)
    }

    func perform(_ command: SpokenCommand) {
        let me = userColor ?? .white
        switch command {
        case .newGame: askNewGame()
        case .resign:
            guard phase == .playing else { return tell("No game is running.", .warning) }
            ask(Prompt(kind: .resign, question: "Resign this game?",
                       choices: [Choice(id: "yes", title: "Resign"), Choice(id: "no", title: "Keep playing")]))
        case .undo: undo()
        case .repeatLastMove: tell(lastMovesSummary, .info)
        case .locate(let kind, let owner):
            tell(MoveAnnouncer.locate(kind, of: color(of: owner), in: position, userColor: me), .info)
        case .describeSquare(let square): tell(MoveAnnouncer.describeSquare(square, in: position), .info)
        case .readBoard: tell(MoveAnnouncer.describeBoard(position), .info)
        case .listPieces(let owner):
            tell(MoveAnnouncer.listPieces(of: color(of: owner), in: position, userColor: me), .info)
        case .whoseTurn: tell(turnSentence, .info)
        case .help: tell(Self.helpText, .info)
        case .cancel:
            if prompt != nil { cancelPrompt() } else { speaker.stop() }
        case .stopListening:
            listener.stop()
            tell("Stopped listening. Tap the microphone to start again.", .info)
        case .yes, .no:
            if let prompt { tell(prompt.question, .question) } else { tell("There's nothing to confirm.", .warning) }
        }
    }

    func askNewGame() {
        let inProgress = phase == .playing && (lastState?.ply ?? 0) > 0
        let question = inProgress ? "Start a new game? This resigns the current one. Play white, black, or random?"
                                  : "New game. Play white, black, or random?"
        ask(Prompt(kind: .newGame, question: question, choices: [
            Choice(id: "white", title: "White"), Choice(id: "black", title: "Black"), Choice(id: "random", title: "Random"),
        ]))
    }

    func undo() {
        guard phase == .playing else { return tell("No game is running.", .warning) }
        undoRequested = true
        Task {
            if await !bridge.takeback() {
                undoRequested = false
                tell("Couldn't take back the move.", .error)
            }
        }
    }

    func reload() {
        loadError = nil
        phase = nil
        bridge.reload()
    }

    func scenePhaseChanged(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .background: listener.pause(.background)
        case .active: listener.resume(.background)
        default: break
        }
    }

    // MARK: - Resolving

    private func handle(_ resolution: Resolution) {
        Log.info("resolution: \(resolution)")
        switch resolution {
        case .command(let command): perform(command)
        case .notUnderstood: tell("Sorry, I didn't catch a move. Say help for examples.", .warning)
        case .move(let resolved): if canMove() { propose(resolved) }
        case .needsClarification(let clarification):
            if canMove() { askToChoose(clarification.candidates, question: clarification.question) }
        case .illegal(let reason): if canMove() { tell(reason, .error) }
        }
    }

    private func answer(_ prompt: Prompt, _ transcripts: [String]) {
        let resolution = MoveResolver.resolve(transcripts, in: position)
        if case .command(let command) = resolution {
            let yes = prompt.choices.first { $0.id == "yes" }
            let no = prompt.choices.first { $0.id == "no" }
            switch command {
            case .yes where yes != nil: return choose(yes!)
            case .no where no != nil: return choose(no!)
            case .no, .cancel: return cancelPrompt()
            default: break
            }
        }
        switch prompt.kind {
        case .moves(let candidates):
            switch MoveResolver.resolveClarification(transcripts, candidates: candidates, in: position) {
            case .move(let resolved) where candidates.contains(resolved.move): play(resolved.move)
            case .command(let command): perform(command)
            case .needsClarification(let again): tell(again.question, .question)
            default: tell("Sorry. \(prompt.question)", .question)
            }
        case .confirmMove:
            // Anything but yes or no is a fresh attempt.
            self.prompt = nil
            handle(resolution)
        case .resign:
            if case .command(let command) = resolution { perform(command) } else { tell("Say yes to resign, or no to keep playing.", .question) }
        case .newGame:
            let words = transcripts.joined(separator: " ").lowercased()
            if let color = ["white", "black", "random"].first(where: { words.contains($0) }) {
                startNewGame(color: color)
            } else if case .command(let command) = resolution {
                perform(command)
            } else {
                tell("Say white, black, or random.", .question)
            }
        }
    }

    private func canMove() -> Bool {
        switch phase {
        case nil: tell("chess.com is still loading.", .warning)
        case .setup?: tell("The game hasn't started yet.", .warning)
        case .over?: tell("The game is over. Say new game to play again.", .warning)
        case .playing?:
            if isMyTurn { return true }
            tell("Wait for your opponent's move.", .warning)
        }
        return false
    }

    private func propose(_ resolved: ResolvedMove) {
        if resolved.defaultedPromotion {
            let promotions = position.legalMoves().filter { $0.from == resolved.move.from && $0.to == resolved.move.to }
            let ordered = [PieceKind.queen, .rook, .bishop, .knight].compactMap { kind in
                promotions.first { $0.promotion == kind }
            }
            askToChoose(ordered, question: "Promote to queen, rook, bishop, or knight?")
        } else if resolved.shouldConfirm {
            let sentence = MoveAnnouncer.announce(resolved.move, in: position)
            ask(Prompt(kind: .confirmMove(resolved.move), question: "Did you mean \(sentence)?",
                       choices: [Choice(id: "yes", title: "Yes, \(sentence)"), Choice(id: "no", title: "No")]))
        } else {
            play(resolved.move)
        }
    }

    private func askToChoose(_ candidates: [Move], question: String) {
        ask(Prompt(kind: .moves(candidates), question: question,
                   choices: candidates.map { choice(for: $0, among: candidates) }))
    }

    private func choice(for move: Move, among candidates: [Move]) -> Choice {
        let title: String
        if let promotion = move.promotion, candidates.allSatisfy({ $0.from == move.from && $0.to == move.to }) {
            title = promotion.name.capitalized
        } else if candidates.allSatisfy({ $0.piece == move.piece && $0.to == move.to }) {
            title = "\(move.piece.name.capitalized) from \(move.from.name)"
        } else {
            title = MoveAnnouncer.announce(move, in: position)
        }
        return Choice(id: move.uci, title: title)
    }

    // MARK: - Acting on chess.com

    private func play(_ move: Move) {
        prompt = nil
        let before = position
        let sentence = MoveAnnouncer.announce(move, in: before)
        Task {
            let outcome = await bridge.move(move.uci)
            Log.info("move \(move.uci): \(outcome)")
            switch outcome {
            case .played(let fen):
                if position == before { position = fen.flatMap { Position(fen: $0) } ?? before.playing(move) }
                lastUserMove = sentence
                tell(sentence, .success)
            case .failed(let error):
                tell(Self.explain(moveError: error), .error)
                if let state = await bridge.state() { apply(state) }
            }
        }
    }

    private func resign() {
        prompt = nil
        Task {
            if await !bridge.resign() { tell("Couldn't resign. Use chess.com's Resign button.", .error) }
        }
    }

    private func startNewGame(color: String) {
        prompt = nil
        UserDefaults.standard.set(color, forKey: AppSettings.playColor)
        startRequested = true
        tell("Starting a new game as \(color).", .info)
        Task {
            if await !bridge.startNewGame(color: color, force: true) {
                startRequested = false
                tell("Couldn't start a new game. Show the board and use chess.com's buttons.", .error)
            }
        }
    }

    /// chess.com shows its "Play the bots" setup screen (or a fresh game on the wrong side): start the user's game.
    private func autoStartIfNeeded(_ state: BridgeState) {
        guard !startRequested else { return }
        let preferred = AppSettings.preferredColor
        let wrongSide = state.phase == .playing && state.ply == 0 && preferred != "random"
            && state.playingAs?.name != preferred
        guard state.phase == .setup || wrongSide else { return }
        startRequested = true
        Log.info("auto-starting a game as \(preferred)")
        Task { await bridge.startNewGame(color: preferred, force: false) }
    }

    // MARK: - Bridge events

    private func handle(_ event: BridgeEvent) {
        switch event {
        case .state(let state): apply(state)
        case .move(let move): applyMove(move)
        case .gameOver(let info):
            phase = .over
            prompt = nil
            let sentence = Self.describe(info)
            result = sentence
            tell(sentence, info.userWon == true ? .success : .info)
        case .newGame(let color):
            Log.info("new game, playing \(color?.name ?? "?")")
            userColor = color ?? userColor
            position = .start
            lastUserMove = nil
            lastOpponentMove = nil
            result = nil
            prompt = nil
        case .takeback(let fen):
            guard let fen, let position = Position(fen: fen) else { return }
            self.position = position
            lastUserMove = nil
            lastOpponentMove = nil
            if undoRequested {
                undoRequested = false
                tell("Move taken back. \(turnSentence)", .info)
            }
        case .setupFailed(let error):
            Log.error("setup failed: \(error)")
            guard phase != .playing else { return }
            if autoStartRetries < 3 {
                autoStartRetries += 1
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    startRequested = false
                    if let lastState { autoStartIfNeeded(lastState) }
                }
            } else {
                tell("Couldn't start a game on chess.com. Show the board and press Play, or say new game.", .error)
            }
        case .loadFailed(let error):
            loadError = error
            tell("Couldn't load chess.com. \(error)", .error)
        }
    }

    private func apply(_ state: BridgeState) {
        let previous = phase
        lastState = state
        phase = state.phase
        loadError = nil
        if let color = state.playingAs { userColor = color }
        if let fen = state.fen, let position = Position(fen: fen) { self.position = position }
        if let over = state.gameOver, result == nil { result = Self.describe(over) }
        if state.phase == .playing, previous != .playing {
            startRequested = false
            autoStartRetries = 0
            tell("\(state.ply == 0 ? "Game started" : "Game resumed"). \(turnSentence)", .info)
        }
        autoStartIfNeeded(state)
    }

    private func applyMove(_ event: BridgeMove) {
        let before = position
        let move = event.uci.flatMap(before.move(uci:)) ?? before.move(san: event.san)
        if let fen = event.fen, let after = Position(fen: fen) {
            position = after
        } else if let move {
            position = before.playing(move)
        }
        guard !event.byUser else {
            // Our own moves are announced when the bridge confirms them. A move found here was not applied yet,
            // e.g. a tap on the web board.
            if let move { lastUserMove = MoveAnnouncer.announce(move, in: before) }
            return
        }
        let sentence = move.map { MoveAnnouncer.announce($0, in: before) } ?? event.san
        lastOpponentMove = sentence
        Log.info("opponent: \(event.san)")
        tell("Opponent: \(sentence).", .info)
    }

    // MARK: - Speech and text

    private func ask(_ prompt: Prompt) {
        self.prompt = prompt
        tell(prompt.question, .question)
    }

    private func tell(_ text: String, _ tone: Feedback.Tone) {
        feedback = Feedback(text: text, tone: tone)
        Log.info("say: \(text)")
        speaker.speak(text)
    }

    private var turnSentence: String {
        switch phase {
        case .playing?: return MoveAnnouncer.describeTurn(position, userColor: userColor ?? .white)
        case .over?: return result ?? "The game is over."
        default: return "No game is running yet."
        }
    }

    private var lastMovesSummary: String {
        switch (lastOpponentMove, lastUserMove) {
        case (nil, nil): return "No moves yet."
        case (let theirs?, nil): return "Opponent played \(theirs)."
        case (nil, let mine?): return "You played \(mine)."
        case (let theirs?, let mine?): return "Opponent played \(theirs). You played \(mine)."
        }
    }

    private func color(of owner: PieceOwner) -> PieceColor {
        let me = userColor ?? .white
        switch owner {
        case .mine: return me
        case .opponent: return me.opponent
        case .color(let color): return color
        }
    }

    private static func describe(_ info: GameOverInfo) -> String {
        let how = info.reason == "unknown" ? "" : " by \(info.reason)"
        switch info.userWon {
        case true?: return "You won\(how)."
        case false?: return "You lost\(how)."
        case nil: return info.winner.map { "\($0.name.capitalized) won\(how)." } ?? "Draw\(how)."
        }
    }

    private static func explain(moveError error: String) -> String {
        switch error {
        case "not-your-turn": return "It's not your turn."
        case "not-playing": return "No game is running. Say new game."
        case "game-over": return "The game is over. Say new game to play again."
        case "illegal": return "chess.com didn't accept that move."
        case "no-bridge": return "The board isn't ready yet."
        default: return "That move didn't go through. Try again."
        }
    }
}
