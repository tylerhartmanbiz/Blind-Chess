//
//  ButtonPad.swift
//  Blind Chess
//
//  Tap a piece (optional), a file and a rank, then Play. The move goes through the same resolver as speech,
//  so ambiguity, promotion and illegal moves are handled the same way.
//

import SwiftUI

struct ButtonPad: View {
    @ObservedObject var game: GameController
    @State private var piece: PieceKind?
    @State private var file: Int?
    @State private var rank: Int?

    private static let pieces: [PieceKind?] = [nil, .pawn, .knight, .bishop, .rook, .queen, .king]

    var body: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(Self.pieces, id: \.self) { kind in
                    PadButton(title: kind?.name.capitalized ?? "Any", isSelected: piece == kind) { piece = kind }
                        .accessibilityLabel(kind.map { "\($0.name)" } ?? "Any piece")
                }
            }
            row(count: 8, title: { String(Square.fileLetters[$0]).uppercased() }, selected: $file, label: "file")
            row(count: 8, title: { String($0 + 1) }, selected: $rank, label: "rank")
            Button(action: play) {
                Text(playTitle)
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 54)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canPlay ? Color.black : Palette.secondaryText)
            .background(canPlay ? Palette.accent : Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .disabled(!canPlay)
            .accessibilityIdentifier("playMoveButton")
        }
    }

    private func row(count: Int, title: @escaping (Int) -> String, selected: Binding<Int?>, label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { index in
                PadButton(title: title(index), isSelected: selected.wrappedValue == index) {
                    selected.wrappedValue = index
                }
                .accessibilityLabel("\(label) \(title(index))")
            }
        }
    }

    private var canPlay: Bool { file != nil && rank != nil }

    private var playTitle: String {
        guard let file, let rank, let square = Square(file: file, rank: rank) else { return "Choose a square" }
        return "Play \(piece?.name.capitalized ?? "move") to \(square.name)"
    }

    private func play() {
        guard let file, let rank else { return }
        game.submit(MoveIntent(piece: piece, toFile: file, toRank: rank))
        piece = nil
        self.file = nil
        self.rank = nil
    }
}

private struct PadButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Color.black : .white)
        .background(isSelected ? Palette.accent : Palette.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
