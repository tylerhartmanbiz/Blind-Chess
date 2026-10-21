//
//  SpokenIntent.swift
//  Blind Chess core
//
//  What a spoken utterance can mean.
//  - `MoveIntent`: a partial move description ("knight to f3", "e takes d5", "castle"); `matches(_:)` tests a Move.
//  - `SpokenCommand`: everything that is not a move (new game, undo, "where is my queen", yes/no, ...).
//  - `SpokenInterpretation`: one candidate meaning with a score in (0, 1]; the parser returns several.
//

import Foundation

public struct MoveIntent: Hashable {
    public var piece: PieceKind?
    /// 0-based origin file/rank when the speaker disambiguated ("rook a to d1", "knight 1 to e2", "g1 to f3").
    public var fromFile: Int?
    public var fromRank: Int?
    /// 0-based target; `toRank` may be missing only for captures ("e takes d", "pawn takes").
    public var toFile: Int?
    public var toRank: Int?
    public var isCapture = false
    public var promotion: PieceKind?
    public var isCastle = false
    /// nil for a plain "castle".
    public var castleSide: CastleSide?

    public init(piece: PieceKind? = nil, fromFile: Int? = nil, fromRank: Int? = nil, toFile: Int? = nil,
                toRank: Int? = nil, isCapture: Bool = false, promotion: PieceKind? = nil,
                isCastle: Bool = false, castleSide: CastleSide? = nil) {
        self.piece = piece
        self.fromFile = fromFile
        self.fromRank = fromRank
        self.toFile = toFile
        self.toRank = toRank
        self.isCapture = isCapture
        self.promotion = promotion
        self.isCastle = isCastle || castleSide != nil
        self.castleSide = castleSide
    }

    public var target: Square? {
        guard let file = toFile, let rank = toRank else { return nil }
        return Square(file: file, rank: rank)
    }

    /// True when `move` fits every detail the speaker gave. "King to g1" also matches castling.
    public func matches(_ move: Move) -> Bool {
        if isCastle {
            guard let side = move.castle else { return false }
            return castleSide == nil || castleSide == side
        }
        if let piece = piece, piece != move.piece { return false }
        if let file = fromFile, file != move.from.file { return false }
        if let rank = fromRank, rank != move.from.rank { return false }
        if let file = toFile, file != move.to.file { return false }
        if let rank = toRank, rank != move.to.rank { return false }
        if isCapture && !move.isCapture { return false }
        if let promotion = promotion, promotion != move.promotion { return false }
        return true
    }
}

/// Whose pieces a question is about.
public enum PieceOwner: Hashable {
    case mine
    case opponent
    case color(PieceColor)
}

public enum SpokenCommand: Hashable {
    case newGame
    case resign
    case undo
    /// "Repeat", "what was the last move".
    case repeatLastMove
    /// "Where is my queen", "where are the black knights".
    case locate(PieceKind, PieceOwner)
    /// "What's on e4".
    case describeSquare(Square)
    case readBoard
    /// "List my pieces", "what pieces does my opponent have".
    case listPieces(PieceOwner)
    case whoseTurn
    case help
    case cancel
    case stopListening
    case yes
    case no
}

public enum SpokenIntent: Hashable {
    case move(MoveIntent)
    case command(SpokenCommand)
}

public struct SpokenInterpretation: Hashable {
    public let intent: SpokenIntent
    /// Relative likelihood in (0, 1]; 1 means every word was taken at face value.
    public let score: Double
    /// True when the reading assumes a misheard sound-alike ("H A" read as h8). Such readings should only win
    /// when nothing heard literally is legal, and the UI may want to confirm them.
    public let usesSoundAlike: Bool

    var cost: Double { -log(score) }

    init(intent: SpokenIntent, cost: Double, usesSoundAlike: Bool) {
        self.intent = intent
        score = exp(-max(0, cost))
        self.usesSoundAlike = usesSoundAlike
    }
}
