import XCTest
@testable import BlindChessCore

/// Table-driven checks of the parser's best reading. Notation (see `render`): "Nf3", "e4" = piece unspecified,
/// "Pe4" = pawn named, "Rad1"/"N1e2" = origin file/rank, "x" = capture, "=Q" = promotion, "O-O", "castle", "cmd:...".
final class SpokenMoveParserTests: XCTestCase {
    private func check(_ cases: [(String, String)], file: StaticString = #filePath, line: UInt = #line) {
        for (transcript, expected) in cases {
            XCTAssertEqual(topReading(transcript), expected, "transcript: \"\(transcript)\"", file: file, line: line)
        }
    }

    func testPlainMoves() {
        check([
            ("e4", "e4"), ("pawn e4", "Pe4"), ("pawn to e4", "Pe4"), ("knight f3", "Nf3"), ("knight to f3", "Nf3"),
            ("night to F3", "Nf3"), ("Knight takes e5", "Nxe5"), ("knight x e5", "Nxe5"), ("bishop captures c6", "Bxc6"),
            ("queen to h5 check", "Qh5"), ("nf3", "Nf3"), ("Nf3", "Nf3"), ("N f3", "Nf3"), ("Nxe5+", "Nxe5"),
            ("Qh4#", "Qh4"), ("king e2", "Ke2"), ("king to e2", "Ke2"), ("rook d1", "Rd1"), ("rook to d1", "Rd1"),
            ("rock to d1", "Rd1"), ("brook d1", "Rd1"), ("queen d4", "Qd4"), ("queen takes d4", "Qxd4"),
            ("bishop b5", "Bb5"), ("bishop to b5 check", "Bb5"), ("pawn d4", "Pd4"), ("pond d4", "Pd4"),
            ("porn to d4", "Pd4"), ("palm d4", "Pd4"), ("knights to c3", "Nc3"), ("nite c3", "Nc3"),
            ("bishop takes f7 check", "Bxf7"), ("queen captures f7 checkmate", "Qxf7"), ("Rook takes a8", "Rxa8"),
            ("king takes f2", "Kxf2"), ("knight goes to f3", "Nf3"), ("knight onto f3", "Nf3"), ("Bb5+", "Bb5"),
            ("Kingside", "O-O"), ("knight towards f3", "Nf3"), ("queen times d4", "Qxd4"), ("Knight eats e5", "Nxe5"),
        ])
    }

    func testDisambiguation() {
        check([
            ("rook a1 to a8", "Ra1a8"), ("rook from a1 to d1", "Ra1d1"), ("rook a d1", "Rad1"), ("rook a to d1", "Rad1"),
            ("rook f to d1", "Rfd1"), ("knight 1 to e2", "N1e2"), ("knight one to e2", "N1e2"), ("knight b d2", "Nbd2"),
            ("knight b to d2", "Nbd2"), ("Nbd2", "Nbd2"), ("N1e2", "N1e2"), ("Rad1", "Rad1"), ("R1a3", "R1a3"),
            ("knight g1 f3", "Ng1f3"), ("knight from g1 to f3", "Ng1f3"), ("knight on g1 to f3", "Ng1f3"),
            ("g1 f3", "g1f3"), ("g1 to f3", "g1f3"), ("g1f3", "g1f3"), ("e2e4", "e2e4"), ("from e2 to e4", "e2e4"),
            ("Qh4xe1", "Qh4xe1"), ("queen h4 takes e1", "Qh4xe1"), ("rook eight to d8", "R8d8"),
        ])
    }

    func testPawnCaptures() {
        check([
            ("e takes d5", "exd5"), ("exd5", "exd5"), ("e x d5", "exd5"), ("e pawn takes d5", "Pexd5"),
            ("pawn takes", "Px"), ("pawn takes d5", "Pxd5"), ("e takes d", "exd"), ("e captures d5", "exd5"),
            ("pawn captures d5", "Pxd5"), ("b takes c4", "bxc4"), ("bxc4", "bxc4"), ("Bxc4", "Bxc4"), ("ed5", "ed5"),
            ("pawn e takes d5", "Pexd5"), ("echo takes delta five", "exd5"), ("h takes g7", "hxg7"),
            ("a pawn takes b5", "Pxb5"), ("takes", "x"), ("pawn takes en passant", "Px"), ("e takes d6 en passant", "exd6"),
        ])
    }

