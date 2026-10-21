//
//  AppSettings.swift
//  Blind Chess
//
//  UserDefaults keys shared by @AppStorage in the views and by the controllers.
//

import Foundation

enum AppSettings {
    static let speechEnabled = "speechEnabled"
    static let boardVisible = "boardVisible"
    static let buttonMode = "buttonMode"
    /// "white", "black" or "random": the side used when a game is started for you.
    static let playColor = "playColor"

    static var isSpeechEnabled: Bool { UserDefaults.standard.object(forKey: speechEnabled) as? Bool ?? true }
    static var preferredColor: String { UserDefaults.standard.string(forKey: playColor) ?? "white" }
}
