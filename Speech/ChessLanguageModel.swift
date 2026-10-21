//
//  ChessLanguageModel.swift
//  Blind Chess
//
//  Custom language model for SFSpeechRecognizer (on-device recognition only), built once and cached; a port of
//  Tools/SpeechLab/recognizer/LM.swift. On-device + RecognitionHints.contextualStrings + this model was the most
//  accurate configuration the speech lab measured (Tools/SpeechLab/REPORT.md).
//

import Foundation
import Speech

enum ChessLanguageModel {
    private static let squares: [String] = "abcdefgh".flatMap { file in (1...8).map { "\(file)\($0)" } }
    private static let pieces = ["knight", "bishop", "rook", "queen", "king"]

    private static let identifier = "Blind-Chess.chess"
    private static let version = "1"

    /// Builds (first launch) or reuses the custom model. Returns nil where custom models are unavailable.
    static func prepare() async -> SFSpeechLanguageModel.Configuration? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("ChessLanguageModel-v\(version)")
        let asset = dir.appendingPathComponent("chess.bin")
        let config = SFSpeechLanguageModel.Configuration(languageModel: dir.appendingPathComponent("lm"),
                                                         vocabulary: dir.appendingPathComponent("vocab"))
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: asset.path) {
                let data = SFCustomLanguageModelData(locale: Locale(identifier: "en_US"), identifier: identifier,
                                                     version: version) {
                    for (phrase, count) in trainingPhrases() {
                        SFCustomLanguageModelData.PhraseCount(phrase: phrase, count: count)
                    }
                }
                try await data.export(to: asset)
            }
            try await SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, clientIdentifier: identifier,
                                                                       configuration: config)
            Log.info("custom language model ready")
            return config
        } catch {
            Log.error("custom language model unavailable: \(error.localizedDescription)")
            return nil
        }
    }

    /// Weighted phrases, the same set the speech lab measured.
    private static func trainingPhrases() -> [(String, Int)] {
        var phrases: [(String, Int)] = []
        for square in squares {
            phrases += [(square, 40), ("pawn to \(square)", 10), ("the one on \(square)", 4)]
            for piece in pieces {
                phrases += [("\(piece) \(square)", 20), ("\(piece) to \(square)", 20), ("\(piece) takes \(square)", 10)]
            }
        }
        let files = Array("abcdefgh")
        for (index, file) in files.enumerated() {
            for neighbour in [index - 1, index + 1] where files.indices.contains(neighbour) {
                for rank in 1...8 { phrases.append(("\(file) takes \(files[neighbour])\(rank)", 3)) }
            }
            for promotion in ["queen", "knight", "rook", "bishop"] {
                for rank in [1, 8] {
                    phrases += [("\(file)\(rank) \(promotion)", 3), ("\(file)\(rank) promote to \(promotion)", 3)]
                }
            }
        }
        let commands = ["castle kingside", "castle queenside", "castles kingside", "castles queenside", "castle short",
                        "castle long", "short castle", "long castle", "castle", "new game", "resign", "repeat", "undo",
                        "take back", "where is my queen", "where is my king", "where are my knights",
                        "where are my rooks", "where are my bishops", "read the board", "what was the last move",
                        "whose turn", "help", "yes", "no", "cancel", "white", "black", "random", "stop listening"]
        phrases += commands.map { ($0, 30) }
        return phrases
    }
}
