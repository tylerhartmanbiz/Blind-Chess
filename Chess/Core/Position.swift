//
//  Position.swift
//  Blind Chess core
//
//  A complete chess position (board, side to move, castling rights, en passant square, move clocks).
//
//  Public API:
//    Position.start, Position.startFEN, Position(fen:) -> Position?, position.fen
//    position[square] -> Piece?, squares(of: Piece) -> [Square], pieces(of: PieceColor) -> [(Square, Piece)]
//    legalMoves() -> [Move]                  (MoveGeneration.swift)
//    play(_ move:), playing(_ move:) -> Position
//    isCheck, isCheckmate, isStalemate, hasInsufficientMaterial
//    san(_ move:), move(san:), move(uci:)     (Notation.swift)
//    perft(depth:) -> Int                    (MoveGeneration.swift)
//

import Foundation

public struct Position: Hashable {
    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    public static let start = Position(fen: startFEN)!

    var board: [Piece?]
    public private(set) var sideToMove: PieceColor
    public private(set) var castlingRights: CastlingRights
    /// The square a pawn skipped over on the previous double push, as written in FEN.
    public private(set) var enPassantSquare: Square?
    public private(set) var halfmoveClock: Int
    public private(set) var fullmoveNumber: Int

    // MARK: FEN

    /// Parses a FEN string. The clocks may be omitted; anything else malformed returns nil.
    /// Castling rights are kept only when king and rook still stand on their original squares.
    /// Positions where the side not to move is in check are rejected.
    public init?(fen: String) {
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard fields.count >= 2 else { return nil }

        var board = [Piece?](repeating: nil, count: 64)
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return nil }
        for (row, text) in rows.enumerated() {
            let rank = 7 - row
            var file = 0
            for char in text {
                if let empty = char.wholeNumberValue, (1...8).contains(empty) {
                    file += empty
                } else if let piece = Piece(fenLetter: char), let square = Square(file: file, rank: rank) {
                    board[square.index] = piece
                    file += 1
                } else {
                    return nil
                }
                guard file <= 8 else { return nil }
            }
            guard file == 8 else { return nil }
        }
        for color in PieceColor.allCases {
            guard board.filter({ $0 == Piece(color, .king) }).count == 1 else { return nil }
        }

        switch fields[1] {
        case "w": sideToMove = .white
        case "b": sideToMove = .black
        default: return nil
        }

        var rights: CastlingRights = []
        let castlingField = fields.count > 2 ? fields[2] : "-"
        if castlingField != "-" {
            for char in castlingField {
                switch char {
                case "K": rights.insert(.whiteKingside)
                case "Q": rights.insert(.whiteQueenside)
                case "k": rights.insert(.blackKingside)
                case "q": rights.insert(.blackQueenside)
                default: return nil
                }
            }
        }

        let epField = fields.count > 3 ? fields[3] : "-"
        if epField == "-" {
            enPassantSquare = nil
        } else {
            guard let square = Square(epField), square.rank == 2 || square.rank == 5 else { return nil }
            enPassantSquare = square
        }

