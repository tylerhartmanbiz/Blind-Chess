//
//  SpokenVocabulary.swift
//  Blind Chess core
//
//  Internal: turns a raw speech transcript into tokens, each with every plausible chess reading and a cost
//  (0 = what the word normally means; higher = less likely). Apple's recognizer writes letters, digits and
//  homophones unpredictably ("H A" for h8, "before" for b4, "night" for knight, "to" for 2), so ambiguity is
//  kept here and settled later by the parser's beam search and the resolver's legality check.
//

import Foundation

enum SpokenLexeme: Hashable {
    case piece(PieceKind)
    case file(Int)
    case rank(Int)
    case capture
    case to
    case from
    case promote
    case castle
    case side(CastleSide)
    case zero
    case check
    case filler
}

struct SpokenReading: Hashable {
    let lexeme: SpokenLexeme
    let cost: Double
    /// True when this reading assumes the recognizer misheard a similar-sounding letter or number.
    var isSoundAlike = false
}

struct SpokenToken {
    let word: String
    var readings: [SpokenReading]

    var canBeFile: Bool { readings.contains { if case .file = $0.lexeme { return true } else { return false } } }
    var canBePiece: Bool { readings.contains { if case .piece = $0.lexeme { return true } else { return false } } }
}

enum SpokenVocabulary {
    static let soundAlikeCost = 1.0

    /// Lowercased words with punctuation removed; the original case is kept on `casedWords` for SAN like "Bc4".
    struct Normalized {
        let words: [String]
        let casedWords: [String]
    }

