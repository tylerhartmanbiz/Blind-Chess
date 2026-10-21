// SpeechAnalyzer / SpeechTranscriber / DictationTranscriber (macOS 26 / iOS 26).
import AVFoundation
import Foundation
import Speech

nonisolated(unsafe) var analyzerAssetsReady: [String: String] = [:]

@available(macOS 26, iOS 26, *)
func ensureAssets(_ key: String, _ modules: [any SpeechModule]) async -> String {
    if let s = analyzerAssetsReady[key] { return s }
    var status = "ok"
    do {
        if let req = try await AssetInventory.assetInstallationRequest(supporting: modules) {
            try await req.downloadAndInstall()
            status = "ok(downloaded)"
        }
    } catch { status = "asset-error: \(describe(error))" }
    analyzerAssetsReady[key] = status
    err("analyzer assets \(key): \(status)")
    return status
}

@available(macOS 26, iOS 26, *)
func makeContext(_ ctx: [String]) -> AnalysisContext {
    let c = AnalysisContext()
    c.contextualStrings[AnalysisContext.ContextualStringsTag.general] = ctx
    return c
}

@available(macOS 26, iOS 26, *)
func runST(url: URL, ctx: [String]?) async throws -> [String: Any] {
    let start = Date()
    let t = SpeechTranscriber(locale: Locale(identifier: "en-US"), transcriptionOptions: [],
                              reportingOptions: [.alternativeTranscriptions], attributeOptions: [])
    if analyzerAssetsReady["st"] == nil { err("st reserve: \(await reserveLocaleHook())") }
    _ = await ensureAssets("st", [t])
    let analyzer = SpeechAnalyzer(modules: [t])
    if let ctx { try await analyzer.setContext(makeContext(ctx)) }
    let collector = Task { () throws -> [[String]] in
        var out: [[String]] = []
        for try await r in t.results where r.isFinal {
            out.append([String(r.text.characters)] + r.alternatives.map { String($0.characters) })
        }
        return out
    }
    let file = try AVAudioFile(forReading: url)
    if let last = try await analyzer.analyzeSequence(from: file) {
        try await analyzer.finalizeAndFinish(through: last)
    } else {
        await analyzer.cancelAndFinishNow()
    }
    return pack(try await collector.value, start)
}

@available(macOS 26, iOS 26, *)
func runDict(url: URL, ctx: [String]?) async throws -> [String: Any] {
    let start = Date()
    let t = DictationTranscriber(locale: Locale(identifier: "en-US"), contentHints: [.shortForm], transcriptionOptions: [],
                                 reportingOptions: [.alternativeTranscriptions], attributeOptions: [])
    _ = await ensureAssets("dict", [t])
    let analyzer = SpeechAnalyzer(modules: [t])
    if let ctx { try await analyzer.setContext(makeContext(ctx)) }
    let collector = Task { () throws -> [[String]] in
        var out: [[String]] = []
        for try await r in t.results where r.isFinal {
            out.append([String(r.text.characters)] + r.alternatives.map { String($0.characters) })
        }
        return out
    }
    let file = try AVAudioFile(forReading: url)
    if let last = try await analyzer.analyzeSequence(from: file) {
        try await analyzer.finalizeAndFinish(through: last)
    } else {
        await analyzer.cancelAndFinishNow()
    }
    return pack(try await collector.value, start)
}

/// parts: one entry per final result, [text, alt1, alt2...]. nbest = joined variants.
func pack(_ parts: [[String]], _ start: Date) -> [String: Any] {
    let trim = { (s: String) in s.trimmingCharacters(in: .whitespacesAndNewlines) }
    let best = parts.map { trim($0.first ?? "") }.filter { !$0.isEmpty }.joined(separator: " ")
    var nbest: [String] = [best]
    if parts.count == 1 {
        for a in parts[0].dropFirst() where !nbest.contains(trim(a)) && nbest.count < 5 { nbest.append(trim(a)) }
    } else {
        // vary one result at a time
        for (i, p) in parts.enumerated() {
            for a in p.dropFirst() {
                var v = parts.map { trim($0.first ?? "") }
                v[i] = trim(a)
                let s = v.filter { !$0.isEmpty }.joined(separator: " ")
                if !nbest.contains(s) && nbest.count < 5 { nbest.append(s) }
            }
        }
    }
    return ["best": best, "nbest": nbest, "latency_ms": ms(since: start)]
}

func analyzerRecognize(kind: String, url: URL, ctx: [String]) async -> [String: Any] {
    guard #available(macOS 26, iOS 26, *) else { return ["error": "needs macOS 26"] }
    do {
        switch kind {
        case "st": return try await runST(url: url, ctx: nil)
        case "st_ctx": return try await runST(url: url, ctx: ctx)
        case "dict": return try await runDict(url: url, ctx: nil)
        case "dict_ctx": return try await runDict(url: url, ctx: ctx)
        default: return ["error": "bad kind"]
        }
    } catch {
        return ["error": describe(error)]
    }
}

func analyzerProbe() async {
    guard #available(macOS 26, iOS 26, *) else { print("analyzer: macOS < 26"); return }
    print("SpeechTranscriber.isAvailable=\(SpeechTranscriber.isAvailable)")
    let sup = await SpeechTranscriber.supportedLocales.map { $0.identifier }.filter { $0.hasPrefix("en") }
    let inst = await SpeechTranscriber.installedLocales.map { $0.identifier }
    print("SpeechTranscriber supported(en)=\(sup) installed=\(inst)")
    let dsup = await DictationTranscriber.supportedLocales.map { $0.identifier }.filter { $0.hasPrefix("en") }
    print("DictationTranscriber supported(en)=\(dsup)")
}
