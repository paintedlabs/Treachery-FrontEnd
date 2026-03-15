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
    @State private var inspectedPlayer: Player?

    init(gameId: String, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: GameBoardViewModel(gameId: gameId))
        _navigationPath = navigationPath
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.isGameUnavailable {
                // Game was deleted or became unavailable
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    Text("Game Unavailable")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("This game is no longer available. It may have been deleted by the host.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Return to Home") {
                        navigationPath.removeLast(navigationPath.count)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top)
                }
                .padding()
                Spacer()
            } else if viewModel.players.isEmpty {
                // Loading state
                Spacer()
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading game...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                // Current player's identity card (tappable)
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
                        .accessibilityLabel("Your identity card: \(card.name), \(player.role?.displayName ?? "Unknown") role, \(player.lifeTotal) life. Tap for details.")
                        .accessibilityHint("Opens full identity card view")

                        // Unveiled banner overlay
                        if showUnveiledBanner {
                            VStack {
                                Text("IDENTITY REVEALED")
                                    .font(.headline)
                                    .fontWeight(.black)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(player.role?.color ?? .blue)
                                            .shadow(color: (player.role?.color ?? .blue).opacity(0.6), radius: 12)
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
                            .foregroundStyle(.orange)
                        Text("Unable to find your player data")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }

                Divider()

                // Player list with life controls
                List {
                    Section("Players") {
                        ForEach(viewModel.players) { player in
                            PlayerRow(player: player, viewModel: viewModel) { tappedPlayer in
                                inspectedPlayer = tappedPlayer
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .sheet(item: $inspectedPlayer) { player in
                    if let card = viewModel.identityCard(for: player) {
                        IdentityCardView(card: card, player: player)
                    }
                }

                // Error display
                if let error = viewModel.errorMessage {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                // Action bar
                ActionBar(viewModel: viewModel, onUnveil: playUnveilAnimation)
            }
        }
        .navigationTitle("Game")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if !viewModel.isGameUnavailable && !(viewModel.currentPlayer?.isEliminated ?? true) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showForfeitConfirmation = true
                    } label: {
                        Image(systemName: "flag.fill")
                            .foregroundStyle(.orange)
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
    }

    // MARK: - Unveil Animation

    private func playUnveilAnimation() {
        // Phase 1: Flip card away (0 → 90 degrees)
        withAnimation(.easeIn(duration: 0.3)) {
            cardFlipDegrees = 90
        }

        // Phase 2: Perform the unveil at the midpoint, then flip back (90 → 0)
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

// MARK: - Identity Card Header

private struct IdentityCardHeader: View {
    let card: IdentityCard
    let player: Player

    var body: some View {
        VStack(spacing: 8) {
            // Role and life
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(player.role?.color ?? .gray)
                        .frame(width: 12, height: 12)
                    Text(player.role?.displayName ?? "Unknown")
                        .font(.headline)
                        .foregroundStyle(player.role?.color ?? .primary)
                }

                Spacer()

                Text("Life: \(player.lifeTotal)")
                    .font(.title2)
                    .fontWeight(.bold)
                    .contentTransition(.numericText())
            }

            // Card name
            HStack {
                Text(card.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Ability text
            Text(card.abilityText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            // Unveil status
            HStack {
                if !player.isUnveiled {
                    Text("Unveil: \(card.unveilCost)")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.2))
                        .clipShape(Capsule())
                } else {
                    Text("UNVEILED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(player.role?.color ?? .gray)
                        .clipShape(Capsule())
                }
                Spacer()
                Text("Tap for details")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Player Row

private struct PlayerRow: View {
    let player: Player
    @ObservedObject var viewModel: GameBoardViewModel
    var onViewCard: ((Player) -> Void)?

    private var isCurrentUser: Bool {
        player.userId == viewModel.currentUserId
    }

    /// Whether this player's card can be inspected by the current user.
    /// True for unveiled players and leaders (but not yourself — you have the header).
    private var canInspectCard: Bool {
        guard !isCurrentUser else { return false }
        guard viewModel.identityCard(for: player) != nil else { return false }
        return player.isUnveiled || player.role == .leader
    }

    var body: some View {
        HStack {
            // Player info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(player.displayName)
                        .fontWeight(isCurrentUser ? .bold : .regular)
                        .strikethrough(player.isEliminated)
                        .foregroundStyle(player.isEliminated ? .secondary : .primary)

                    if isCurrentUser {
                        Text("You")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(.blue.opacity(0.2))
                            .clipShape(Capsule())
                    }

                    if player.isEliminated {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                // Role visibility
                if viewModel.canSeeRole(of: player) {
                    if canInspectCard {
                        Button {
                            onViewCard?(player)
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(player.role?.color ?? .gray)
                                    .frame(width: 8, height: 8)
                                Text(player.role?.displayName ?? "")
                                    .font(.caption)
                                    .foregroundStyle(player.role?.color ?? .secondary)
                                if player.isUnveiled && player.role != .leader {
                                    Text("(Unveiled)")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Image(systemName: "info.circle")
                                    .font(.caption2)
                                    .foregroundStyle(player.role?.color ?? .secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View \(player.displayName)'s identity card")
                        .accessibilityHint("Shows their role ability and card details")
                    } else {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(player.role?.color ?? .gray)
                                .frame(width: 8, height: 8)
                            Text(player.role?.displayName ?? "")
                                .font(.caption)
                                .foregroundStyle(player.role?.color ?? .secondary)
                            if player.isUnveiled && !isCurrentUser && player.role != .leader {
                                Text("(Unveiled)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Text("Role Hidden")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Life controls
            if !player.isEliminated {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.adjustLife(for: player.id, by: -1) }
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Decrease \(player.displayName)'s life")

                    Text("\(player.lifeTotal)")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(minWidth: 36)
                        .multilineTextAlignment(.center)
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(player.lifeTotal) life")

                    Button {
                        Task { await viewModel.adjustLife(for: player.id, by: 1) }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Increase \(player.displayName)'s life")
                }
            } else {
                Text("Eliminated")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Action Bar

private struct ActionBar: View {
    @ObservedObject var viewModel: GameBoardViewModel
    @State private var showUnveilConfirmation = false
    var onUnveil: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if let player = viewModel.currentPlayer,
               !player.isUnveiled,
               !player.isEliminated,
               player.role != .leader {
                Button("Unveil Identity") {
                    showUnveilConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(player.role?.color ?? .blue)
                .accessibilityLabel("Unveil your identity as \(player.role?.displayName ?? "unknown")")
                .accessibilityHint("Reveals your role to all players. Cannot be undone.")
                .confirmationDialog(
                    "Unveil your identity?",
                    isPresented: $showUnveilConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Unveil") {
                        onUnveil()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    if let card = viewModel.currentIdentityCard {
                        Text("This will reveal your role (\(player.role?.displayName ?? "")) and card (\(card.name)) to all players. This cannot be undone.")
                    }
                }
            }

            // Win condition reminder
            if let player = viewModel.currentPlayer {
                Text(player.role?.winConditionText ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Win condition: \(player.role?.winConditionText ?? "")")
            }
        }
        .padding()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Game Board") {
    NavigationStack {
        GameBoardView(gameId: "preview-game", navigationPath: .preview)
    }
    .environmentObject(AuthViewModel())
}

#Preview("Identity Card Header") {
    IdentityCardHeader(
        card: .sampleLeaderCard,
        player: .sampleLeader
    )
}

#Preview("Identity Card Header - Unveiled") {
    IdentityCardHeader(
        card: .sampleAssassinCard,
        player: .sampleAssassin
    )
}

#Preview("Player Row - Active") {
    List {
        PlayerRow(
            player: .sampleGuardian,
            viewModel: GameBoardViewModel(gameId: "preview")
        )
        PlayerRow(
            player: .sampleAssassin,
            viewModel: GameBoardViewModel(gameId: "preview")
        )
        PlayerRow(
            player: .sampleEliminated,
            viewModel: GameBoardViewModel(gameId: "preview")
        )
    }
}
#endif
