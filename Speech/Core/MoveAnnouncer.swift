//
//  MoveAnnouncer.swift
//  Blind Chess core
//
//  English sentences for text-to-speech: moves, squares and board descriptions.
//
//  Public API:
//    MoveAnnouncer.announce(_ move: Move, in position: Position) -> String     position = before the move
//    MoveAnnouncer.spokenSquare(_ square: Square) -> String                   "E 4"
//    MoveAnnouncer.locate(_ kind: PieceKind, of color: PieceColor, in position: Position, userColor: PieceColor) -> String
//    MoveAnnouncer.listPieces(of color: PieceColor, in position: Position, userColor: PieceColor) -> String
//    MoveAnnouncer.describeSquare(_ square: Square, in position: Position) -> String
//    MoveAnnouncer.describeBoard(_ position: Position) -> String
//    MoveAnnouncer.describeTurn(_ position: Position, userColor: PieceColor) -> String
//
//  Squares are written as an uppercase file letter, a space and the digit ("E 4", "A 8"). Read as one word,
//  "a8" or "e4" can come out of AVSpeechSynthesizer as "ate" or "ee-four"; a lowercase lone "a" is read as the
//  article "uh". The uppercase letter followed by a separate digit is spelled out as a letter name, then the number.
//

import Foundation

public enum MoveAnnouncer {
    public static func spokenSquare(_ square: Square) -> String {
        "\(String(square.fileLetter).uppercased()) \(square.rank + 1)"
    }

    /// "Knight to F 3", "Pawn takes D 5", "E pawn takes D 5" (when two pawns could), "Castles kingside",
    /// "Pawn to E 8 promotes to queen, check", "Queen takes F 7, checkmate".
    public static func announce(_ move: Move, in position: Position) -> String {
        var sentence: String
        if let side = move.castle {
            sentence = side == .kingside ? "Castles kingside" : "Castles queenside"
        } else {
            sentence = moverPhrase(move, in: position)
            sentence += move.isCapture ? " takes " : " to "
            sentence += spokenSquare(move.to)
            if move.isEnPassant { sentence += " en passant" }
            if let promotion = move.promotion { sentence += " promotes to \(promotion.name)" }
        }
        let after = position.playing(move)
        if after.isCheckmate {
            sentence += ", checkmate"
        } else if after.isCheck {
            sentence += ", check"
        } else if after.isStalemate {
            sentence += ", stalemate"
        }
        return sentence
    }

    /// "Your queen is on D 1.", "Your knights are on B 1 and G 1.", "Black has no queen."
    public static func locate(_ kind: PieceKind, of color: PieceColor, in position: Position, userColor: PieceColor) -> String {
        let squares = position.squares(of: Piece(color, kind)).map(spokenSquare)
        let owner = color == userColor ? "Your" : "The \(color.name)"
        switch squares.count {
        case 0:
            return color == userColor ? "You have no \(kind.name)." : "\(color.name.capitalized) has no \(kind.name)."
        case 1:
            return "\(owner) \(kind.name) is on \(squares[0])."
        default:
            return "\(owner) \(plural(kind)) are on \(MoveResolver.listed(squares, conjunction: "and"))."
        }
    }

    /// "You have: king G 1; queen D 1; rooks A 1 and F 1; ..." (or "Black has: ...").
    public static func listPieces(of color: PieceColor, in position: Position, userColor: PieceColor) -> String {
        let owner = color == userColor ? "You have" : "\(color.name.capitalized) has"
        return "\(owner): \(pieceGroups(of: color, in: position))."
    }

    /// "E 4 is empty." or "E 4 has a white pawn."
    public static func describeSquare(_ square: Square, in position: Position) -> String {
        guard let piece = position[square] else { return "\(spokenSquare(square)) is empty." }
        return "\(spokenSquare(square)) has a \(piece.color.name) \(piece.kind.name)."
    }

    /// Both armies followed by whose move it is.
    public static func describeBoard(_ position: Position) -> String {
        let white = "White: \(pieceGroups(of: .white, in: position))."
        let black = "Black: \(pieceGroups(of: .black, in: position))."
        return "\(white) \(black) \(position.sideToMove.name.capitalized) to move."
    }

    /// "Your move." / "White's move, waiting for your opponent."
    public static func describeTurn(_ position: Position, userColor: PieceColor) -> String {
        if position.isCheckmate { return "Checkmate. \(position.sideToMove.opponent.name.capitalized) won." }
        if position.isStalemate { return "Stalemate. The game is drawn." }
        let check = position.isCheck ? " You are in check." : ""
        return position.sideToMove == userColor
            ? "Your move, you play \(userColor.name).\(check)"
            : "\(position.sideToMove.name.capitalized)'s move. Waiting for your opponent."
    }

    // MARK: - Helpers

    private static func moverPhrase(_ move: Move, in position: Position) -> String {
        let name = move.piece.name.capitalized
        let rivals = position.legalMoves().filter {
            $0.piece == move.piece && $0.to == move.to && $0.from != move.from
        }
        guard !rivals.isEmpty else { return name }
        if move.piece == .pawn {
            return "\(String(move.from.fileLetter).uppercased()) pawn"
        }
        return "\(name) from \(spokenSquare(move.from))"
    }

    private static func pieceGroups(of color: PieceColor, in position: Position) -> String {
        PieceKind.allCases.reversed().compactMap { kind -> String? in
            let squares = position.squares(of: Piece(color, kind)).map(spokenSquare)
            guard !squares.isEmpty else { return nil }
            let name = squares.count == 1 ? kind.name : plural(kind)
            return "\(name) \(MoveResolver.listed(squares, conjunction: "and"))"
        }.joined(separator: "; ")
    }

    private static func plural(_ kind: PieceKind) -> String { kind.name + "s" }
}
