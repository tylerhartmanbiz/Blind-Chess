//
//  ChessMoveValidator.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import Foundation

/// Validates chess moves according to standard chess rules
struct ChessMoveValidator {
    
    /// Represents a chess board state
    struct BoardState {
        var board: [[String]] // 8x8 grid, empty string for empty squares
        var isWhiteTurn: Bool
        
        init(board: [[String]], isWhiteTurn: Bool) {
            self.board = board
            self.isWhiteTurn = isWhiteTurn
        }
        
        /// Get piece at position (row, col)
        func pieceAt(row: Int, col: Int) -> String? {
            guard row >= 0 && row < 8 && col >= 0 && col < 8 else { return nil }
            let piece = board[row][col]
            return piece.isEmpty ? nil : piece
        }
        
        /// Check if a square is empty
        func isEmpty(row: Int, col: Int) -> Bool {
            return pieceAt(row: row, col: col) == nil
        }
        
        /// Check if a piece belongs to white
        func isWhitePiece(_ piece: String) -> Bool {
            return piece == piece.uppercased()
        }
        
        /// Check if a piece belongs to the current player
        func isOwnPiece(row: Int, col: Int) -> Bool {
            guard let piece = pieceAt(row: row, col: col) else { return false }
            return isWhitePiece(piece) == isWhiteTurn
        }
        
        /// Check if a piece belongs to the opponent
        func isOpponentPiece(row: Int, col: Int) -> Bool {
            guard let piece = pieceAt(row: row, col: col) else { return false }
            return isWhitePiece(piece) != isWhiteTurn
        }
    }
    
