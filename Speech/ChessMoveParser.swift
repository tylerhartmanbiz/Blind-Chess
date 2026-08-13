//
//  ChessMoveParser.swift
//  Blind Chess
//
//  Created by Tyler Hartman on 8/13/26.
//

import Foundation

struct ChessMoveParser {
    
    // Parse spoken text into chess coordinates
    static func parseMove(from transcript: String) -> ChessMove? {
        let lowercased = transcript.lowercased()
        let words = lowercased.components(separatedBy: .whitespacesAndNewlines)
        
        var piece: String? = nil
        var file: String? = nil
        var rank: String? = nil
        
        // Piece mappings
        let pieceMap = [
            "pawn": "p", "pond": "p", "porn": "p", "palm": "p",
            "rook": "r", "brook": "r", "rock": "r",
            "knight": "n", "night": "n", "nite": "n",
            "bishop": "b", "bishup": "b",
            "queen": "q", "quin": "q",
            "king": "k"
        ]
        
        // File mappings (letters A-H)
        let fileMap = [
            "a": "a", "alpha": "a", "able": "a", "hey": "a",
            "b": "b", "bravo": "b", "be": "b", "bee": "b",
            "c": "c", "charlie": "c", "sea": "c", "see": "c",
            "d": "d", "delta": "d", "dee": "d",
            "e": "e", "echo": "e",
            "f": "f", "foxtrot": "f",
            "g": "g", "golf": "g", "gee": "g",
            "h": "h", "hotel": "h"
        ]
        
        // Rank mappings (numbers 1-8)
        let rankMap = [
            "1": "1", "one": "1", "won": "1",
            "2": "2", "two": "2", "to": "2", "too": "2",
            "3": "3", "three": "3", "tree": "3",
            "4": "4", "four": "4", "for": "4", "fore": "4",
            "5": "5", "five": "5",
            "6": "6", "six": "6",
            "7": "7", "seven": "7",
            "8": "8", "eight": "8", "ate": "8"
        ]
        
        // Parse words
        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters)
            
            // Check for piece
            if piece == nil, let p = pieceMap[cleanWord] {
                piece = p
            }
            
            // Check for file
            if file == nil, let f = fileMap[cleanWord] {
                file = f
            }
            
            // Check for rank
            if rank == nil, let r = rankMap[cleanWord] {
                rank = r
            }
        }
        
        // Must have file and rank at minimum
        guard let f = file, let r = rank else {
            return nil
        }
        
        return ChessMove(piece: piece, file: f, rank: r)
    }
    
    // Convert file (a-h) and rank (1-8) to chess.com coordinate format (11-88)
    static func toChessComCoordinate(file: String, rank: String) -> String {
        let fileNum = Int(file.uppercased().unicodeScalars.first!.value) - 64 // A=1, B=2, etc.
        return "\(fileNum)\(rank)"
    }
}

struct ChessMove {
    let piece: String? // p, r, n, b, q, k (or nil for any piece)
    let file: String   // a-h
    let rank: String   // 1-8
    
    var coordinate: String {
        return ChessMoveParser.toChessComCoordinate(file: file, rank: rank)
    }
    
    var description: String {
        let pieceName = piece?.uppercased() ?? "Piece"
        return "\(pieceName) to \(file.uppercased())\(rank)"
    }
}
