//
//  ControlPanel.swift
//  Blind Chess
//
//  Toolbar, game status, the current question (if any) and the active input mode.
//

import SwiftUI

struct ControlPanel: View {
    @ObservedObject var game: GameController
    @ObservedObject var listener: SpeechRecognizer
    /// True while the board takes the top of the screen.
    let isCompact: Bool

    @AppStorage(AppSettings.buttonMode) private var buttonMode = false

    var body: some View {
        VStack(spacing: 0) {
            Toolbar(game: game)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StatusView(game: game)
                    if let prompt = game.prompt {
                        PromptView(prompt: prompt, choose: game.choose, cancel: { game.cancelPrompt() })
                    } else if buttonMode {
                        ButtonPad(game: game)
                    }
                    if !isCompact && game.prompt == nil { QuickActions(game: game) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            if !buttonMode {
                VoicePanel(game: game, listener: listener, isCompact: isCompact)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.panel)
    }
}

private struct Toolbar: View {
    @ObservedObject var game: GameController
    @AppStorage(AppSettings.buttonMode) private var buttonMode = false
    @AppStorage(AppSettings.speechEnabled) private var speechEnabled = true
    @AppStorage(AppSettings.boardVisible) private var boardVisible = true

    var body: some View {
        HStack(spacing: 8) {
            ToolbarToggle(systemImage: buttonMode ? "square.grid.3x3.fill" : "mic.fill",
                          title: buttonMode ? "Buttons" : "Voice",
                          label: buttonMode ? "Input mode: buttons" : "Input mode: voice",
                          hint: "Switches between voice and button input") {
                buttonMode.toggle()
                if buttonMode, game.listener.isOn { game.listener.stop() }
            }
            .accessibilityIdentifier("inputModeToggle")

            ToolbarToggle(systemImage: speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                          title: speechEnabled ? "Speech" : "Muted",
                          label: speechEnabled ? "Spoken announcements on" : "Spoken announcements off",
                          hint: "Turns spoken announcements on or off") {
                speechEnabled.toggle()
                if !speechEnabled { game.speaker.stop() }
            }
            .accessibilityIdentifier("speechToggle")

            ToolbarToggle(systemImage: boardVisible ? "eye.fill" : "eye.slash.fill",
                          title: boardVisible ? "Board" : "Blind",
                          label: boardVisible ? "Board shown" : "Board hidden",
                          hint: "Shows or hides the chess board") {
                boardVisible.toggle()
            }
            .accessibilityIdentifier("boardVisibilityToggle")

            Spacer(minLength: 0)

            Menu {
                Button("New game", systemImage: "plus.circle") { game.askNewGame() }
                Button("Take back", systemImage: "arrow.uturn.backward") { game.undo() }
                Button("Resign", systemImage: "flag", role: .destructive) { game.perform(.resign) }
                Button("Help", systemImage: "questionmark.circle") { game.perform(.help) }
                if game.loadError != nil {
                    Button("Reload chess.com", systemImage: "arrow.clockwise") { game.reload() }
                }
            } label: {
                Label("Game", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Game menu")
            .accessibilityIdentifier("gameMenu")
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .foregroundStyle(.white)
    }
}

private struct ToolbarToggle: View {
    let systemImage: String
    let title: String
    let label: String
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Palette.secondaryText)
            }
            .frame(minWidth: 58, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }
}

/// Whose turn, the last move of each side, and the latest message.
private struct StatusView: View {
    @ObservedObject var game: GameController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(game.statusLine)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(game.isMyTurn ? Palette.accent : .white)
                    .accessibilityIdentifier("statusText")
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if let color = game.userColor {
                    Text(color == .white ? "White" : "Black")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .foregroundStyle(color == .white ? Color.black : .white)
                        .background(color == .white ? Color.white : Palette.raised, in: Capsule())
                        .accessibilityLabel("You play \(color.name)")
                }
            }
            if game.lastUserMove != nil || game.lastOpponentMove != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let move = game.lastOpponentMove {
                        Text("Opponent: \(move)").accessibilityIdentifier("opponentLastMove")
                    }
                    if let move = game.lastUserMove {
                        Text("You: \(move)").accessibilityIdentifier("userLastMove")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(Palette.secondaryText)
            }
            if let feedback = game.feedback {
                Text(feedback.text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Palette.color(for: feedback.tone))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedbackText")
            }
        }
    }
}

/// Large shortcuts for playing without the board.
private struct QuickActions: View {
    @ObservedObject var game: GameController

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            action("Last move", "arrow.counterclockwise", id: "quickLastMove") { game.perform(.repeatLastMove) }
            action("Whose turn", "person.2", id: "quickWhoseTurn") { game.perform(.whoseTurn) }
            action("My pieces", "list.bullet", id: "quickMyPieces") { game.perform(.listPieces(.mine)) }
            action("Read board", "square.grid.3x3", id: "quickReadBoard") { game.perform(.readBoard) }
        }
    }

    private func action(_ title: String, _ systemImage: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityIdentifier(id)
    }
}
