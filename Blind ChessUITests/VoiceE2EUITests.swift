//
//  VoiceE2EUITests.swift
//  Blind ChessUITests
//
//  Real end-to-end voice: the host plays spoken audio into the Mac's default input
//  device (a BlackHole loopback on CI), which the simulator uses as its microphone.
//
//  Handshake with Tools/AppLab/voice_driver.sh through files in $APPLAB_DIR/voice:
//    test writes  req-<n>.txt   (the phrase)        -> host speaks it
//    host writes  done-<n>      when playback ended -> test samples the UI for APPLAB_SETTLE s (default 7)
//    test writes  result-<n>.txt (every distinct native UI text seen while waiting)
//    test writes  finished      at the end
//

import XCTest

final class VoiceE2EUITests: XCTestCase {

    @MainActor
    func testSpokenPhrasesReachRecognizer() throws {
        guard let dir = AppLab.dir else {
            throw XCTSkip("APPLAB_DIR not set; run via Tools/AppLab (TEST_RUNNER_APPLAB_DIR)")
        }
        continueAfterFailure = true
        AppLab.installInterruptionMonitor(on: self)
        let app = AppLab.makeApp()
        app.launch()
        AppLab.dismissSystemAlerts(timeout: 6)
        Thread.sleep(forTimeInterval: 3)
        waitForGame(app)

        // Make sure we are in voice mode: the mic button exists only there.
        var mic = AppLab.find(app, ids: ["micButton"], labelKeywords: ["speak", "listening", "microphone"])
        if mic == nil, let mode = AppLab.find(app, ids: ["inputModeToggle"], labelKeywords: ["mode"]) {
            AppLab.log("mic not found, toggling input mode '\(mode.label)'")
            mode.tap()
            Thread.sleep(forTimeInterval: 1)
            mic = AppLab.find(app, ids: ["micButton"], labelKeywords: ["speak", "listening", "microphone"])
        }
        AppLab.screenshot("voice_00_before_mic", in: self)
        guard let micButton = mic else {
            AppLab.write(app.debugDescription, to: "voice_ui_tree.txt")
            XCTFail("mic button not found")
            return
        }
        // Only tap if not already listening.
        if !micButton.label.lowercased().contains("listening") {
            AppLab.log("tapping mic '\(micButton.label)'")
            micButton.tap()
        }
        let alerts = AppLab.dismissSystemAlerts(timeout: 6)
        AppLab.log("alerts after mic tap: \(alerts)")
        Thread.sleep(forTimeInterval: 2)
        AppLab.screenshot("voice_01_listening", in: self)
        AppLab.write(AppLab.describe(AppLab.nativeTexts(app)), to: "voice/listening_native_ui.txt")

        var summary: [String] = []
        var previous = Set<String>()
        for (i, phrase) in AppLab.phrases.enumerated() {
            let n = i + 1
            AppLab.write(phrase, to: "voice/req-\(n).txt")
            AppLab.log("requested phrase \(n): '\(phrase)'")
            var seen: [String] = []
            var doneAt: Date?
            let start = Date()
            // Sample until `settle` s after the host reports playback done (max 60 s). The default
            // (7 s) outlasts the app's 5 s silence reset so phrases don't merge into one transcript.
            let settle = Double(AppLab.env["APPLAB_SETTLE"] ?? "") ?? 7
            while Date().timeIntervalSince(start) < 60 {
                for t in AppLab.nativeTexts(app) where t.type == .staticText {
                    if !seen.contains(t.label) {
                        seen.append(t.label)
                        AppLab.log("phrase \(n) ui text: \(t.label)")
                    }
                }
                if doneAt == nil, AppLab.fileExists("voice/done-\(n)") { doneAt = Date() }
                if let d = doneAt, Date().timeIntervalSince(d) > settle { break }
                Thread.sleep(forTimeInterval: 0.4)
            }
            AppLab.screenshot(String(format: "voice_%02d_after_%@", n + 1,
                                     phrase.replacingOccurrences(of: " ", with: "_")), in: self)
            let played = doneAt != nil
            let idle: Set<String> = ["Listening...", "Listening…", "Tap to speak", "Tap the microphone and say a move", ""]
            let fresh = seen.filter { !idle.contains($0) && !previous.contains($0) }
            XCTAssertTrue(played, "host never played phrase \(n)")
            XCTAssertFalse(fresh.isEmpty, "no new transcript/status text after phrase \(n) '\(phrase)'")
            previous = Set(seen)
            let result = "phrase: \(phrase)\nhost_played: \(played)\nui_texts_seen:\n" +
                seen.map { "  - \($0)" }.joined(separator: "\n") + "\n"
            AppLab.write(result, to: "voice/result-\(n).txt")
            summary.append(result)
            if !played { AppLab.log("host never confirmed playback of phrase \(n) (is voice_driver.sh running?)") }
        }
        AppLab.write(summary.joined(separator: "\n"), to: "voice/summary.txt")
        AppLab.write("finished", to: "voice/finished")
        AppLab.log("voice test finished, dir=\(dir)")
    }

    /// Waits (up to 90 s) until chess.com has a game running and it is the user's move, so the first phrase
    /// is not spent on the setup screen.
    @MainActor
    private func waitForGame(_ app: XCUIApplication) {
        let status = app.staticTexts.matching(identifier: "statusText").firstMatch
        let start = Date()
        var last = ""
        while Date().timeIntervalSince(start) < 90 {
            let label = status.exists ? status.label : ""
            if label != last {
                AppLab.log("status: \(label)")
                last = label
            }
            if label.hasPrefix("Your move") { break }
            Thread.sleep(forTimeInterval: 1)
        }
        AppLab.log("game ready after \(Int(Date().timeIntervalSince(start))) s: \(last)")
        // Let the "game started" announcement finish before the first phrase.
        Thread.sleep(forTimeInterval: 4)
    }
}
