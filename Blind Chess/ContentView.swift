//
//  ContentView.swift
//  Blind Chess
//
//  chess.com on top, controls below. Hiding the board slides the control panel over the web view instead of
//  removing it, so the game keeps running (and stays out of VoiceOver's way).
//

import SwiftUI

struct ContentView: View {
    @StateObject private var game = GameController()
    @AppStorage(AppSettings.boardVisible) private var boardVisible = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        GeometryReader { geometry in
            let boardHeight = min(geometry.size.height * 0.55, geometry.size.width + 140)
            ZStack(alignment: .top) {
                ChessWebView(bridge: game.bridge)
                    .frame(height: boardHeight)
                    .accessibilityHidden(!boardVisible)
                ControlPanel(game: game, listener: game.listener, isCompact: boardVisible)
                    .frame(height: boardVisible ? geometry.size.height - boardHeight : geometry.size.height)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .animation(.easeOut(duration: 0.25), value: boardVisible)
        }
        .background(Palette.background)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { _, phase in game.scenePhaseChanged(phase) }
    }
}

enum Palette {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let panel = Color(red: 0.11, green: 0.11, blue: 0.12)
    static let raised = Color(red: 0.18, green: 0.18, blue: 0.2)
    /// chess.com's board green.
    static let accent = Color(red: 0.506, green: 0.714, blue: 0.298)
    static let listening = Color(red: 0.93, green: 0.36, blue: 0.32)
    static let secondaryText = Color.white.opacity(0.72)

    static func color(for tone: GameController.Feedback.Tone) -> Color {
        switch tone {
        case .info: return .white
        case .success: return accent
        case .question: return Color(red: 0.98, green: 0.8, blue: 0.4)
        case .warning: return Color(red: 0.98, green: 0.7, blue: 0.4)
        case .error: return Color(red: 1, green: 0.5, blue: 0.47)
        }
    }
}

#Preview {
    ContentView()
}
