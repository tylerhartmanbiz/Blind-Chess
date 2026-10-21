//
//  PromptView.swift
//  Blind Chess
//
//  The open question (which piece, did you mean, promotion, resign, new game) with one button per answer.
//  The same answers work by voice.
//

import SwiftUI

struct PromptView: View {
    let prompt: GameController.Prompt
    let choose: (GameController.Choice) -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(prompt.question)
                .font(.headline)
                .foregroundStyle(Palette.color(for: .question))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("promptQuestion")
            ForEach(prompt.choices) { choice in
                Button {
                    choose(choice)
                } label: {
                    Text(choice.title)
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 54)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityIdentifier("choice-\(choice.id)")
            }
            if !prompt.choices.contains(where: { $0.id == "no" }) {
                Button("Cancel", action: cancel)
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Palette.secondaryText)
                    .accessibilityIdentifier("promptCancel")
            }
        }
    }
}
