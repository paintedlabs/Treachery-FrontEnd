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
    @State private var cardFlipDegrees: Double = 0
    @State private var showUnveiledBanner = false
    @State private var showForfeitConfirmation = false
    @State private var showGameUnavailableAlert = false
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

                if viewModel.isGameUnavailable {
                    // Game was deleted or became unavailable
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.mtgGold)
                        Text("Game Unavailable")
                            .font(.system(.title2, design: .serif))
                            .fontWeight(.bold)
                            .foregroundStyle(Color.mtgTextPrimary)
                        Text("This game is no longer available. It may have been deleted by the host.")
                            .font(.subheadline)
                            .foregroundStyle(Color.mtgTextSecondary)
                            .multilineTextAlignment(.center)
                        Button("Return to Home") {
                            navigationPath.removeLast(navigationPath.count)
                        }
                        .buttonStyle(MtgPrimaryButtonStyle())
                        .padding(.top)
                        .padding(.horizontal, 40)
                    }
                    .padding()
                    Spacer()
                } else if viewModel.players.isEmpty {
                    // Loading state
                    Spacer()
                    MtgLoadingView(message: "Loading game...")
                    Spacer()
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
                                    .degrees(cardFlipDegrees),
                                    axis: (x: 0, y: 1, z: 0),
                                    perspective: 0.5
                                )

                                // Unveiled banner overlay
                                if showUnveiledBanner {
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
                        } else {
                            // Current player not found (reconnection case)
                            VStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.title)
                                    .foregroundStyle(Color.mtgGold)
                                Text("Unable to find your player data")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.mtgTextSecondary)
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

                            // Phenomenon overlay when current plane is a phenomenon
                            if plane.isPhenomenon {
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

                    // Spectator overlay for eliminated players (treachery only)
                    if viewModel.isTreacheryActive,
                       let player = viewModel.currentPlayer, player.isEliminated {
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
                                navigationPath.removeLast(navigationPath.count)
                                navigationPath.append(AppDestination.gameOver(gameId: viewModel.gameId))
                            }
                            .foregroundStyle(Color.mtgError)
                            .padding(.top, 4)
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
                    if viewModel.isTreacheryActive,
                       !(viewModel.currentPlayer?.isEliminated ?? true) {
                        ActionBar(viewModel: viewModel, onUnveil: playUnveilAnimation)
                    }

                    // End Game button — only when NOT treachery (host only)
                    if !viewModel.isTreacheryActive && viewModel.isHost {
                        Button {
                            selectedWinners = []
                            showWinnerSelection = true
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
            // Forfeit button — available in all game modes so players can always leave
            if !viewModel.isGameUnavailable && !(viewModel.currentPlayer?.isEliminated ?? true) {
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
                    navigationPath.removeLast(navigationPath.count)
                    navigationPath.append(AppDestination.gameOver(gameId: viewModel.gameId))
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will be eliminated from the game. This cannot be undone.")
        }
        .onAppear {
            viewModel.currentUserId = authViewModel.currentUserId
        }
        .onChange(of: viewModel.isGameFinished) { _, finished in
            if finished {
                navigationPath.append(AppDestination.gameOver(gameId: viewModel.gameId))
            }
        }
        .onChange(of: viewModel.isGameUnavailable) { _, unavailable in
            if unavailable {
                showGameUnavailableAlert = true
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
    }

    // MARK: - Unveil Animation

    private func playUnveilAnimation() {
        // Phase 1: Flip card away (0 -> 90 degrees)
        withAnimation(.easeIn(duration: 0.3)) {
            cardFlipDegrees = 90
        }

        // Phase 2: Perform the unveil at the midpoint, then flip back (90 -> 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            Task { await viewModel.unveilCurrentPlayer() }

            withAnimation(.easeOut(duration: 0.3)) {
                cardFlipDegrees = 0
            }

            // Phase 3: Show the "IDENTITY REVEALED" banner
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                showUnveiledBanner = true
            }

            // Phase 4: Dismiss the banner after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    showUnveiledBanner = false
                }
            }
        }
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
