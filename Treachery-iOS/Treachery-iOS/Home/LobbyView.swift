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
                                        let isMe = player.userId == viewModel.currentUserId

                                        VStack(spacing: 0) {
                                            HStack(spacing: 0) {
                                                // Left accent bar for player color
                                                if let hex = player.playerColor {
                                                    RoundedRectangle(cornerRadius: 1.5)
                                                        .fill(Color(hex: hex))
                                                        .frame(width: 3)
                                                        .padding(.vertical, 2)
                                                        .padding(.trailing, 8)
                                                }

                                                // Color picker toggle for current user
                                                if isMe {
                                                    Button {
                                                        withAnimation(.easeInOut(duration: 0.2)) {
                                                            showColorPicker.toggle()
                                                        }
                                                    } label: {
                                                        if let hex = player.playerColor {
                                                            Circle()
                                                                .fill(Color(hex: hex))
                                                                .frame(width: 16, height: 16)
                                                                .overlay(
                                                                    Circle().stroke(Color.mtgTextSecondary.opacity(0.3), lineWidth: 1)
                                                                )
                                                        } else {
                                                            Circle()
                                                                .stroke(Color.mtgTextSecondary, lineWidth: 1.5)
                                                                .frame(width: 16, height: 16)
                                                        }
                                                    }
                                                    .buttonStyle(.plain)
                                                    .padding(.trailing, 6)
                                                    .accessibilityLabel("Choose player color")
                                                }

                                                VStack(alignment: .leading, spacing: 2) {
                                                    Text(player.displayName)
                                                        .fontWeight(player.userId == viewModel.game?.hostId ? .semibold : .regular)
                                                        .foregroundStyle(Color.mtgTextPrimary)

                                                    // Commander name display for other players
                                                    if !isMe, let commanderName = player.commanderName, !commanderName.isEmpty {
                                                        Text(commanderName)
                                                            .font(.system(.caption, design: .serif))
                                                            .italic()
                                                            .foregroundStyle(Color.mtgTextSecondary)
                                                    }
                                                }

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

                                            // Commander name input for current user
                                            if isMe {
                                                TextField("Commander name...", text: $commanderNameInput)
                                                    .font(.system(.caption, design: .serif))
                                                    .italic()
                                                    .foregroundStyle(Color.mtgTextPrimary)
                                                    .padding(.horizontal, 10)
                                                    .padding(.vertical, 6)
                                                    .background(Color.mtgCardElevated)
                                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color.mtgDivider, lineWidth: 1)
                                                    )
                                                    .padding(.top, 6)
                                                    .onSubmit {
                                                        commanderNameDebounce?.cancel()
                                                        Task { await viewModel.updateCommanderName(commanderNameInput.isEmpty ? nil : commanderNameInput) }
                                                    }
                                                    .onChange(of: commanderNameInput) { _, newValue in
                                                        commanderNameDebounce?.cancel()
                                                        commanderNameDebounce = Task {
                                                            try? await Task.sleep(nanoseconds: 500_000_000)
                                                            guard !Task.isCancelled else { return }
                                                            await viewModel.updateCommanderName(newValue.isEmpty ? nil : newValue)
                                                        }
                                                    }
                                            }

                                            // Color picker row (current user only)
                                            if isMe && showColorPicker {
                                                LobbyColorPickerRow(selectedHex: player.playerColor) { hex in
                                                    Task { await viewModel.updatePlayerColor(hex) }
                                                }
                                                .padding(.top, 8)
                                                .transition(.asymmetric(
                                                    insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity
                                                ))
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
        .onAppear {
            viewModel.currentUserId = authViewModel.currentUserId
            if let player = viewModel.currentPlayer {
                commanderNameInput = player.commanderName ?? ""
            }
        }
        .onChange(of: viewModel.players) { _, _ in
            // Sync commander name input when player data first arrives
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
}

// MARK: - Lobby Color Picker Row

private struct LobbyColorPickerRow: View {
    let selectedHex: String?
    let onSelect: (String?) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PlayerColors.palette, id: \.hex) { playerColor in
                Button {
                    if selectedHex == playerColor.hex {
                        onSelect(nil)
                    } else {
                        onSelect(playerColor.hex)
                    }
                } label: {
                    Circle()
                        .fill(playerColor.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.mtgTextPrimary, lineWidth: selectedHex == playerColor.hex ? 2 : 0)
                                .padding(selectedHex == playerColor.hex ? -2 : 0)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playerColor.name)
            }

            // Clear button
            Button {
                onSelect(nil)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.mtgTextSecondary, lineWidth: 1)
                        .frame(width: 24, height: 24)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.mtgTextSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear color")
        }
        .padding(.vertical, 4)
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
