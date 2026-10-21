//
//  SpeechRecognizer.swift
//  Blind Chess
//
//  Continuous listening for moves. One recognition request per utterance: partial results are only displayed;
//  the n-best list is delivered once the utterance ends (a final result, or `utteranceEndDelay` without a
//  change), then a fresh request starts. Tasks that fail (silence timeouts, the server's one-minute limit)
//  are restarted. Listening pauses while the app speaks, during audio interruptions and in the background.
//

import AVFoundation
import Combine
import Speech

@MainActor
final class SpeechRecognizer: ObservableObject {
    enum Status: Equatable {
        case off
        case starting
        case listening
        /// Wants to listen but is held by app speech, an interruption or the background.
        case paused
        case denied(String)
        case unavailable(String)
    }

    enum PauseReason {
        case speaking, interruption, background
    }

    @Published private(set) var status: Status = .off
    /// The words heard so far in the current utterance (display only).
    @Published private(set) var partialTranscript = ""
    /// Receives the recognizer's alternatives (best first) for each finished utterance.
    var onUtterance: (([String]) -> Void)?

    var isOn: Bool { wantsListening }

    private static let utteranceEndDelay: Duration = .milliseconds(1000)
    private static let resumeAfterSpeechDelay: Duration = .milliseconds(350)
    /// Recycle a task this old that has heard nothing, before the server's one-minute limit ends it.
    private static let idleTaskLifetime: Duration = .seconds(50)
    private nonisolated static let alternatives = 5

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private let feed = AudioFeed()
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private var heard: [String] = []
    private var utteranceTimer: Task<Void, Never>?
    private var idleTimer: Task<Void, Never>?
    private var resumeTimer: Task<Void, Never>?
    private var wantsListening = false
    private var pauses: Set<PauseReason> = []
    private var failures = 0
    private var useOnDevice = true
    private var languageModel: SFSpeechLanguageModel.Configuration?
    private var languageModelRequested = false
    private var observers: [NSObjectProtocol] = []

    init() {
        observeAudioSession()
    }

    // MARK: - Control

    func start() async {
        guard !wantsListening else { return }
        wantsListening = true
        status = .starting
        guard await authorize() else {
            wantsListening = false
            return
        }
        prepareLanguageModel()
        startAudio()
    }

    func stop() {
        wantsListening = false
        resumeTimer?.cancel()
        teardown()
        status = .off
    }

    func pause(_ reason: PauseReason) {
        pauses.insert(reason)
        resumeTimer?.cancel()
        guard wantsListening else { return }
        teardown()
        status = .paused
    }

    func resume(_ reason: PauseReason) {
        pauses.remove(reason)
        guard wantsListening, pauses.isEmpty else { return }
        resumeTimer?.cancel()
        resumeTimer = Task {
            // Let the speaker's tail fade so it is not picked up as the start of an utterance.
            if reason == .speaking { try? await Task.sleep(for: Self.resumeAfterSpeechDelay) }
            guard !Task.isCancelled else { return }
            startAudio()
        }
    }

    // MARK: - Audio

    private func startAudio() {
        guard wantsListening, pauses.isEmpty else { return }
        guard let recognizer, recognizer.isAvailable else {
            status = .unavailable("Speech recognition isn't available right now. Check the internet connection and try again.")
            wantsListening = false
            return
        }
        do {
            try AudioSession.activate()
            if !engine.isRunning {
                let input = engine.inputNode
                input.removeTap(onBus: 0)
                let format = input.outputFormat(forBus: 0)
                guard format.sampleRate > 0, format.channelCount > 0 else {
                    throw RecognizerError("No microphone is available.")
                }
                Self.installTap(on: input, format: format, feed: feed)
                engine.prepare()
                try engine.start()
            }
            status = .listening
            beginUtterance()
        } catch {
            Log.error("audio start failed: \(error.localizedDescription)")
            teardown()
            wantsListening = false
            status = .unavailable("The microphone couldn't start. \(error.localizedDescription)")
        }
    }

    private func teardown() {
        generation += 1
        endTask()
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        heard = []
        partialTranscript = ""
    }

    // MARK: - Utterances

