// SpeechLab recognizer: runs Apple's speech recognizers over a manifest of audio clips.
//
//   speechlab auth                         print / request speech-recognition authorization
//   speechlab probe <wav>                  recognise one file with every available config
//   speechlab run --manifest m.jsonl --out o.jsonl --configs a,b,c [--root dir] [--limit N]
//
// Configs:
//   server        SFSpeechRecognizer en-US, default (server allowed), no hints   (what the app does today)
//   server_ctx    same + contextualStrings (chess vocabulary)
//   ondevice      SFSpeechRecognizer requiresOnDeviceRecognition = true
//   ondevice_ctx  on-device + contextualStrings
//   ondevice_lm   on-device + custom language model (SFCustomLanguageModelData, macOS 14+)
//   st / st_ctx   SpeechAnalyzer + SpeechTranscriber (macOS 26), optionally with AnalysisContext strings
//   dict / dict_ctx  SpeechAnalyzer + DictationTranscriber (macOS 26)

import AVFoundation
import Foundation
import Speech

let chessContextualStrings: [String] = {
    var s = ["knight", "bishop", "rook", "queen", "king", "pawn", "takes", "captures", "castle", "castles",
             "kingside", "queenside", "promote", "check", "checkmate", "resign", "new game", "repeat", "undo",
             "where is my", "the one on"]
    for f in "abcdefgh" { for r in 1...8 { s.append("\(f)\(r)") } }
    return s
}()

final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ v: T) { value = v }
}

final class Once: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func run(_ f: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if done { return }
        done = true
        f()
    }
}

func describe(_ error: Error) -> String {
    let e = error as NSError
    return "\(e.domain)#\(e.code): \(e.localizedDescription)"
}

func ms(since start: Date) -> Int { Int(Date().timeIntervalSince(start) * 1000) }

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

let recognizer: SFSpeechRecognizer = {
    let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))!
    r.queue = OperationQueue()
    return r
}()

func sfRecognize(url: URL, onDevice: Bool, ctx: [String]?, lm: AnyObject?, timeout: Double = 30) async -> [String: Any] {
    let start = Date()
    return await withCheckedContinuation { (cont: CheckedContinuation<[String: Any], Never>) in
        let once = Once()
        let req = SFSpeechURLRecognitionRequest(url: url)
        req.shouldReportPartialResults = false
        req.requiresOnDeviceRecognition = onDevice
        if let ctx { req.contextualStrings = ctx }
        if let lm { applyLM(lm, to: req) }
        let taskBox = Box<SFSpeechRecognitionTask?>(nil)
        taskBox.value = recognizer.recognitionTask(with: req) { result, error in
            if let result, result.isFinal {
                let best = result.bestTranscription
                let segs = best.segments
                let conf = segs.isEmpty ? 0 : segs.map { Double($0.confidence) }.reduce(0, +) / Double(segs.count)
                var row: [String: Any] = [
                    "best": best.formattedString,
                    "nbest": Array(result.transcriptions.prefix(5).map { $0.formattedString }),
                    "conf": (conf * 1000).rounded() / 1000,
                    "latency_ms": ms(since: start),
                ]
                let alts = segs.compactMap { s -> [String]? in s.alternativeSubstrings.isEmpty ? nil : [s.substring] + s.alternativeSubstrings }
                if !alts.isEmpty { row["seg_alts"] = alts }
                once.run { cont.resume(returning: row) }
                return
            }
            if let error {
                let ns = error as NSError
                // 1110 = "No speech detected": a valid (empty) answer, not a failure.
                if ns.code == 1110 {
                    once.run { cont.resume(returning: ["best": "", "nbest": [String](), "latency_ms": ms(since: start), "note": describe(error)]) }
                } else {
                    once.run { cont.resume(returning: ["error": describe(error), "latency_ms": ms(since: start)]) }
                }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            once.run {
                taskBox.value?.cancel()
                cont.resume(returning: ["error": "timeout", "latency_ms": ms(since: start)])
            }
        }
    }
}

func authStatusName(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
    switch s {
    case .authorized: return "authorized"
    case .denied: return "denied"
    case .restricted: return "restricted"
    case .notDetermined: return "notDetermined"
    @unknown default: return "unknown"
    }
}

func ensureAuthorized(timeout: Double = 20) async -> String {
    let now = SFSpeechRecognizer.authorizationStatus()
    if now != .notDetermined { return authStatusName(now) }
    return await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
        let once = Once()
        SFSpeechRecognizer.requestAuthorization { st in once.run { cont.resume(returning: authStatusName(st)) } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.run { cont.resume(returning: "request-timeout(\(authStatusName(SFSpeechRecognizer.authorizationStatus())))") } }
    }
}

func jsonLine(_ obj: Any) -> String {
    let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .withoutEscapingSlashes])
    return String(data: d, encoding: .utf8)!
}

var lmHandle: AnyObject?
var lmError: String?

