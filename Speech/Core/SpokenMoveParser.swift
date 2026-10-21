//
//  SpokenMoveParser.swift
//  Blind Chess core
//
//  Turns one speech transcript into ranked candidate meanings (moves and commands). It never looks at the board:
//  ambiguous words keep all their readings ("to" = preposition or rank 2, "A" = file a or a misheard 8) and
//  `MoveResolver` picks the reading that is legal.
//
//  Public API:
//    SpokenMoveParser.parse(_ transcript: String) -> [SpokenInterpretation]    best first, may be empty
//
//  How it works: words become tokens with weighted readings (SpokenVocabulary), a small beam search enumerates
//  reading combinations, and each combination is read as "[piece] [origin] [takes|to] target [promotion]".
//  Self-corrections ("knight f3, no wait, g5") keep only the last attempt, inheriting the piece if omitted.
//

import Foundation

public enum SpokenMoveParser {
    public static func parse(_ transcript: String) -> [SpokenInterpretation] {
        let normalized = SpokenVocabulary.normalize(transcript)
        guard !normalized.words.isEmpty else { return [] }
        let all = commandInterpretations(normalized.words) + moveInterpretations(normalized.casedWords)
        return all.sorted { $0.score > $1.score }
    }

    // MARK: - Moves

    private static let beamWidth = 256
    private static let maxTokens = 12

    static func moveInterpretations(_ casedWords: [String]) -> [SpokenInterpretation] {
        // Only the last attempt counts; if the speaker ends on "no wait" (nothing after it) there is no move.
        let segments = segmentsAfterCorrections(casedWords).map(SpokenVocabulary.tokens(casedWords:))
        guard let last = segments.last else { return [] }
        var found = interpretations(of: last)
        if let piece = segments.dropLast().reversed().lazy.compactMap(firstPiece(in:)).first {
            found = inherit(piece, into: found)
        }
        return found.map { SpokenInterpretation(intent: .move($0.intent), cost: $0.cost, usesSoundAlike: $0.soundAlike) }
    }

    private struct Candidate {
        var intent: MoveIntent
        var cost: Double
        var soundAlike: Bool
    }

    private struct Path {
        var lexemes: [SpokenLexeme] = []
        var cost = 0.0
        var soundAlike = false
    }

    private static func interpretations(of tokens: [SpokenToken]) -> [Candidate] {
        var beam = [Path()]
        for token in tokens.suffix(maxTokens) {
            var next: [Path] = []
            for path in beam {
                for reading in token.readings {
                    var extended = path
                    if reading.lexeme != .filler { extended.lexemes.append(reading.lexeme) }
                    extended.cost += reading.cost
                    extended.soundAlike = extended.soundAlike || reading.isSoundAlike
                    next.append(extended)
                }
            }
            beam = Array(next.sorted { $0.cost < $1.cost }.prefix(beamWidth))
        }

        var best: [MoveIntent: Candidate] = [:]
        for path in beam {
            guard let (intent, penalty) = readMove(path.lexemes) else { continue }
            let candidate = Candidate(intent: intent, cost: path.cost + penalty, soundAlike: path.soundAlike)
            if let existing = best[intent], !isBetter(candidate, than: existing) { continue }
            best[intent] = candidate
        }
        return best.values.sorted { isBetter($0, than: $1) }
    }

    private static func isBetter(_ a: Candidate, than b: Candidate) -> Bool {
        a.cost != b.cost ? a.cost < b.cost : (!a.soundAlike && b.soundAlike)
    }

    /// "Knight f3, no wait, g5" means knight g5: a correction without a piece keeps the earlier piece.
    private static func inherit(_ piece: PieceKind, into candidates: [Candidate]) -> [Candidate] {
        let inheritedPenalty = 0.3
        return candidates.flatMap { candidate -> [Candidate] in
            guard candidate.intent.piece == nil, !candidate.intent.isCastle else { return [candidate] }
            var inherited = candidate
            inherited.intent.piece = piece
            var original = candidate
            original.cost += inheritedPenalty
            return [inherited, original]
        }
    }

    private static func firstPiece(in tokens: [SpokenToken]) -> PieceKind? {
        for token in tokens {
            for reading in token.readings where reading.cost == 0 {
                if case .piece(let kind) = reading.lexeme { return kind }
            }
        }
        return nil
    }

    // MARK: SpokenReading one combination

    private enum Element: Equatable {
        case piece(PieceKind), square(Int, Int), file(Int), rank(Int), capture, other
    }

