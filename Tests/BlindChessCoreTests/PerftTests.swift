import XCTest
@testable import BlindChessCore

/// Perft node counts from https://www.chessprogramming.org/Perft_Results.
/// Debug builds check up to ~200k nodes per position; the deep counts (millions of nodes) run in release builds
/// (`swift test -c release -Xswiftc -enable-testing`) or when BLINDCHESS_DEEP_PERFT is set.
final class PerftTests: XCTestCase {
    private static let runDeep: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["BLINDCHESS_DEEP_PERFT"] != nil
        #else
        return true
        #endif
    }()

    private func assertPerft(_ fen: String, _ counts: [Int], deep: [Int], file: StaticString = #filePath, line: UInt = #line) {
        guard let position = Position(fen: fen) else { return XCTFail("bad FEN \(fen)", file: file, line: line) }
        let expected = PerftTests.runDeep ? counts + deep : counts
        for (index, nodes) in expected.enumerated() {
            XCTAssertEqual(position.perft(depth: index + 1), nodes, "depth \(index + 1) of \(fen)", file: file, line: line)
        }
    }

    func testStartPosition() {
        assertPerft(Position.startFEN, [20, 400, 8_902, 197_281], deep: [4_865_609])
    }

    func testKiwipete() {
        assertPerft("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
                    [48, 2_039, 97_862], deep: [4_085_603])
    }

    func testPosition3() {
        assertPerft("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2_812, 43_238], deep: [674_624])
    }

    func testPosition4() {
        assertPerft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9_467], deep: [422_333])
    }

    func testPosition4Mirrored() {
        assertPerft("r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1", [6, 264, 9_467], deep: [422_333])
    }

    func testPosition5() {
        assertPerft("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1_486, 62_379], deep: [2_103_487])
    }

    func testPosition6() {
        assertPerft("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10",
                    [46, 2_079, 89_890], deep: [3_894_594])
    }
}
