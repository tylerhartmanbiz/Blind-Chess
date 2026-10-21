//
//  SmokeUITests.swift
//  Blind ChessUITests
//
//  Launch, permission alerts, chess.com load check, mode toggles, screenshots.
//

import XCTest

final class SmokeUITests: XCTestCase {

    @MainActor
    func testLaunchAndChessComLoad() throws {
        continueAfterFailure = true
        AppLab.installInterruptionMonitor(on: self)
        let app = AppLab.makeApp()
        app.launch()
        AppLab.screenshot("smoke_01_launch", in: self)
        let alerts = AppLab.dismissSystemAlerts(timeout: 6)
        AppLab.log("alerts at launch: \(alerts)")
        AppLab.screenshot("smoke_02_after_alerts", in: self)

        let web = app.webViews.firstMatch
        let hasWeb = web.waitForExistence(timeout: 20)
        AppLab.log("web view exists: \(hasWeb)")

        // Give chess.com time to load (or to show a bot challenge).
        for i in 1...4 {
            Thread.sleep(forTimeInterval: 8)
            AppLab.screenshot("smoke_03_web_\(i * 8)s", in: self)
        }
        let webTexts = AppLab.webTexts(app)
        AppLab.write(webTexts.joined(separator: "\n"), to: "chesscom_web_texts.txt")
        let joined = webTexts.joined(separator: " ").lowercased()
        let challenge = ["verify you are human", "just a moment", "checking your browser", "cloudflare", "captcha"]
            .filter { joined.contains($0) }
        AppLab.log("web texts: \(webTexts.count), challenge markers: \(challenge)")
        AppLab.write(AppLab.describe(AppLab.nativeTexts(app)), to: "smoke_native_ui.txt")
        AppLab.write(app.debugDescription, to: "smoke_ui_tree.txt")
        XCTAssertTrue(app.state == .runningForeground, "app should still be running")
    }

    @MainActor
    func testModeToggles() throws {
        continueAfterFailure = true
        AppLab.installInterruptionMonitor(on: self)
        let app = AppLab.makeApp()
        app.launch()
        AppLab.dismissSystemAlerts(timeout: 5)
        Thread.sleep(forTimeInterval: 2)
        AppLab.screenshot("toggle_01_initial", in: self)
        AppLab.write(AppLab.describe(AppLab.nativeTexts(app)), to: "toggle_01_native_ui.txt")

        if let mode = AppLab.find(app, ids: ["inputModeToggle"], labelKeywords: ["mode"]) {
            AppLab.log("tapping input mode toggle '\(mode.label)'")
            mode.tap()
            Thread.sleep(forTimeInterval: 1.5)
            AppLab.screenshot("toggle_02_input_mode_switched", in: self)
            AppLab.write(AppLab.describe(AppLab.nativeTexts(app)), to: "toggle_02_native_ui.txt")
            mode.tap()
            Thread.sleep(forTimeInterval: 1)
        } else {
            XCTFail("input mode toggle not found")
        }

        if let board = AppLab.find(app, ids: ["boardVisibilityToggle"], labelKeywords: ["board"]) {
            AppLab.log("tapping board toggle '\(board.label)'")
            board.tap()
            Thread.sleep(forTimeInterval: 1.5)
            AppLab.screenshot("toggle_03_board_toggled", in: self)
            board.tap()
            Thread.sleep(forTimeInterval: 1)
            AppLab.screenshot("toggle_04_board_toggled_back", in: self)
        } else {
            XCTFail("board visibility toggle not found")
        }
    }
}