    /// Interprets one sequence of lexemes as a move, returning the intent and a penalty for unused coordinates.
    private static func readMove(_ lexemes: [SpokenLexeme]) -> (MoveIntent, Double)? {
        if let castle = readCastle(lexemes) { return castle }

        var elements: [Element] = []
        var index = 0
        while index < lexemes.count {
            switch lexemes[index] {
            case .file(let file):
                if index + 1 < lexemes.count, case .rank(let rank) = lexemes[index + 1] {
                    elements.append(.square(file, rank))
                    index += 1
                } else {
                    elements.append(.file(file))
                }
            case .rank(let rank): elements.append(.rank(rank))
            case .piece(let kind): elements.append(.piece(kind))
            case .capture: elements.append(.capture)
            default: elements.append(.other)
            }
            index += 1
        }

        let isCapture = elements.contains(.capture)
        let captureIndex = elements.firstIndex(of: .capture) ?? elements.count
        guard let targetIndex = elements.lastIndex(where: { if case .square = $0 { return true } else { return false } })
                ?? (isCapture ? elements.count : nil) else { return nil }

        var intent = MoveIntent(isCapture: isCapture)
        var penalty = 0.0
        if targetIndex < elements.count, case .square(let file, let rank) = elements[targetIndex] {
            intent.toFile = file
            intent.toRank = rank
        } else if let loneFile = elements[captureIndex...].compactMap({ if case .file(let f) = $0 { return f } else { return nil } }).first {
            intent.toFile = loneFile   // "e takes d"
        }

        var sourceSquares = 0
        for (position, element) in elements.enumerated() where position < targetIndex {
            switch element {
            case .piece(let kind):
                // A piece named after "takes" is the victim ("bishop takes knight on c6"), not the mover.
                if position < captureIndex {
                    if intent.piece == nil { intent.piece = kind } else { penalty += 0.5 }
                }
            case .square(let file, let rank):
                sourceSquares += 1
                intent.fromFile = file
                intent.fromRank = rank
            case .file(let file):
                let isPartialTarget = intent.toFile == file && intent.toRank == nil && position > captureIndex
                if isPartialTarget { continue }
                if sourceSquares == 0 { intent.fromFile = file } else { penalty += 0.5 }
            case .rank(let rank):
                if sourceSquares == 0 { intent.fromRank = rank } else { penalty += 0.5 }
            default:
                break
            }
        }
        penalty += Double(max(0, sourceSquares - 1)) * 0.5

        for element in elements.dropFirst(targetIndex + 1) {
            switch element {
            case .piece(let kind):
                if intent.promotion == nil, PieceKind.promotionChoices.contains(kind),
                   intent.piece == nil || intent.piece == .pawn {
                    intent.promotion = kind
                } else {
                    penalty += 0.2
                }
            case .square, .file, .rank:
                penalty += 0.6
            default:
                break
            }
        }
        if intent.piece == nil, intent.fromFile == nil, intent.toRank == nil { penalty += 0.5 }  // bare "takes"
        return (intent, penalty)
    }

    private static func readCastle(_ lexemes: [SpokenLexeme]) -> (MoveIntent, Double)? {
        let zeros = lexemes.filter { $0 == .zero }.count
        let side = lexemes.lazy.compactMap { lexeme -> CastleSide? in
            if case .side(let side) = lexeme { return side } else { return nil }
        }.first
        let saysCastle = lexemes.contains(.castle)
        guard saysCastle || zeros >= 2 || side != nil else { return nil }
        let hasSquare = zip(lexemes, lexemes.dropFirst()).contains { pair in
            if case .file = pair.0, case .rank = pair.1 { return true } else { return false }
        }
        if !saysCastle && zeros < 2 && hasSquare { return nil }   // "long" or "short" inside an ordinary move

        var resolvedSide = side
        if resolvedSide == nil && zeros >= 2 { resolvedSide = zeros >= 3 ? .queenside : .kingside }
        if resolvedSide == nil, let castleIndex = lexemes.firstIndex(of: .castle) {
            for lexeme in lexemes[castleIndex...] {
                if lexeme == .piece(.queen) { resolvedSide = .queenside; break }
                if lexeme == .piece(.king) { resolvedSide = .kingside; break }
            }
        }
        let penalty = saysCastle || zeros >= 2 ? 0 : 0.5
        return (MoveIntent(isCastle: true, castleSide: resolvedSide), penalty)
    }

    // MARK: Self-corrections

