import XCTest
@testable import BlindChessCore

/// End-to-end accuracy of MoveResolver on real Apple recognizer transcripts (Tests/SpeechCorpus), board-aware.
/// See SpeechCorpusEvaluation.swift for the metric. Prints tables and asserts held-out floors so parser changes
/// cannot silently regress.
///
/// Environment:
///   SPEECH_CORPUS=1                       also run in debug builds (slow)
///   SPEECH_CORPUS_DUMP=/path/file.jsonl   write every non-correct clip (config, split, transcripts, outcome)
///   SPEECH_CORPUS_SPLIT=tune|heldout|all  which split the dump covers (default tune)
///   SPEECH_CORPUS_CONFIGS=a,b             configs to evaluate (default: all)
final class SpeechCorpusAccuracyTests: XCTestCase {
    /// The configuration the app uses (on-device + custom language model) and the app before this work (server).
    static let appConfig = "ondevice_lm"
    static let baselineConfig = "server"

    /// Held-out floors (correct = auto + confirm, as a fraction); raise them as accuracy improves.
    static let floors: [String: (correct: Double, maxWrong: Double)] = [
        // Measured 2026-10-21 before any parser tuning: ondevice_lm 56.0% / 5.7% wrong, ondevice_ctx 54.5% / 5.5%,
        // server 50.5% / 3.3%.
        "ondevice_lm": (0.55, 0.065),
        "ondevice_ctx": (0.535, 0.065),
        "server": (0.49, 0.045),
    ]

    func testCorpusAccuracy() throws {
        #if DEBUG
        // ~7 minutes unoptimised; CI runs it with `swift test -c release -Xswiftc -enable-testing`.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SPEECH_CORPUS"] == "1",
                          "release-only (or set SPEECH_CORPUS=1)")
        #endif
        let phrases = SpeechCorpus.loadPhrases()
        let clips = SpeechCorpus.loadClips()
        try XCTSkipIf(clips.isEmpty || phrases.isEmpty, "speech corpus not found")
        let environment = ProcessInfo.processInfo.environment
        let configs = environment["SPEECH_CORPUS_CONFIGS"].map { $0.split(separator: ",").map(String.init) }
            ?? SpeechCorpus.configs

        let start = Date()
        let candidates = ScenarioBuilder.candidates(pool: ScenarioBuilder.positionPool())
        var scenarios: [String: [Scenario]] = [:]
        for phrase in phrases.values where !SpeechCorpus.unsupportedPhrases.contains(phrase.id) {
            scenarios[phrase.id] = ScenarioBuilder.scenarios(for: phrase, in: candidates)
            if scenarios[phrase.id]!.isEmpty { XCTFail("no scenario for phrase \(phrase.id)") }
        }
        let setup = Date().timeIntervalSince(start)

        var rows: [EvaluationRow] = []
        for clip in clips {
            guard let phrase = phrases[clip.phraseID], let options = scenarios[clip.phraseID], !options.isEmpty else { continue }
            let scenario = options[Int(SpeechCorpus.fnv1a("scenario:" + clip.clip) % UInt64(options.count))]
            for config in configs {
                if let row = SpeechCorpus.evaluate(clip, phrase: phrase, config: config, scenario: scenario) { rows.append(row) }
            }
        }
        print(String(format: "speech corpus: %d clips, %d rows, setup %.1fs, total %.1fs", clips.count, rows.count,
                     setup, Date().timeIntervalSince(start)))

        let report = AccuracyReport(rows: rows)
        print(report.configTable(configs: configs))
        for config in [Self.appConfig, Self.baselineConfig] where configs.contains(config) {
            print(report.breakdown(config: config, split: "heldout"))
        }

        if let path = environment["SPEECH_CORPUS_DUMP"] {
            let split = environment["SPEECH_CORPUS_SPLIT"] ?? "tune"
            report.dump(to: path, split: split)
        }