    private func beginUtterance() {
        endTask()
        guard let recognizer, status == .listening else { return }
        generation += 1
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = false
        request.contextualStrings = RecognitionHints.contextualStrings
        if useOnDevice, recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            if let languageModel { request.customizedLanguageModel = languageModel }
        }
        feed.request = request
        let current = generation
        task = Self.recognitionTask(recognizer, request) { [weak self] update in
            self?.handle(update, generation: current)
        }
        heard = []
        partialTranscript = ""
        idleTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTaskLifetime)
            guard !Task.isCancelled, let self, self.generation == current, self.heard.isEmpty else { return }
            self.beginUtterance()
        }
    }

    private func endTask() {
        utteranceTimer?.cancel()
        idleTimer?.cancel()
        feed.request?.endAudio()
        feed.request = nil
        task?.cancel()
        task = nil
    }

    private func handle(_ update: RecognitionUpdate, generation current: Int) {
        guard current == generation else { return }
        if let error = update.error {
            // Speech already heard still counts; otherwise start over after a short, growing pause.
            if heard.isEmpty { restartAfterFailure(error) } else { deliver() }
            return
        }
        failures = 0
        if !update.transcripts.isEmpty {
            heard = update.transcripts
            partialTranscript = update.transcripts[0]
        }
        if update.isFinal {
            deliver()
            return
        }
        utteranceTimer?.cancel()
        utteranceTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.utteranceEndDelay)
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.deliver()
        }
    }

    /// Hands the finished utterance to `onUtterance` and starts listening for the next one.
    private func deliver() {
        let transcripts = heard.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        heard = []
        endTask()
        if !transcripts.isEmpty {
            Log.info("heard: \(transcripts.joined(separator: " | "))")
            onUtterance?(transcripts)
        }
        // onUtterance may have paused listening (the app started speaking).
        if status == .listening { beginUtterance() }
    }

    private func restartAfterFailure(_ error: String) {
        failures += 1
        Log.info("recognition ended: \(error) (failure \(failures))")
        if failures >= 3, useOnDevice, recognizer?.supportsOnDeviceRecognition == true {
            Log.error("on-device recognition keeps failing, using server recognition")
            useOnDevice = false
        }
        endTask()
        let current = generation
        let delay = Duration.milliseconds(min(2000, 150 * (1 << min(failures, 4))))
        utteranceTimer = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.beginUtterance()
        }
    }

    // MARK: - Permissions and setup

    private func authorize() async -> Bool {
        guard await Self.speechAuthorization() == .authorized else {
            Log.info("Speech recognition denied")
            status = .denied("Blind Chess needs Speech Recognition permission to hear your moves. Turn it on in Settings.")
            return false
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            Log.info("Microphone denied")
            status = .denied("Blind Chess needs the microphone to hear your moves. Turn it on in Settings.")
            return false
        }
        Log.info("Speech recognition authorized (on-device available: \(recognizer?.supportsOnDeviceRecognition == true))")
        return true
    }

    private func prepareLanguageModel() {
        guard !languageModelRequested, recognizer?.supportsOnDeviceRecognition == true else { return }
        languageModelRequested = true
        Task { [weak self] in
            let model = await ChessLanguageModel.prepare()
            self?.languageModel = model
        }
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            MainActor.assumeIsolated {
                switch raw.flatMap({ AVAudioSession.InterruptionType(rawValue: $0) }) {
                case .began?: self?.pause(.interruption)
                case .ended?: self?.resume(.interruption)
                default: break
                }
            }
        })
        // A new route (headset, Bluetooth) or engine reconfiguration changes the input format: restart the tap.
        for name in [AVAudioSession.routeChangeNotification, Notification.Name.AVAudioEngineConfigurationChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restartAudioIfRunning() }
            })
        }
    }

    private func restartAudioIfRunning() {
        guard status == .listening else { return }
        Log.info("audio route changed, restarting the microphone")
        teardown()
        startAudio()
    }

    // MARK: - Off the main actor

    private nonisolated static func installTap(on node: AVAudioInputNode, format: AVAudioFormat, feed: AudioFeed) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            feed.append(buffer)
        }
    }

    private nonisolated static func recognitionTask(
        _ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @MainActor @Sendable (RecognitionUpdate) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let update = RecognitionUpdate(
                transcripts: result.map { Array($0.transcriptions.prefix(alternatives).map(\.formattedString)) } ?? [],
                isFinal: result?.isFinal ?? false,
                error: error.map { "\(($0 as NSError).domain) \(($0 as NSError).code): \($0.localizedDescription)" })
            Task { @MainActor in handler(update) }
        }
    }

    private nonisolated static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
    }
}

private nonisolated struct RecognitionUpdate: Sendable {
    let transcripts: [String]
    let isFinal: Bool
    let error: String?
}

private nonisolated struct RecognizerError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// The current request, shared with the audio thread that appends microphone buffers to it.
private nonisolated final class AudioFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}

/// One audio session for listening and speaking: play-and-record through the speaker (or Bluetooth headset).
enum AudioSession {
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        if session.category != .playAndRecord {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        }
        try session.setActive(true)
    }
}
