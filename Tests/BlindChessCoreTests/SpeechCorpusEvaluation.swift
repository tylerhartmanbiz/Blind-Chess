import Foundation
@testable import BlindChessCore

// Board-aware evaluation of the speech pipeline on the speech lab's corpus of real Apple recognizer transcripts
// (Tests/SpeechCorpus). For every clip and recognizer config the clip's top-5 transcripts go through
// MoveResolver exactly as the app does, in a realistic position where the spoken move is legal, and the outcome
// is classified:
//
//   auto     the right move (or command) is executed without asking
//   confirm  the right move is proposed with shouldConfirm ("Did you mean ...?"), or a clarification lists the
//            right move when the spoken phrase itself was ambiguous in the position ("castles" with both legal)
//   clarify  a clarification question that lists the right move among at most 3 options although the phrase was
//            specific (the recognizer garbled it). NOT counted as correct in the headline.
//   safe     nothing happens: not understood, explained as illegal, a harmless command, a clarification without
//            the right move, or a WRONG move that is only proposed with shouldConfirm (counted in `wrongConfirm`)
//   wrong    a wrong move is executed without confirmation, or a wrong command that changes the game
//            (new game, resign, undo) is executed
//
// Positions come from games of random-but-sensible legal moves (fixed seed), falling back to hand-made FENs for
// promotions and other rare situations. Speakers are split by a hash of the speaker id: ~60% "tune" (allowed for
// developing the parser) and ~40% "heldout" (headline numbers).

enum Outcome: String, CaseIterable {
    case auto, confirm, clarify, safe, wrong
}

struct CorpusClip {
    let clip: String
    let phraseID: String
    let text: String
    let source: String
    let speaker: String
    let env: String
    /// config -> [best] + alternatives (empty when the recognizer heard nothing or failed).
    let transcripts: [String: [String]]
    var split: String { SpeechCorpus.isHeldOut(speaker: speaker) ? "heldout" : "tune" }
}

struct CorpusPhrase {
    let id: String
    let text: String
    let semantics: [String: Any]
    let tags: [String]
    var kind: String { semantics["kind"] as? String ?? "" }

    /// Report category.
    var category: String {
        if tags.contains("nato") { return "nato" }
        if tags.contains("hesitation") { return "hesitation" }
        if tags.contains("disambiguation") { return "disambiguation" }
        if tags.contains("promotion") { return "promotion" }
        if tags.contains("capture") { return "capture" }
        if tags.contains("castle") { return "castle" }
        if kind == "square" { return "bare square (confusable)" }
        if kind == "answer" { return "answer" }
        if kind == "command" || kind == "query" { return "command" }
        if tags.contains("piece"), let piece = semantics["piece"] as? String {
            return piece == "P" ? "pawn to <sq>" : "piece \(piece)"
        }
        return "bare pawn move"
    }
}

/// A situation in which a clip is evaluated.
enum Scenario {
    case move(Position, expected: Move, phraseAmbiguous: Bool)
    case answer(Position, candidates: [Move], expected: Move)
    case command(Position, expected: SpokenCommand)
}

struct EvaluationRow {
    let clip: CorpusClip
    let phrase: CorpusPhrase
    let config: String
    let outcome: Outcome
    let wrongConfirm: Bool
    let detail: String
    /// "FEN => expected".
    var context = ""
}

enum SpeechCorpus {
    static let directory: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("SpeechCorpus")

