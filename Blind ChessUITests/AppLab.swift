//
//  AppLab.swift
//  Blind ChessUITests
//
//  Shared helpers for the simulator lab (see Tools/AppLab/README.md).
//
//  Environment (pass from xcodebuild as TEST_RUNNER_<NAME>, the prefix is stripped):
//    APPLAB_DIR      absolute host directory for screenshots, UI dumps, app stdout
//                    and the voice handshake files. Simulator processes can write
//                    to host paths, so the host script sees these files directly.
//    APPLAB_PHRASES  phrases for the voice test, separated by "|"
//                    (default: "pawn to e4|knight to f3|h8").
//

import XCTest

@MainActor
enum AppLab {
    static let env = ProcessInfo.processInfo.environment

    static var dir: String? {
        guard let d = env["APPLAB_DIR"], !d.isEmpty else { return nil }
        try? FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
        return d
    }

    static var phrases: [String] {
        let raw = env["APPLAB_PHRASES"] ?? "pawn to e4|knight to f3|h8"
        return raw.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    static func log(_ message: String) {
        let line = "[AppLab \(timestamp())] \(message)"
        print(line)
        append(line + "\n", to: "uitest.log")
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f.string(from: Date())
    }

    static func write(_ text: String, to name: String) {
        guard let d = dir else { return }
        let path = (d as NSString).appendingPathComponent(name)
        try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    static func append(_ text: String, to name: String) {
        guard let d = dir else { return }
        let path = (d as NSString).appendingPathComponent(name)
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? text.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    static func fileExists(_ name: String) -> Bool {
        guard let d = dir else { return false }
        return FileManager.default.fileExists(atPath: (d as NSString).appendingPathComponent(name))
    }

    /// Screenshot attached to the xcresult AND written to $APPLAB_DIR/screens/<name>.png.
    static func screenshot(_ name: String, in test: XCTestCase) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        test.add(att)
        if let d = dir {
            let path = (d as NSString).appendingPathComponent("screens/\(name).png")
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        }
        log("screenshot \(name)")
    }

    // MARK: - App launch + permission alerts

    static func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTesting"]
        if let d = dir {
            // Read by Blind Chess/Testing/LabStdoutRedirect.c
            app.launchEnvironment["BLINDCHESS_LOG_FILE"] = (d as NSString).appendingPathComponent("app_stdout_uitest.log")
        }
        return app
    }

    static let allowButtons = ["Allow", "OK", "Allow While Using App", "Allow Once", "Continue"]

    /// Taps through any system permission alert (microphone / speech recognition) shown by SpringBoard.
    /// Returns the alert titles it handled.
    @discardableResult
    static func dismissSystemAlerts(timeout: TimeInterval) -> [String] {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var handled: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let alert = springboard.alerts.firstMatch
            if alert.waitForExistence(timeout: 1) {
                let title = alert.label
                var tapped = false
                for name in allowButtons where alert.buttons[name].exists {
                    alert.buttons[name].tap()
                    tapped = true
                    log("system alert '\(title)' -> tapped \(name)")
                    break
                }
                if !tapped {
                    let buttons = alert.buttons.allElementsBoundByIndex
                    if let last = buttons.last {
                        log("system alert '\(title)' -> tapped last button '\(last.label)'")
                        last.tap()
                    } else {
                        break
                    }
                }
                handled.append(title)
                continue
            }
            if handled.isEmpty == false { break }
        }
        return handled
    }

    static func installInterruptionMonitor(on test: XCTestCase) {
        test.addUIInterruptionMonitor(withDescription: "System permission alerts") { alert in
            for name in allowButtons where alert.buttons[name].exists {
                alert.buttons[name].tap()
                AppLab.log("interruption monitor: tapped \(name) on '\(alert.label)'")
                return true
            }
            return false
        }
    }

    // MARK: - Reading the native UI (skipping the chess.com web view)

    struct UIText {
        var identifier: String
        var label: String
        var type: XCUIElement.ElementType
    }

    /// All labelled native elements (static texts, buttons), excluding anything inside a web view.
    static func nativeTexts(_ app: XCUIApplication) -> [UIText] {
        guard let snap = try? app.snapshot() else { return [] }
        var out: [UIText] = []
        func walk(_ s: XCUIElementSnapshot) {
            if s.elementType == .webView { return }
            if (s.elementType == .staticText || s.elementType == .button), !s.label.isEmpty {
                out.append(UIText(identifier: s.identifier, label: s.label, type: s.elementType))
            }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return out
    }

    /// Texts inside the web view (to see whether chess.com loaded or a bot challenge is shown).
    static func webTexts(_ app: XCUIApplication, limit: Int = 120) -> [String] {
        guard let snap = try? app.snapshot() else { return [] }
        var out: [String] = []
        func walk(_ s: XCUIElementSnapshot, inWeb: Bool) {
            if out.count >= limit { return }
            let web = inWeb || s.elementType == .webView
            if web, !s.label.isEmpty { out.append(s.label) }
            for c in s.children { walk(c, inWeb: web) }
        }
        walk(snap, inWeb: false)
        return out
    }

    static func describe(_ texts: [UIText]) -> String {
        texts.map { t in
            let kind = t.type == .button ? "button" : "text"
            return t.identifier.isEmpty ? "\(kind): \(t.label)" : "\(kind)[\(t.identifier)]: \(t.label)"
        }.joined(separator: "\n")
    }

    /// First element matching any accessibility identifier, else any label containing one of the keywords.
    static func find(_ app: XCUIApplication, ids: [String], labelKeywords: [String],
                     type: XCUIElement.ElementType = .button) -> XCUIElement? {
        for id in ids {
            let e = app.descendants(matching: type).matching(identifier: id).firstMatch
            if e.exists { return e }
        }
        for kw in labelKeywords {
            let e = app.descendants(matching: type).matching(NSPredicate(format: "label CONTAINS[c] %@", kw)).firstMatch
            if e.exists { return e }
        }
        return nil
    }
}
