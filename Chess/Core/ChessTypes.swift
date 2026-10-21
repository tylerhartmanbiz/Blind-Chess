//
//  ChessTypes.swift
//  Blind Chess core
//
//  Small value types shared by the whole core.
//  - `PieceColor`, `PieceKind`, `Piece`: what stands on a square.
//  - `Square`: a board square, 0 = a1 ... 63 = h8; `Square("e4")`, `.name`, `.file`/`.rank` (0-based).
//  - `CastleSide`, `CastlingRights`: castling bookkeeping.
//  - `Move`: a fully described legal move (only `Position` creates them); `.uci` gives "e7e8q" style text.
//

import Foundation

public enum PieceColor: CaseIterable, Hashable {
    case white, black

    public var opponent: PieceColor { self == .white ? .black : .white }
    public var name: String { self == .white ? "white" : "black" }
}

public enum PieceKind: Int, CaseIterable, Hashable {
    case pawn, knight, bishop, rook, queen, king

    /// English name, lowercase: "knight".
    public var name: String {
        switch self {
        case .pawn: return "pawn"
        case .knight: return "knight"
        case .bishop: return "bishop"
        case .rook: return "rook"
        case .queen: return "queen"
        case .king: return "king"
        }
    }

    /// Uppercase SAN letter ("N"); the pawn has the letter "P" although SAN omits it.
    public var letter: Character {
        switch self {
        case .pawn: return "P"
        case .knight: return "N"
        case .bishop: return "B"
        case .rook: return "R"
        case .queen: return "Q"
        case .king: return "K"
        }
    }

    /// Accepts upper- or lowercase SAN/FEN letters.
    public init?(letter: Character) {
        switch letter.uppercased() {
        case "P": self = .pawn
        case "N": self = .knight
        case "B": self = .bishop
        case "R": self = .rook
        case "Q": self = .queen
        case "K": self = .king
        default: return nil
        }
    }

    static let promotionChoices: [PieceKind] = [.queen, .rook, .bishop, .knight]
}

public struct Piece: Hashable {
    public let color: PieceColor
    public let kind: PieceKind

    public init(_ color: PieceColor, _ kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    /// FEN letter: uppercase for white, lowercase for black.
    public var fenLetter: Character {
        color == .white ? kind.letter : Character(kind.letter.lowercased())
    }

    public init?(fenLetter: Character) {
        guard let kind = PieceKind(letter: fenLetter) else { return nil }
        self.init(fenLetter.isUppercase ? .white : .black, kind)
    }
}

public struct Square: Hashable, Comparable, CustomStringConvertible {
    /// 0 = a1, 7 = h1, 56 = a8, 63 = h8.
    public let index: Int

    init(index: Int) {
        self.index = index
    }

    /// `file` and `rank` are 0-based (file 0 = a, rank 0 = rank 1).
    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        index = rank * 8 + file
    }

    /// Parses "e4" (case-insensitive).
    public init?(_ name: String) {
        let chars = Array(name.lowercased())
        guard chars.count == 2,
              let file = Square.fileIndex(chars[0]),
              let rankDigit = chars[1].wholeNumberValue else { return nil }
        self.init(file: file, rank: rankDigit - 1)
    }

    public var file: Int { index % 8 }
    public var rank: Int { index / 8 }
    public var fileLetter: Character { Square.fileLetters[file] }
    public var name: String { "\(fileLetter)\(rank + 1)" }
    public var description: String { name }
    public var isLight: Bool { (file + rank) % 2 == 1 }

    public static let all: [Square] = (0..<64).map { Square(index: $0) }
    public static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }

    static let fileLetters: [Character] = Array("abcdefgh")

    static func fileIndex(_ letter: Character) -> Int? {
        fileLetters.firstIndex(of: Character(letter.lowercased()))
    }

    func offset(file df: Int, rank dr: Int) -> Square? {
        Square(file: file + df, rank: rank + dr)
    }
}

public enum CastleSide: Hashable {
    case kingside, queenside
}

public struct CastlingRights: OptionSet, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    static func of(_ color: PieceColor, _ side: CastleSide) -> CastlingRights {
        switch (color, side) {
        case (.white, .kingside): return .whiteKingside
        case (.white, .queenside): return .whiteQueenside
        case (.black, .kingside): return .blackKingside
        case (.black, .queenside): return .blackQueenside
        }
    }
}

/// A move as produced by `Position.legalMoves()`; it carries enough context to be announced without the board.
public struct Move: Hashable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let piece: PieceKind
    public let captured: PieceKind?
    public let promotion: PieceKind?
    public let isEnPassant: Bool
    public let castle: CastleSide?

    init(from: Square, to: Square, piece: PieceKind, captured: PieceKind? = nil, promotion: PieceKind? = nil,
         isEnPassant: Bool = false, castle: CastleSide? = nil) {
        self.from = from
        self.to = to
        self.piece = piece
        self.captured = captured
        self.promotion = promotion
        self.isEnPassant = isEnPassant
        self.castle = castle
    }

    public var isCapture: Bool { captured != nil }

    /// Long algebraic UCI text, e.g. "e2e4", "e7e8q", "e1g1".
    public var uci: String {
        from.name + to.name + (promotion.map { String($0.letter).lowercased() } ?? "")
    }

    public var description: String { uci }
}
