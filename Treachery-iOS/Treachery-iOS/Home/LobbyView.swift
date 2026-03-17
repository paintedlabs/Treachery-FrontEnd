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
    @State private var isLeaving = false

    init(gameId: String, isHost: Bool, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: LobbyViewModel(gameId: gameId, isHost: isHost))
        _navigationPath = navigationPath
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                ConnectionBanner()

                if viewModel.game == nil && viewModel.errorMessage == nil {
                    // Loading state
                    Spacer()
                    ProgressView("Loading lobby...")
                        .tint(Color.mtgGold)
                        .foregroundStyle(Color.mtgTextSecondary)
                    Spacer()
                } else if viewModel.isGameDisbanded {
                    // Host deleted the game
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "xmark.octagon.fill")
                            .font(.largeTitle)
                            .foregroundStyle(Color.mtgError)
                        Text("Game Disbanded")
                            .font(.system(.title2, design: .serif))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.mtgTextPrimary)
                        Text("The host has left and the game was closed.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mtgTextSecondary)
                            .multilineTextAlignment(.center)
                        Button("Return Home") {
                            navigationPath.removeLast(navigationPath.count)
                        }
                        .buttonStyle(MtgPrimaryButtonStyle())
                        .padding(.top)
                        .padding(.horizontal, 40)
                    }
                    .padding()
                    Spacer()
                } else {
                    // Game code display
                    if let game = viewModel.game {
                        VStack(spacing: 8) {
                            MtgSectionHeader(title: "Game Code")

                            Text(game.code)
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.mtgGoldBright)
                                .kerning(8)
                                .accessibilityLabel("Game code: \(game.code.map(String.init).joined(separator: " "))")

                            // Game mode badge
                            Text(game.gameMode.displayName)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(Color.mtgBackground)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color.mtgGold)
                                .clipShape(Capsule())
                                .accessibilityLabel("Game mode: \(game.gameMode.displayName)")

                            Button {
                                showShareSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.caption)
                                    Text("Share Code")
                                        .font(.caption)
                                }
                                .foregroundStyle(Color.mtgGold)
                            }
                            .padding(.top, 4)
                            .accessibilityLabel("Share game code with friends")
                        }
                        .padding(20)
                        .mtgCardFrame()
                        .padding(.horizontal)
                        .padding(.top, 12)
                    }

                    OrnateDivider()
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                    // Player list
                    ScrollView {
                        VStack(spacing: 0) {
                            MtgSectionHeader(title: "Players (\(viewModel.players.count)/\(viewModel.game?.maxPlayers ?? 0))")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            if viewModel.players.isEmpty {
                                Text("Waiting for players to join...")
                                    .foregroundStyle(Color.mtgTextSecondary)
                                    .font(.subheadline)
                                    .padding(.vertical, 20)
                            } else {
                                VStack(spacing: 0) {
                                    ForEach(viewModel.players) { player in
                                        HStack {
                                            Text(player.displayName)
                                                .fontWeight(player.userId == viewModel.game?.hostId ? .semibold : .regular)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            Spacer()
                                            if player.userId == viewModel.game?.hostId {
                                                Text("Host")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.mtgGold)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 2)
                                                    .background(Color.mtgGold.opacity(0.15))
                                                    .clipShape(Capsule())
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .accessibilityLabel("\(player.displayName)\(player.userId == viewModel.game?.hostId ? ", Host" : "")")

                                        if player.id != viewModel.players.last?.id {
                                            Rectangle()
                                                .fill(Color.mtgDivider)
                                                .frame(height: 1)
                                                .padding(.horizontal, 16)
                                        }
                                    }
                                }
                                .mtgCardFrame()
                                .padding(.horizontal)
                            }

                            if !viewModel.isHost {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                        .tint(Color.mtgGold)
                                    Text("Waiting for host to start the game...")
                                        .font(.subheadline)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }
                                .padding(.top, 16)
                            }
                        }
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(Color.mtgError)
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
                                            .tint(Color.mtgBackground)
                                        Text("Starting...")
                                    }
                                } else {
                                    Text("Start Game")
                                }
                            }
                            .buttonStyle(MtgPrimaryButtonStyle(isDisabled: !viewModel.canStartGame || viewModel.isStartingGame))
                            .disabled(!viewModel.canStartGame || viewModel.isStartingGame)

                            if !viewModel.canStartGame && viewModel.players.count < viewModel.minimumPlayerCount {
                                Text("Need at least \(viewModel.minimumPlayerCount) player\(viewModel.minimumPlayerCount == 1 ? "" : "s") to start")
                                    .font(.caption)
                                    .foregroundStyle(Color.mtgTextSecondary)
                            }
                        }

                        Button {
                            isLeaving = true
                            Task {
                                if let userId = authViewModel.currentUserId {
                                    await viewModel.leaveGame(userId: userId)
                                }
                                navigationPath.removeLast(navigationPath.count)
                            }
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
        }
        .navigationTitle("Lobby")
        .toolbarColorScheme(.dark, for: .navigationBar)
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