    private static let correctionWords: Set<String> = [
        "no", "nope", "wait", "actually", "sorry", "instead", "oops", "correction", "rather", "cancel", "nevermind",
    ]
    private static let correctionPhrases: [[String]] = [
        ["i", "mean"], ["scratch", "that"], ["make", "that"], ["change", "that"], ["not", "that"],
        ["never", "mind"], ["forget", "it"],
    ]

    private static func segmentsAfterCorrections(_ casedWords: [String]) -> [[String]] {
        var segments: [[String]] = [[]]
        var index = 0
        while index < casedWords.count {
            let word = casedWords[index].lowercased()
            if let phrase = correctionPhrases.first(where: { Array(casedWords.dropFirst(index).prefix($0.count)).map { $0.lowercased() } == $0 }) {
                segments.append([])
                index += phrase.count
            } else if correctionWords.contains(word) {
                segments.append([])
                index += 1
            } else {
                segments[segments.count - 1].append(casedWords[index])
                index += 1
            }
        }
        return segments
    }

    // MARK: - Commands

    private static let leadingFillers: Set<String> = [
        "um", "uh", "uhh", "umm", "er", "erm", "hmm", "so", "well", "hey", "please", "ok", "okay", "just", "lets",
        "can", "could", "would", "you", "i", "want", "to", "id", "like", "let", "me", "now",
    ]
    private static let trailingFillers: Set<String> = ["please", "thanks", "now", "again", "thank", "you"]

    /// Phrases that are a command when they are (nearly) the whole utterance.
    private static let commandPhrases: [(SpokenCommand, [String])] = [
        (.yes, ["yes", "yeah", "yep", "yup", "yes please", "confirm", "confirmed", "correct", "right", "sure",
                "do it", "ok", "okay", "affirmative", "thats right", "exactly", "go ahead", "yes do it"]),
        (.no, ["no", "nope", "nah", "wrong", "incorrect", "no thanks", "negative", "thats wrong", "not that"]),
        (.cancel, ["cancel", "never mind", "nevermind", "forget it", "scratch that", "cancel that"]),
        (.stopListening, ["stop listening", "stop", "be quiet", "quiet", "pause", "go to sleep", "mute",
                          "shut up", "sleep", "stop listening to me"]),
        (.help, ["help", "help me", "what can i say", "commands", "options", "what are the commands"]),
        (.whoseTurn, ["whose turn", "whose turn is it", "whos turn", "whos turn is it", "who is to move",
                      "whos to move", "who to move", "is it my turn", "my turn", "whose move", "whose move is it",
                      "who moves", "who moves next", "is it your turn"]),
        (.readBoard, ["read the board", "read board", "read the position", "describe the board",
                      "describe the position", "board", "the board", "whats the position", "where are the pieces",
                      "position", "read me the board", "tell me the position", "show the board", "say the board"]),
        (.repeatLastMove, ["repeat", "repeat that", "say again", "say that again", "what was that", "last move",
                           "what was the last move", "what did they play", "what did he play", "what did she play",
                           "what did you play", "what did the computer play", "pardon", "repeat the last move",
                           "what was their move", "what was his move", "what was your move", "come again"]),
        (.newGame, ["new game", "start over", "restart", "rematch", "play again", "start a new game", "new match",
                    "another game", "start new game", "begin a new game"]),
        (.resign, ["resign", "i resign", "i give up", "give up", "i quit", "quit", "resign the game"]),
        (.undo, ["undo", "take back", "takeback", "take it back", "take that back", "undo move", "undo that",
                 "go back", "take back move", "undo last move", "undo the last move", "take back that move"]),
    ]

    /// Distinctive words or phrases that signal a command even inside a longer sentence.
    private static let embeddedCommandPhrases: [(SpokenCommand, [String])] = [
        (.resign, ["resign", "give up"]),
        (.undo, ["undo", "take back", "takeback", "take it back", "take that back"]),
        (.newGame, ["new game", "start over", "rematch", "play again"]),
        (.stopListening, ["stop listening"]),
        (.readBoard, ["read the board", "describe the board", "read me the board"]),
        (.whoseTurn, ["whose turn", "whos turn", "whose move", "my turn"]),
        (.repeatLastMove, ["last move", "say that again", "repeat"]),
        (.help, ["help", "what can i say"]),
        (.cancel, ["cancel", "never mind", "nevermind", "scratch that", "forget it"]),
    ]