    static let configs = ["server", "server_ctx", "ondevice", "ondevice_ctx", "ondevice_lm", "dict", "dict_ctx", "dict_lm"]
    /// Phrases whose meaning the app does not support (no draw offers against the computer).
    static let unsupportedPhrases: Set<String> = ["cmd_draw"]

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return hash
    }

    static func isHeldOut(speaker: String) -> Bool { fnv1a("split:" + speaker) % 100 < 40 }

    // MARK: Loading

    static func loadPhrases() -> [String: CorpusPhrase] {
        var phrases: [String: CorpusPhrase] = [:]
        for object in jsonLines("phrases.jsonl") {
            guard let id = object["phrase_id"] as? String else { continue }
            phrases[id] = CorpusPhrase(id: id, text: object["text"] as? String ?? "",
                                       semantics: object["semantics"] as? [String: Any] ?? [:],
                                       tags: object["tags"] as? [String] ?? [])
        }
        return phrases
    }

    static func loadClips() -> [CorpusClip] {
        jsonLines("transcripts.jsonl").compactMap { object in
            guard let clip = object["clip"] as? String, let phrase = object["phrase_id"] as? String,
                  let results = object["results"] as? [String: Any] else { return nil }
            var transcripts: [String: [String]] = [:]
            for (config, value) in results {
                guard let result = value as? [String: Any], result["error"] == nil else { continue }
                let best = result["best"] as? String ?? ""
                let alternatives = result["nbest_alt"] as? [String] ?? []
                transcripts[config] = ([best] + alternatives).filter { !$0.isEmpty }
            }
            return CorpusClip(clip: clip, phraseID: phrase, text: object["expected_text"] as? String ?? "",
                              source: object["speaker_source"] as? String ?? "?",
                              speaker: object["speaker"] as? String ?? "?", env: object["env"] as? String ?? "?",
                              transcripts: transcripts)
        }
    }

    private static func jsonLines(_ name: String) -> [[String: Any]] {
        guard let text = try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
        }
    }

    // MARK: Evaluation

    static func evaluate(_ clip: CorpusClip, phrase: CorpusPhrase, config: String, scenario: Scenario) -> EvaluationRow? {
        guard let transcripts = clip.transcripts[config] else { return nil }
        let context: String
        switch scenario {
        case .command(let position, let expected): context = "\(position.fen) => \(expected)"
        case .move(let position, let expected, _): context = "\(position.fen) => \(position.san(expected))"
        case .answer(let position, let candidates, let expected):
            context = "\(position.fen) => \(position.san(expected)) of \(candidates.map { $0.uci })"
        }
        func row(_ outcome: Outcome, _ detail: String, wrongConfirm: Bool = false) -> EvaluationRow {
            EvaluationRow(clip: clip, phrase: phrase, config: config, outcome: outcome, wrongConfirm: wrongConfirm,
                          detail: detail, context: context)
        }
        switch scenario {
        case .command(let position, let expected):
            let result = MoveResolver.resolve(transcripts, in: position)
            switch result {
            case .command(let command):
                if command == expected { return row(.auto, "cmd \(command)") }
                return row(isDestructive(command) ? .wrong : .safe, "cmd \(command)")
            case .move(let resolved):
                return resolved.shouldConfirm ? row(.safe, "~\(resolved.san)", wrongConfirm: true) : row(.wrong, resolved.san)
            default:
                return row(.safe, describe(result, in: position))
            }
        case .move(let position, let expected, let ambiguous):
            let result = MoveResolver.resolve(transcripts, in: position)
            return classify(result, expected: expected, ambiguous: ambiguous, in: position, row: row)
        case .answer(let position, let candidates, let expected):
            let result = MoveResolver.resolveClarification(transcripts, candidates: candidates, in: position)
            return classify(result, expected: expected, ambiguous: false, in: position, row: row)
        }
    }

    private static func classify(_ result: Resolution, expected: Move, ambiguous: Bool, in position: Position,
                                 row: (Outcome, String, Bool) -> EvaluationRow) -> EvaluationRow {
        let detail = describe(result, in: position)
        switch result {
        case .move(let resolved):
            if resolved.move == expected { return row(resolved.shouldConfirm ? .confirm : .auto, detail, false) }
            return resolved.shouldConfirm ? row(.safe, detail, true) : row(.wrong, detail, false)
        case .needsClarification(let clarification):
            guard clarification.candidates.contains(expected) else { return row(.safe, detail, false) }
            if ambiguous { return row(.confirm, detail, false) }
            return row(clarification.candidates.count <= 3 ? .clarify : .safe, detail, false)
        case .command(let command):
            return row(isDestructive(command) ? .wrong : .safe, detail, false)
        case .illegal, .notUnderstood:
            return row(.safe, detail, false)
        }
    }

    static func isDestructive(_ command: SpokenCommand) -> Bool {
        switch command {
        case .newGame, .resign, .undo: return true
        default: return false
        }
    }

    static func describe(_ result: Resolution, in position: Position) -> String {
        switch result {
        case .move(let resolved): return (resolved.shouldConfirm ? "confirm " : "play ") + resolved.san
        case .needsClarification(let clarification):
            return "ask " + clarification.candidates.map { position.san($0) }.joined(separator: "|")
        case .command(let command): return "cmd \(command)"
        case .illegal(let reason): return "illegal: \(reason)"
        case .notUnderstood: return "not understood"
        }
    }
}