    func testCastling() {
        check([
            ("castle", "castle"), ("castles", "castle"), ("castling", "castle"), ("castle kingside", "O-O"),
            ("castle king side", "O-O"), ("castle king's side", "O-O"), ("castle short", "O-O"), ("O-O", "O-O"),
            ("0-0", "O-O"), ("oh oh", "O-O"), ("zero zero", "O-O"), ("castle queenside", "O-O-O"),
            ("castle queen side", "O-O-O"), ("castle long", "O-O-O"), ("O-O-O", "O-O-O"), ("0-0-0", "O-O-O"),
            ("zero zero zero", "O-O-O"), ("oh oh oh", "O-O-O"), ("castle queen", "O-O-O"), ("castle king", "O-O"),
            ("short castle", "O-O"), ("long castle", "O-O-O"), ("let's castle", "castle"), ("I'll castle kingside", "O-O"),
            ("kassel", "castle"), ("queenside", "O-O-O"), ("castles kingside check", "O-O"), ("o-o", "O-O"),
        ])
    }

    func testPromotion() {
        check([
            ("e8 queen", "e8=Q"), ("e8 promote to knight", "e8=N"), ("pawn to e8 equals queen", "Pe8=Q"),
            ("a1=Q", "a1=Q"), ("a1 = Q", "a1=Q"), ("e8=N", "e8=N"), ("e8Q", "e8=Q"), ("e7e8q", "e7e8=Q"),
            ("pawn e8 promotes to rook", "Pe8=R"), ("e8 becomes a bishop", "e8=B"), ("pawn to e8", "Pe8"),
            ("d takes e8 queen", "dxe8=Q"), ("pawn takes e8 knight", "Pxe8=N"), ("e8 queen check", "e8=Q"),
            ("b1 equals knight", "b1=N"), ("pawn to h8 promote to queen", "Ph8=Q"), ("echo eight queen", "e8=Q"),
            ("pawn e8 promote", "Pe8"), ("e8 promote", "e8"),
        ])
    }

    func testSpokenCoordinates() {
        check([
            ("echo four", "e4"), ("hotel eight", "h8"), ("h eight", "h8"), ("aitch 8", "h8"), ("age 8", "h8"),
            ("E 4", "e4"), ("E-4", "e4"), ("e. 4", "e4"), ("E4", "e4"), ("84", "e4"), ("before", "b4"),
            ("see four", "c4"), ("sea 4", "c4"), ("deep 5", "d5"), ("dee five", "d5"), ("delta five", "d5"),
            ("bee three", "b3"), ("be 3", "b3"), ("gee seven", "g7"), ("golf seven", "g7"), ("alpha one", "a1"),
            ("A 1", "a1"), ("a one", "a1"), ("a won", "a1"), ("charlie six", "c6"), ("c sex", "c6"), ("c fix", "c6"),
            ("c six", "c6"), ("f free", "f3"), ("f tree", "f3"), ("f three", "f3"), ("ef three", "f3"),
            ("foxtrot three", "f3"), ("e for", "e4"), ("e fore", "e4"), ("d to", "d2"), ("d too", "d2"),
            ("d two", "d2"), ("g second", "g2"), ("h ate", "h8"), ("e eighth", "e8"), ("e fifth", "e5"),
            ("knight to f free", "Nf3"), ("knight to see three", "Nc3"), ("night two f three", "Nf3"),
            ("bishop to bee five", "Bb5"), ("queen to hotel five", "Qh5"), ("queen h five", "Qh5"),
            ("rook to dee one", "Rd1"), ("pawn to echo four", "Pe4"), ("pawn to e for", "Pe4"),
            ("knight to f3.", "Nf3"), ("Knight to F3!", "Nf3"), ("KNIGHT TO F3", "Nf3"), ("knight, to, f, 3", "Nf3"),
            ("Knight to F three", "Nf3"), ("knight to F 3", "Nf3"), ("Knight-F3", "Nf3"), ("ee four", "e4"),
            ("e 4", "e4"), ("E four", "e4"), ("e won", "e1"), ("eh four", "a4"), ("H8", "h8"),
        ])
    }

    func testFillersAndPoliteness() {
        check([
            ("um knight f3", "Nf3"), ("uh knight to f3", "Nf3"), ("okay knight to f3", "Nf3"), ("move knight to f3", "Nf3"),
            ("let's play e4", "e4"), ("I'll go knight f3", "Nf3"), ("please knight f3", "Nf3"), ("knight f3 please", "Nf3"),
            ("okay so um knight to f3", "Nf3"), ("I'll play pawn to e4", "Pe4"), ("I want to move my knight to f3", "Nf3"),
            ("move my queen to h5", "Qh5"), ("let me play bishop c4", "Bc4"), ("hmm let's go e4", "e4"),
            ("well I think knight f3", "Nf3"), ("I'd like to castle", "castle"), ("I will castle kingside", "O-O"),
            ("my move is knight f3", "Nf3"), ("knight to the f3 square", "Nf3"), ("put the knight on f3", "Nf3"),
            ("a knight to f3", "Nf3"), ("the knight to f3", "Nf3"), ("now knight f3", "Nf3"), ("just e4", "e4"),
        ])
    }

