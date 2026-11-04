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
    /// Counts changes to the pinned controls' height, to flash their scroll
    /// indicators when there's more of them than fits.
    @State private var pinnedControlsChanges = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // A players snapshot redraws the board with a short ease, at once
        // with Reduce Motion. A tap's change shows at once, as before: the
        // totals animate by themselves.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: viewModel.serverPlayers)
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
        // What each change reads out, if anything, is the view model's call;
        // see GameBoardViewModel+Accessibility.swift. Nothing is, once the
        // game is over and Game Over covers the board.
        .onChange(of: viewModel.errorMessage) { _, message in
            // An action that fails (a roll, a forfeit, an ability) says so in
            // the controls pinned below the players.
            guard let announcement = viewModel.announcement(forError: message) else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
        .onChange(of: viewModel.lifeChangeFailures) { old, new in
            // Each new failure by itself.
            for announcement in viewModel.announcements(forFailuresFrom: old, to: new) {
                var message = AttributedString(announcement.message)
                // Low priority waits for VoiceOver to finish what it's saying.
                message.accessibilitySpeechAnnouncementPriority = announcement.interrupts ? .default : .low
                AccessibilityNotification.Announcement(message).post()
            }
        }
        .onChange(of: viewModel.seat) { oldSeat, newSeat in
            guard let announcement = viewModel.announcement(forSeatChangeFrom: oldSeat, to: newSeat) else { return }
            AccessibilityNotification.Announcement(announcement).post()
        }
        .onChange(of: viewModel.unveilProgress) { _, progress in
            guard let announcement = viewModel.announcement(for: progress) else { return }
            AccessibilityNotification.Announcement(announcement).post()
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

    /// How strongly the signed-in player's color tints the board.
    static let playerTintOpacity = 0.15

    /// The parts of the board that its own actions bring into view, and the
    /// feedback that appears in its pinned controls.
    private enum ScrollTarget: Hashable {
        case identity, plane
        case error, lifeChanges, unveilFailure, dieResult
    }

    /// The identity card, the plane and the players scroll together. The
    /// controls that act on the game stay pinned below them, so Unveil,
    /// Roll and End Game are always within reach.
    private var board: some View {
        GeometryReader { proxy in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 0) {
                        GameBoardIdentityArea(
                            viewModel: viewModel,
                            onShowCard: { showCardDetail = true },
                            onGoHome: { goHome() }
                        )
                        .id(ScrollTarget.identity)

                        planechaseArea
                            .id(ScrollTarget.plane)

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
                // The reveal plays in the identity card, and a roll is about
                // the plane: when the player unveils or rolls from further
                // down the board, bring it into view. Only on their own
                // tap, so the rows never move under a finger.
                .onChange(of: viewModel.unveilProgress) { _, progress in
                    guard progress == .sending else { return }
                    bringIntoView(.identity, with: scroll)
                }
                .onChange(of: viewModel.isRollingDie) { _, isRolling in
                    guard isRolling else { return }
                    bringIntoView(.plane, with: scroll)
                }
                // Feedback appears at the top of the pinned controls. When
                // there's more of them than fits, as at large text sizes,
                // that's above the part in view: bring it into view.
                .onChange(of: viewModel.errorMessage) { _, message in
                    guard message != nil else { return }
                    bringIntoView(.error, anchor: .top, with: scroll)
                }
                .onChange(of: viewModel.lifeChangeMessage) { _, message in
                    guard message != nil else { return }
                    bringIntoView(.lifeChanges, anchor: .top, with: scroll)
                }
                .onChange(of: viewModel.unveilFailure) { _, failure in
                    guard failure != nil else { return }
                    bringIntoView(.unveilFailure, anchor: .top, with: scroll)
                }
                .onChange(of: viewModel.dieRollResult) { _, result in
                    guard result != nil else { return }
                    bringIntoView(.dieResult, anchor: .top, with: scroll)
                }
            }
            .sheet(item: $inspectedPlayer) { player in
                if let card = viewModel.identityCard(for: player) {
                    IdentityCardView(card: card, player: player)
                }
            }
        }
    }

    /// Scrolls just far enough to show `target`, or to put it at `anchor`,
    /// at once with Reduce Motion.
    private func bringIntoView(_ target: ScrollTarget, anchor: UnitPoint? = nil, with scroll: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
            scroll.scrollTo(target, anchor: anchor)
        }
    }

    /// The plane card banner, only when Planechase is on and the board deals
    /// the planes (not with the players' own decks).
    @ViewBuilder
    private var planechaseArea: some View {
        if viewModel.isPlanechaseActive && !viewModel.isOwnDeckMode {
            VStack(spacing: 0) {
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
    /// need, up to `maxHeight`, past which they scroll by themselves. Then
    /// they show their end first, where the controls are, and keep it in
    /// view as they grow, flashing their scroll indicators to show there's
    /// more above.
    private func pinnedControls(maxHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                errorBanners

                // Planar die bar — only when planechase active. A roll's
                // result shows at its top.
                if viewModel.isPlanechaseActive {
                    PlanarDieBar(viewModel: viewModel)
                        .id(ScrollTarget.dieResult)
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
                                .accessibilityHidden(true)
                            Text("End Game")
                                .fontWeight(.semibold)
                        }
                    }
                    .buttonStyle(MtgSecondaryButtonStyle())
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                // Spectator bar for eliminated players, in every mode: its
                // Leave is their only way off the board, so it comes last,
                // the first thing shown when the controls don't all fit.
                if let leave = viewModel.spectatorLeave {
                    SpectatorBar(leave: leave, onGoHome: { goHome() }, onEndGame: { presentWinnerSelection() })
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.bottom)
        .defaultScrollAnchor(.bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: CGFloat.self, of: \.contentSize.height) { _, _ in
            pinnedControlsChanges += 1
        }
        .scrollIndicatorsFlash(trigger: pinnedControlsChanges)
        .scrollIndicatorsFlash(onAppear: true)
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
                .id(ScrollTarget.error)
        }
        if let message = viewModel.lifeChangeMessage {
            MtgErrorBanner(message: message)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .id(ScrollTarget.lifeChanges)
        }
        if let failure = viewModel.unveilFailure {
            MtgErrorBanner(message: failure)
                .padding(.horizontal)
                .padding(.vertical, 4)
                .id(ScrollTarget.unveilFailure)
        }
    }

    /// Dark, tinted with the signed-in player's color.
    private var boardBackground: some View {
        ZStack {
            Color.mtgBackground
            if let hex = viewModel.currentPlayer?.playerColor {
                Color(hex: hex).opacity(Self.playerTintOpacity)
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
/// The board with `players`, signed in as user2.
@MainActor
private func gameBoard(_ players: [Player]) -> some View {
    NavigationStack {
        GameBoardView(
            viewModel: GameBoardViewModel(
                gameId: "preview-game",
                previewPlayers: players,
                previewGame: .sampleInProgress,
                currentUserId: "user2"
            ),
            navigationPath: .preview
        )
    }
    .environmentObject(AuthViewModel())
}

#Preview("Game Board") {
    gameBoard(Player.sampleGamePlayers)  // Sarah (Guardian)
}

#Preview("Game Board, long names, xxxLarge") {
    gameBoard(Player.sampleLongNamePlayers)
        .dynamicTypeSize(.xxxLarge)
}

#Preview("Game Board, long names, AX5") {
    gameBoard(Player.sampleLongNamePlayers)
        .dynamicTypeSize(.accessibility5)
}
#endif
