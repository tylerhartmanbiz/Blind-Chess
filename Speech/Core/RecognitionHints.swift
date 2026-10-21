//
//  RecognitionHints.swift
//  Blind Chess core
//
//  Vocabulary hints for the speech recognizer (SFSpeechRecognitionRequest.contextualStrings, at most 100):
//  the pieces, move words, commands and the 64 squares, as measured by the speech lab (Tools/SpeechLab/REPORT.md).
//

import Foundation

public enum RecognitionHints {
    public static let contextualStrings: [String] = [
        "pawn", "knight", "bishop", "rook", "queen", "king",
        "takes", "captures", "castle", "castles", "kingside", "queenside", "promote", "check", "checkmate",
        "resign", "new game", "repeat", "undo", "where is my", "the one on",
    ] + "abcdefgh".flatMap { file in (1...8).map { "\(file)\($0)" } }
}
