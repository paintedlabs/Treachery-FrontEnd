//
//  GameBoardView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Accessibility
import SwiftUI

struct GameBoardView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: GameBoardViewModel
    @Binding var navigationPath: NavigationPath
    @State private var showCardDetail = false
    @State private var showForfeitConfirmation = false
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
            boardBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ConnectionBanner()

                if viewModel.status != .ready {
                    statusContent
                } else {
                    board
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
        .onChange(of: viewModel.errorMessage) { _, message in
            // An action that fails (a roll, a forfeit, an ability) says so in
            // the controls pinned below the players, away from where the
            // player is looking or VoiceOver is reading: read it out.
            guard let message else { return }
            AccessibilityNotification.Announcement(message).post()
        }
        .onChange(of: viewModel.lifeChangeFailures) { old, new in
            // A failed change can put a total back with no other sign, and
            // the banner is away from the rows: read out each new one.
            for announcement in GameBoardViewModel.LifeChangeFailure.announcements(from: old, to: new) {
                var message = AttributedString(announcement.message)
                // Low priority waits for VoiceOver to finish what it's saying.
                message.accessibilitySpeechAnnouncementPriority = announcement.interrupts ? .default : .low
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: viewModel.seat) { oldSeat, newSeat in
            // Elimination changes the board with no other sign: the life
            // buttons stop working, and the spectator bar, now the way
            // home, appears at the bottom.
            guard oldSeat == .playing, newSeat == .spectating else { return }
            AccessibilityNotification.Announcement(
                "You've been eliminated. You can keep watching, or use Leave Game at the bottom of the screen."
            ).post()
        }
        .onChange(of: viewModel.unveilProgress) { _, progress in
            switch progress {
            case .revealing:
                // The banner is the only sign the unveil went through.
                AccessibilityNotification.Announcement("Identity revealed").post()
            case .failed(let message):
                // And the error, away below the players, the only sign it
                // didn't: the button just goes back to Unveil.
                AccessibilityNotification.Announcement(message).post()
            case .idle, .sending, .flippingAway, .awaitingSnapshot:
                break
            }
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

    // MARK: - Board

    /// How much of the board the pinned controls may take before they
    /// scroll by themselves. At the largest text sizes they would otherwise
    /// leave no room for the players.
    private static let pinnedControlsShare: CGFloat = 0.5

    /// The identity card, the plane and the players scroll together. The
    /// controls that act on the game stay pinned below them, so Unveil,
    /// Roll and End Game are always within reach.
    private var board: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    GameBoardIdentityArea(
                        viewModel: viewModel,
                        onShowCard: { showCardDetail = true },
                        onGoHome: { goHome() }
                    )

                    planechaseArea

                    OrnateDivider()
                        .padding(.horizontal)
                        .padding(.vertical, 4)

                    playersSection
                }
                .padding(.bottom, 8)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                pinnedControls(maxHeight: proxy.size.height * Self.pinnedControlsShare)
            }
            .sheet(item: $inspectedPlayer) { player in
                if let card = viewModel.identityCard(for: player) {
                    IdentityCardView(card: card, player: player)
                }
            }
        }
    }

    /// The plane card banner, only when Planechase is on and the board deals
    /// the planes (not with the players' own decks).
    @ViewBuilder
    private var planechaseArea: some View {
        if viewModel.isPlanechaseActive && !viewModel.isOwnDeckMode {
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
    }

    /// Every player, with their life controls.
    private var playersSection: some View {
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

    /// The errors, and the controls that act on the game: as tall as they
    /// need, up to `maxHeight`, past which they scroll by themselves.
    private func pinnedControls(maxHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                errorBanners

                // Spectator bar for eliminated players, in every mode:
                // its Leave is their only way off the board.
                if let leave = viewModel.spectatorLeave {
                    SpectatorBar(leave: leave, onGoHome: { goHome() }, onEndGame: { presentWinnerSelection() })
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
        .scrollBounceBehavior(.basedOnSize)
        // Asks the scroll view for its content's height, capped.
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .background { boardBackground.ignoresSafeArea(edges: .bottom) }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.mtgDivider)
                .frame(height: 1)
        }
    }

    /// The last action's error, failed life changes and a failed unveil.
    /// They wrap rather than truncate, so they stay readable at the largest
    /// text sizes; the pinned controls scroll if they need to.
    @ViewBuilder
    private var errorBanners: some View {
        if let error = viewModel.errorMessage {
            MtgErrorBanner(message: error)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
        if let message = viewModel.lifeChangeMessage {
            MtgErrorBanner(message: message)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
        if let failure = viewModel.unveilFailure {
            MtgErrorBanner(message: failure)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
    }

    /// Dark, tinted with the signed-in player's color.
    private var boardBackground: some View {
        ZStack {
            Color.mtgBackground
            if let hex = viewModel.currentPlayer?.playerColor {
                Color(hex: hex).opacity(0.15)
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
        case .notInGame:
            GameStatusView.notInGame(onGoHome: { goHome() })
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
