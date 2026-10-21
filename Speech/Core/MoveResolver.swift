//
//  MoveResolver.swift
//  Blind Chess core
//
//  Chooses the move (or command) the player meant, given the position and the recognizer's n-best transcripts.
//
//  Public API:
//    MoveResolver.resolve(_ transcripts: [String], in position: Position) -> Resolution
//    MoveResolver.resolveClarification(_ transcripts: [String], candidates: [Move], in position: Position) -> Resolution
//    Resolution: .move(ResolvedMove) | .needsClarification(Clarification) | .command(SpokenCommand)
//                | .illegal(reason: String) | .notUnderstood
//
//  Rules: literal readings beat sound-alike ones; the cheapest literal reading with a legal match decides.
//  Several matches ask a question ("Which knight, B 1 or F 3?"), except that a bare square goes to the single
//  pawn that can reach it (SAN convention). Sound-alike readings ("H A" -> h8) are used only when nothing heard
//  literally is legal and they point to one move; such moves carry low confidence. Unspecified promotions become
//  queens and are reported via `defaultedPromotion`.
//

import Foundation

public enum Resolution: Equatable {
    case move(ResolvedMove)
    case needsClarification(Clarification)
    case command(SpokenCommand)
    /// The words were understood as a move but no legal move fits; `reason` is a sentence to speak.
    case illegal(reason: String)
    case notUnderstood
}

public struct ResolvedMove: Equatable {
    public let move: Move
    public let san: String
    /// 0...1. Literal readings of the best transcript score near 1; sound-alike guesses score below 0.5.
    public let confidence: Double
    /// The player did not name a promotion piece and a queen was chosen.
    public let defaultedPromotion: Bool
    /// The move came from a sound-alike reading (e.g. "H A" heard for h8).
    public let usedSoundAlike: Bool

    /// Suggests asking "Did you mean ...?" before playing.
    public var shouldConfirm: Bool { usedSoundAlike || confidence < 0.5 }
}

public struct Clarification: Equatable {
    public let candidates: [Move]
    public let question: String
}

public enum MoveResolver {
    /// Cost added per position in the recognizer's n-best list.
    private static let alternativeCost = 0.3
    /// Literal readings this much worse than the best one are not considered.
    private static let literalWindow = 1.6

    public static func resolve(_ transcripts: [String], in position: Position) -> Resolution {
        var commands: [(SpokenCommand, Double)] = []
        var moves: [(intent: MoveIntent, cost: Double, soundAlike: Bool)] = []
        for (rank, transcript) in transcripts.enumerated() {
            for interpretation in SpokenMoveParser.parse(transcript) {
                let cost = interpretation.cost + Double(rank) * alternativeCost
                switch interpretation.intent {
                case .command(let command): commands.append((command, cost))
                case .move(let intent): moves.append((intent, cost, interpretation.usesSoundAlike))
                }
            }
        }
        let bestCommand = commands.min { $0.1 < $1.1 }
        let bestMoveCost = moves.map(\.cost).min() ?? .infinity
        if let command = bestCommand, command.1 <= bestMoveCost { return .command(command.0) }
        guard !moves.isEmpty else { return .notUnderstood }

        moves.sort { $0.cost < $1.cost }
        let legal = position.legalMoves()
        let literal = moves.filter { !$0.soundAlike && $0.cost <= bestMoveCost + literalWindow }

        for (index, reading) in literal.enumerated() {
            let matches = legal.filter(reading.intent.matches)
            guard !matches.isEmpty else { continue }
            let choice = choose(from: matches, intent: reading.intent)
            if choice.count == 1 {
                return resolved(choice[0], intent: reading.intent, cost: reading.cost, soundAlike: false, in: position)
            }
            // "a pawn takes b5": the article reading is ambiguous, but the a-file reading narrows it to one move.
            for other in literal[(index + 1)...] where other.cost <= reading.cost + 1 {
                let narrowed = choose(from: legal.filter(other.intent.matches), intent: other.intent)
                if narrowed.count == 1, choice.contains(narrowed[0]) {
                    return resolved(narrowed[0], intent: other.intent,
                                    cost: other.cost, soundAlike: false, in: position)
                }
            }
            return .needsClarification(Clarification(candidates: choice, question: question(for: choice, in: position)))
        }

        if let guess = soundAlikeGuess(moves.filter(\.soundAlike), legal: legal, in: position) { return guess }
        let explained = literal.first ?? moves[0]
        return .illegal(reason: explain(explained.intent, in: position))
    }

