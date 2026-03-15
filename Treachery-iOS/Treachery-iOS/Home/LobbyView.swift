//
//  LobbyView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import SwiftUI

struct LobbyView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: LobbyViewModel
    @Binding var navigationPath: NavigationPath
    @State private var showHostLeftAlert = false
    @State private var showShareSheet = false

    init(gameId: String, isHost: Bool, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: LobbyViewModel(gameId: gameId, isHost: isHost))
        _navigationPath = navigationPath
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.game == nil && viewModel.errorMessage == nil {
                // Loading state
                Spacer()
                ProgressView("Loading lobby...")
                Spacer()
            } else if viewModel.isGameDisbanded {
                // Host deleted the game
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text("Game Disbanded")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("The host has left and the game was closed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Return Home") {
                        navigationPath.removeLast(navigationPath.count)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .padding()
                Spacer()
            } else {
                // Game code display
                if let game = viewModel.game {
                    VStack(spacing: 4) {
                        Text("Game Code")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(game.code)
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .kerning(8)
                            .accessibilityLabel("Game code: \(game.code.map(String.init).joined(separator: " "))")

                        Button {
                            showShareSheet = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.caption)
                                Text("Share Code")
                                    .font(.caption)
                            }
                        }
                        .padding(.top, 4)
                        .accessibilityLabel("Share game code with friends")
                    }
                    .padding()
                }

                Divider()

                // Player list
                List {
                    Section("Players (\(viewModel.players.count)/\(viewModel.game?.maxPlayers ?? 0))") {
                        if viewModel.players.isEmpty {
                            Text("Waiting for players to join...")
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        } else {
                            ForEach(viewModel.players) { player in
                                HStack {
                                    Text(player.displayName)
                                        .fontWeight(player.userId == viewModel.game?.hostId ? .semibold : .regular)
                                    Spacer()
                                    if player.userId == viewModel.game?.hostId {
                                        Text("Host")
                                            .font(.caption)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(.secondary.opacity(0.2))
                                            .clipShape(Capsule())
                                    }
                                }
                                .accessibilityLabel("\(player.displayName)\(player.userId == viewModel.game?.hostId ? ", Host" : "")")
                            }
                        }
                    }

                    if !viewModel.isHost {
                        Section {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Waiting for host to start the game...")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }

                // Bottom buttons
                VStack(spacing: 12) {
                    if viewModel.isHost {
                        Button {
                            Task { await viewModel.startGame() }
                        } label: {
                            if viewModel.isStartingGame {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(.white)
                                    Text("Starting...")
                                }
                            } else {
                                Text("Start Game")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canStartGame || viewModel.isStartingGame)

                        if !viewModel.canStartGame && viewModel.players.count < Role.minimumPlayerCount {
                            Text("Need at least \(Role.minimumPlayerCount) player\(Role.minimumPlayerCount == 1 ? "" : "s") to start")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Leave Game", role: .destructive) {
                        Task {
                            if let userId = authViewModel.currentUserId {
                                await viewModel.leaveGame(userId: userId)
                                navigationPath.removeLast(navigationPath.count)
                            }
                        }
                    }
                    .accessibilityLabel("Leave game")
                }
                .padding()
            }
        }
        .navigationTitle("Lobby")
        .navigationBarBackButtonHidden(true)
        .onChange(of: viewModel.isGameStarted) { _, started in
            if started {
                navigationPath.append(AppDestination.gameBoard(gameId: viewModel.gameId))
            }
        }
        .onChange(of: viewModel.isGameDisbanded) { _, disbanded in
            if disbanded && !viewModel.isHost {
                showHostLeftAlert = true
            }
        }
        .alert("Game Disbanded", isPresented: $showHostLeftAlert) {
            Button("OK") {
                navigationPath.removeLast(navigationPath.count)
            }
        } message: {
            Text("The host has left and the game was closed.")
        }
        .sheet(isPresented: $showShareSheet) {
            if let code = viewModel.game?.code {
                ShareSheet(items: ["Join my Treachery game! Code: \(code)"])
            }
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#if DEBUG
#Preview("Lobby - Host") {
    NavigationStack {
        LobbyView(gameId: "preview-game", isHost: true, navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}

#Preview("Lobby - Guest") {
    NavigationStack {
        LobbyView(gameId: "preview-game", isHost: false, navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}
#endif
