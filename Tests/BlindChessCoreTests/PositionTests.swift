import XCTest
@testable import BlindChessCore

final class PositionTests: XCTestCase {
    private func play(_ sans: [String], from start: Position = .start, file: StaticString = #filePath, line: UInt = #line) -> Position {
        var board = start
        for san in sans {
            guard let move = board.move(san: san) else {
                XCTFail("illegal \(san) in \(board.fen)", file: file, line: line)
                return board
            }
            board.play(move)
        }
        return board
    }

    // MARK: FEN

    func testFENRoundTrip() {
        let fens = [
            Position.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
            "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2",
            "8/8/8/8/8/8/8/K6k b - - 99 120",
        ]
        for fen in fens { XCTAssertEqual(Position(fen: fen)?.fen, fen) }
        XCTAssertEqual(Position(fen: "8/8/8/8/8/8/8/K6k w")?.fen, "8/8/8/8/8/8/8/K6k w - - 0 1")
    }

    func testInvalidFENsAreRejected() {
        let bad = [
            "", "hello", "8/8/8/8/8/8/8/8 w - - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1",
            "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1",
            "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkx - 0 1", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq e5 0 1",
            "rnbqkbnr/ppppXppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", "kk6/8/8/8/8/8/8/K7 w - - 0 1",
            "6k1/8/8/8/8/8/8/K5R1 w - - 0 1",   // the side not to move is in check
        ]
        for fen in bad { XCTAssertNil(Position(fen: fen), fen) }
    }

