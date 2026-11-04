//
//  ActionBar.swift
//  Treachery-iOS
//

import SwiftUI

struct ActionBar: View {
    @ObservedObject var viewModel: GameBoardViewModel
    @State private var showUnveilConfirmation = false

    var body: some View {
        VStack(spacing: 12) {
            if let player = viewModel.currentPlayer, viewModel.offersUnveil {
                Button {
                    showUnveilConfirmation = true
                } label: {
                    if isSending {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgBackground)
                            Text("Unveiling...")
                        }
                    } else {
                        Text("Unveil Identity")
                    }
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isSending))
                .disabled(isSending)
                .padding(.horizontal)
                .accessibilityLabel(
                    isSending
                        ? "Unveiling your identity"
                        : "Unveil your identity as \(player.role?.displayName ?? "unknown")"
                )
                .accessibilityHint("Reveals your role to all players. Cannot be undone.")
                .confirmationDialog(
                    "Unveil your identity?",
                    isPresented: $showUnveilConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Unveil") {
                        viewModel.unveilCurrentPlayer()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if let card = viewModel.currentIdentityCard {
                        Text("This will reveal your role (\(player.role?.displayName ?? "")) and card (\(card.name)) to all players. This cannot be undone.")
                    }
                }
            }

            if viewModel.resolvableAbility != nil {
                Button("Activate Ability") {
                    viewModel.presentAbilityResolver()
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: viewModel.isPending))
                .disabled(viewModel.isPending)
                .padding(.horizontal)
                .accessibilityLabel("Activate traitor ability")
                .accessibilityHint("Opens the ability you unveiled. You can skip and come back later.")
            }
        }
        .padding()
    }

    /// While the call is under way. The view model ignores a second unveil
    /// then too; this keeps the button from looking tappable. Once the
    /// server has unveiled them, the button goes.
    private var isSending: Bool {
        viewModel.unveilProgress == .sending
    }
}