    /// Validate if a move is legal
    /// - Parameters:
    ///   - from: Starting position as "xy" (e.g., "52" for e2)
    ///   - to: Ending position as "xy" (e.g., "54" for e4)
    ///   - boardState: Current board state
    /// - Returns: ValidationResult indicating if move is valid and why
    static func validateMove(from: String, to: String, boardState: BoardState) -> ValidationResult {
        // Parse coordinates
        guard from.count == 2, to.count == 2,
              let fromFile = Int(String(from.prefix(1))),
              let fromRank = Int(String(from.suffix(1))),
              let toFile = Int(String(to.prefix(1))),
              let toRank = Int(String(to.suffix(1))) else {
            return .invalid("Invalid coordinate format")
        }
        
        // Convert to board coordinates (0-7)
        let fromRow = 8 - fromRank
        let fromCol = fromFile - 1
        let toRow = 8 - toRank
        let toCol = toFile - 1
        
        // Check if coordinates are in bounds
        guard fromRow >= 0 && fromRow < 8 && fromCol >= 0 && fromCol < 8,
              toRow >= 0 && toRow < 8 && toCol >= 0 && toCol < 8 else {
            return .invalid("Move out of bounds")
        }
        
        // Check if there's a piece at the starting position
        guard let piece = boardState.pieceAt(row: fromRow, col: fromCol) else {
            return .invalid("No piece at starting position")
        }
        
        // Check if it's the correct player's piece
        guard boardState.isOwnPiece(row: fromRow, col: fromCol) else {
            return .invalid("Not your piece")
        }
        
        // Check if destination doesn't have own piece
        if boardState.isOwnPiece(row: toRow, col: toCol) {
            return .invalid("Cannot capture your own piece")
        }
        
        // Validate move based on piece type
        let pieceType = piece.lowercased()
        let isCapture = boardState.isOpponentPiece(row: toRow, col: toCol)
        
        switch pieceType {
        case "p":
            return validatePawnMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, isCapture: isCapture, boardState: boardState)
        case "n":
            return validateKnightMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol)
        case "b":
            return validateBishopMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        case "r":
            return validateRookMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        case "q":
            return validateQueenMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        case "k":
            return validateKingMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol)
        default:
            return .invalid("Unknown piece type")
        }
    }
    
    // MARK: - Piece-Specific Validation
    
    private static func validatePawnMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, isCapture: Bool, boardState: BoardState) -> ValidationResult {
        let direction = boardState.isWhiteTurn ? -1 : 1 // White moves up (decreasing row), black moves down
        let startRow = boardState.isWhiteTurn ? 6 : 1
        
        let rowDiff = toRow - fromRow
        let colDiff = abs(toCol - fromCol)
        
        // Moving forward
        if colDiff == 0 {
            if isCapture {
                return .invalid("Pawns cannot capture forward")
            }
            
            // Single square forward
            if rowDiff == direction {
                return .valid
            }
            
            // Two squares forward from starting position
            if rowDiff == 2 * direction && fromRow == startRow {
                // Check if path is clear
                let middleRow = fromRow + direction
                if !boardState.isEmpty(row: middleRow, col: fromCol) {
                    return .invalid("Path is blocked")
                }
                return .valid
            }
            
            return .invalid("Invalid pawn move")
        }
        
        // Diagonal capture
        if colDiff == 1 && rowDiff == direction {
            if isCapture {
                return .valid
            }
            // TODO: En passant would go here
            return .invalid("Pawns can only move diagonally when capturing")
        }
        
        return .invalid("Invalid pawn move")
    }
    
    private static func validateKnightMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int) -> ValidationResult {
        let rowDiff = abs(toRow - fromRow)
        let colDiff = abs(toCol - fromCol)
        
        // Knight moves in L-shape: 2+1 or 1+2
        if (rowDiff == 2 && colDiff == 1) || (rowDiff == 1 && colDiff == 2) {
            return .valid
        }
        
        return .invalid("Invalid knight move")
    }
    
    private static func validateBishopMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> ValidationResult {
        let rowDiff = abs(toRow - fromRow)
        let colDiff = abs(toCol - fromCol)
        
        // Bishop moves diagonally
        guard rowDiff == colDiff && rowDiff > 0 else {
            return .invalid("Bishops move diagonally")
        }
        
        // Check if path is clear
        if !isDiagonalPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState) {
            return .invalid("Path is blocked")
        }
        
        return .valid
    }
    
    private static func validateRookMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> ValidationResult {
        // Rook moves horizontally or vertically
        guard fromRow == toRow || fromCol == toCol else {
            return .invalid("Rooks move horizontally or vertically")
        }
        
        guard fromRow != toRow || fromCol != toCol else {
            return .invalid("Must move to a different square")
        }
        
        // Check if path is clear
        if !isStraightPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState) {
            return .invalid("Path is blocked")
        }
        
        return .valid
    }
    
    private static func validateQueenMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> ValidationResult {
        let rowDiff = abs(toRow - fromRow)
        let colDiff = abs(toCol - fromCol)
        
        // Queen moves like rook or bishop
        let isDiagonal = rowDiff == colDiff && rowDiff > 0
        let isStraight = (fromRow == toRow || fromCol == toCol) && (fromRow != toRow || fromCol != toCol)
        
        guard isDiagonal || isStraight else {
            return .invalid("Queens move diagonally or straight")
        }
        
        // Check if path is clear
        if isDiagonal {
            if !isDiagonalPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState) {
                return .invalid("Path is blocked")
            }
        } else {
            if !isStraightPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState) {
                return .invalid("Path is blocked")
            }
        }
        
        return .valid
    }
    
    private static func validateKingMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int) -> ValidationResult {
        let rowDiff = abs(toRow - fromRow)
        let colDiff = abs(toCol - fromCol)
        
        // King moves one square in any direction
        guard rowDiff <= 1 && colDiff <= 1 && (rowDiff + colDiff) > 0 else {
            return .invalid("Kings move one square in any direction")
        }
        
        // TODO: Castling would go here
        
        return .valid
    }
    
    // MARK: - Path Checking Helpers
    
    private static func isStraightPathClear(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> Bool {
        if fromRow == toRow {
            // Horizontal movement
            let minCol = min(fromCol, toCol)
            let maxCol = max(fromCol, toCol)
            for col in (minCol + 1)..<maxCol {
                if !boardState.isEmpty(row: fromRow, col: col) {
                    return false
                }
            }
        } else {
            // Vertical movement
            let minRow = min(fromRow, toRow)
            let maxRow = max(fromRow, toRow)
            for row in (minRow + 1)..<maxRow {
                if !boardState.isEmpty(row: row, col: fromCol) {
                    return false
                }
            }
        }
        return true
    }
    
    private static func isDiagonalPathClear(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> Bool {
        let rowStep = toRow > fromRow ? 1 : -1
        let colStep = toCol > fromCol ? 1 : -1
        
        var currentRow = fromRow + rowStep
        var currentCol = fromCol + colStep
        
        while currentRow != toRow && currentCol != toCol {
            if !boardState.isEmpty(row: currentRow, col: currentCol) {
                return false
            }
            currentRow += rowStep
            currentCol += colStep
        }
        
        return true
    }
    
    // MARK: - Validation Result
    
    enum ValidationResult {
        case valid
        case invalid(String)
        
        var isValid: Bool {
            if case .valid = self {
                return true
            }
            return false
        }
        
        var errorMessage: String? {
            if case .invalid(let message) = self {
                return message
            }
            return nil
        }
    }
}

// MARK: - Extension for parsing board from JavaScript result

extension ChessMoveValidator.BoardState {
    /// Create a board state from the JavaScript scrapeScript result
    static func from(scriptResult: [String: Any]) -> ChessMoveValidator.BoardState? {
        guard let boardArray = scriptResult["board"] as? [[String]],
              let isWhiteSide = scriptResult["isWhiteSide"] as? Bool else {
            return nil
        }
        
        return ChessMoveValidator.BoardState(board: boardArray, isWhiteTurn: isWhiteSide)
    }
}
