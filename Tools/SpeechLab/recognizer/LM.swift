// Custom language model for chess (SFCustomLanguageModelData, macOS 14+ / iOS 17+).
import Foundation
import Speech

func chessTrainingPhrases() -> [(String, Int)] {
    let pieces = ["knight", "bishop", "rook", "queen", "king"]
    var squares: [String] = []
    for f in "abcdefgh" { for r in 1...8 { squares.append("\(f)\(r)") } }
    var out: [(String, Int)] = []
    for sq in squares {
        out.append((sq, 40))
        out.append(("pawn to \(sq)", 10))
        out.append(("the one on \(sq)", 4))
        for p in pieces {
            out.append(("\(p) \(sq)", 20))
            out.append(("\(p) to \(sq)", 20))
            out.append(("\(p) takes \(sq)", 10))
        }
    }
    for f in "abcdefgh" {
        for sq in squares { if abs(Int(sq.unicodeScalars.first!.value) - Int(f.unicodeScalars.first!.value)) == 1 { out.append(("\(f) takes \(sq)", 3)) } }
    }
    for f in "abcdefgh" {
        for promo in ["queen", "knight", "rook", "bishop"] {
            out.append(("\(f)8 \(promo)", 3)); out.append(("\(f)1 \(promo)", 3))
            out.append(("\(f)8 promote to \(promo)", 3)); out.append(("\(f)1 promote to \(promo)", 3))
        }
    }
    for c in ["castle kingside", "castle queenside", "castles kingside", "castles queenside", "castle short",
              "castle long", "short castle", "long castle", "castle", "new game", "resign", "repeat", "undo",
              "take back", "where is my queen", "where is my king", "where are my knights", "where are my rooks",
              "where are my bishops", "read the board", "what was the last move", "offer a draw", "yes", "no", "cancel"] {
        out.append((c, 30))
    }
    return out
}

@available(macOS 14, iOS 17, *)
func buildLanguageModelImpl() async throws -> AnyObject {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speechlab-lm-\(getpid())")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let data = SFCustomLanguageModelData(locale: Locale(identifier: "en_US"), identifier: "com.blindchess.speechlab", version: "1.0") {
        for (p, c) in chessTrainingPhrases() {
            SFCustomLanguageModelData.PhraseCount(phrase: p, count: c)
        }
    }
    let asset = dir.appendingPathComponent("chess.bin")
    try await data.export(to: asset)
    let config = SFSpeechLanguageModel.Configuration(languageModel: dir.appendingPathComponent("lm"),
                                                     vocabulary: dir.appendingPathComponent("vocab"))
    try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, clientIdentifier: "com.blindchess.speechlab", configuration: config)
    return config
}

func buildLanguageModel() async throws -> AnyObject {
    if #available(macOS 14, iOS 17, *) { return try await buildLanguageModelImpl() }
    throw NSError(domain: "speechlab", code: 1, userInfo: [NSLocalizedDescriptionKey: "needs macOS 14"])
}

func applyLM(_ lm: AnyObject, to req: SFSpeechRecognitionRequest) {
    if #available(macOS 14, iOS 17, *), let cfg = lm as? SFSpeechLanguageModel.Configuration {
        req.customizedLanguageModel = cfg
    }
}