        halfmoveClock = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        fullmoveNumber = max(1, fields.count > 5 ? Int(fields[5]) ?? 1 : 1)
        self.board = board
        castlingRights = Position.rights(rights, stillValidOn: board)
        // The side that just moved cannot be in check; such a position could never arise and would let kings be captured.
        guard !isAttacked(kingSquare(sideToMove.opponent), by: sideToMove) else { return nil }
    }

    public var fen: String {
        var rows: [String] = []
        for rank in (0..<8).reversed() {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[rank * 8 + file] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenLetter)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { row += String(empty) }
            rows.append(row)
        }
        var castling = ""
        if castlingRights.contains(.whiteKingside) { castling += "K" }
        if castlingRights.contains(.whiteQueenside) { castling += "Q" }
        if castlingRights.contains(.blackKingside) { castling += "k" }
        if castlingRights.contains(.blackQueenside) { castling += "q" }
        return [
            rows.joined(separator: "/"),
            sideToMove == .white ? "w" : "b",
            castling.isEmpty ? "-" : castling,
            enPassantSquare?.name ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }

    // MARK: Board queries

    public subscript(square: Square) -> Piece? { board[square.index] }

    public func squares(of piece: Piece) -> [Square] {
        Square.all.filter { board[$0.index] == piece }
    }

    /// All pieces of one colour, king first, then queen, rooks, bishops, knights, pawns; a-file to h-file.
    public func pieces(of color: PieceColor) -> [(square: Square, piece: Piece)] {
        PieceKind.allCases.reversed().flatMap { kind in
            squares(of: Piece(color, kind)).map { (square: $0, piece: Piece(color, kind)) }
        }
    }

    func kingSquare(_ color: PieceColor) -> Square {
        // FEN parsing guarantees exactly one king per side and moves never capture kings.
        Square(index: board.firstIndex(of: Piece(color, .king))!)
    }

    // MARK: Making moves

    /// Plays a move obtained from `legalMoves()` (or `move(san:)` / `move(uci:)`).
    public mutating func play(_ move: Move) {
        let mover = sideToMove
        let piece = Piece(mover, move.piece)

        board[move.from.index] = nil
        board[move.to.index] = move.promotion.map { Piece(mover, $0) } ?? piece
        if move.isEnPassant, let victim = Square(file: move.to.file, rank: move.from.rank) {
            board[victim.index] = nil
        }
        if let side = move.castle {
            let rank = move.from.rank
            let (rookFrom, rookTo) = side == .kingside ? (7, 5) : (0, 3)
            board[rank * 8 + rookFrom] = nil
            board[rank * 8 + rookTo] = Piece(mover, .rook)
        }

        castlingRights = Position.rights(castlingRights, stillValidOn: board)
        enPassantSquare = nil
        if move.piece == .pawn, abs(move.to.rank - move.from.rank) == 2 {
            enPassantSquare = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
        }
        halfmoveClock = (move.piece == .pawn || move.isCapture) ? 0 : halfmoveClock + 1
        if mover == .black { fullmoveNumber += 1 }
        sideToMove = mover.opponent
    }

    public func playing(_ move: Move) -> Position {
        var next = self
        next.play(move)
        return next
    }

    // MARK: Game state

    public var isCheck: Bool { isAttacked(kingSquare(sideToMove), by: sideToMove.opponent) }
    public var isCheckmate: Bool { isCheck && legalMoves().isEmpty }
    public var isStalemate: Bool { !isCheck && legalMoves().isEmpty }

    /// True when neither side can possibly mate: K v K, K+minor v K, or only same-coloured bishops besides kings.
    public var hasInsufficientMaterial: Bool {
        let others = Square.all.compactMap { square -> (Square, Piece)? in
            guard let piece = board[square.index], piece.kind != .king else { return nil }
            return (square, piece)
        }
        if others.isEmpty { return true }
        if others.count == 1 { return others[0].1.kind == .knight || others[0].1.kind == .bishop }
        let bishopSquareColors = Set(others.map { $0.1.kind == .bishop ? $0.0.isLight : nil })
        return others.allSatisfy { $0.1.kind == .bishop } && bishopSquareColors.count == 1
    }

    // MARK: Helpers

    /// Drops every right whose king or rook has left (or been captured on) its original square.
    private static func rights(_ rights: CastlingRights, stillValidOn board: [Piece?]) -> CastlingRights {
        var kept: CastlingRights = []
        for color in PieceColor.allCases {
            let rank = color == .white ? 0 : 7
            guard board[rank * 8 + 4] == Piece(color, .king) else { continue }
            for (side, rookFile) in [(CastleSide.kingside, 7), (.queenside, 0)] {
                let right = CastlingRights.of(color, side)
                if rights.contains(right), board[rank * 8 + rookFile] == Piece(color, .rook) { kept.insert(right) }
            }
        }
        return kept
    }
}
