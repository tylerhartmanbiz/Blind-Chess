import XCTest
@testable import BlindChessCore

/// Resolver outcomes rendered as: SAN for a move ("~" prefix = sound-alike guess), "?a|b" for a clarification
/// listing the candidates' SAN, "!reason" for an explained illegal move, "cmd:..." for commands, "nil".
final class MoveResolverTests: XCTestCase {
    private let ruyLopez = "r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4"
    private let twoKnightsToD2 = "4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1"
    private let knightsOnGFile = "4k3/8/8/8/8/6N1/8/4K1N1 w - - 0 1"
    private let pinnedKnight = "4k3/4r3/8/8/8/8/4N3/4K1N1 w - - 0 1"
    private let enPassant = "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"
    private let promotion = "7k/P7/8/8/8/8/8/4K3 w - - 0 1"
    private let promotionCapture = "1r5k/P7/8/8/8/8/8/4K3 w - - 0 1"
    private let bothCastles = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
    private let twoPawnsToD5 = "4k3/8/8/3p4/2P1P3/8/8/4K3 w - - 0 1"

    private func check(_ fen: String, _ cases: [([String], String)], file: StaticString = #filePath, line: UInt = #line) {
        let board = position(fen, file: file, line: line)
        for (transcripts, expected) in cases {
            let result = render(MoveResolver.resolve(transcripts, in: board), in: board)
            XCTAssertEqual(result, expected, "\(transcripts) in \(fen)", file: file, line: line)
        }
    }

    func testStartingPosition() {
        check(Position.startFEN, [
            (["e4"], "e4"), (["pawn to e4"], "e4"), (["knight f3"], "Nf3"), (["night to F3"], "Nf3"), (["84"], "e4"),
            (["before"], "b4"), (["echo four"], "e4"), (["E-4"], "e4"), (["e. 4"], "e4"), (["knight c3"], "Nc3"),
            (["a knight to c3"], "Nc3"), (["aitch four"], "h4"), (["see four"], "c4"), (["f3"], "f3"),
            (["knight to f free"], "Nf3"), (["e to e4"], "e4"), (["g1 f3"], "Nf3"), (["e2e4"], "e4"),
            (["knight f3 no wait c3"], "Nc3"), (["e4 no d4"], "d4"), (["knight f3 no wait e4"], "e4"),
            (["um okay let's play e4 please"], "e4"), (["Upon to E4"], "e4"), (["up on to e4"], "e4"),
            (["a pawn to e4"], "e4"), (["Night to F3"], "Nf3"), (["pawn to d for"], "d4"), (["pawn to d two"], "!D 2 has your own pawn on it."),
            (["knight f5"], "!No knight can reach F 5."), (["e5"], "!Nothing can reach E 5."),
            (["e2"], "!E 2 has your own pawn on it."), (["castle"], "!There are pieces in the way of castling."),
            (["knight takes e5"], "!There's nothing to capture on E 5."), (["bishop to c4"], "!No bishop can reach C 4."),
            (["queen h5"], "!No queen can reach H 5."), (["takes"], "!No piece can capture anything."),
            (["new game"], "cmd:newGame"), (["undo"], "cmd:undo"), (["what's on e4"], "cmd:square e4"),
            ([], "nil"), (["hello there"], "nil"), ([""], "nil"),
        ])
    }

    func testNBestAlternatives() {
        check(Position.startFEN, [
            (["", "e4"], "e4"), (["blah blah", "knight f3"], "Nf3"), (["knight f5", "knight f3"], "Nf3"),
            (["e4", "resign"], "e4"), (["resign", "e4"], "cmd:resign"), (["night to have three", "knight to h3"], "Nh3"),
            (["bishop c4", "be for", "b4"], "b4"),
        ])
        check("6k1/8/8/8/8/8/8/R3K2R w KQ - 0 1", [(["rook to H A", "rook to h8"], "Rh8+")])
    }