    /// Resolves an answer to a clarification question ("the one on b1", "b", "from g1", "kingside").
    public static func resolveClarification(_ transcripts: [String], candidates: [Move], in position: Position) -> Resolution {
        for transcript in transcripts {
            let words = SpokenVocabulary.normalize(transcript)
            let hints = ClarificationHints(SpokenVocabulary.tokens(casedWords: words.casedWords))
            let narrowed = hints.filter(candidates)
            if narrowed.count == 1 {
                return resolved(narrowed[0], intent: MoveIntent(), cost: 0, soundAlike: false, in: position)
            }
        }
        let fresh = resolve(transcripts, in: position)
        switch fresh {
        case .command:
            return fresh
        case .move(let resolvedMove) where candidates.contains(resolvedMove.move):
            return fresh
        default:
            return .needsClarification(Clarification(candidates: candidates,
                                                     question: "Sorry. " + question(for: candidates, in: position)))
        }
    }

    // MARK: - Choosing

    /// Distinct moves after collapsing promotion choices to the queen, then the SAN pawn preference.
    private static func choose(from matches: [Move], intent: MoveIntent) -> [Move] {
        var distinct: [Move] = []
        for move in matches where move.promotion == nil || move.promotion == (intent.promotion ?? .queen) {
            distinct.append(move)
        }
        if distinct.count > 1, intent.piece == nil {
            let pawnMoves = distinct.filter { $0.piece == .pawn }
            if pawnMoves.count == 1 { return pawnMoves }
        }
        return distinct
    }

    private static func resolved(_ move: Move, intent: MoveIntent, cost: Double, soundAlike: Bool,
                                 in position: Position) -> Resolution {
        let defaulted = move.promotion != nil && intent.promotion == nil
        return .move(ResolvedMove(move: move, san: position.san(move), confidence: exp(-cost),
                                  defaultedPromotion: defaulted, usedSoundAlike: soundAlike))
    }

    /// Sound-alike readings may only win if the cheapest ones agree on a single legal move.
    private static func soundAlikeGuess(_ readings: [(intent: MoveIntent, cost: Double, soundAlike: Bool)],
                                        legal: [Move], in position: Position) -> Resolution? {
        let viable = readings.compactMap { reading -> (Move, MoveIntent, Double)? in
            let choice = choose(from: legal.filter(reading.intent.matches), intent: reading.intent)
            return choice.count == 1 ? (choice[0], reading.intent, reading.cost) : nil
        }
        guard let bestCost = viable.map(\.2).min() else { return nil }
        let contenders = viable.filter { $0.2 <= bestCost + 0.3 }
        var distinct: [Move] = []
        for contender in contenders where !distinct.contains(contender.0) { distinct.append(contender.0) }
        if distinct.count == 1, let winner = contenders.first {
            return resolved(winner.0, intent: winner.1, cost: winner.2, soundAlike: true, in: position)
        }
        let options = distinct.prefix(4).map { MoveAnnouncer.announce($0, in: position) }
        return .needsClarification(Clarification(candidates: Array(distinct.prefix(4)),
                                                 question: "Did you mean \(listed(options, conjunction: "or"))?"))
    }

    // MARK: - Questions and explanations

    static func question(for candidates: [Move], in position: Position) -> String {
        if candidates.allSatisfy({ $0.castle != nil }) { return "Castle kingside or queenside?" }
        let first = candidates[0]
        if candidates.allSatisfy({ $0.piece == first.piece && $0.to == first.to }) {
            let origins = candidates.map { MoveAnnouncer.spokenSquare($0.from) }
            return "Which \(first.piece.name), \(listed(origins, conjunction: "or"))?"
        }
        let options = candidates.prefix(4).map { MoveAnnouncer.announce($0, in: position) }
        return "Did you mean \(listed(options, conjunction: "or"))?"
    }