        for (config, floor) in Self.floors where configs.contains(config) {
            let stats = report.stats(rows.filter { $0.config == config && $0.clip.split == "heldout" })
            XCTAssertGreaterThanOrEqual(stats.correct, floor.correct, "\(config) held-out correct rate regressed")
            XCTAssertLessThanOrEqual(stats.wrong, floor.maxWrong, "\(config) held-out wrong rate regressed")
        }
    }
}

struct AccuracyReport {
    let rows: [EvaluationRow]

    struct Stats {
        var n = 0
        var counts: [Outcome: Int] = [:]
        var wrongConfirm = 0
        func rate(_ outcome: Outcome) -> Double { n == 0 ? 0 : Double(counts[outcome, default: 0]) / Double(n) }
        var correct: Double { rate(.auto) + rate(.confirm) }
        var wrong: Double { rate(.wrong) }
    }

    func stats(_ subset: [EvaluationRow]) -> Stats {
        var stats = Stats()
        for row in subset {
            stats.n += 1
            stats.counts[row.outcome, default: 0] += 1
            if row.wrongConfirm { stats.wrongConfirm += 1 }
        }
        return stats
    }

    private func pct(_ value: Double) -> String { String(format: "%5.1f%%", value * 100) }

    private func line(_ label: String, _ stats: Stats) -> String {
        let label = label.padding(toLength: 28, withPad: " ", startingAt: 0)
        return "| \(label) | \(String(format: "%5d", stats.n)) | \(pct(stats.correct)) | \(pct(stats.rate(.auto))) | "
            + "\(pct(stats.rate(.confirm))) | \(pct(stats.rate(.clarify))) | \(pct(stats.rate(.safe))) | \(pct(stats.wrong)) |"
    }

    private var header: String {
        "| " + "".padding(toLength: 28, withPad: " ", startingAt: 0)
            + " |     n | correct |   auto | confirm | clarify |   safe |  WRONG |\n|---|---|---|---|---|---|---|---|"
    }

    func configTable(configs: [String]) -> String {
        var out = ["", "## Correct (auto + confirm) by config and split", header]
        for config in configs {
            for split in ["tune", "heldout"] {
                let subset = rows.filter { $0.config == config && $0.clip.split == split }
                out.append(line("\(config) \(split)", stats(subset)))
            }
        }
        return out.joined(separator: "\n")
    }

    func breakdown(config: String, split: String) -> String {
        let subset = rows.filter { $0.config == config && $0.clip.split == split }
        var out = ["", "## \(config), \(split)", header, line("ALL", stats(subset))]
        let realistic: Set<String> = ["clean", "quiet_-15", "slow", "fan_10", "white_20", "street_10", "living_10", "phone"]
        out.append(line("realistic (clean+mild)", stats(subset.filter { realistic.contains($0.clip.env) })))
        out.append(line("noisy (other envs)", stats(subset.filter { !realistic.contains($0.clip.env) })))
        func group(_ title: String, _ key: (EvaluationRow) -> String) {
            out.append("| **\(title)** | | | | | | | |")
            let keys = Set(subset.map(key)).sorted()
            for value in keys { out.append(line(value, stats(subset.filter { key($0) == value }))) }
        }
        group("environment") { $0.clip.env }
        group("voice source") { $0.clip.source }
        group("category") { $0.phrase.category }
        let wrongConfirm = stats(subset).wrongConfirm
        out.append("wrong move proposed with confirmation (counted as safe): \(wrongConfirm)")
        return out.joined(separator: "\n")
    }

    func dump(to path: String, split: String) {
        var lines: [String] = []
        for row in rows where row.outcome != .auto && (split == "all" || row.clip.split == split) {
            let object: [String: Any] = [
                "config": row.config, "split": row.clip.split, "clip": row.clip.clip, "phrase": row.phrase.id,
                "text": row.phrase.text, "env": row.clip.env, "source": row.clip.source, "outcome": row.outcome.rawValue,
                "result": row.detail, "context": row.context, "transcripts": row.clip.transcripts[row.config] ?? [],
            ]
            if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { lines.append(text) }
        }
        try? (lines.joined(separator: "\n") + "\n").write(toFile: path, atomically: true, encoding: .utf8)
        print("dumped \(lines.count) rows to \(path)")
    }
}
