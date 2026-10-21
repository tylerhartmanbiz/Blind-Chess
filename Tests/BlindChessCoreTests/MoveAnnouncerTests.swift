import XCTest
@testable import BlindChessCore

final class MoveAnnouncerTests: XCTestCase {
    private func announce(_ san: String, _ fen: String = Position.startFEN, file: StaticString = #filePath, line: UInt = #line) -> String {
        let board = position(fen, file: file, line: line)
        guard let move = board.move(san: san) else {
            XCTFail("illegal \(san)", file: file, line: line)
            return ""
        }
        return MoveAnnouncer.announce(move, in: board)
    }

    func testMoves() {
        XCTAssertEqual(announce("Nf3"), "Knight to F 3")
        XCTAssertEqual(announce("e4"), "Pawn to E 4")
        XCTAssertEqual(announce("a3"), "Pawn to A 3")
        XCTAssertEqual(announce("Bxc6", "r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 0 4"), "Bishop takes C 6")
        XCTAssertEqual(announce("O-O", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"), "Castles kingside")
        XCTAssertEqual(announce("O-O-O", "r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1"), "Castles queenside")
        XCTAssertEqual(announce("a8=Q", "7k/P7/8/8/8/8/8/4K3 w - - 0 1"), "Pawn to A 8 promotes to queen, check")
        XCTAssertEqual(announce("axb8=N", "1r5k/P7/8/8/8/8/8/4K3 w - - 0 1"), "Pawn takes B 8 promotes to knight")
        XCTAssertEqual(announce("exd6", "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"), "Pawn takes D 6 en passant")
        XCTAssertEqual(announce("Qh4", "rnbqkbnr/pppp1ppp/8/4p3/6P1/5P2/PPPPP2P/RNBQKBNR b KQkq - 0 2"), "Queen to H 4, checkmate")
        XCTAssertEqual(announce("cxd5", "4k3/8/8/3p4/2P1P3/8/8/4K3 w - - 0 1"), "C pawn takes D 5")
        XCTAssertEqual(announce("Nbd2", "4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1"), "Knight from B 1 to D 2")
        XCTAssertEqual(announce("Qg6", "7k/8/8/6Q1/8/8/8/K7 w - - 0 1"), "Queen to G 6, stalemate")
        XCTAssertEqual(announce("Rxa8", "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"), "Rook takes A 8, check")
    }

    func testSquaresAreSpelledForSpeech() {
        XCTAssertEqual(MoveAnnouncer.spokenSquare(Square("a8")!), "A 8")
        XCTAssertEqual(MoveAnnouncer.spokenSquare(Square("e4")!), "E 4")
    }

    func testPieceLocations() {
        let start = Position.start
        XCTAssertEqual(MoveAnnouncer.locate(.queen, of: .white, in: start, userColor: .white), "Your queen is on D 1.")
        XCTAssertEqual(MoveAnnouncer.locate(.knight, of: .white, in: start, userColor: .white), "Your knights are on B 1 and G 1.")
        XCTAssertEqual(MoveAnnouncer.locate(.queen, of: .black, in: start, userColor: .white), "The black queen is on D 8.")
        XCTAssertEqual(MoveAnnouncer.locate(.pawn, of: .black, in: start, userColor: .black),
                       "Your pawns are on A 7, B 7, C 7, D 7, E 7, F 7, G 7, and H 7.")
        let bare = position("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(MoveAnnouncer.locate(.queen, of: .white, in: bare, userColor: .white), "You have no queen.")
        XCTAssertEqual(MoveAnnouncer.locate(.queen, of: .black, in: bare, userColor: .white), "Black has no queen.")
    }

    func testBoardDescriptions() {
        let board = position("4k3/8/8/8/4P3/8/8/R3K3 b Q - 0 1")
        XCTAssertEqual(MoveAnnouncer.describeSquare(Square("e4")!, in: board), "E 4 has a white pawn.")
        XCTAssertEqual(MoveAnnouncer.describeSquare(Square("d4")!, in: board), "D 4 is empty.")
        XCTAssertEqual(MoveAnnouncer.listPieces(of: .white, in: board, userColor: .white), "You have: king E 1; rook A 1; pawn E 4.")
        XCTAssertEqual(MoveAnnouncer.listPieces(of: .black, in: board, userColor: .white), "Black has: king E 8.")
        XCTAssertEqual(MoveAnnouncer.describeBoard(board), "White: king E 1; rook A 1; pawn E 4. Black: king E 8. Black to move.")
        XCTAssertEqual(MoveAnnouncer.describeTurn(board, userColor: .black), "Your move, you play black.")
        XCTAssertEqual(MoveAnnouncer.describeTurn(board, userColor: .white), "Black's move. Waiting for your opponent.")
        let mated = position("R5k1/5ppp/8/8/8/8/8/6K1 b - - 1 1")
        XCTAssertEqual(MoveAnnouncer.describeTurn(mated, userColor: .white), "Checkmate. White won.")
        let checked = position("4k3/8/8/8/8/8/4r3/4K3 w - - 0 1")
        XCTAssertEqual(MoveAnnouncer.describeTurn(checked, userColor: .white), "Your move, you play white. You are in check.")
    }
}