    func testSelfCorrections() {
        check([
            ("knight f3 no wait g5", "Ng5"), ("knight f3 no bishop c4", "Bc4"), ("knight f3 no wait bishop c4", "Bc4"),
            ("e4 no d4", "d4"), ("e4 sorry d4", "d4"), ("e4 I mean d4", "d4"), ("e4 actually d4", "d4"),
            ("queen h5 wait no queen f3", "Qf3"), ("rook d1 scratch that rook e1", "Re1"), ("e4 make that e3", "e3"),
            ("knight to f3 oops knight to h3", "Nh3"), ("bishop b5 no c4", "Bc4"), ("knight f3 no wait", "nil"),
            ("no, knight f3", "Nf3"), ("e4, sorry", "nil"), ("castle no wait e4", "e4"), ("e4 no castle", "castle"),
            ("knight to c3 no no no knight to f3", "Nf3"), ("rook a1 instead rook h1 to f1", "Rh1f1"),
        ])
    }

    func testCommands() {
        check([
            ("new game", "cmd:newGame"), ("start a new game", "cmd:newGame"), ("start over", "cmd:newGame"),
            ("restart", "cmd:newGame"), ("rematch", "cmd:newGame"), ("let's play again", "cmd:newGame"),
            ("resign", "cmd:resign"), ("I resign", "cmd:resign"), ("I give up", "cmd:resign"), ("I quit", "cmd:resign"),
            ("undo", "cmd:undo"), ("take back", "cmd:undo"), ("takeback", "cmd:undo"), ("take that back", "cmd:undo"),
            ("can you undo that", "cmd:undo"), ("please take it back", "cmd:undo"), ("undo the last move", "cmd:undo"),
            ("repeat", "cmd:repeatLastMove"), ("say that again", "cmd:repeatLastMove"),
            ("what was the last move", "cmd:repeatLastMove"), ("what did they play", "cmd:repeatLastMove"),
            ("what did the computer play", "cmd:repeatLastMove"), ("repeat the last move please", "cmd:repeatLastMove"),
            ("where is my queen", "cmd:locate queen mine"), ("where's my queen", "cmd:locate queen mine"),
            ("where are my knights", "cmd:locate knight mine"), ("where are my rooks", "cmd:locate rook mine"),
            ("where is the black queen", "cmd:locate queen black"), ("where is their king", "cmd:locate king opponent"),
            ("where is your queen", "cmd:locate queen opponent"), ("where are the opponent's bishops", "cmd:locate bishop opponent"),
            ("find my king", "cmd:locate king mine"), ("where are my pawns", "cmd:locate pawn mine"),
            ("what knights do I have", "cmd:locate knight mine"),
            ("what's on e4", "cmd:square e4"), ("what is on e4", "cmd:square e4"), ("what's on echo four", "cmd:square e4"),
            ("what is at h8", "cmd:square h8"), ("whats on d 5", "cmd:square d5"), ("is e4 empty", "cmd:square e4"),
            ("what's on H A", "cmd:square h8"), ("who is on f7", "cmd:square f7"),
            ("read the board", "cmd:readBoard"), ("describe the board", "cmd:readBoard"), ("board", "cmd:readBoard"),
            ("read me the board please", "cmd:readBoard"), ("where are the pieces", "cmd:readBoard"),
            ("list my pieces", "cmd:list mine"), ("what pieces do I have", "cmd:list mine"),
            ("list their pieces", "cmd:list opponent"), ("what does my opponent have", "cmd:list opponent"),
            ("list black's pieces", "cmd:list black"), ("what do I have left", "cmd:list mine"),
            ("whose turn", "cmd:whoseTurn"), ("whose turn is it", "cmd:whoseTurn"), ("who's turn is it", "cmd:whoseTurn"),
            ("is it my turn", "cmd:whoseTurn"), ("whose move is it", "cmd:whoseTurn"),
            ("help", "cmd:help"), ("what can I say", "cmd:help"), ("help me", "cmd:help"),
            ("cancel", "cmd:cancel"), ("never mind", "cmd:cancel"), ("nevermind", "cmd:cancel"), ("forget it", "cmd:cancel"),
            ("knight f3 cancel", "cmd:cancel"), ("knight f3 never mind", "cmd:cancel"),
            ("stop listening", "cmd:stopListening"), ("stop", "cmd:stopListening"), ("be quiet", "cmd:stopListening"),
            ("pause", "cmd:stopListening"),
            ("yes", "cmd:yes"), ("yeah", "cmd:yes"), ("yep", "cmd:yes"), ("confirm", "cmd:yes"), ("correct", "cmd:yes"),
            ("okay", "cmd:yes"), ("yes please", "cmd:yes"), ("do it", "cmd:yes"), ("that's right", "cmd:yes"),
            ("no", "cmd:no"), ("nope", "cmd:no"), ("wrong", "cmd:no"), ("no thanks", "cmd:no"), ("Yes.", "cmd:yes"),
            ("No!", "cmd:no"), ("um yes", "cmd:yes"), ("I want to resign", "cmd:resign"),
        ])
    }