    func testSoundAlikes() {
        check("6k1/8/8/8/8/8/8/R3K2R w KQ - 0 1", [
            (["rook to H A"], "~Rh8+"), (["rook HA"], "~Rh8+"), (["rook to a8"], "Ra8+"), (["H A"], "~Rh8+"),
        ])
        check(bothCastles, [(["rook to H A"], "~Rxh8+"), (["rook takes H A"], "Rxh8+")])
        // The b-pawn is gone: "b4" is illegal, and d4, e4 and g4 all sound alike, so ask.
        check("rnbqkbnr/pppppppp/8/8/8/8/P1PPPPPP/RNBQKBNR w KQkq - 0 1", [(["b4"], "?d4|e4|g4")])
        // Literal readings always win when legal.
        check(Position.startFEN, [(["b4"], "b4"), (["d4"], "d4")])

        let board = position("6k1/8/8/8/8/8/8/R3K2R w KQ - 0 1")
        guard case .move(let guessed) = MoveResolver.resolve(["rook to H A"], in: board) else { return XCTFail() }
        XCTAssertTrue(guessed.shouldConfirm)
        XCTAssertLessThan(guessed.confidence, 0.5)
        guard case .move(let literal) = MoveResolver.resolve(["rook to h8"], in: board) else { return XCTFail() }
        XCTAssertFalse(literal.shouldConfirm)
        XCTAssertEqual(literal.confidence, 1)
    }

    func testRuyLopez() {
        check(ruyLopez, [
            (["bishop takes c6"], "Bxc6"), (["bishop captures knight on c6"], "Bxc6"), (["castle"], "O-O"),
            (["castle kingside"], "O-O"), (["O-O"], "O-O"), (["king g1"], "O-O"), (["knight takes e5"], "Nxe5"),
            (["bishop a4"], "Ba4"), (["takes"], "?Bxa6|Bxc6|Nxe5"), (["bishop takes"], "?Bxa6|Bxc6"),
            (["castle queenside"], "!There are pieces in the way of castling queenside."),
            (["pawn takes"], "!No pawn can capture anything."), (["B c4"], "Bc4"), (["Bc4"], "Bc4"),
            (["rook to f1"], "Rf1"), (["queen e2"], "Qe2"), (["king e2"], "Ke2"), (["king f1"], "Kf1"),
        ])
    }

    func testAmbiguityAsksWhichPiece() {
        check(twoKnightsToD2, [
            (["knight d2"], "?Nbd2|Nfd2"), (["knight b d2"], "Nbd2"), (["knight f to d2"], "Nfd2"),
            (["knight b1 to d2"], "Nbd2"), (["Nfd2"], "Nfd2"), (["knight 1 to d2"], "?Nbd2|Nfd2"),
            (["d2"], "?Kd2|Nbd2|Nfd2"), (["knight on f1 to d2"], "Nfd2"), (["knight bravo d2"], "Nbd2"),
        ])
        check(knightsOnGFile, [
            (["knight 1 to e2"], "N1e2"), (["knight 3 e2"], "N3e2"), (["knight three to e2"], "N3e2"),
            (["knight e2"], "?N1e2|N3e2"), (["knight won to e2"], "N1e2"), (["N3e2"], "N3e2"),
        ])
        check(twoPawnsToD5, [
            (["d5"], "?cxd5|exd5"), (["takes d5"], "?cxd5|exd5"), (["c takes d5"], "cxd5"), (["exd5"], "exd5"),
            (["pawn takes"], "?cxd5|exd5"), (["e takes"], "exd5"), (["e takes d"], "exd5"),
        ])
        check("4k3/8/8/1p6/P1P5/8/8/4K3 w - - 0 1", [(["a pawn takes b5"], "axb5"), (["pawn takes b5"], "?axb5|cxb5")])
    }

