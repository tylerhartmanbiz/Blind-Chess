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
        var canWhiteCastleKingside: Bool
        var canWhiteCastleQueenside: Bool
        var canBlackCastleKingside: Bool
        var canBlackCastleQueenside: Bool
        var enPassantTarget: String? // e.g., "e3" if a pawn just moved from e2 to e4
        
        init(board: [[String]], isWhiteTurn: Bool, 
             canWhiteCastleKingside: Bool = true, 
             canWhiteCastleQueenside: Bool = true,
             canBlackCastleKingside: Bool = true,
             canBlackCastleQueenside: Bool = true,
             enPassantTarget: String? = nil) {
            self.board = board
            self.isWhiteTurn = isWhiteTurn
            self.canWhiteCastleKingside = canWhiteCastleKingside
            self.canWhiteCastleQueenside = canWhiteCastleQueenside
            self.canBlackCastleKingside = canBlackCastleKingside
            self.canBlackCastleQueenside = canBlackCastleQueenside
            self.enPassantTarget = enPassantTarget
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
        
        /// Make a move on the board (mutating)
        mutating func makeMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int) {
            let piece = board[fromRow][fromCol]
            board[toRow][toCol] = piece
            board[fromRow][fromCol] = ""
        }
        
        /// Find the king's position for a given color
        func findKing(forWhite: Bool) -> (row: Int, col: Int)? {
            let kingChar = forWhite ? "K" : "k"
            for row in 0..<8 {
                for col in 0..<8 {
                    if board[row][col] == kingChar {
                        return (row, col)
                    }
                }
            }
            return nil
        }
        
        /// Count pieces on the board for the current player
        func countPieces() -> [String: Int] {
            var counts: [String: Int] = [:]
            
            for row in 0..<8 {
                for col in 0..<8 {
                    if let piece = pieceAt(row: row, col: col), isWhitePiece(piece) == isWhiteTurn {
                        let pieceType = piece.uppercased()
                        counts[pieceType, default: 0] += 1
                    }
                }
            }
            
            return counts
        }
        
        /// Find all pieces of a type that belong to the current player
        func findPieces(ofType pieceType: String) -> [(row: Int, col: Int)] {
            var positions: [(row: Int, col: Int)] = []
            let targetPiece = isWhiteTurn ? pieceType.uppercased() : pieceType.lowercased()
            
            for row in 0..<8 {
                for col in 0..<8 {
                    if board[row][col] == targetPiece {
                        positions.append((row, col))
                    }
                }
            }
            
            return positions
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
        
        let basicValidation: ValidationResult
        switch pieceType {
        case "p":
            basicValidation = validatePawnMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, isCapture: isCapture, boardState: boardState)
        case "n":
            basicValidation = validateKnightMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol)
        case "b":
            basicValidation = validateBishopMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        case "r":
            basicValidation = validateRookMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        case "q":
            basicValidation = validateQueenMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        case "k":
            basicValidation = validateKingMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        default:
            return .invalid("Unknown piece type")
        }
        
        // If basic move is invalid, return immediately
        if !basicValidation.isValid {
            return basicValidation
        }
        
        // Simulate the move and check if it leaves/puts king in check
        var simulatedState = boardState
        simulatedState.makeMove(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol)
        
        if isKingInCheck(boardState: simulatedState, forWhite: boardState.isWhiteTurn) {
            return .invalid("Move leaves king in check")
        }
        
        // For king moves, also check if moving into an attacked square
        if pieceType == "k" {
            if isSquareUnderAttack(row: toRow, col: toCol, boardState: boardState, byWhite: !boardState.isWhiteTurn) {
                return .invalid("Cannot move king into check")
            }
        }
        
        return .valid
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
            
            // Check for en passant
            if let enPassantTarget = boardState.enPassantTarget {
                // Convert target square (e.g., "e3") to row/col
                let targetFile = Int(enPassantTarget.lowercased().unicodeScalars.first!.value) - 96 // a=1
                let targetRank = Int(String(enPassantTarget.suffix(1)))!
                let targetRow = 8 - targetRank
                let targetCol = targetFile - 1
                
                // Check if this move is to the en passant target square
                if toRow == targetRow && toCol == targetCol {
                    print("  ✅ En passant capture detected")
                    return .valid
                }
            }
            
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
    
    private static func validateKingMove(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> ValidationResult {
        let rowDiff = abs(toRow - fromRow)
        let colDiff = abs(toCol - fromCol)
        
        // Check for castling (king moves 2 squares horizontally)
        if rowDiff == 0 && colDiff == 2 {
            return validateCastling(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
        }
        
        // King moves one square in any direction
        guard rowDiff <= 1 && colDiff <= 1 && (rowDiff + colDiff) > 0 else {
            return .invalid("Kings move one square in any direction")
        }
        
        return .valid
    }
    
    private static func validateCastling(fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> ValidationResult {
        // Castling only on back rank
        let expectedRow = boardState.isWhiteTurn ? 7 : 0
        guard fromRow == expectedRow && toRow == expectedRow else {
            return .invalid("Cannot castle from this position")
        }
        
        // King must start on e-file (column 4)
        guard fromCol == 4 else {
            return .invalid("King not in starting position")
        }
        
        let isKingside = toCol > fromCol
        
        // Check castling rights
        if boardState.isWhiteTurn {
            if isKingside && !boardState.canWhiteCastleKingside {
                return .invalid("White cannot castle kingside")
            }
            if !isKingside && !boardState.canWhiteCastleQueenside {
                return .invalid("White cannot castle queenside")
            }
        } else {
            if isKingside && !boardState.canBlackCastleKingside {
                return .invalid("Black cannot castle kingside")
            }
            if !isKingside && !boardState.canBlackCastleQueenside {
                return .invalid("Black cannot castle queenside")
            }
        }
        
        // King cannot be in check
        if isKingInCheck(boardState: boardState, forWhite: boardState.isWhiteTurn) {
            return .invalid("Cannot castle while in check")
        }
        
        // Check path is clear and not under attack
        if isKingside {
            // Kingside: check f and g files (columns 5 and 6)
            // Rook should be on h file (column 7)
            guard boardState.isEmpty(row: fromRow, col: 5) && 
                  boardState.isEmpty(row: fromRow, col: 6) else {
                return .invalid("Path is blocked")
            }
            
            // Verify rook is there
            let rookChar = boardState.isWhiteTurn ? "R" : "r"
            guard boardState.pieceAt(row: fromRow, col: 7) == rookChar else {
                return .invalid("Rook not in position")
            }
            
            // King cannot move through check (f and g squares)
            if isSquareUnderAttack(row: fromRow, col: 5, boardState: boardState, byWhite: !boardState.isWhiteTurn) ||
               isSquareUnderAttack(row: fromRow, col: 6, boardState: boardState, byWhite: !boardState.isWhiteTurn) {
                return .invalid("Cannot castle through check")
            }
        } else {
            // Queenside: check b, c, and d files (columns 1, 2, and 3)
            // Rook should be on a file (column 0)
            guard boardState.isEmpty(row: fromRow, col: 1) && 
                  boardState.isEmpty(row: fromRow, col: 2) &&
                  boardState.isEmpty(row: fromRow, col: 3) else {
                return .invalid("Path is blocked")
            }
            
            // Verify rook is there
            let rookChar = boardState.isWhiteTurn ? "R" : "r"
            guard boardState.pieceAt(row: fromRow, col: 0) == rookChar else {
                return .invalid("Rook not in position")
            }
            
            // King cannot move through check (c and d squares)
            if isSquareUnderAttack(row: fromRow, col: 2, boardState: boardState, byWhite: !boardState.isWhiteTurn) ||
               isSquareUnderAttack(row: fromRow, col: 3, boardState: boardState, byWhite: !boardState.isWhiteTurn) {
                return .invalid("Cannot castle through check")
            }
        }
        
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
    
    // MARK: - Check Detection
    
    /// Check if the king is in check
    private static func isKingInCheck(boardState: BoardState, forWhite: Bool) -> Bool {
        guard let kingPos = boardState.findKing(forWhite: forWhite) else {
            return false // No king found (shouldn't happen)
        }
        
        return isSquareUnderAttack(row: kingPos.row, col: kingPos.col, boardState: boardState, byWhite: !forWhite)
    }
    
    /// Check if a square is under attack by the specified color
    private static func isSquareUnderAttack(row: Int, col: Int, boardState: BoardState, byWhite: Bool) -> Bool {
        // Check all opponent pieces to see if they can attack this square
        for r in 0..<8 {
            for c in 0..<8 {
                guard let piece = boardState.pieceAt(row: r, col: c) else { continue }
                
                // Check if this is an opponent piece
                if boardState.isWhitePiece(piece) != byWhite { continue }
                
                // Check if this piece can attack the target square
                if canPieceAttack(piece: piece, fromRow: r, fromCol: c, toRow: row, toCol: col, boardState: boardState) {
                    return true
                }
            }
        }
        
        return false
    }
    
    /// Check if a piece can attack a specific square
    private static func canPieceAttack(piece: String, fromRow: Int, fromCol: Int, toRow: Int, toCol: Int, boardState: BoardState) -> Bool {
        let pieceType = piece.lowercased()
        let rowDiff = abs(toRow - fromRow)
        let colDiff = abs(toCol - fromCol)
        
        switch pieceType {
        case "p":
            // Pawns attack diagonally
            let direction = boardState.isWhitePiece(piece) ? -1 : 1
            return (toRow - fromRow == direction) && colDiff == 1
            
        case "n":
            // Knight L-shape
            return (rowDiff == 2 && colDiff == 1) || (rowDiff == 1 && colDiff == 2)
            
        case "b":
            // Bishop diagonal
            if rowDiff != colDiff || rowDiff == 0 { return false }
            return isDiagonalPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
            
        case "r":
            // Rook straight
            if fromRow != toRow && fromCol != toCol { return false }
            if fromRow == toRow && fromCol == toCol { return false }
            return isStraightPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
            
        case "q":
            // Queen diagonal or straight
            let isDiag = rowDiff == colDiff && rowDiff > 0
            let isStraight = (fromRow == toRow || fromCol == toCol) && (fromRow != toRow || fromCol != toCol)
            
            if isDiag {
                return isDiagonalPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
            } else if isStraight {
                return isStraightPathClear(fromRow: fromRow, fromCol: fromCol, toRow: toRow, toCol: toCol, boardState: boardState)
            }
            return false
            
        case "k":
            // King one square
            return rowDiff <= 1 && colDiff <= 1 && (rowDiff + colDiff) > 0
            
        default:
            return false
        }
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
    
    // MARK: - Disambiguation Support
    
    /// Find all pieces that can legally move to a target square
    /// - Parameters:
    ///   - to: Target position as "xy" (e.g., "54" for e4)
    ///   - pieceType: Optional piece type filter ("P", "N", "B", "R", "Q", "K")
    ///   - boardState: Current board state
    /// - Returns: Array of valid source positions that can move to the target
    static func findValidMovesTo(to: String, pieceType: String?, boardState: BoardState) -> [(from: String, piece: String, fileChar: String, rank: String)] {
        guard to.count == 2,
              let toFile = Int(String(to.prefix(1))),
              let toRank = Int(String(to.suffix(1))) else {
            return []
        }
        
        let toRow = 8 - toRank
        let toCol = toFile - 1
        
        guard toRow >= 0 && toRow < 8 && toCol >= 0 && toCol < 8 else {
            return []
        }
        
        var validMoves: [(from: String, piece: String, fileChar: String, rank: String)] = []
        
        // If piece type is specified, only check those pieces
        let piecesToCheck: [String]
        if let type = pieceType {
            piecesToCheck = [pieceLetter(for: type)]
        } else {
            piecesToCheck = ["P", "N", "B", "R", "Q", "K"]
        }
        
        for pieceChar in piecesToCheck {
            let positions = boardState.findPieces(ofType: pieceChar)
            
            for pos in positions {
                let fromFile = pos.col + 1
                let fromRank = 8 - pos.row
                let fromSquare = "\(fromFile)\(fromRank)"
                
                // Validate this move
                let validation = validateMove(from: fromSquare, to: to, boardState: boardState)
                
                if validation.isValid {
                    let pieceName = pieceTypeName(pieceChar)
                    let files = ["a", "b", "c", "d", "e", "f", "g", "h"]
                    let fileCharacter = files[fromFile - 1]
                    validMoves.append((from: fromSquare, piece: pieceName, fileChar: fileCharacter, rank: "\(fromRank)"))
                }
            }
        }
        
        return validMoves
    }
    
    /// Analyze if multiple pieces can reach the target and determine disambiguation needed
    static func analyzeAmbiguity(validMoves: [(from: String, piece: String, fileChar: String, rank: String)]) -> DisambiguationType {
        guard validMoves.count > 1 else { return .none }
        
        // Extract files and ranks
        let files = validMoves.map { $0.fileChar }
        let ranks = validMoves.map { $0.rank }
        
        let uniqueFiles = Set(files)
        let uniqueRanks = Set(ranks)
        
        // If all pieces are on different files, ask for file
        if uniqueFiles.count == validMoves.count {
            return .needFile
        }
        
        // If all pieces are on different ranks, ask for rank
        if uniqueRanks.count == validMoves.count {
            return .needRank
        }
        
        // Mixed situation - need both file and rank (or exact square)
        return .needBoth
    }
    
    /// Convert piece character to human-readable name
    private static func pieceTypeName(_ char: String) -> String {
        switch char.uppercased() {
        case "P": return "Pawn"
        case "N": return "Knight"
        case "B": return "Bishop"
        case "R": return "Rook"
        case "Q": return "Queen"
        case "K": return "King"
        default: return "Piece"
        }
    }

    /// Convert a piece name ("Pawn", "pawn") or letter code ("P", "p") to its single-letter code
    private static func pieceLetter(for name: String) -> String {
        switch name.uppercased() {
        case "PAWN", "P": return "P"
        case "KNIGHT", "N": return "N"
        case "BISHOP", "B": return "B"
        case "ROOK", "R": return "R"
        case "QUEEN", "Q": return "Q"
        case "KING", "K": return "K"
        default: return name.uppercased()
        }
    }
    
    enum DisambiguationType {
        case none
        case needFile
        case needRank
        case needBoth
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
        
        // Get en passant target if available
        let enPassantTarget = scriptResult["enPassantTarget"] as? String
        
        if let target = enPassantTarget {
            print("  🎯 En passant target detected: \(target)")
        }
        
        // Detect castling rights based on piece positions
        // If king and rooks are in starting positions, assume castling is available
        let whiteKingOnE1 = boardArray[7][4] == "K"
        let whiteRookOnH1 = boardArray[7][7] == "R"
        let whiteRookOnA1 = boardArray[7][0] == "R"
        
        let blackKingOnE8 = boardArray[0][4] == "k"
        let blackRookOnH8 = boardArray[0][7] == "r"
        let blackRookOnA8 = boardArray[0][0] == "r"
        
        let canWhiteCastleKingside = whiteKingOnE1 && whiteRookOnH1
        let canWhiteCastleQueenside = whiteKingOnE1 && whiteRookOnA1
        let canBlackCastleKingside = blackKingOnE8 && blackRookOnH8
        let canBlackCastleQueenside = blackKingOnE8 && blackRookOnA8
        
        return ChessMoveValidator.BoardState(
            board: boardArray, 
            isWhiteTurn: isWhiteSide,
            canWhiteCastleKingside: canWhiteCastleKingside,
            canWhiteCastleQueenside: canWhiteCastleQueenside,
            canBlackCastleKingside: canBlackCastleKingside,
            canBlackCastleQueenside: canBlackCastleQueenside,
            enPassantTarget: enPassantTarget
        )
    }
}