    static func explain(_ intent: MoveIntent, in position: Position) -> String {
        let me = position.sideToMove
        if intent.isCastle { return explainCastling(intent.castleSide, in: position) }

        let pseudo = position.pseudoLegalMoves().filter(intent.matches)
        if let blocked = pseudo.first {
            if position.isCheck { return "You're in check, and that doesn't get out of it." }
            if blocked.piece == .king { return "That square is attacked." }
            return "Your \(blocked.piece.name) on \(MoveAnnouncer.spokenSquare(blocked.from)) is pinned."
        }

        let pieceName = intent.piece?.name ?? "piece"
        if let piece = intent.piece, position.squares(of: Piece(me, piece)).isEmpty {
            return "You have no \(piece.name)."
        }
        if let target = intent.target, let occupant = position[target], occupant.color == me {
            return "\(MoveAnnouncer.spokenSquare(target)) has your own \(occupant.kind.name) on it."
        }
        if intent.isCapture, let target = intent.target, position[target] == nil, target != position.enPassantSquare {
            return "There's nothing to capture on \(MoveAnnouncer.spokenSquare(target))."
        }
        if let piece = intent.piece, intent.fromFile != nil || intent.fromRank != nil {
            let origin = [intent.fromFile.map { "the \(String(Square.fileLetters[$0]).uppercased()) file" },
                          intent.fromRank.map { "rank \($0 + 1)" }].compactMap { $0 }.joined(separator: " and ")
            let onOrigin = position.squares(of: Piece(me, piece)).filter { square in
                (intent.fromFile ?? square.file) == square.file && (intent.fromRank ?? square.rank) == square.rank
            }
            if onOrigin.isEmpty { return "You have no \(piece.name) on \(origin)." }
        }
        guard let target = intent.target else {
            return intent.isCapture ? "No \(pieceName) can capture anything." : "That move isn't possible."
        }
        if position.isCheck { return "You're in check, and that doesn't get out of it." }
        let verb = intent.isCapture ? "capture on" : "reach"
        if intent.piece == nil { return "Nothing can \(verb) \(MoveAnnouncer.spokenSquare(target))." }
        return "No \(pieceName) can \(verb) \(MoveAnnouncer.spokenSquare(target))."
    }

    private static func explainCastling(_ side: CastleSide?, in position: Position) -> String {
        let me = position.sideToMove
        let sides = side.map { [$0] } ?? [.kingside, .queenside]
        let sideName = side.map { $0 == .kingside ? " kingside" : " queenside" } ?? ""
        if !sides.contains(where: { position.castlingRights.contains(.of(me, $0)) }) {
            return "You can no longer castle\(sideName)."
        }
        if position.isCheck { return "You can't castle while in check." }
        let rank = me == .white ? 0 : 7
        let pathIsClear = sides.contains { candidate in
            let files = candidate == .kingside ? [5, 6] : [1, 2, 3]
            return position.castlingRights.contains(.of(me, candidate))
                && files.allSatisfy { position[Square(file: $0, rank: rank)!] == nil }
        }
        return pathIsClear ? "You can't castle through or into check." : "There are pieces in the way of castling\(sideName)."
    }

    static func listed(_ items: [String], conjunction: String) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) \(conjunction) \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + ", \(conjunction) \(items.last!)"
        }
    }
}

/// What a clarification answer pins down: origin squares, files, ranks, piece kinds or castling side.
private struct ClarificationHints {
    var squares: Set<Square> = []
    var files: Set<Int> = []
    var ranks: Set<Int> = []
    var pieces: Set<PieceKind> = []
    var castleSides: Set<CastleSide> = []

    init(_ tokens: [SpokenToken]) {
        let literal = tokens.map { $0.readings.filter { !$0.isSoundAlike && $0.cost < 0.6 }.map(\.lexeme) }
        for (index, lexemes) in literal.enumerated() {
            for lexeme in lexemes {
                switch lexeme {
                case .file(let file):
                    files.insert(file)
                    for case .rank(let rank) in index + 1 < literal.count ? literal[index + 1] : [] {
                        squares.insert(Square(file: file, rank: rank)!)
                    }
                case .rank(let rank): ranks.insert(rank)
                case .piece(let kind): pieces.insert(kind)
                case .side(let side): castleSides.insert(side)
                default: break
                }
            }
        }
    }

    /// Squares beat lone files and ranks; each hint only applies if it keeps at least one candidate.
    func filter(_ candidates: [Move]) -> [Move] {
        var remaining = candidates
        func narrow(_ keep: (Move) -> Bool) {
            let narrowed = remaining.filter(keep)
            if !narrowed.isEmpty { remaining = narrowed }
        }
        if !castleSides.isEmpty { narrow { $0.castle.map(castleSides.contains) ?? false } }
        if !pieces.isEmpty { narrow { pieces.contains($0.piece) || ($0.promotion.map(pieces.contains) ?? false) } }
        if !squares.isEmpty {
            narrow { squares.contains($0.from) }
            narrow { squares.contains($0.to) }
            return remaining
        }
        if !files.isEmpty { narrow { files.contains($0.from.file) } }
        if !ranks.isEmpty { narrow { ranks.contains($0.from.rank) } }
        return remaining
    }
}
