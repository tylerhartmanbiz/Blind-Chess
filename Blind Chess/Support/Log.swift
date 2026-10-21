//
//  Log.swift
//  Blind Chess
//
//  App logging through os.Logger. When the simulator lab sets BLINDCHESS_LOG_FILE (see Testing/LabStdoutRedirect.c),
//  lines are also printed so they land in the lab's stdout capture.
//

import Foundation
import os

nonisolated enum Log {
    private static let logger = Logger(subsystem: "Blind-Chess.Blind-Chess", category: "app")
    private static let mirrorsToStdout = ProcessInfo.processInfo.environment["BLINDCHESS_LOG_FILE"] != nil

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        if mirrorsToStdout { print("[BlindChess] \(message)") }
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        if mirrorsToStdout { print("[BlindChess] ERROR \(message)") }
    }
}
