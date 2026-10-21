//
//  Notation.swift
//  Blind Chess core
//
//  Standard Algebraic Notation and UCI for `Position`.
//
//  Public API:
//    san(_ move:) -> String          "Nbd2", "exd5", "e8=Q+", "O-O-O", "Qh4#"
//    move(san:) -> Move?             tolerant: ignores +, #, !, ?, "x", "=", accepts 0-0, "e8Q", lowercase pieces
//                                    except b (b is the b-file), and over-specified moves like "Ng1f3"
//    move(uci:) -> Move?             "e2e4", "e7e8q"
//

import Foundation

extension Position {
    public func san(_ move: Move) -> String {
        sanWithoutSuffix(move, among: legalMoves()) + checkSuffix(after: move)
    }

    public func move(uci: String) -> Move? {
        let text = uci.lowercased().trimmingCharacters(in: .whitespaces)
        return legalMoves().first { $0.uci == text }
    }

    public func move(san: String) -> Move? {
        let wanted = Position.normalizedSAN(san)
        guard !wanted.isEmpty else { return nil }
        let moves = legalMoves()
        if let exact = moves.first(where: { Position.normalizedSAN(sanWithoutSuffix($0, among: moves)) == wanted }) {
            return exact
        }
        // Over-specified forms such as "Ng1f3" or "Pe2e4" reduce to plain UCI once the piece letter is dropped.
        let longForm = wanted.drop { "PNBRQK".contains($0) }.lowercased()
        return moves.first { Position.normalizedSAN($0.uci).lowercased() == longForm }
    }

    // MARK: - Helpers

    func sanWithoutSuffix(_ move: Move, among legal: [Move]) -> String {
        if let side = move.castle { return side == .kingside ? "O-O" : "O-O-O" }
        var text = ""
        if move.piece == .pawn {
            if move.isCapture { text.append(move.from.fileLetter) }
        } else {
            text.append(move.piece.letter)
            let rivals = legal.filter {
                $0.piece == move.piece && $0.to == move.to && $0.from != move.from
            }
            if !rivals.isEmpty {
                if !rivals.contains(where: { $0.from.file == move.from.file }) {
                    text.append(move.from.fileLetter)
                } else if !rivals.contains(where: { $0.from.rank == move.from.rank }) {
                    text += String(move.from.rank + 1)
                } else {
                    text += move.from.name
                }
            }
        }
        if move.isCapture { text += "x" }
        text += move.to.name
        if let promotion = move.promotion { text += "=\(promotion.letter)" }
        return text
    }

    func checkSuffix(after move: Move) -> String {
        let next = playing(move)
        guard next.isCheck else { return "" }
        return next.legalMoves().isEmpty ? "#" : "+"
    }

    /// Strips decorations so that "exd5", "ed5", "Nxe5+", "e8=Q" and "e8Q" compare equal to the generated SAN.
    private static func normalizedSAN(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "0", with: "O")
        result.removeAll { "+#!?x=:-".contains($0) }
        if result.uppercased() == "OO" { return "OO" }
        if result.uppercased() == "OOO" { return "OOO" }
        // Lowercase piece letters ("nf3") are accepted, but a lowercase b always means the b-file.
        if let first = result.first, "nrqk".contains(first) {
            result = first.uppercased() + result.dropFirst()
        }
        // A trailing promotion letter must be uppercase ("e8q" -> "e8Q").
        if let last = result.last, "nbrq".contains(last), result.count >= 3 {
            result = result.dropLast() + last.uppercased()
        }
        return result
    }
}
