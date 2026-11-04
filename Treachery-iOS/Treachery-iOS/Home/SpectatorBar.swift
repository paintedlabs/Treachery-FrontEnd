//
//  SpectatorBar.swift
//  Treachery-iOS
//

import SwiftUI

/// The bar every eliminated player gets, in every game mode: its Leave is
/// their only way off the board.
struct SpectatorBar: View {
    let leave: GameBoardViewModel.SpectatorLeave
    let onGoHome: () -> Void
    let onEndGame: () -> Void
    @State private var isConfirmingLeave = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// How strongly the bar's red wash shows over the board.
    static let washOpacity = 0.1

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // At the accessibility text sizes the bar keeps to the title,
                // with the whole width, and Leave Game, so the two fit in the
                // pinned controls. VoiceOver says as much on elimination.
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "person.slash.fill")
                        .foregroundStyle(Color.mtgError)
                        .accessibilityHidden(true)
                }
                Text("You've Been Eliminated")
                    .font(.system(.headline, design: .serif))
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mtgErrorText)
                    .multilineTextAlignment(.center)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Text("You're now spectating. Watch the game unfold or leave.")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .italic()
                    .multilineTextAlignment(.center)
            }

            Button {
                switch leave {
                case .goHome:
                    // Spectators go home — game-over must not reveal identities mid-game.
                    onGoHome()
                case .confirmFirst:
                    isConfirmingLeave = true
                }
            } label: {
                // Every eliminated player's way home: a full-size target.
                Text("Leave Game")
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(Color.mtgErrorText)
            .confirmationDialog(
                "Leave without ending the game?",
                isPresented: $isConfirmingLeave,
                titleVisibility: .visible
            ) {
                Button("End Game") { onEndGame() }
                Button("Leave Game", role: .destructive) { onGoHome() }
                Button("Stay", role: .cancel) {}
            } message: {
                Text("Only you can end this game. If you leave, it stays open for the others until you come back from Home to end it.")
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.mtgError.opacity(Self.washOpacity))
        .overlay(
            Rectangle()
                .fill(Color.mtgError)
                .frame(height: 1),
            alignment: .top
        )
    }
}