    func testCastlingRightsComeFromFENAndBoard() {
        XCTAssertEqual(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w Kq - 0 1")?.castlingRights, [.whiteKingside, .blackQueenside])
        // A right whose rook is missing is dropped.
        XCTAssertEqual(Position(fen: "r3k3/8/8/8/8/8/8/4K2R w KQkq - 0 1")?.castlingRights, [.whiteKingside, .blackQueenside])
        let noRights = Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")!
        XCTAssertFalse(noRights.legalMoves().contains { $0.castle != nil })
    }

    // MARK: Making moves

    func testMoveUpdatesState() {
        let afterE4 = play(["e4"])
        XCTAssertEqual(afterE4.fen, "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")
        let afterNf6 = play(["e4", "Nf6"])
        XCTAssertEqual(afterNf6.fen, "rnbqkb1r/pppppppp/5n2/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2")
        let afterKingMove = play(["e4", "e5", "Ke2"])
        XCTAssertEqual(afterKingMove.castlingRights, [.blackKingside, .blackQueenside])
        let afterRookMove = play(["h4", "a5", "Rh3", "Ra6"])
        XCTAssertEqual(afterRookMove.castlingRights, [.whiteQueenside, .blackKingside])
    }

    func testCapturingARookRemovesItsCastlingRight() {
        let board = play(["Rxh8"], from: Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!)
        XCTAssertEqual(board.castlingRights, [.whiteQueenside, .blackQueenside])
    }

    func testCastlingMovesTheRook() {
        let board = play(["O-O-O"], from: Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")!)
        XCTAssertEqual(board.fen, "r3k2r/8/8/8/8/8/8/2KR3R b kq - 1 1")
    }

    func testEnPassantCaptureRemovesThePawn() {
        let board = play(["e4", "a6", "e5", "d5", "exd6"])
        XCTAssertNil(board[Square("d5")!])
        XCTAssertEqual(board[Square("d6")!], Piece(.white, .pawn))
        let move = play(["e4", "a6", "e5", "d5"]).move(san: "exd6")!
        XCTAssertTrue(move.isEnPassant)
        XCTAssertEqual(move.captured, .pawn)
    }

    func testPromotionChoices() {
        let board = Position(fen: "7k/P7/8/8/8/8/8/4K3 w - - 0 1")!
        let promotions = board.legalMoves().filter { $0.from == Square("a7")! }.compactMap(\.promotion)
        XCTAssertEqual(Set(promotions), [.queen, .rook, .bishop, .knight])
        XCTAssertEqual(board.playing(board.move(san: "a8=N")!)[Square("a8")!], Piece(.white, .knight))
    }

    // MARK: Game state

    func testCheckmateAndStalemate() {
        let foolsMate = play(["f3", "e5", "g4", "Qh4"])
        XCTAssertTrue(foolsMate.isCheck)
        XCTAssertTrue(foolsMate.isCheckmate)
        XCTAssertFalse(foolsMate.isStalemate)

        let stalemate = Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")!
        XCTAssertFalse(stalemate.isCheck)
        XCTAssertTrue(stalemate.isStalemate)
        XCTAssertFalse(stalemate.isCheckmate)

        XCTAssertFalse(Position.start.isCheck)
        XCTAssertEqual(Position.start.legalMoves().count, 20)
    }

    func testInsufficientMaterial() {
        let insufficient = [
            "8/8/8/4k3/8/8/8/4K3 w - - 0 1", "8/8/8/4k3/8/8/8/4KN2 w - - 0 1", "8/8/8/4k3/8/8/8/4KB2 w - - 0 1",
            "8/8/8/4kb2/8/8/8/4KB2 w - - 0 1",   // bishops on same-coloured squares (f5 and f1 are both light)
        ]
        let sufficient = [
            Position.startFEN, "8/8/8/4k3/8/8/8/4KR2 w - - 0 1", "8/8/8/4k3/8/8/4P3/4K3 w - - 0 1",
            "8/8/8/4kb2/8/8/8/3KB3 w - - 0 1", "8/8/8/4k3/8/8/8/3NKN2 w - - 0 1", "8/8/8/4kn2/8/8/8/4KB2 w - - 0 1",
        ]
        for fen in insufficient { XCTAssertTrue(Position(fen: fen)!.hasInsufficientMaterial, fen) }
        for fen in sufficient { XCTAssertFalse(Position(fen: fen)!.hasInsufficientMaterial, fen) }
    }

    func testPiecesAndSquares() {
        XCTAssertEqual(Position.start.squares(of: Piece(.white, .knight)).map(\.name), ["b1", "g1"])
        XCTAssertEqual(Position.start.pieces(of: .black).first?.piece, Piece(.black, .king))
        XCTAssertEqual(Position.start.pieces(of: .white).count, 16)
        XCTAssertEqual(Square("h8")?.index, 63)
        XCTAssertNil(Square("i1"))
        XCTAssertNil(Square("a9"))
        XCTAssertNil(Square("e44"))
        XCTAssertTrue(Square("h1")!.isLight)
        XCTAssertFalse(Square("a1")!.isLight)
    }

    // MARK: Notation

    func testSANGeneration() {
        let cases: [(String, String, String)] = [
            (Position.startFEN, "g1f3", "Nf3"), (Position.startFEN, "e2e4", "e4"),
            ("4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1", "b1d2", "Nbd2"),
            ("4k3/8/8/8/8/6N1/8/4K1N1 w - - 0 1", "g3e2", "N3e2"),
            ("4k3/8/8/8/8/2N3N1/8/2N1K1N1 w - - 0 1", "c3e2", "Nc3e2"),     // file and rank both shared
            ("4k3/8/8/3p4/2P1P3/8/8/4K3 w - - 0 1", "c4d5", "cxd5"),
            ("4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2", "e5d6", "exd6"),
            ("7k/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8q", "a8=Q+"), ("7k/P7/8/8/8/8/8/4K3 w - - 0 1", "a7a8n", "a8=N"),
            ("1r5k/P7/8/8/8/8/8/4K3 w - - 0 1", "a7b8q", "axb8=Q+"),
            ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1g1", "O-O"), ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "e1c1", "O-O-O"),
            ("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1", "a1a8", "Rxa8+"),
            ("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1", "a1a8", "Ra8#"),
            ("rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2", "d8h4", "Qh4#"),
            // Only the knight that is not pinned may go to d4, so no disambiguation is needed.
            ("4k3/4r3/8/8/8/8/2N1N3/4K3 w - - 0 1", "c2d4", "Nd4"),
            ("R6R/8/8/8/8/1k6/8/4K3 w - - 0 1", "a8d8", "Rad8"),
        ]
        for (fen, uci, san) in cases {
            let board = Position(fen: fen)!
            guard let move = board.move(uci: uci) else {
                XCTFail("no move \(uci) in \(fen)")
                continue
            }
            XCTAssertEqual(board.san(move), san, fen)
            XCTAssertEqual(board.move(san: san), move, "parsing \(san)")
        }
    }

    func testTolerantSANParsing() {
        let board = Position(fen: "r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4")!
        for text in ["Bxc6", "Bc6", "Bxc6+", "Bxc6!?", " Bxc6 "] { XCTAssertEqual(board.move(san: text)?.uci, "b5c6", text) }
        for text in ["O-O", "0-0", "o-o", "OO"] { XCTAssertEqual(board.move(san: text)?.uci, "e1g1", text) }
        for text in ["Nxe5", "nxe5", "Nf3e5", "Nf3xe5"] { XCTAssertEqual(board.move(san: text)?.uci, "f3e5", text) }
        for text in ["", "Qh5h5", "O-O-O", "Nf4", "e5", "xyz"] { XCTAssertNil(board.move(san: text), text) }

        let promotion = Position(fen: "7k/P7/8/8/8/8/8/4K3 w - - 0 1")!
        for text in ["a8=Q", "a8Q", "a8q", "a8=Q+"] { XCTAssertEqual(promotion.move(san: text)?.uci, "a7a8q", text) }
        XCTAssertNil(promotion.move(san: "a8"), "a promotion needs its piece in SAN")

        XCTAssertEqual(Position.start.move(uci: "E2E4")?.uci, "e2e4")
        XCTAssertNil(Position.start.move(uci: "e2e5"))
        XCTAssertNil(Position.start.move(uci: "zz"))
    }
}
