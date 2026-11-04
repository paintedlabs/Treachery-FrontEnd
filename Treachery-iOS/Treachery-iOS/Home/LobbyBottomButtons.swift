//
//  LobbyBottomButtons.swift
//  Treachery-iOS
//

import SwiftUI

struct LobbyBottomButtons: View {
    @ObservedObject var viewModel: LobbyViewModel
    var onLeave: () -> Void
    /// Goes home without leaving the game. Offered only after a failed
    /// leave, when Leave may be the one thing that doesn't work.
    var onGoHome: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if viewModel.isHost {
                Button {
                    Task { await viewModel.startGame() }
                } label: {
                    if viewModel.isStartingGame {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgBackground)
                            Text("Starting...")
                        }
                    } else {
                        Text("Start Game")
                    }
                }
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: !canTapStart))
                .disabled(!canTapStart)
                // The visible reason sits by the player count, in the
                // scrolling content, to keep this pinned bar short.
                .accessibilityHint(viewModel.startRequirement ?? "")
            }

            Button {
                onLeave()
            } label: {
                Group {
                    if viewModel.isLeaving {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.mtgError)
                            Text("Leaving...")
                        }
                    } else {
                        Text("Leave Game")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .foregroundStyle(Color.mtgError)
            .disabled(viewModel.pendingAction != nil)
            .accessibilityLabel(viewModel.isLeaving ? "Leaving game" : "Leave game")

            if viewModel.offersHomeWithoutLeaving {
                Button {
                    onGoHome()
                } label: {
                    Text("Back to Home")
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .foregroundStyle(Color.mtgGold)
                .accessibilityHint("Keeps your seat in this game. You can rejoin it from Home.")
            }
        }
        .padding()
    }

    /// Start needs enough players and no start or leave already in flight.
    /// The view model refuses a repeat start as well; this keeps the button
    /// from looking tappable while one is pending.
    private var canTapStart: Bool {
        viewModel.canStartGame && viewModel.pendingAction == nil
    }
}
