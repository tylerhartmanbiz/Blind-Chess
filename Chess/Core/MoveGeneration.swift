//
//  MoveGeneration.swift
//  Blind Chess core
//
//  Legal move generation for `Position`: pseudo-legal moves filtered by "own king not attacked afterwards".
//
//  Public API:
//    legalMoves() -> [Move]
//    isAttacked(_ square:, by color:) -> Bool
//    perft(depth:) -> Int        (leaf-node count, for verifying the generator)
//

import Foundation

private let knightSteps = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
private let kingSteps = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
private let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
private let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

extension Position {
    public func legalMoves() -> [Move] {
        let mover = sideToMove
        return pseudoLegalMoves().filter { !leavesKingAttacked($0, mover: mover) }
    }

    func leavesKingAttacked(_ move: Move, mover: PieceColor) -> Bool {
        let after = playing(move)
        return after.isAttacked(after.kingSquare(mover), by: mover.opponent)
    }

    /// Moves that obey piece movement but may leave the mover's own king in check.
    /// Castling is only generated when it is fully legal (king not in, through or into check).
    func pseudoLegalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for from in Square.all {
            guard let piece = board[from.index], piece.color == sideToMove else { continue }
            switch piece.kind {
            case .pawn: addPawnMoves(from: from, into: &moves)
            case .knight: addStepMoves(from: from, kind: .knight, steps: knightSteps, into: &moves)
            case .bishop: addSlidingMoves(from: from, kind: .bishop, directions: bishopDirections, into: &moves)
            case .rook: addSlidingMoves(from: from, kind: .rook, directions: rookDirections, into: &moves)
            case .queen:
                addSlidingMoves(from: from, kind: .queen, directions: rookDirections + bishopDirections, into: &moves)
            case .king:
                addStepMoves(from: from, kind: .king, steps: kingSteps, into: &moves)
                addCastlingMoves(from: from, into: &moves)
            }
        }
        return moves
    }

    public func isAttacked(_ square: Square, by attacker: PieceColor) -> Bool {
        let pawnRankStep = attacker == .white ? -1 : 1
        for fileStep in [-1, 1] {
            if let s = square.offset(file: fileStep, rank: pawnRankStep), board[s.index] == Piece(attacker, .pawn) {
                return true
            }
        }
        for (df, dr) in knightSteps {
            if let s = square.offset(file: df, rank: dr), board[s.index] == Piece(attacker, .knight) { return true }
        }
        for (df, dr) in kingSteps {
            if let s = square.offset(file: df, rank: dr), board[s.index] == Piece(attacker, .king) { return true }
        }
        return firstPiece(from: square, directions: rookDirections) { $0 == Piece(attacker, .rook) || $0 == Piece(attacker, .queen) }
            || firstPiece(from: square, directions: bishopDirections) { $0 == Piece(attacker, .bishop) || $0 == Piece(attacker, .queen) }
    }

    /// Counts leaf nodes of the legal move tree; the standard test of move generator correctness.
    public func perft(depth: Int) -> Int {
        let moves = legalMoves()
        if depth <= 1 { return depth == 1 ? moves.count : 1 }
        return moves.reduce(0) { $0 + playing($1).perft(depth: depth - 1) }
    }

    // MARK: - Generators

    private func addPawnMoves(from: Square, into moves: inout [Move]) {
        let forward = sideToMove == .white ? 1 : -1
        let startRank = sideToMove == .white ? 1 : 6
        let lastRank = sideToMove == .white ? 7 : 0

        func add(to: Square, captured: PieceKind?, isEnPassant: Bool = false) {
            if to.rank == lastRank {
                for promotion in PieceKind.promotionChoices {
                    moves.append(Move(from: from, to: to, piece: .pawn, captured: captured, promotion: promotion))
                }
            } else {
                moves.append(Move(from: from, to: to, piece: .pawn, captured: captured, isEnPassant: isEnPassant))
            }
        }

        if let one = from.offset(file: 0, rank: forward), board[one.index] == nil {
            add(to: one, captured: nil)
            if from.rank == startRank, let two = one.offset(file: 0, rank: forward), board[two.index] == nil {
                add(to: two, captured: nil)
            }
        }
        for fileStep in [-1, 1] {
            guard let target = from.offset(file: fileStep, rank: forward) else { continue }
            if let victim = board[target.index], victim.color != sideToMove {
                add(to: target, captured: victim.kind)
            } else if target == enPassantSquare {
                add(to: target, captured: .pawn, isEnPassant: true)
            }
        }
    }

    private func addStepMoves(from: Square, kind: PieceKind, steps: [(Int, Int)], into moves: inout [Move]) {
        for (df, dr) in steps {
            guard let to = from.offset(file: df, rank: dr) else { continue }
            let occupant = board[to.index]
            if occupant?.color == sideToMove { continue }
            moves.append(Move(from: from, to: to, piece: kind, captured: occupant?.kind))
        }
    }

    private func addSlidingMoves(from: Square, kind: PieceKind, directions: [(Int, Int)], into moves: inout [Move]) {
        for (df, dr) in directions {
            var current = from
            while let to = current.offset(file: df, rank: dr) {
                if let occupant = board[to.index] {
                    if occupant.color != sideToMove {
                        moves.append(Move(from: from, to: to, piece: kind, captured: occupant.kind))
                    }
                    break
                }
                moves.append(Move(from: from, to: to, piece: kind))
                current = to
            }
        }
    }

    private func addCastlingMoves(from king: Square, into moves: inout [Move]) {
        let enemy = sideToMove.opponent
        for side in [CastleSide.kingside, .queenside] {
            guard castlingRights.contains(.of(sideToMove, side)) else { continue }
            let rank = king.rank
            let mustBeEmpty = side == .kingside ? [5, 6] : [1, 2, 3]
            let kingPath = side == .kingside ? [4, 5, 6] : [4, 3, 2]
            guard mustBeEmpty.allSatisfy({ board[rank * 8 + $0] == nil }),
                  kingPath.allSatisfy({ !isAttacked(Square(index: rank * 8 + $0), by: enemy) }) else { continue }
            moves.append(Move(from: king, to: Square(index: rank * 8 + kingPath[2]), piece: .king, castle: side))
        }
    }

    private func firstPiece(from square: Square, directions: [(Int, Int)], matches: (Piece) -> Bool) -> Bool {
        for (df, dr) in directions {
            var current = square
            while let next = current.offset(file: df, rank: dr) {
                if let piece = board[next.index] {
                    if matches(piece) { return true }
                    break
                }
                current = next
            }
        }
        return false
    }
}