func recognize(config: String, url: URL) async -> [String: Any] {
    switch config {
    case "server": return await sfRecognize(url: url, onDevice: false, ctx: nil, lm: nil)
    case "server_ctx": return await sfRecognize(url: url, onDevice: false, ctx: chessContextualStrings, lm: nil)
    case "ondevice": return await sfRecognize(url: url, onDevice: true, ctx: nil, lm: nil)
    case "ondevice_ctx": return await sfRecognize(url: url, onDevice: true, ctx: chessContextualStrings, lm: nil)
    case "ondevice_lm":
        if lmHandle == nil && lmError == nil {
            do { lmHandle = try await buildLanguageModel() } catch { lmError = describe(error) }
            err("custom LM: \(lmHandle != nil ? "ready" : "failed: \(lmError ?? "?")")")
        }
        guard let lm = lmHandle else { return ["error": "lm unavailable: \(lmError ?? "?")"] }
        return await sfRecognize(url: url, onDevice: true, ctx: nil, lm: lm)
    case "st", "st_ctx", "dict", "dict_ctx":
        return await analyzerRecognize(kind: config, url: url, ctx: chessContextualStrings)
    default:
        return ["error": "unknown config \(config)"]
    }
}

func runManifest(args: [String: String]) async {
    guard let manifest = args["manifest"], let out = args["out"] else { err("need --manifest and --out"); exit(2) }
    let configs = (args["configs"] ?? "server,ondevice").split(separator: ",").map(String.init)
    let root = URL(fileURLWithPath: args["root"] ?? ".")
    let limit = Int(args["limit"] ?? "") ?? Int.max
    // Optional per-config clip filter: --only server=clean  (env must equal value) or server=every:4
    var configFilter: [String: String] = [:]
    for f in (args["filter"] ?? "").split(separator: ";") {
        let kv = f.split(separator: "=", maxSplits: 1).map(String.init)
        if kv.count == 2 { configFilter[kv[0]] = kv[1] }
    }
    let text = try! String(contentsOfFile: manifest, encoding: .utf8)
    FileManager.default.createFile(atPath: out, contents: nil)
    let fh = FileHandle(forWritingAtPath: out)!
    var n = 0
    let t0 = Date()
    var stats: [String: (Int, Int, Int)] = [:] // config -> (count, errors, total latency)
    for (i, line) in text.split(separator: "\n").enumerated() {
        if i >= limit { break }
        guard let data = line.data(using: .utf8),
              let clip = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = clip["path"] as? String else { continue }
        let url = root.appendingPathComponent(path)
        for config in configs {
            if let f = configFilter[config] {
                if f.hasPrefix("every:"), let k = Int(f.dropFirst(6)), i % k != 0 { continue }
                if f.hasPrefix("env:"), (clip["env"] as? String) != String(f.dropFirst(4)) { continue }
            }
            var row = clip
            row["config"] = config
            let r = await recognize(config: config, url: url)
            for (k, v) in r { row[k] = v }
            fh.write((jsonLine(row) + "\n").data(using: .utf8)!)
            var s = stats[config] ?? (0, 0, 0)
            s.0 += 1
            if r["error"] != nil { s.1 += 1 }
            s.2 += (r["latency_ms"] as? Int) ?? 0
            stats[config] = s
            n += 1
        }
        if i % 100 == 0 {
            let summary = stats.map { "\($0.key):\($0.value.0)/err\($0.value.1)/avg\($0.value.0 > 0 ? $0.value.2 / $0.value.0 : 0)ms" }.sorted().joined(separator: " ")
            err("[\(Int(Date().timeIntervalSince(t0)))s] clip \(i) rows \(n) \(summary)")
        }
    }
    fh.closeFile()
    let summary = stats.map { "\($0.key):\($0.value.0)/err\($0.value.1)/avg\($0.value.0 > 0 ? $0.value.2 / $0.value.0 : 0)ms" }.sorted().joined(separator: " ")
    err("done rows=\(n) in \(Int(Date().timeIntervalSince(t0)))s \(summary)")
}

func parseArgs(_ a: [String]) -> [String: String] {
    var d: [String: String] = [:]
    var i = 0
    while i < a.count {
        if a[i].hasPrefix("--"), i + 1 < a.count { d[String(a[i].dropFirst(2))] = a[i + 1]; i += 2 } else { i += 1 }
    }
    return d
}

@main
struct SpeechLabMain {
    static func main() async {
        setvbuf(stdout, nil, _IOLBF, 0)
        let argv = CommandLine.arguments
        let cmd = argv.count > 1 ? argv[1] : "auth"
        let auth = await ensureAuthorized()
        print("auth=\(auth) onDeviceSupported=\(recognizer.supportsOnDeviceRecognition) available=\(recognizer.isAvailable) pid=\(getpid()) exe=\(argv[0])")
        switch cmd {
        case "auth":
            await analyzerProbe()
        case "probe":
            let url = URL(fileURLWithPath: argv[2])
            await analyzerProbe()
            for c in ["server", "server_ctx", "ondevice", "ondevice_ctx", "ondevice_lm", "st", "st_ctx", "dict", "dict_ctx"] {
                let r = await recognize(config: c, url: url)
                print("PROBE \(c): \(jsonLine(r))")
            }
        case "run":
            await runManifest(args: parseArgs(Array(argv.dropFirst(2))))
        default:
            err("unknown command \(cmd)")
            exit(2)
        }
        exit(0)
    }
}
