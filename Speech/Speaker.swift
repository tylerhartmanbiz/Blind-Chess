//
//  Speaker.swift
//  Blind Chess
//
//  Text-to-speech for announcements. Reports when it starts and stops talking so the recognizer can pause
//  and not hear the app's own voice. With speech turned off, VoiceOver users still get the text as an
//  accessibility announcement.
//

import AVFoundation
import Combine
import UIKit

@MainActor
final class Speaker: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    /// Called with true when speech starts and false once the queue is empty.
    var onSpeakingChanged: ((Bool) -> Void)?

    private let synthesizer = AVSpeechSynthesizer()
    private var queued = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        guard AppSettings.isSpeechEnabled else {
            if UIAccessibility.isVoiceOverRunning { UIAccessibility.post(notification: .announcement, argument: text) }
            return
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.prefersAssistiveTechnologySettings = true
        try? AudioSession.activate()
        queued += 1
        setSpeaking(true)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishedOne() {
        queued = max(0, queued - 1)
        if queued == 0 { setSpeaking(false) }
    }

    private func setSpeaking(_ speaking: Bool) {
        guard speaking != isSpeaking else { return }
        isSpeaking = speaking
        onSpeakingChanged?(speaking)
    }
}

extension Speaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finishedOne() }
    }
}