    func testAdversarialInputs() {
        check([
            ("", "nil"), ("   ", "nil"), ("!!!", "nil"), ("?", "nil"), ("12", "nil"), ("0", "nil"), ("9", "nil"),
            ("99", "nil"), ("1234567", "nil"), ("e9", "nil"), ("i9", "nil"), ("knight", "nil"), ("knight to", "nil"),
            ("knight to f", "nil"), ("to", "nil"), ("for", "nil"), ("check", "nil"), ("the", "nil"), ("hello", "nil"),
            ("🙂", "nil"), ("日本語", "nil"), ("knight 🙂 f3", "Nf3"), ("Knïght tö f3", "Nf3"), ("ｅ４", "e4"),
            ("knight\tto\nf3", "Nf3"), ("what", "nil"), ("bad", "nil"), ("head", "nil"), ("bed", "nil"),
            ("the quick brown fox", "nil"), ("asdfghjkl", "nil"), ("e4e4e4e4", "nil"),
            ("so I was thinking that maybe I should um move my knight over to f3 because it controls the center", "Nf3"),
            (String(repeating: "um ", count: 200) + "knight f3", "Nf3"),
            (String(repeating: "blah ", count: 500), "nil"),
        ])
    }

    /// Every combination of piece word, connector and square spelling must give the same move.
    func testGeneratedCombinations() {
        let pieces: [(String, String)] = [
            ("knight", "N"), ("night", "N"), ("Knight", "N"), ("N", "N"), ("bishop", "B"), ("Bishop", "B"),
            ("rook", "R"), ("rock", "R"), ("queen", "Q"), ("Queen", "Q"), ("king", "K"), ("pawn", "P"), ("", ""),
        ]
        let connectors = ["", "to ", "goes to ", "takes ", "captures "]
        let squares: [(String, String)] = [
            ("f3", "f3"), ("F 3", "f3"), ("f three", "f3"), ("foxtrot three", "f3"), ("e4", "e4"), ("echo four", "e4"),
            ("E-4", "e4"), ("d5", "d5"), ("dee five", "d5"), ("h8", "h8"), ("hotel eight", "h8"), ("aitch 8", "h8"),
            ("c6", "c6"), ("see six", "c6"), ("g7", "g7"), ("gee seven", "g7"), ("a7", "a7"), ("alpha seven", "a7"),
            ("b1", "b1"), ("bravo one", "b1"),
        ]
        var count = 0
        for (pieceWord, letter) in pieces {
            for connector in connectors {
                for (squareWords, square) in squares {
                    let transcript = [pieceWord, connector + squareWords].filter { !$0.isEmpty }.joined(separator: " ")
                    let capture = connector.hasPrefix("takes") || connector.hasPrefix("captures") ? "x" : ""
                    XCTAssertEqual(topReading(transcript), letter + capture + square, "transcript: \"\(transcript)\"")
                    count += 1
                }
            }
        }
        XCTAssertEqual(count, 1_300)
    }

    func testInterpretationsAreRankedAndKeepAlternatives() {
        let readings = SpokenMoveParser.parse("rook to H A")
        XCTAssertEqual(readings.first.map { render($0.intent) }, "Rh8")
        XCTAssertTrue(readings.first?.usesSoundAlike ?? false)
        XCTAssertEqual(readings.map(\.score), readings.map(\.score).sorted(by: >))

        let literal = SpokenMoveParser.parse("knight to f3")
        XCTAssertEqual(literal.first?.score, 1)
        XCTAssertFalse(literal.first?.usesSoundAlike ?? true)

        // "a" before a piece is an article first, a file second.
        let article = SpokenMoveParser.parse("a knight to f3").map { render($0.intent) }
        XCTAssertEqual(Array(article.prefix(2)), ["Nf3", "Naf3"])

        // "to" is only a rank right after a file.
        XCTAssertFalse(SpokenMoveParser.parse("knight to f3").contains { render($0.intent) == "N2f3" })
        XCTAssertTrue(SpokenMoveParser.parse("e to").contains { render($0.intent) == "e2" })
    }
}