    private static func commandInterpretations(_ words: [String]) -> [SpokenInterpretation] {
        var core = Array(words.drop { leadingFillers.contains($0) && words.count > 1 })
        while core.count > 1, let last = core.last, trailingFillers.contains(last) { core.removeLast() }
        if core.isEmpty { core = words }
        let text = core.joined(separator: " ")
        let fullText = " " + words.joined(separator: " ") + " "

        var found: [SpokenInterpretation] = []
        func add(_ command: SpokenCommand, cost: Double) {
            found.append(SpokenInterpretation(intent: .command(command), cost: cost, usesSoundAlike: false))
        }
        for (command, phrases) in commandPhrases where phrases.contains(text) || phrases.contains(words.joined(separator: " ")) {
            add(command, cost: 0)
        }
        for (command, phrases) in embeddedCommandPhrases where phrases.contains(where: { fullText.contains(" \($0) ") }) {
            add(command, cost: 0.7)
        }
        if let query = pieceQuery(core) { add(query.command, cost: query.cost) }
        if let square = squareQuery(core) { add(.describeSquare(square), cost: 0) }

        var seen = Set<SpokenCommand>()
        return found.sorted { $0.score > $1.score }.filter { interpretation in
            guard case .command(let command) = interpretation.intent else { return false }
            return seen.insert(command).inserted
        }
    }

    /// "Where is my queen", "where are the black knights", "list my pieces", "what does my opponent have".
    private static func pieceQuery(_ words: [String]) -> (command: SpokenCommand, cost: Double)? {
        let piece = words.lazy.compactMap { word -> PieceKind? in
            pieceWords.first { $0.value.contains(word) }?.key
        }.first
        let owner = pieceOwner(in: words)
        let asksWhere = words.contains { ["where", "wheres", "find", "locate"].contains($0) }
        if asksWhere, let piece = piece {
            return (.locate(piece, owner), words.first?.hasPrefix("where") == true ? 0 : 0.3)
        }
        let asksList = words.contains("pieces") || words.contains("list")
            || (words.contains("what") && (words.contains("have") || words.contains("left")))
        guard asksList else { return nil }
        if let piece = piece { return (.locate(piece, owner), 0.3) }
        return (.listPieces(owner), 0)
    }

    private static let pieceWords: [PieceKind: Set<String>] = [
        .pawn: ["pawn", "pawns", "porn", "pond"],
        .knight: ["knight", "knights", "night", "nights"],
        .bishop: ["bishop", "bishops"],
        .rook: ["rook", "rooks", "rock", "rocks"],
        .queen: ["queen", "queens"],
        .king: ["king", "kings"],
    ]

    private static func pieceOwner(in words: [String]) -> PieceOwner {
        if words.contains(where: { ["his", "her", "their", "theirs", "opponent", "opponents", "enemy", "computer",
                                    "computers", "your", "its", "he", "she", "they"].contains($0) }) {
            return .opponent
        }
        if words.contains(where: { ["black", "blacks"].contains($0) }) { return .color(.black) }
        if words.contains(where: { ["white", "whites"].contains($0) }) { return .color(.white) }
        return .mine
    }

    /// "What's on e4", "what is at hotel eight", "is d5 empty".
    private static func squareQuery(_ words: [String]) -> Square? {
        guard let first = words.first else { return nil }
        let rest: ArraySlice<String>
        if ["what", "whats", "who", "whos", "which", "anything"].contains(first),
           let preposition = words.firstIndex(where: { ["on", "at", "in"].contains($0) }) {
            rest = words[(preposition + 1)...]
        } else if first == "is", let last = words.last, ["empty", "free", "occupied", "taken"].contains(last) {
            rest = words.dropFirst().dropLast()
        } else {
            return nil
        }
        return bestSquare(in: Array(rest))
    }

    /// The most plausible "file rank" pair in the words, sound-alikes included.
    static func bestSquare(in words: [String]) -> Square? {
        let tokens = SpokenVocabulary.tokens(casedWords: words)
        var best: (square: Square, cost: Double)?
        for (first, second) in zip(tokens, tokens.dropFirst()) {
            for fileReading in first.readings {
                guard case .file(let file) = fileReading.lexeme else { continue }
                for rankReading in second.readings {
                    guard case .rank(let rank) = rankReading.lexeme,
                          let square = Square(file: file, rank: rank) else { continue }
                    let cost = fileReading.cost + rankReading.cost
                    if best == nil || cost < best!.cost { best = (square, cost) }
                }
            }
        }
        return best?.square
    }
}
