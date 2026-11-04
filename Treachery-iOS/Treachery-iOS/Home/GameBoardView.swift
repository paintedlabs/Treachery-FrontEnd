//
//  GameBoardView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct GameBoardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: GameBoardViewModel
    @Binding var navigationPath: NavigationPath
    @State private var showCardDetail = false
    @State private var showForfeitConfirmation = false
    @State private var isConfirmingSpectatorLeave = false
    @State private var showEndGameConfirmation = false
    @State private var showWinnerSelection = false
    @State private var selectedWinners: Set<String> = []
    @State private var inspectedPlayer: Player?
    @State private var showColorPicker = false

    init(gameId: String, currentUserId: String? = nil, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: GameBoardViewModel(gameId: gameId, currentUserId: currentUserId))
        _navigationPath = navigationPath
    }

    #if DEBUG
    /// Preview-only initializer with pre-populated view model.
    init(viewModel: GameBoardViewModel, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: viewModel)
        _navigationPath = navigationPath
    }
    #endif

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            if let hex = viewModel.currentPlayer?.playerColor {
                Color(hex: hex).opacity(0.15).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                ConnectionBanner()

                if viewModel.status != .ready {
                    statusContent
                } else {
                    // Identity card header — only when treachery active
                    if viewModel.isTreacheryActive {
                        if let card = viewModel.currentIdentityCard,
                           let player = viewModel.currentPlayer {
                            ZStack {
                                Button {
                                    showCardDetail = true
                                } label: {
                                    IdentityCardHeader(card: card, player: player)
                                }
                                .buttonStyle(.plain)
                                .rotation3DEffect(
                                    .degrees(viewModel.unveilProgress == .flippingAway ? 90 : 0),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.5
                                )
                                .animation(
                                    viewModel.unveilProgress == .flippingAway ? .easeIn(duration: 0.3) : .easeOut(duration: 0.3),
                                    value: viewModel.unveilProgress
                                )

                                // Unveiled banner overlay, once the server has
                                // unveiled the player
                                if viewModel.unveilProgress == .revealing {
                                    VStack {
                                        Text("IDENTITY REVEALED")
                                            .font(.headline)
                                            .fontWeight(.black)
                                            .foregroundStyle(Color.mtgBackground)
                                            .padding(.horizontal, 20)
                                            .padding(.vertical, 10)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(player.role?.color ?? Color.mtgGuardian)
                                                    .shadow(color: (player.role?.color ?? Color.mtgGuardian).opacity(0.6), radius: 12)
                                            )
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                    .zIndex(1)
                                }
                            }
                            .animation(
                                viewModel.unveilProgress == .revealing
                                    ? .spring(response: 0.4, dampingFraction: 0.6)
                                    : .easeOut(duration: 0.5),
                                value: viewModel.unveilProgress
                            )
                        } else {
                            // Current player not found (reconnection case).
                            // Forfeit and the action bar need that player, so
                            // this state offers its own way out.
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.mtgGold)
                                    .accessibilityHidden(true)
                                Text("Unable to find your player data")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.mtgTextSecondary)
                                Button {
                                    goHome()
                                } label: {
                                    Text("Back to Home")
                                        .font(.subheadline)
                                        .frame(minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .foregroundStyle(Color.mtgGold)
                            }
                            .padding()
                        }
                    }

                    // Plane card banner — only when planechase active (and not own-deck)
                    if viewModel.isPlanechaseActive && !viewModel.isOwnDeckMode {
                        // Chaotic Aether indicator
                        if viewModel.isChaoticAetherActive {
                            ChaoticAetherIndicator()
                        }

                        if let plane = viewModel.currentPlane {
                            PlaneCardBanner(plane: plane, secondaryPlane: viewModel.secondaryPlane)

                            // Phenomenon overlay when current plane is a phenomenon.
                            // Eliminated spectators keep the banner but not the
                            // resolver — the server rejects their resolve anyway.
                            if plane.isPhenomenon && viewModel.currentPlayer?.isEliminated != true {
                                PhenomenonOverlay(plane: plane, viewModel: viewModel)
                            }
                        }
                    }

                    OrnateDivider()
                        .padding(.horizontal)
                        .padding(.vertical, 4)

                    // Player list with life controls — always shown
                    ScrollView {
                        VStack(spacing: 0) {
                            MtgSectionHeader(title: "Players")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)

                            VStack(spacing: 0) {
                                ForEach(viewModel.players) { player in
                                    GameBoardPlayerRow(
                                        player: player,
                                        viewModel: viewModel,
                                        showColorPicker: player.userId == viewModel.currentUserId ? $showColorPicker : .constant(false)
                                    ) { tappedPlayer in
                                        inspectedPlayer = tappedPlayer
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)

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
                    }
                    .sheet(item: $inspectedPlayer) { player in
                        if let card = viewModel.identityCard(for: player) {
                            IdentityCardView(card: card, player: player)
                        }
                    }

                    // Error display
                    if let error = viewModel.errorMessage {
                        MtgErrorBanner(message: error)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                    }
                    if let failure = viewModel.lifeChangeFailure {
                        MtgErrorBanner(message: failure.message)
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                    }

                    // Spectator bar for eliminated players, in every mode:
                    // its Leave is their only way off the board.
                    if let leave = viewModel.spectatorLeave {
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "person.slash.fill")
                                    .foregroundStyle(Color.mtgError)
                                Text("You've Been Eliminated")
                                    .font(.system(.headline, design: .serif))
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.mtgError)
                            }

                            Text("You're now spectating. Watch the game unfold or leave.")
                                .font(.caption)
                                .foregroundStyle(Color.mtgTextSecondary)
                                .italic()
                                .multilineTextAlignment(.center)

                            Button("Leave Game") {
                                switch leave {
                                case .goHome:
                                    // Spectators go home — game-over must not reveal identities mid-game.
                                    goHome()
                                case .confirmFirst:
                                    isConfirmingSpectatorLeave = true
                                }
                            }
                            .foregroundStyle(Color.mtgError)
                            .padding(.top, 4)
                            .confirmationDialog(
                                "Leave without ending the game?",
                                isPresented: $isConfirmingSpectatorLeave,
                                titleVisibility: .visible
                            ) {
                                Button("End Game") { presentWinnerSelection() }
                                Button("Leave Game", role: .destructive) { goHome() }
                                Button("Stay", role: .cancel) {}
                            } message: {
                                Text("Only you can end this game. If you leave, it stays open for the others until you come back from Home to end it.")
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.mtgError.opacity(0.1))
                        .overlay(
                            Rectangle()
                                .fill(Color.mtgError)
                                .frame(height: 1),
                            alignment: .top
                        )
                    }

                    // Planar die bar — only when planechase active
                    if viewModel.isPlanechaseActive {
                        PlanarDieBar(viewModel: viewModel)
                    }

                    // Action bar (unveil/win) — only when treachery active
                    if viewModel.isTreacheryActive, viewModel.seat == .playing {
                        ActionBar(viewModel: viewModel)
                    }

                    // End Game button — the host's, in every mode but Treachery's,
                    // eliminated or not
                    if viewModel.canEndGame {
                        Button {
                            presentWinnerSelection()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "flag.checkered")
                                Text("End Game")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(MtgSecondaryButtonStyle())
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear { AnalyticsService.trackScreen("GameBoard") }
        .toolbar {
            // Forfeit button — available in all game modes so players can always
            // leave: a forfeit brings up the spectator bar, whose Leave goes home
            if viewModel.status == .ready && viewModel.seat == .playing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showForfeitConfirmation = true
                    } label: {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(Color.mtgGold)
                    }
                    .accessibilityLabel("Forfeit and leave game")
                }
            }
        }
        .confirmationDialog(
            "Forfeit Game?",
            isPresented: $showForfeitConfirmation,
            titleVisibility: .visible
        ) {
            Button("Forfeit", role: .destructive) {
                Task {
                    await viewModel.eliminateAndLeave()
                    // Stay on the board (or let isGameFinished navigate);
                    // do not open game-over mid-session.
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be eliminated from the game. This cannot be undone.")
        }
        .onAppear {
            viewModel.currentUserId = authViewModel.currentUserId
        }
        .onDisappear {
            // Taps still waiting out their debounce would go with the board.
            viewModel.sendPendingLifeChanges()
        }
        .onChange(of: viewModel.lifeChangeFailure) { _, failure in
            // A failed change can put a total back with no other sign, and
            // the banner is away from the rows: read it out.
            guard let failure else { return }
            AccessibilityNotification.Announcement(failure.message).post()
        }
        .onChange(of: viewModel.unveilProgress) { _, progress in
            // The banner is the only sign the unveil went through.
            guard progress == .revealing else { return }
            AccessibilityNotification.Announcement("Identity revealed").post()
        }
        .onChange(of: viewModel.isGameFinished) { _, finished in
            if finished {
                navigationPath.append(AppDestination.gameOver(gameId: viewModel.gameId))
            }
        }
        .sheet(isPresented: $showCardDetail) {
            if let card = viewModel.currentIdentityCard,
               let player = viewModel.currentPlayer {
                IdentityCardView(card: card, player: player)
            }
        }
        .sheet(isPresented: Binding(
            get: { viewModel.tunnelOptions != nil },
            set: { if !$0 { viewModel.tunnelOptions = nil } }
        )) {
            if let options = viewModel.tunnelOptions {
                InterplanarTunnelPicker(options: options, viewModel: viewModel)
            }
        }
        .sheet(isPresented: $showWinnerSelection) {
            WinnerSelectionSheet(
                players: viewModel.alivePlayers,
                selectedWinners: $selectedWinners,
                isPending: viewModel.isPending
            ) {
                Task {
                    await viewModel.endGame(winnerUserIds: Array(selectedWinners))
                    showWinnerSelection = false
                }
            } onCancel: {
                showWinnerSelection = false
            }
        }
        .sheet(item: $viewModel.pendingAbilityResolution, onDismiss: {
            viewModel.dismissAbility()
        }) { resolution in
            switch resolution.abilityType {
            case .metamorph:
                MetamorphAbilitySheet(
                    viewModel: viewModel,
                    eliminatedPlayers: resolution.candidatePlayers
                )
            case .puppetMaster:
                PuppetMasterAbilitySheet(
                    viewModel: viewModel,
                    players: resolution.candidatePlayers
                )
            case .wearerOfMasks:
                WearerOfMasksAbilitySheet(viewModel: viewModel)
            }
        }
    }

    // MARK: - Status

    /// Everything but the board itself. Each state offers a way home, since
    /// this screen hides the back button and the tab bar.
    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.status {
        case .ready:
            EmptyView() // the board itself is shown instead
        case .loading:
            GameLoadingView(message: "Loading game...", onGoHome: { goHome() })
        case .unavailable:
            GameStatusView(
                systemImage: "wifi.exclamationmark",
                title: "Game Unavailable",
                message: "This game has closed and is no longer available.",
                onGoHome: { goHome() }
            )
        case .failed:
            GameStatusView(
                systemImage: "exclamationmark.triangle.fill",
                title: "Couldn't Load the Game",
                message: "Check your connection and try again.",
                action: .tryAgain { viewModel.retry() },
                onGoHome: { goHome() }
            )
        case .needsNewerVersion:
            GameStatusView.needsNewerVersion(onGoHome: { goHome() })
        }
    }

    private func goHome() {
        navigationPath.removeLast(navigationPath.count)
    }

    private func presentWinnerSelection() {
        selectedWinners = []
        showWinnerSelection = true
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Game Board") {
    NavigationStack {
        GameBoardView(
            viewModel: GameBoardViewModel(
                gameId: "preview-game",
                previewPlayers: Player.sampleGamePlayers,
                previewGame: .sampleInProgress,
                currentUserId: "user2"  // Sarah (Guardian)
            ),
            navigationPath: .preview
        )
    }
    .environmentObject(AuthViewModel())
}
#endif
