import XCTest
@testable import BlindChessCore

/// Compact rendering of an interpretation: "Nf3", "e4" (piece unspecified), "Pexd5", "N1e2", "e8=Q", "O-O",
/// "castle", or "cmd:undo".
func render(_ intent: SpokenIntent) -> String {
    switch intent {
    case .command(let command): return render(command)
    case .move(let move):
        if move.isCastle {
            switch move.castleSide {
            case .kingside?: return "O-O"
            case .queenside?: return "O-O-O"
            case nil: return "castle"
            }
        }
        var text = move.piece.map { String($0.letter) } ?? ""
        if let file = move.fromFile { text.append(Square.fileLetters[file]) }
        if let rank = move.fromRank { text += String(rank + 1) }
        if move.isCapture { text += "x" }
        if let file = move.toFile { text.append(Square.fileLetters[file]) }
        if let rank = move.toRank { text += String(rank + 1) }
        if let promotion = move.promotion { text += "=\(promotion.letter)" }
        return text
    }
}

func topReading(_ transcript: String) -> String {
    SpokenMoveParser.parse(transcript).first.map { render($0.intent) } ?? "nil"
}

/// Compact rendering of a resolution: SAN for moves, "?a|b" for clarification (SAN of candidates),
/// "!reason" for illegal, "cmd:x" for commands, "nil" for not understood. Sound-alike moves get a "~" prefix.
func render(_ resolution: Resolution, in position: Position) -> String {
    switch resolution {
    case .move(let resolved): return (resolved.usedSoundAlike ? "~" : "") + resolved.san
    case .needsClarification(let clarification):
        return "?" + clarification.candidates.map { position.san($0) }.sorted().joined(separator: "|")
    case .command(let command): return render(command)
    case .illegal(let reason): return "!" + reason
    case .notUnderstood: return "nil"
    }
}

func position(_ fen: String, file: StaticString = #filePath, line: UInt = #line) -> Position {
    guard let position = Position(fen: fen) else {
        XCTFail("bad FEN \(fen)", file: file, line: line)
        return .start
    }
    return position
}

/// "cmd:undo", "cmd:locate queen mine", "cmd:square e4", "cmd:list opponent".
func render(_ command: SpokenCommand) -> String {
    func owner(_ owner: PieceOwner) -> String {
        switch owner {
        case .mine: return "mine"
        case .opponent: return "opponent"
        case .color(let color): return color.name
        }
    }
    switch command {
    case .locate(let kind, let who): return "cmd:locate \(kind.name) \(owner(who))"
    case .listPieces(let who): return "cmd:list \(owner(who))"
    case .describeSquare(let square): return "cmd:square \(square.name)"
    default: return "cmd:\(command)"
    }
}
