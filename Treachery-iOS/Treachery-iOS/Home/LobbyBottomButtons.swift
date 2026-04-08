//
//  LobbyBottomButtons.swift
//  Treachery-iOS
//

import SwiftUI

struct LobbyBottomButtons: View {
    @ObservedObject var viewModel: LobbyViewModel
    @Binding var isLeaving: Bool
    var onLeave: () -> Void

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
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: !viewModel.canStartGame || viewModel.isStartingGame))
                .disabled(!viewModel.canStartGame || viewModel.isStartingGame)

                if !viewModel.canStartGame {
                    if viewModel.players.count < viewModel.minimumPlayerCount {
                        Text("Need at least \(viewModel.minimumPlayerCount) player\(viewModel.minimumPlayerCount == 1 ? "" : "s") to start")
                            .font(.caption)
                            .foregroundStyle(Color.mtgTextSecondary)
                    } else if !viewModel.allPlayersReady {
                        Text("All players must be ready to start")
                            .font(.caption)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                }
            }

            Button {
                onLeave()
            } label: {
                if isLeaving {
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
            .foregroundStyle(Color.mtgError)
            .disabled(isLeaving)
            .accessibilityLabel("Leave game")
        }
        .padding()
    }
}
