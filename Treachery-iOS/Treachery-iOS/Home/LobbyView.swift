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
    @State private var showColorPicker = false
    @State private var commanderNameInput = ""
    @State private var commanderNameDebounce: Task<Void, Never>?

    init(gameId: String, isHost: Bool, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: LobbyViewModel(gameId: gameId, isHost: isHost))
        _navigationPath = navigationPath
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()
            RadialGradient(
                colors: [
                    Color(hex: "1e1735").opacity(0.6),
                    Color.mtgBackground
                ],
                center: .top,
                startRadius: 20,
                endRadius: 420
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                ConnectionBanner()

                if viewModel.game == nil && viewModel.errorMessage == nil {
                    loadingContent
                } else if viewModel.isGameDisbanded {
                    disbandedContent
                } else {
                    lobbyContent
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            AnalyticsService.trackScreen("Lobby")
            viewModel.currentUserId = authViewModel.currentUserId
            if let player = viewModel.currentPlayer {
                commanderNameInput = player.commanderName ?? ""
            }
        }
        .onChange(of: viewModel.players) { _, _ in
            if commanderNameInput.isEmpty, let player = viewModel.currentPlayer, let name = player.commanderName {
                commanderNameInput = name
            }
        }
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

    // MARK: - Loading

    private var loadingContent: some View {
        VStack {
            Spacer()
            MtgLoadingView(message: "Loading lobby...")
            Spacer()
        }
    }

    // MARK: - Disbanded

    private var disbandedContent: some View {
        VStack {
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
        }
    }

    // MARK: - Lobby Content

    private var lobbyContent: some View {
        VStack(spacing: 0) {
            if let game = viewModel.game {
                LobbyGameCodeCard(game: game, showShareSheet: $showShareSheet)
            }

            OrnateDivider()
                .padding(.horizontal)
                .padding(.vertical, 12)

            if viewModel.isHost {
                gameSettingsSection
                    .padding(.bottom, 8)
            }

            playerListSection

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(Color.mtgError)
                    .font(.caption)
                    .padding(.horizontal)
            }

            LobbyBottomButtons(
                viewModel: viewModel,
                isLeaving: $isLeaving,
                onLeave: {
                    isLeaving = true
                    Task {
                        if let userId = authViewModel.currentUserId {
                            await viewModel.leaveGame(userId: userId)
                        }
                        navigationPath.removeLast(navigationPath.count)
                    }
                }
            )
        }
    }

    // MARK: - Game Settings (Host Only)

    private var gameSettingsSection: some View {
        VStack(spacing: 12) {
            MtgSectionHeader(title: "Game Settings")
                .frame(maxWidth: .infinity, alignment: .leading)

            if let game = viewModel.game {
                VStack(spacing: 12) {
                    // Max Players
                    HStack {
                        Text("Max Players")
                            .foregroundStyle(Color.mtgTextSecondary)
                            .font(.subheadline)
                        Spacer()
                        HStack(spacing: 12) {
                            Button {
                                let newVal = max(2, game.maxPlayers - 1)
                                Task { await viewModel.updateGameSettings(maxPlayers: newVal) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(game.maxPlayers > 2 ? Color.mtgGold : Color.mtgTextSecondary.opacity(0.3))
                            }
                            .disabled(game.maxPlayers <= 2)

                            Text("\(game.maxPlayers)")
                                .foregroundStyle(Color.mtgTextPrimary)
                                .fontWeight(.semibold)
                                .frame(width: 24, alignment: .center)

                            Button {
                                let newVal = min(8, game.maxPlayers + 1)
                                Task { await viewModel.updateGameSettings(maxPlayers: newVal) }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(game.maxPlayers < 8 ? Color.mtgGold : Color.mtgTextSecondary.opacity(0.3))
                            }
                            .disabled(game.maxPlayers >= 8)
                        }
                    }

                    Rectangle().fill(Color.mtgDivider).frame(height: 1)

                    // Starting Life
                    HStack {
                        Text("Starting Life")
                            .foregroundStyle(Color.mtgTextSecondary)
                            .font(.subheadline)
                        Spacer()
                        Menu {
                            ForEach([20, 25, 30, 40, 50], id: \.self) { life in
                                Button("\(life)") {
                                    Task { await viewModel.updateGameSettings(startingLife: life) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(game.startingLife)")
                                    .foregroundStyle(Color.mtgTextPrimary)
                                    .fontWeight(.semibold)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(Color.mtgGold)
                                    .font(.caption2)
                            }
                        }
                    }

                    Rectangle().fill(Color.mtgDivider).frame(height: 1)

                    // Game Mode
                    HStack {
                        Text("Game Mode")
                            .foregroundStyle(Color.mtgTextSecondary)
                            .font(.subheadline)
                        Spacer()
                        Menu {
                            ForEach(GameMode.allCases, id: \.self) { mode in
                                Button(mode.displayName) {
                                    Task { await viewModel.updateGameSettings(gameMode: mode.rawValue) }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(game.gameMode.displayName)
                                    .foregroundStyle(Color.mtgTextPrimary)
                                    .fontWeight(.semibold)
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundStyle(Color.mtgGold)
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .padding(16)
                .mtgCardFrame()
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Player List

    private var playerListSection: some View {
        ScrollView {
            VStack(spacing: 0) {
                MtgSectionHeader(title: "Players (\(viewModel.players.count))")
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
                        ForEach(Array(viewModel.players.enumerated()), id: \.element.id) { index, player in
                            LobbyPlayerRow(
                                player: player,
                                isMe: player.userId == viewModel.currentUserId,
                                isHost: player.userId == viewModel.game?.hostId,
                                showColorPicker: player.userId == viewModel.currentUserId ? $showColorPicker : .constant(false),
                                commanderNameInput: player.userId == viewModel.currentUserId ? $commanderNameInput : .constant(""),
                                onColorChange: { hex in
                                    Task { await viewModel.updatePlayerColor(hex) }
                                },
                                onCommanderNameChange: { name in
                                    commanderNameDebounce?.cancel()
                                    commanderNameDebounce = Task {
                                        try? await Task.sleep(nanoseconds: 500_000_000)
                                        guard !Task.isCancelled else { return }
                                        await viewModel.updateCommanderName(name.isEmpty ? nil : name)
                                    }
                                },
                                onCommanderNameSubmit: { name in
                                    commanderNameDebounce?.cancel()
                                    Task { await viewModel.updateCommanderName(name.isEmpty ? nil : name) }
                                }
                            )
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))

                            if player.id != viewModel.players.last?.id {
                                Rectangle()
                                    .fill(Color.mtgDivider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.players.map(\.id))
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
    }
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