    func testClarificationQuestions() {
        let board = position(twoKnightsToD2)
        guard case .needsClarification(let knights) = MoveResolver.resolve(["knight d2"], in: board) else { return XCTFail() }
        XCTAssertEqual(knights.question, "Which knight, B 1 or F 1?")

        let castles = position(bothCastles)
        guard case .needsClarification(let castling) = MoveResolver.resolve(["castle"], in: castles) else { return XCTFail() }
        XCTAssertEqual(castling.question, "Castle kingside or queenside?")

        guard case .needsClarification(let mixed) = MoveResolver.resolve(["d2"], in: board) else { return XCTFail() }
        XCTAssertEqual(mixed.question, "Did you mean Knight from B 1 to D 2, King to D 2, or Knight from F 1 to D 2?")
    }

    func testClarificationAnswers() {
        assertAnswers(twoKnightsToD2, ["knight d2"], [
            ("the one on b1", "Nbd2"), ("b", "Nbd2"), ("b knight", "Nbd2"), ("bee", "Nbd2"), ("from f1", "Nfd2"),
            ("f", "Nfd2"), ("the f one", "Nfd2"), ("foxtrot", "Nfd2"), ("knight f1 d2", "Nfd2"), ("Nbd2", "Nbd2"),
            ("cancel", "cmd:cancel"), ("no", "cmd:no"), ("hotel", "?Nbd2|Nfd2"), ("", "?Nbd2|Nfd2"),
            ("um the b one please", "Nbd2"), ("one", "?Nbd2|Nfd2"),
        ])
        assertAnswers(twoKnightsToD2, ["d2"], [("king", "Kd2"), ("knight on b1", "Nbd2"), ("the king", "Kd2")])
        assertAnswers(knightsOnGFile, ["knight e2"], [
            ("one", "N1e2"), ("three", "N3e2"), ("the one on g3", "N3e2"), ("won", "N1e2"), ("g1", "N1e2"), ("free", "N3e2"),
        ])
        assertAnswers(bothCastles, ["castle"], [
            ("kingside", "O-O"), ("long", "O-O-O"), ("queen side", "O-O-O"), ("short", "O-O"), ("king side", "O-O"),
        ])
        assertAnswers(twoPawnsToD5, ["d5"], [("c", "cxd5"), ("e pawn", "exd5"), ("from e4", "exd5"), ("see", "cxd5")])

        let board = position(twoKnightsToD2)
        guard case .needsClarification(let again) = MoveResolver.resolveClarification(
            ["hotel"], candidates: board.legalMoves().filter { $0.to == Square("d2")! && $0.piece == .knight }, in: board)
        else { return XCTFail() }
        XCTAssertEqual(again.question, "Sorry. Which knight, B 1 or F 1?")
    }

    private func assertAnswers(_ fen: String, _ request: [String], _ answers: [(String, String)],
                               file: StaticString = #filePath, line: UInt = #line) {
        let board = position(fen, file: file, line: line)
        guard case .needsClarification(let clarification) = MoveResolver.resolve(request, in: board) else {
            return XCTFail("\(request) should need clarification", file: file, line: line)
        }
        for (answer, expected) in answers {
            let result = MoveResolver.resolveClarification([answer], candidates: clarification.candidates, in: board)
            XCTAssertEqual(render(result, in: board), expected, "answer \"\(answer)\"", file: file, line: line)
        }
    }