// MARK: - Positions

struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

enum ScenarioBuilder {
    /// Positions from games of weighted-random legal moves: captures (especially winning ones), castling and
    /// development are preferred and aimless king moves avoided, so games look roughly like real ones.
    static func positionPool(games: Int = 120, plies: Int = 70, seed: UInt64 = 2026) -> [Position] {
        var rng = SplitMix64(state: seed)
        var pool: [Position] = []
        let value: [PieceKind: Double] = [.pawn: 1, .knight: 3, .bishop: 3, .rook: 5, .queen: 9, .king: 0]
        for _ in 0..<games {
            var position = Position.start
            for _ in 0..<plies {
                let moves = position.legalMoves()
                if moves.isEmpty || position.hasInsufficientMaterial { break }
                pool.append(position)
                let weights = moves.map { move -> Double in
                    var weight = 1.0
                    if let captured = move.captured {
                        weight += 2 + max(0, value[captured]! - value[move.piece]!)
                    }
                    if move.castle != nil { weight += 6 }
                    let homeRank = position.sideToMove == .white ? 0 : 7
                    if (move.piece == .knight || move.piece == .bishop) && move.from.rank == homeRank { weight += 2 }
                    if move.piece == .king && move.castle == nil { weight *= 0.2 }
                    if move.promotion != nil && move.promotion != .queen { weight *= 0.1 }
                    return weight
                }
                var pick = rng.unit() * weights.reduce(0, +)
                var chosen = moves[moves.count - 1]
                for (move, weight) in zip(moves, weights) {
                    pick -= weight
                    if pick <= 0 { chosen = move; break }
                }
                position.play(chosen)
            }
        }
        return pool
    }

