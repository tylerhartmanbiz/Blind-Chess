//
//  VoicePanel.swift
//  Blind Chess
//
//  What was heard, permission problems, and the microphone button.
//

import SwiftUI
import UIKit

struct VoicePanel: View {
    @ObservedObject var game: GameController
    @ObservedObject var listener: SpeechRecognizer
    let isCompact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 10) {
            problem
            Text(transcript)
                .font(.title3.weight(.medium))
                .foregroundStyle(transcriptIsPlaceholder ? Palette.secondaryText : .white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("transcriptText")
            micButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    @ViewBuilder private var problem: some View {
        switch listener.status {
        case .denied(let message):
            VStack(spacing: 8) {
                Text(message)
                    .foregroundStyle(Palette.color(for: .error))
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("permissionMessage")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
                .accessibilityIdentifier("openSettingsButton")
            }
        case .unavailable(let message):
            Text(message)
                .foregroundStyle(Palette.color(for: .warning))
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("permissionMessage")
        default:
            EmptyView()
        }
    }

    private var transcriptIsPlaceholder: Bool { listener.partialTranscript.isEmpty && game.heard.isEmpty }

    private var transcript: String {
        if !listener.partialTranscript.isEmpty { return listener.partialTranscript }
        if !game.heard.isEmpty { return "“\(game.heard)”" }
        return listener.isOn ? "Listening…" : "Tap the microphone and say a move"
    }

    private var isListening: Bool { listener.status == .listening }

    private var micButton: some View {
        let size: CGFloat = isCompact ? 84 : 132
        return Button {
            game.toggleListening()
        } label: {
            ZStack {
                if isListening && !reduceMotion {
                    PulseRing(color: Palette.listening, size: size)
                }
                Circle()
                    .fill(listener.isOn ? Palette.listening : Palette.accent)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
                Image(systemName: micSymbol)
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: size + 24, height: size + 24)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(micLabel)
        .accessibilityHint(listener.isOn ? "Stops listening" : "Starts listening for moves and commands")
        .accessibilityIdentifier("micButton")
    }

    private var micSymbol: String {
        switch listener.status {
        case .paused: return "speaker.wave.2.fill"
        case .listening, .starting: return "waveform"
        default: return "mic.fill"
        }
    }

    /// The idle label must not contain "listening": the UI tests use that word to tell the states apart.
    private var micLabel: String {
        switch listener.status {
        case .listening, .starting: return "Listening. Tap to stop"
        case .paused: return "Listening paused while speaking. Tap to stop"
        default: return "Microphone off. Tap to speak"
        }
    }
}

private struct PulseRing: View {
    let color: Color
    let size: CGFloat
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(color.opacity(expanded ? 0 : 0.6), lineWidth: 3)
            .frame(width: size, height: size)
            .scaleEffect(expanded ? 1.25 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { expanded = true }
            }
            .accessibilityHidden(true)
    }
}