    func testPinsAndChecks() {
        check(pinnedKnight, [
            (["knight to f3"], "Nf3"), (["knight to c3"], "!Your knight on E 2 is pinned."),
            (["knight d4"], "!Your knight on E 2 is pinned."), (["knight e2 to c3"], "!Your knight on E 2 is pinned."),
        ])
        let inCheck = "4k3/8/8/8/8/8/4r3/R3K2R w KQ - 0 1"
        check(inCheck, [
            (["king takes e2"], "Kxe2"), (["takes"], "Kxe2"), (["castle"], "!You can't castle while in check."),
            (["rook a2"], "!You're in check, and that doesn't get out of it."),
            (["king f2"], "!You're in check, and that doesn't get out of it."),
            (["king d2"], "~Kxe2"), (["king d1"], "Kd1"),
        ])
        check("4k3/8/8/8/8/8/5r2/R3K2R w KQ - 0 1", [
            (["castle kingside"], "!You can't castle through or into check."), (["castle"], "O-O-O"),
            (["king to f1"], "!That square is attacked."),
            (["king to g1"], "!You can't castle through or into check."),
        ])
        check("4k3/8/8/8/8/8/8/4K2R w - - 0 1", [
            (["castle"], "!You can no longer castle."), (["king to g1"], "!You can no longer castle kingside."),
        ])
        check("4k3/8/8/8/8/8/8/4K2R w K - 0 1", [
            (["castle queenside"], "!You can no longer castle queenside."), (["castle"], "O-O"),
            (["queen d1"], "!You have no queen."), (["knight f3"], "!You have no knight."),
            (["rook c to h4"], "!You have no rook on the C file."), (["rook a to h4"], "Rh4"),
        ])
        check("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", [(["rook a8"], "Ra8#"), (["rook to alpha eight check"], "Ra8#")])
    }

    func testEnPassant() {
        check(enPassant, [
            (["e takes d6"], "exd6"), (["pawn takes"], "exd6"), (["exd6"], "exd6"), (["e takes d6 en passant"], "exd6"),
            (["takes"], "exd6"), (["pawn takes d6"], "exd6"), (["d6"], "exd6"), (["e5"], "!E 5 has your own pawn on it."),
        ])
        check("4k3/8/8/3pP3/8/8/8/4K3 w - - 0 2", [(["e takes d6"], "!There's nothing to capture on D 6.")])
    }

    func testPromotion() {
        check(promotion, [
            (["a8"], "a8=Q+"), (["a8 knight"], "a8=N"), (["pawn to a8 equals rook"], "a8=R+"),
            (["a8 promote to bishop"], "a8=B"), (["alpha eight queen"], "a8=Q+"), (["a8=Q"], "a8=Q+"),
            (["pawn a8"], "a8=Q+"), (["a7a8n"], "a8=N"), (["a8 king"], "a8=Q+"),
        ])
        check(promotionCapture, [
            (["a takes b8"], "axb8=Q+"), (["pawn takes"], "axb8=Q+"), (["a8"], "a8=Q"), (["pawn takes b8 knight"], "axb8=N"),
            (["takes b8 rook"], "axb8=R+"),
        ])
        let board = position(promotion)
        guard case .move(let defaulted) = MoveResolver.resolve(["a8"], in: board) else { return XCTFail() }
        XCTAssertTrue(defaulted.defaultedPromotion)
        guard case .move(let chosen) = MoveResolver.resolve(["a8 queen"], in: board) else { return XCTFail() }
        XCTAssertFalse(chosen.defaultedPromotion)
    }

    func testButtonIntent() {
        let board = position(twoKnightsToD2)
        func button(_ intent: MoveIntent) -> String { render(MoveResolver.resolve(intent, in: board), in: board) }
        XCTAssertEqual(button(MoveIntent(piece: .knight, toFile: 3, toRank: 1)), "?Nbd2|Nfd2")
        XCTAssertEqual(button(MoveIntent(piece: .knight, fromFile: 1, toFile: 3, toRank: 1)), "Nbd2")
        XCTAssertEqual(button(MoveIntent(piece: .knight, toFile: 5, toRank: 4)), "!No knight can reach F 5.")
        XCTAssertEqual(button(MoveIntent(toFile: 4, toRank: 1)), "Ke2")
    }

    func testCastlingChoices() {
        check(bothCastles, [
            (["castle"], "?O-O|O-O-O"), (["castle kingside"], "O-O"), (["castle long"], "O-O-O"),
            (["zero zero zero"], "O-O-O"), (["O-O"], "O-O"), (["king to c1"], "O-O-O"), (["king g1"], "O-O"),
            (["rook to d1"], "Rd1"), (["rook a8"], "Rxa8+"),
        ])
        check("r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1", [(["castle short"], "O-O"), (["castle queenside"], "O-O-O")])
    }
}