    /// Hand-made positions for situations random games rarely reach (promotions, rare disambiguations, answers).
    static let fallbackFENs: [String] = [
        "r3k2r/pPpp1ppp/8/4p3/4P3/8/P1PP1PPP/R3K2R w KQkq - 0 12",
        "1nb1kbnr/P3pppp/8/8/8/8/1PPP1PPP/RNBQKBNR w KQk - 0 9",
        "rnbqk2r/pppp1P1p/5n2/8/8/8/PPPP2PP/RNBQKBNR w KQkq - 0 7",
        "2rqkbnr/pPpppppp/8/8/8/8/P1PPPPPP/RNBQKBNR w KQk - 0 6",
        "1rbqkb1r/pPpppppp/8/8/8/8/P1PPPPPP/RNBQKBNR w KQk - 0 6",
        "rnbqkbnr/pp2pppp/8/8/8/8/PPP1PPpP/RNBQK2R b KQkq - 0 7",
        "rnbqkbnr/pp1ppppp/8/8/8/8/PPPPPPpP/RNBQKB1R b KQkq - 0 7",
        "rnbqkbnr/pp1ppppp/8/8/8/8/PpPPPPPP/R1BQKBNR b KQkq - 0 7",
        "rnbqkbnr/pp1ppppp/8/8/8/8/PpPPPPPP/2BQKBNR b Kkq - 0 7",
        "3qkbnr/2pppppp/8/8/8/8/6PP/1N1QKBNR w Kk - 0 15",
        "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
        "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 6 5",
        "r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R w KQkq - 4 8",
        "r3k2r/pppq1ppp/2npbn2/2b1p3/2B1P3/2NPBN2/PPPQ1PPP/R3K2R b KQkq - 5 8",
        "r4rk1/ppp2ppp/2n5/3p4/3P4/2N5/PPP2PPP/R4RK1 w - - 0 15",
        "r4rk1/ppp2ppp/2n5/3p4/3P4/2N5/PPP2PPP/R4RK1 b - - 0 15",
        "r3r1k1/ppp2ppp/8/8/8/8/PPP2PPP/R4RK1 b - - 0 20",
        "r6r/pppk1ppp/8/8/8/8/PPP2PPP/R4RK1 b - - 0 20",
        "r6r/pppk1ppp/8/8/8/8/PPP2PPP/R4RK1 w - - 0 20",
        "6k1/5ppp/8/8/8/3N4/1P3PPP/1N4K1 w - - 0 25",
        "6k1/5ppp/8/8/8/8/1P3PPP/1N3NK1 w - - 0 25",
        "r5k1/5ppp/8/8/8/8/5PPP/R5KR w - - 0 30",
        "r1bqk3/pp1pp2P/2n2n2/2p5/8/8/PPPP1PPP/RNBQKBNR w KQq - 0 9",
        "r1bqk3/pp1pp1bP/2n2n2/2p5/3P4/2N5/PPP2PPP/R1BQKBNR w KQq - 1 10",
        "rnbq1rk1/pppP1ppp/5n2/8/8/8/PPP2PPP/RNBQKBNR w KQ - 0 8",
        "r1bq1rk1/pppP1ppp/2n2n2/8/1b6/2N5/PPP2PPP/R1BQKBNR w KQ - 1 9",
    ]

    /// Every pool position, plus the fallback positions, with legal moves cached.
    struct Candidate {
        let position: Position
        let moves: [Move]
    }

    static func candidates(pool: [Position]) -> [Candidate] {
        (pool + fallbackFENs.compactMap(Position.init(fen:))).map { Candidate(position: $0, moves: $0.legalMoves()) }
    }

    static func square(_ name: Any?) -> Square? { (name as? String).flatMap { Square($0) } }

    static func pieceKind(_ letter: Any?) -> PieceKind? {
        (letter as? String).flatMap { $0.first }.flatMap { PieceKind(letter: $0) }
    }

    /// The intent the phrase literally expresses (what a perfect transcript would yield).
    static func spokenIntent(_ phrase: CorpusPhrase) -> MoveIntent? {
        let semantics = phrase.semantics
        switch phrase.kind {
        case "square":
            guard let target = square(semantics["square"]) else { return nil }
            return MoveIntent(toFile: target.file, toRank: target.rank)
        case "castle":
            let side: CastleSide? = phrase.text == "castles" ? nil : (semantics["side"] as? String == "Q" ? .queenside : .kingside)
            return MoveIntent(isCastle: true, castleSide: side)
        case "move":
            guard let target = square(semantics["to"]) else { return nil }
            var intent = MoveIntent(toFile: target.file, toRank: target.rank, isCapture: semantics["capture"] as? Bool ?? false)
            let saysPiece = phrase.text.split(separator: " ").contains { word in
                ["pawn", "knight", "bishop", "rook", "queen", "king"].contains(word.trimmingCharacters(in: .punctuationCharacters))
            }
            if saysPiece { intent.piece = pieceKind(semantics["piece"]) }
            if let from = semantics["from"] as? String {
                if let origin = Square(from) {
                    intent.fromFile = origin.file
                    intent.fromRank = origin.rank
                } else if let letter = from.first, let file = Square.fileLetters.firstIndex(of: letter) {
                    intent.fromFile = file
                }
            }
            intent.promotion = pieceKind(semantics["promo"])
            return intent
        default:
            return nil
        }
    }