    static func normalize(_ transcript: String) -> Normalized {
        let folded = transcript
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "=", with: " = ")
        let spaced = String(folded.map { $0.isLetter || $0.isNumber || $0 == "=" ? $0 : " " })
        var cased = spaced.split(separator: " ").map(String.init)
        var lower = cased.map { $0.lowercased() }
        for (phrase, replacement) in phraseReplacements {
            var index = 0
            while index + phrase.count <= lower.count {
                if Array(lower[index..<index + phrase.count]) == phrase {
                    lower.replaceSubrange(index..<index + phrase.count, with: [replacement])
                    cased.replaceSubrange(index..<index + phrase.count, with: [replacement])
                }
                index += 1
            }
        }
        return Normalized(words: lower, casedWords: cased)
    }

    /// Tokens for the chess-relevant words; unknown words are dropped.
    static func tokens(casedWords: [String]) -> [SpokenToken] {
        var tokens: [SpokenToken] = []
        for cased in casedWords {
            let word = cased.lowercased()
            if let entry = lexicon[word] {
                tokens += entry.map { SpokenToken(word: word, readings: $0) }
            } else if let split = splitCompound(cased) {
                tokens += split
            }
        }
        applyContext(to: &tokens)
        for index in tokens.indices where !natoWords.contains(tokens[index].word) {
            tokens[index].readings += soundAlikes(of: tokens[index].readings)
        }
        return tokens
    }

    // MARK: - Context-dependent words

    /// "to", "for", "two" and "a" only mean a coordinate in the right place: "e to" is e2, "rook to d1" is not.
    private static func applyContext(to tokens: inout [SpokenToken]) {
        for index in tokens.indices {
            let previousIsFile = index > 0 && tokens[index - 1].canBeFile
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            switch tokens[index].word {
            case "to", "too":
                if previousIsFile && !(next?.canBeFile ?? false) {
                    tokens[index].readings.append(SpokenReading(lexeme: .rank(1), cost: 0.4))
                }
            case "two":
                tokens[index].readings = previousIsFile
                    ? [SpokenReading(lexeme: .rank(1), cost: 0), SpokenReading(lexeme: .to, cost: 0.5)]
                    : [SpokenReading(lexeme: .to, cost: 0.2), SpokenReading(lexeme: .rank(1), cost: 0.5)]
            case "for":
                tokens[index].readings = previousIsFile
                    ? [SpokenReading(lexeme: .rank(3), cost: 0.1), SpokenReading(lexeme: .filler, cost: 0.8)]
                    : [SpokenReading(lexeme: .filler, cost: 0), SpokenReading(lexeme: .rank(3), cost: 0.6)]
            case "a":
                tokens[index].readings = (next?.canBePiece ?? false)
                    ? [SpokenReading(lexeme: .filler, cost: 0), SpokenReading(lexeme: .file(0), cost: 0.5)]
                    : [SpokenReading(lexeme: .file(0), cost: 0), SpokenReading(lexeme: .filler, cost: 0.5)]
            default:
                break
            }
        }
    }

    // MARK: - Sound-alike confusions

    /// Groups of coordinates the recognizer confuses: a/8/h ("A", "eight", "aitch"), b/d/e/g/3 ("bee", "dee", "three").
    private static let confusionGroups: [[SpokenLexeme]] = [
        [.file(0), .rank(7), .file(7)],
        [.file(1), .file(3), .file(4), .file(6), .rank(2)],
    ]

    private static func soundAlikes(of readings: [SpokenReading]) -> [SpokenReading] {
        let present = Set(readings.map(\.lexeme))
        var extra: [SpokenReading] = []
        for reading in readings where reading.cost < 0.5 {
            for group in confusionGroups where group.contains(reading.lexeme) {
                for alternative in group where !present.contains(alternative) && !extra.contains(where: { $0.lexeme == alternative }) {
                    extra.append(SpokenReading(lexeme: alternative, cost: reading.cost + soundAlikeCost, isSoundAlike: true))
                }
            }
        }
        return extra
    }

    // MARK: - Compound tokens ("Nf3", "exd5", "g1f3", "a1", "HA", "84")

    private static let sanPattern = try! NSRegularExpression(
        pattern: "^([kqrbnp])?([a-h])?([1-8])?(x)?([a-h])([1-8])?([qrbn])?$", options: [.caseInsensitive])

    private static func splitCompound(_ cased: String) -> [SpokenToken]? {
        let lower = cased.lowercased()
        if lower.allSatisfy({ $0 == "o" || $0 == "0" }), (2...3).contains(lower.count) {
            return lower.map { _ in SpokenToken(word: "0", readings: [SpokenReading(lexeme: .zero, cost: 0)]) }
        }
        if lower.allSatisfy(\.isNumber), lower.count == 2 {
            // Apple formats "e four" as "84" (eighty-four), so a leading 8 is most likely the e-file.
            let digits = lower.map(String.init)
            var tokens = digits.compactMap { digit in lexicon[digit]?.first.map { SpokenToken(word: digit, readings: $0) } }
            if digits[0] == "8", !tokens.isEmpty {
                tokens[0].readings = [SpokenReading(lexeme: .file(4), cost: 0.3), SpokenReading(lexeme: .file(0), cost: 0.6),
                                      SpokenReading(lexeme: .file(7), cost: 0.9), SpokenReading(lexeme: .rank(7), cost: 0.6)]
            }
            return tokens
        }
        let range = NSRange(cased.startIndex..., in: cased)
        guard cased.count >= 2, cased.count <= 7,
              let match = sanPattern.firstMatch(in: cased, range: range) else { return nil }

        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: cased).map { String(cased[$0]) }
        }
        var tokens: [SpokenToken] = []
        if let pieceLetter = group(1) {
            let kind = PieceKind(letter: Character(pieceLetter))!
            // In SAN an uppercase B is the bishop and a lowercase b the b-file ("bxc4"); speech gets this wrong often.
            if kind == .bishop {
                let bishopFirst = pieceLetter == "B"
                tokens.append(SpokenToken(word: "b", readings: [
                    SpokenReading(lexeme: .piece(.bishop), cost: bishopFirst ? 0 : 0.4),
                    SpokenReading(lexeme: .file(1), cost: bishopFirst ? 0.4 : 0),
                ]))
            } else {
                tokens.append(SpokenToken(word: pieceLetter.lowercased(), readings: [SpokenReading(lexeme: .piece(kind), cost: 0)]))
            }
        }
        for index in 2...6 {
            guard let part = group(index)?.lowercased() else { continue }
            tokens += (lexicon[part] ?? []).map { SpokenToken(word: part, readings: $0) }
        }
        if let promotion = group(7) {
            tokens.append(SpokenToken(word: promotion.lowercased(),
                                readings: [SpokenReading(lexeme: .piece(PieceKind(letter: Character(promotion))!), cost: 0)]))
        }
        // A bare pair of letters is only a coordinate if both are files ("HA", "e e" style); otherwise it is a word.
        let hasDigit = lower.contains(where: \.isNumber)
        if !hasDigit && !(lower.count == 2 && group(1) == nil) && group(4) == nil { return nil }
        return tokens
    }

    // MARK: - Word lists

    private static let natoWords: Set<String> = ["alpha", "bravo", "charlie", "delta", "echo", "foxtrot", "golf", "hotel"]

    private static let phraseReplacements: [([String], String)] = [
        (["up", "on"], "upon"), (["king", "side"], "kingside"), (["kings", "side"], "kingside"), (["king", "sight"], "kingside"),
        (["queen", "side"], "queenside"), (["queens", "side"], "queenside"),
        (["check", "mate"], "checkmate"), (["en", "passant"], "enpassant"), (["on", "passant"], "enpassant"),
        (["in", "passing"], "enpassant"), (["o", "o", "o"], "ooo"), (["o", "o"], "oo"),
    ]

    private static let lexicon: [String: [[SpokenReading]]] = {
        var table: [String: [[SpokenReading]]] = [:]
        func add(_ words: [String], _ lexeme: SpokenLexeme, cost: Double = 0) {
            let reading = SpokenReading(lexeme: lexeme, cost: cost, isSoundAlike: cost >= soundAlikeCost)
            for word in words { table[word, default: [[]]][0].append(reading) }
        }

        add(["pawn", "pawns", "pon", "paun", "porn", "pond", "palm", "p", "pee"], .piece(.pawn))
        add(["prawn", "pan", "paw", "pawned", "pound", "upon", "apon"], .piece(.pawn), cost: 0.4)
        add(["knight", "knights", "night", "nights", "nite", "knite", "n", "en"], .piece(.knight))
        add(["knife", "nate", "neat", "m", "em"], .piece(.knight), cost: 0.5)
        add(["bishop", "bishops", "bish", "bishup", "bishep"], .piece(.bishop))
        add(["b", "be", "bee"], .piece(.bishop), cost: 0.7)
        add(["rook", "rooks", "rock", "rocks", "ruk", "brook", "r"], .piece(.rook))
        add(["roof", "rook's", "route", "look", "rogue", "rug"], .piece(.rook), cost: 0.5)
        add(["queen", "queens", "kween", "quinn", "q", "cue", "queue"], .piece(.queen))
        add(["clean", "green", "quin", "queenie"], .piece(.queen), cost: 0.5)
        add(["king", "kings", "k"], .piece(.king))
        add(["keen", "kin", "kang", "kink"], .piece(.king), cost: 0.5)

        add(["a", "ay", "aye", "alpha"], .file(0))
        add(["eh", "hey", "ey"], .file(0), cost: 0.5)
        add(["b", "be", "bee", "bea", "bravo"], .file(1))
        add(["v", "vee", "bi", "p", "pee"], .file(1), cost: 0.7)
        add(["c", "see", "sea", "cee", "si", "charlie"], .file(2))
        add(["z", "zee", "seat"], .file(2), cost: 0.7)
        add(["d", "dee", "de", "di", "delta"], .file(3))
        add(["deep", "dean"], .file(3), cost: 0.8)
        add(["e", "ee", "echo"], .file(4))
        add(["eat", "ye"], .file(4), cost: 0.8)
        add(["f", "ef", "eff", "foxtrot"], .file(5))
        add(["if", "s", "es", "x", "ex"], .file(5), cost: 1.0)
        add(["g", "gee", "jee", "ji", "golf"], .file(6))
        add(["h", "aitch", "haitch", "age", "ach", "hotel"], .file(7))
        add(["each", "edge", "itch", "h's"], .file(7), cost: 0.6)

        add(["1", "one", "won", "wan", "first", "1st"], .rank(0))
        add(["juan", "want"], .rank(0), cost: 0.6)
        add(["2", "two", "second", "2nd"], .rank(1))
        add(["3", "three", "tree", "free", "third", "3rd", "thee"], .rank(2))
        add(["4", "four", "for", "fore", "fourth", "4th"], .rank(3))
        add(["far", "floor", "fort"], .rank(3), cost: 0.6)
        add(["5", "five", "fife", "fifth", "5th"], .rank(4))
        add(["hive", "fire", "vive"], .rank(4), cost: 0.6)
        add(["6", "six", "sex", "fix", "sicks", "sick", "sixth", "6th", "sax"], .rank(5))
        add(["7", "seven", "seventh", "7th"], .rank(6))
        add(["heaven", "kevin"], .rank(6), cost: 0.6)
        add(["8", "eight", "ate", "ait", "eighth", "8th"], .rank(7))
        add(["hate", "eighty"], .rank(7), cost: 0.6)

        add(["takes", "take", "taking", "took", "captures", "capture", "capturing", "captured", "x", "ex", "eats",
             "kills", "times"], .capture)
        add(["to", "too", "towards", "into", "goes", "onto"], .to)
        add(["from", "on", "at", "in"], .from)
        add(["promote", "promotes", "promoting", "promoted", "promotion", "equals", "equal", "=", "becomes",
             "become", "as", "underpromote"], .promote)
        add(["castle", "castles", "castling", "castled", "kassel", "cassel", "castel", "castile"], .castle)
        add(["kingside", "short"], .side(.kingside))
        add(["queenside", "long"], .side(.queenside))
        add(["o", "oh", "0", "zero"], .zero)
        add(["check", "checkmate", "mate", "plus"], .check)
        add(["um", "uh", "uhh", "umm", "er", "erm", "hmm", "okay", "ok", "so", "well", "like", "move", "moving",
             "play", "playing", "lets", "ill", "i", "will", "go", "going", "please", "my", "and", "then", "now",
             "just", "let", "me", "want", "think", "maybe", "piece", "square", "with", "an", "id", "do", "enpassant",
             "the"], .filler)

        // Multi-token words: "before" is b4, "oo"/"ooo" are castling zeros.
        table["before"] = [[SpokenReading(lexeme: .file(1), cost: 0.3)], [SpokenReading(lexeme: .rank(3), cost: 0.3)]]
        table["oo"] = Array(repeating: [SpokenReading(lexeme: .zero, cost: 0)], count: 2)
        table["ooo"] = Array(repeating: [SpokenReading(lexeme: .zero, cost: 0)], count: 3)
        return table
    }()
}
