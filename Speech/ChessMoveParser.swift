//
//  ChessMoveParser.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import Foundation

struct ChessMoveParser {
    
    /// Parse transcript and extract chess piece and move
    static func parse(transcript: String) -> ParsedMove? {
        guard !transcript.isEmpty else { return nil }
        
        let lowercased = transcript.lowercased()
        print("🔍 Parsing: \(transcript)")
        
        // Check for castling commands first
        if let castleMove = parseCastling(in: lowercased) {
            print("✅ Parsed castling: \(castleMove.description)")
            return castleMove
        }
        
        var piece: String? = nil
        var file: String? = nil
        var rank: String? = nil
        
        // Parse piece
        piece = findPiece(in: lowercased)
        
        // Parse file (a-h)
        file = findFile(in: lowercased)
        
        // Parse rank (1-8)
        rank = findRank(in: lowercased)
        
        // Must have at least file and rank
        guard let finalFile = file, let finalRank = rank else {
            print("❌ Parse failed - file: \(file ?? "nil"), rank: \(rank ?? "nil")")
            return nil
        }
        
        let parsedMove = ParsedMove(piece: piece, file: finalFile, rank: finalRank)
        print("✅ Parsed: \(parsedMove.description)")
        return parsedMove
    }
    
    // MARK: - Parse Castling
    
    private static func parseCastling(in text: String) -> ParsedMove? {
        // Check for castling keywords
        let hasCastle = text.contains("castle") || text.contains("kassle") || text.contains("cassel")
        guard hasCastle else { return nil }
        
        // Check for queenside
        let isQueenside = text.contains("queen") || text.contains("queenside") || 
                          text.contains("long") || text.contains("left")
        
        if isQueenside {
            // Queenside castling: King e1 -> c1 (or e8 -> c8 for black)
            // Determine if white or black based on rank in text, default to white (rank 1)
            let rank = text.contains("8") ? "8" : "1"
            print("  🏰 Detected queenside castling")
            return ParsedMove(piece: "King", file: "c", rank: rank)
        } else {
            // Kingside castling (default): King e1 -> g1 (or e8 -> g8 for black)
            let rank = text.contains("8") ? "8" : "1"
            print("  🏰 Detected kingside castling")
            return ParsedMove(piece: "King", file: "g", rank: rank)
        }
    }
    
    // MARK: - Find Piece
    
    private static func findPiece(in text: String) -> String? {
        // Dictionary of "sounds like" -> actual piece
        let pieceMap: [String: String] = [
            // Pawn variations
            "pawn": "Pawn", "pawns": "Pawn", "paw": "Pawn", "on": "Pawn",
            "pond": "Pawn", "porn": "Pawn", "palm": "Pawn", "pawne": "Pawn",
            "pon": "Pawn", "pahn": "Pawn",
            
            // Rook variations
            "rook": "Rook", "rooks": "Rook", "brook": "Rook", "rock": "Rook",
            "roc": "Rook", "rue": "Rook",
            
            // Knight variations
            "knight": "Knight", "knights": "Knight", "night": "Knight",
            "nite": "Knight", "nights": "Knight", "knite": "Knight",
            
            // Bishop variations
            "bishop": "Bishop", "bishops": "Bishop", "bishup": "Bishop",
            "bish": "Bishop", "bishep": "Bishop",
            
            // Queen variations
            "queen": "Queen", "queens": "Queen", "quin": "Queen",
            "quean": "Queen", "kween": "Queen",
            
            // King variations
            "king": "King", "kings": "King", "keen": "King",
            "kin": "King"
        ]
        
        // Check each word in the text
        let words = text.split(separator: " ")
        for word in words {
            let cleanWord = String(word).trimmingCharacters(in: .punctuationCharacters)
            if let piece = pieceMap[cleanWord] {
                print("  🔸 Found piece: \(piece) (from '\(cleanWord)')")
                return piece
            }
        }
        
        print("  ⚪️ No piece found")
        return nil
    }
    
    // MARK: - Find File (A-H)
    
    private static func findFile(in text: String) -> String? {
        // Dictionary of "sounds like" -> actual file
        let fileMap: [String: String] = [
            "a": "a", "alpha": "a", "able": "a", "hey": "a", "aye": "a", "ay": "a",
            "b": "b", "bravo": "b", "be": "b", "bee": "b", "bea": "b",
            "c": "c", "charlie": "c", "sea": "c", "see": "c", "si": "c",
            "d": "d", "delta": "d", "dee": "d", "di": "d",
            "e": "e", "echo": "e", "ee": "e",
            "f": "f", "foxtrot": "f", "ef": "f",
            "g": "g", "golf": "g", "gee": "g", "jee": "g",
            "h": "h", "hotel": "h", "aych": "h", "aitch": "h"
        ]
        
        // First, check for combined notation like "e4", "a5"
        let pattern = "([a-h])([1-8])"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let fileRange = Range(match.range(at: 1), in: text) {
                let file = String(text[fileRange])
                print("  🔹 Found file: \(file.uppercased()) (from combined notation)")
                return file
            }
        }
        
        // Check each word
        let words = text.split(separator: " ")
        for word in words {
            let cleanWord = String(word).trimmingCharacters(in: .punctuationCharacters)
            if let file = fileMap[cleanWord] {
                print("  🔹 Found file: \(file.uppercased()) (from '\(cleanWord)')")
                return file
            }
        }
        
        print("  ⚪️ No file found")
        return nil
    }
    
    // MARK: - Find Rank (1-8)
    
    private static func findRank(in text: String) -> String? {
        // Dictionary of "sounds like" -> actual rank
        let rankMap: [String: String] = [
            "1": "1", "one": "1", "won": "1", "wan": "1",
            "2": "2", "two": "2", "to": "2", "too": "2", "tu": "2",
            "3": "3", "three": "3", "tree": "3", "free": "3",
            "4": "4", "four": "4", "for": "4", "fore": "4", "fir": "4",
            "5": "5", "five": "5", "fiv": "5",
            "6": "6", "six": "6", "sicks": "6",
            "7": "7", "seven": "7", "sevn": "7",
            "8": "8", "eight": "8", "ate": "8", "ait": "8"
        ]
        
        // First, check for combined notation like "e4", "a5"
        let pattern = "([a-h])([1-8])"
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let rankRange = Range(match.range(at: 2), in: text) {
                let rank = String(text[rankRange])
                print("  🔺 Found rank: \(rank) (from combined notation)")
                return rank
            }
        }
        
        // Check each word
        let words = text.split(separator: " ")
        for word in words {
            let cleanWord = String(word).trimmingCharacters(in: .punctuationCharacters)
            if let rank = rankMap[cleanWord] {
                print("  🔺 Found rank: \(rank) (from '\(cleanWord)')")
                return rank
            }
        }
        
        print("  ⚪️ No rank found")
        return nil
    }
}

// MARK: - Parsed Move Result

struct ParsedMove {
    let piece: String?  // "Pawn", "Rook", "Knight", "Bishop", "Queen", "King" (or nil)
    let file: String    // "a" through "h"
    let rank: String    // "1" through "8"
    
    var description: String {
        let pieceName = piece ?? "Piece"
        return "\(pieceName) → \(file.uppercased())\(rank)"
    }
    
    /// Chess.com coordinate format (e.g., "e4" -> "54")
    var coordinate: String {
        let fileNum = Int(file.uppercased().unicodeScalars.first!.value) - 64 // A=1, B=2, etc.
        return "\(fileNum)\(rank)"
    }
}
