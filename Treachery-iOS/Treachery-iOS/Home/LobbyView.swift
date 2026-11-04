//
//  LobbyView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import Accessibility
import SwiftUI

struct LobbyView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: LobbyViewModel
    @Binding var navigationPath: NavigationPath
    @State private var showShareSheet = false
    @State private var showColorPicker = false
    @State private var isConfirmingHostLeave = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

                switch viewModel.status {
                case .loading:
                    GameLoadingView(message: "Loading lobby...", onGoHome: { goHome() })
                case .loaded(let game):
                    lobbyContent(game)
                case .finished:
                    GameStatusView(
                        systemImage: "flag.checkered",
                        title: "Game Over",
                        message: "This game has already finished.",
                        action: GameStatusView.Action(title: "See Results", perform: { seeResults() }),
                        onGoHome: { goHome() }
                    )
                case .needsNewerVersion:
                    GameStatusView.needsNewerVersion(onGoHome: { goHome() })
                case .disbanded:
                    GameStatusView(
                        systemImage: "xmark.octagon.fill",
                        tint: .mtgError,
                        title: "Game Disbanded",
                        message: "This lobby has closed. You can create or join another game from Home.",
                        onGoHome: { goHome() }
                    )
                case .notInGame:
                    GameStatusView.notInGame(onGoHome: { goHome() })
                case .failed:
                    GameStatusView(
                        systemImage: "exclamationmark.triangle.fill",
                        title: "Couldn't Load the Lobby",
                        message: "Check your connection and try again.",
                        action: .tryAgain { viewModel.retry() },
                        onGoHome: { goHome() }
                    )
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            AnalyticsService.trackScreen("Lobby")
            viewModel.currentUserId = authViewModel.currentUserId
        }
        .task(id: viewModel.commanderNameDraft) {
            // Debounce: each keystroke changes the id, which cancels this
            // wait, and leaving the lobby cancels it too.
            do {
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                return
            }
            await viewModel.saveCommanderName()
        }
        .onDisappear {
            // Going off screen cancels the debounce above, as when the board
            // replaces the lobby the moment the host starts. Save whatever
            // was typed since the last pause, so it isn't lost.
            Task { await viewModel.saveCommanderName() }
        }
        .onChange(of: viewModel.isGameStarted) { _, started in
            if started {
                navigationPath.append(AppDestination.gameBoard(gameId: viewModel.gameId))
            }
        }
        .confirmationDialog(
            "Leave the game?",
            isPresented: $isConfirmingHostLeave,
            titleVisibility: .visible
        ) {
            Button("Leave Game", role: .destructive) { leave() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(hostLeaveMessage)
        }
        .sheet(isPresented: $showShareSheet) {
            if let code = viewModel.game?.code {
                ShareSheet(items: ["Join my Treachery game! Code: \(code)"])
            }
        }
    }

    // MARK: - Navigation

    private func goHome() {
        navigationPath.removeLast(navigationPath.count)
    }

    private func seeResults() {
        navigationPath.append(AppDestination.gameOver(gameId: viewModel.gameId))
    }

    /// The host confirms first, because leaving hands the lobby to someone
    /// else or closes it. Anyone else leaves straight away.
    private func requestLeave() {
        if viewModel.hostLeaveOutcome == nil {
            leave()
        } else {
            isConfirmingHostLeave = true
        }
    }

    /// Goes home only once the player is out of the game. A failed leave
    /// keeps the lobby on screen, still updating, with the error and a Back
    /// to Home that keeps the seat.
    private func leave() {
        Task {
            if await viewModel.leave() {
                goHome()
            }
        }
    }

    private var hostLeaveMessage: String {
        switch viewModel.hostLeaveOutcome {
        case .passesHost(let name):
            return "You're the host. If you leave, \(name) becomes the host."
        case .closesLobby:
            return "You're the only player, so leaving will close the lobby."
        case nil:
            return ""
        }
    }

    // MARK: - Lobby Content

    private static let errorBannerID = "lobby-error"

    /// The code card, settings and players scroll together; the buttons stay
    /// pinned below them so Start Game is reachable on an iPhone SE and at the
    /// largest text sizes. Only the buttons are pinned: at those sizes an
    /// error message there would leave no room for the lobby itself.
    private func lobbyContent(_ game: Game) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LobbyGameCodeCard(game: game, showShareSheet: $showShareSheet)

                    if game.gameMode.isUnknown {
                        Text("This game mode needs a newer version of Treachery to play.")
                            .font(.caption)
                            .foregroundStyle(Color.mtgTextSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }

                    OrnateDivider()
                        .padding(.horizontal)
                        .padding(.vertical, 12)

                    if viewModel.isHost {
                        gameSettingsSection
                            .padding(.bottom, 8)
                    }

                    playerListSection

                    // Last, so scrolling to it puts it right above the buttons.
                    if let error = viewModel.errorMessage {
                        MtgErrorBanner(message: error)
                            .padding(.horizontal)
                            .padding(.vertical, 12)
                            .id(Self.errorBannerID)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: viewModel.errorMessage) { _, message in
                guard let message else { return }
                // It appears away from wherever the player is looking, or
                // VoiceOver is reading: bring it into view, at once with
                // Reduce Motion, and read it out.
                withAnimation(reduceMotion ? nil : .default) { proxy.scrollTo(Self.errorBannerID, anchor: .bottom) }
                AccessibilityNotification.Announcement(message).post()
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LobbyBottomButtons(viewModel: viewModel, onLeave: { requestLeave() }, onGoHome: { goHome() })
                    .frame(maxWidth: .infinity)
                    .background(Color.mtgBackground)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.mtgDivider)
                            .frame(height: 1)
                    }
            }
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
                        // No spacing: the buttons' 44pt hit areas already
                        // space their glyphs out from the number.
                        HStack(spacing: 0) {
                            Button {
                                // Clamp to 8 so legacy games stored with a
                                // higher max don't send server-rejected values,
                                // and never below the players already seated,
                                // which the server refuses too.
                                let newVal = max(viewModel.smallestMaxPlayers, min(8, game.maxPlayers - 1))
                                Task { await viewModel.updateGameSettings(maxPlayers: newVal) }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(
                                        game.maxPlayers > viewModel.smallestMaxPlayers ? Color.mtgGold : Color.mtgTextSecondary.opacity(0.3)
                                    )
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .disabled(game.maxPlayers <= viewModel.smallestMaxPlayers)
                            .accessibilityLabel("Decrease max players")

                            Text("\(game.maxPlayers)")
                                .foregroundStyle(Color.mtgTextPrimary)
                                .fontWeight(.semibold)
                                .frame(minWidth: 24, alignment: .center)

                            Button {
                                let newVal = min(8, game.maxPlayers + 1)
                                Task { await viewModel.updateGameSettings(maxPlayers: newVal) }
                            } label: {
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(game.maxPlayers < 8 ? Color.mtgGold : Color.mtgTextSecondary.opacity(0.3))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .disabled(game.maxPlayers >= 8)
                            .accessibilityLabel("Increase max players")
                        }
                    }

                    Rectangle().fill(Color.mtgDivider).frame(height: 1)

                    // Starting Life. The menu carries the label and value for
                    // VoiceOver, so the text beside it isn't read twice.
                    HStack {
                        Text("Starting Life")
                            .foregroundStyle(Color.mtgTextSecondary)
                            .font(.subheadline)
                            .accessibilityHidden(true)
                        Spacer()
                        Menu {
                            // The values the create screen offers. The system
                            // menu scrolls when the nine don't fit at large
                            // text sizes.
                            ForEach(Game.startingLifeOptions, id: \.self) { life in
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
                                    .accessibilityHidden(true)
                            }
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Starting life")
                        .accessibilityValue("\(game.startingLife)")
                    }

                    Rectangle().fill(Color.mtgDivider).frame(height: 1)

                    // Game Mode, labeled for VoiceOver by its menu
                    HStack {
                        Text("Game Mode")
                            .foregroundStyle(Color.mtgTextSecondary)
                            .font(.subheadline)
                            .accessibilityHidden(true)
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
                                    .accessibilityHidden(true)
                            }
                            .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                            .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Game mode")
                        .accessibilityValue(game.gameMode.displayName)
                    }

                    // Max Traitor Rarity — only meaningful in treachery modes
                    if game.gameMode.includesTreachery {
                        Rectangle().fill(Color.mtgDivider).frame(height: 1)

                        HStack {
                            Text("Max Traitor Rarity")
                                .foregroundStyle(Color.mtgTextSecondary)
                                .font(.subheadline)
                                .accessibilityHidden(true)
                            Spacer()
                            Menu {
                                ForEach(Rarity.allCases) { rarity in
                                    Button(rarity.displayName) {
                                        Task { await viewModel.updateGameSettings(maxTraitorRarity: rarity.rawValue) }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(viewModel.maxTraitorRarity.displayName)
                                        .foregroundStyle(Color.mtgTextPrimary)
                                        .fontWeight(.semibold)
                                    Image(systemName: "chevron.up.chevron.down")
                                        .foregroundStyle(Color.mtgGold)
                                        .font(.caption2)
                                        .accessibilityHidden(true)
                                }
                                .frame(minWidth: 44, minHeight: 44, alignment: .trailing)
                                .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Max traitor rarity")
                            .accessibilityValue(viewModel.maxTraitorRarity.displayName)
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
        VStack(spacing: 0) {
            MtgSectionHeader(title: "Players (\(viewModel.players.count))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            if let requirement = viewModel.startRequirement {
                Text(requirement)
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }

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
                            commanderNameInput: player.userId == viewModel.currentUserId ? $viewModel.commanderNameDraft : .constant(""),
                            onColorChange: { hex in
                                Task { await viewModel.updatePlayerColor(hex) }
                            },
                            onCommanderNameSubmit: {
                                Task { await viewModel.saveCommanderName() }
                            }
                        )
                        .transition(reduceMotion ? .opacity : .asymmetric(
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
        // A players snapshot redraws the list with a short ease, at once
        // with Reduce Motion.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.players)
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