    static func expectedCommand(_ phrase: CorpusPhrase) -> SpokenCommand? {
        let semantics = phrase.semantics
        if phrase.kind == "query", let piece = pieceKind(semantics["piece"]) { return .locate(piece, .mine) }
        switch semantics["command"] as? String {
        case "new_game": return .newGame
        case "resign": return .resign
        case "repeat", "last_move": return .repeatLastMove
        case "undo": return .undo
        case "read_board": return .readBoard
        case "yes": return .yes
        case "no": return .no
        case "cancel": return .cancel
        default: return nil
        }
    }

    /// All scenarios in which the phrase is a natural thing to say (several per phrase; clips pick one by hash).
    static func scenarios(for phrase: CorpusPhrase, in candidates: [Candidate], limit: Int = 24) -> [Scenario] {
        if let command = expectedCommand(phrase) {
            return stride(from: 0, to: candidates.count, by: max(1, candidates.count / limit)).prefix(limit).map {
                .command(candidates[$0].position, expected: command)
            }
        }
        if phrase.kind == "answer" {
            return answerScenarios(phrase, candidates: candidates, limit: limit)
        }
        guard let intent = spokenIntent(phrase) else { return [] }
        let semantics = phrase.semantics
        var found: [Scenario] = []
        for candidate in candidates {
            let matching = candidate.moves.filter(intent.matches)
            let distinct = matching.filter { $0.promotion == nil || $0.promotion == (intent.promotion ?? .queen) }
            if distinct.isEmpty { continue }
            if phrase.kind == "castle" {
                guard let side = semantics["side"] as? String == "Q" ? CastleSide.queenside : .kingside as CastleSide?,
                      let expected = distinct.first(where: { $0.castle == side }) else { continue }
                found.append(.move(candidate.position, expected: expected, phraseAmbiguous: distinct.count > 1))
                continue
            }
            // The phrase must name exactly one legal move (bare squares: SAN pawn preference applies).
            guard case .move(let resolved) = MoveResolver.resolve(intent, in: candidate.position) else { continue }
            let expected = resolved.move
            if phrase.kind == "move" {
                guard let piece = pieceKind(semantics["piece"]), expected.piece == piece,
                      expected.isCapture == (semantics["capture"] as? Bool ?? false) else { continue }
                if phrase.tags.contains("disambiguation") {
                    var loose = intent
                    loose.fromFile = nil
                    loose.fromRank = nil
                    guard candidate.moves.filter(loose.matches).count >= 2 else { continue }
                }
            }
            found.append(.move(candidate.position, expected: expected, phraseAmbiguous: false))
        }
        return spread(found, limit: limit)
    }

    private static func answerScenarios(_ phrase: CorpusPhrase, candidates: [Candidate], limit: Int) -> [Scenario] {
        guard let origin = square(phrase.semantics["square"]) else { return [] }
        var found: [Scenario] = []
        for candidate in candidates {
            for expected in candidate.moves where expected.from == origin && expected.promotion == nil && expected.castle == nil {
                let rivals = candidate.moves.filter {
                    $0.to == expected.to && $0.piece == expected.piece && $0.from != origin && $0.promotion == nil
                }
                guard !rivals.isEmpty else { continue }
                found.append(.answer(candidate.position, candidates: [expected] + rivals, expected: expected))
                break
            }
        }
        return spread(found, limit: limit)
    }

    private static func spread(_ items: [Scenario], limit: Int) -> [Scenario] {
        guard items.count > limit else { return items }
        let step = Double(items.count) / Double(limit)
        return (0..<limit).map { items[Int(Double($0) * step)] }
    }
}
