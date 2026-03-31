//
//  ActionBar.swift
//  Treachery-iOS
//

import SwiftUI

struct ActionBar: View {
    @ObservedObject var viewModel: GameBoardViewModel
    @State private var showUnveilConfirmation = false
    var onUnveil: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let player = viewModel.currentPlayer,
               !player.isUnveiled,
               !player.isEliminated,
               player.role != .leader {
                Button("Unveil Identity") {
                    showUnveilConfirmation = true
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: viewModel.isPending))
                .disabled(viewModel.isPending)
                .padding(.horizontal)
                .accessibilityLabel("Unveil your identity as \(player.role?.displayName ?? "unknown")")
                .accessibilityHint("Reveals your role to all players. Cannot be undone.")
                .confirmationDialog(
                    "Unveil your identity?",
                    isPresented: $showUnveilConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Unveil") {
                        onUnveil()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if let card = viewModel.currentIdentityCard {
                        Text("This will reveal your role (\(player.role?.displayName ?? "")) and card (\(card.name)) to all players. This cannot be undone.")
                    }
                }
            }

        }
        .padding()
    }
}
