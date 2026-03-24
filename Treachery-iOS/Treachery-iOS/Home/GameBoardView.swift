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

    init(gameId: String, navigationPath: Binding<NavigationPath>) {
        _viewModel = StateObject(wrappedValue: GameBoardViewModel(gameId: gameId))
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
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Color.mtgGold)
                        Text("Loading game...")
                            .font(.subheadline)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
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
                                    PlayerRow(
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
        .navigationTitle("Game")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            // Forfeit button — only when treachery active
            if viewModel.isTreacheryActive && !viewModel.isGameUnavailable && !(viewModel.currentPlayer?.isEliminated ?? true) {
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

// MARK: - Identity Card Header

private struct IdentityCardHeader: View {
    let card: IdentityCard
    let player: Player

    /// Leaders are always face-up; unveiled players show openly; everyone else is hidden.
    private var isAlwaysVisible: Bool {
        player.isUnveiled || player.role == .leader
    }

    var body: some View {
        if isAlwaysVisible {
            revealedContent
        } else {
            concealedContent
        }
    }

    // MARK: - Concealed (tap to open sheet)

    private var concealedContent: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "eye.slash.fill")
                    .font(.title3)
                    .foregroundStyle(Color.mtgGold)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color.mtgError)
                    Text("\(player.lifeTotal)")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color.mtgTextPrimary)
                        .contentTransition(.numericText())
                }
            }

            Text("Tap to peek at your identity")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color.mtgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.mtgBorderAccent, lineWidth: 1)
        )
    }

    // MARK: - Revealed (unveiled)

    private var revealedContent: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(player.role?.color ?? .gray)
                        .frame(width: 12, height: 12)
                    Text(player.role?.displayName ?? "Unknown")
                        .font(.headline)
                        .foregroundStyle(player.role?.color ?? Color.mtgTextPrimary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(Color.mtgError)
                    Text("\(player.lifeTotal)")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(Color.mtgTextPrimary)
                        .contentTransition(.numericText())
                }
            }

            HStack {
                Text(card.name)
                    .font(.system(.title3, design: .serif))
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.mtgTextPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }

            Text(card.abilityText)
                .font(.caption)
                .foregroundStyle(Color.mtgTextSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(3)

            HStack {
                if player.isUnveiled {
                    Text("UNVEILED")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.mtgBackground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(player.role?.color ?? .gray)
                        .clipShape(Capsule())
                } else if player.role == .leader {
                    Text("LEADER — ALWAYS VISIBLE")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.mtgGold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.mtgGold.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                Text("Tap for details")
                    .font(.caption2)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
        .padding()
        .background(Color.mtgSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 0)
                .stroke(Color.mtgBorderAccent, lineWidth: 1)
        )
    }
}

// MARK: - Player Row

private struct PlayerRow: View {
    let player: Player
    @ObservedObject var viewModel: GameBoardViewModel
    @Binding var showColorPicker: Bool
    var onViewCard: ((Player) -> Void)?

    private var isCurrentUser: Bool {
        player.userId == viewModel.currentUserId
    }

    /// Whether this player's card can be inspected by the current user.
    /// True for unveiled players and leaders (but not yourself -- you have the header).
    private var canInspectCard: Bool {
        guard !isCurrentUser else { return false }
        guard viewModel.identityCard(for: player) != nil else { return false }
        return player.isUnveiled || player.role == .leader
    }

    var body: some View {
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
                if isCurrentUser {
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

                // Player info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(player.displayName)
                            .fontWeight(isCurrentUser ? .bold : .regular)
                            .strikethrough(player.isEliminated)
                            .foregroundStyle(player.isEliminated ? Color.mtgTextSecondary : Color.mtgTextPrimary)

                        if isCurrentUser {
                            Text("You")
                                .font(.caption2)
                                .foregroundStyle(Color.mtgGold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .background(Color.mtgGold.opacity(0.15))
                                .clipShape(Capsule())
                        }

                        if player.isEliminated {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.mtgError)
                                .font(.caption)
                        }
                    }

                    // Commander name
                    if let commanderName = player.commanderName, !commanderName.isEmpty {
                        Text(commanderName)
                            .font(.system(.caption, design: .serif))
                            .italic()
                            .foregroundStyle(Color.mtgTextSecondary)
                    }

                    // Role visibility — only show for unveiled players and leaders
                    // to prevent leaking info when the phone is on the table
                    if player.isUnveiled || player.role == .leader {
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
                                        .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
                                    if player.isUnveiled && player.role != .leader {
                                        Text("(Unveiled)")
                                            .font(.caption2)
                                            .foregroundStyle(Color.mtgTextSecondary)
                                    }
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
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
                                    .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
                                if player.isUnveiled && player.role != .leader {
                                    Text("(Unveiled)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }
                            }
                        }
                    } else if viewModel.isTreacheryActive {
                        Text("Role Hidden")
                            .font(.caption)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                }

                Spacer()

                // Life controls
                if !player.isEliminated {
                    HStack(spacing: 14) {
                        Button {
                            viewModel.adjustLife(for: player.id, by: -1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.mtgAssassin)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease \(player.displayName)'s life")

                        Text("\(player.lifeTotal)")
                            .font(.system(size: 32, weight: .bold, design: .serif))
                            .foregroundStyle(Color.mtgTextPrimary)
                            .frame(minWidth: 48)
                            .multilineTextAlignment(.center)
                            .contentTransition(.numericText())
                            .accessibilityLabel("\(player.lifeTotal) life")

                        Button {
                            viewModel.adjustLife(for: player.id, by: 1)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.mtgSuccess)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Increase \(player.displayName)'s life")
                    }
                } else {
                    Text("Eliminated")
                        .font(.caption)
                        .foregroundStyle(Color.mtgError)
                }
            }
            .padding(.vertical, 4)

            // Color picker row (current user only)
            if isCurrentUser && showColorPicker {
                ColorPickerRow(selectedHex: player.playerColor) { hex in
                    Task { await viewModel.updatePlayerColor(hex) }
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Color Picker Row

private struct ColorPickerRow: View {
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
                .buttonStyle(MtgPrimaryButtonStyle(isDisabled: viewModel.isPending))
                .disabled(viewModel.isPending)
                .padding(.horizontal)
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

        }
        .padding()
    }
}

// MARK: - Winner Selection Sheet

private struct WinnerSelectionSheet: View {
    let players: [Player]
    @Binding var selectedWinners: Set<String>
    let isPending: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                VStack(spacing: 16) {
                    Text("Select the winner(s) of this game for ELO tracking.")
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(players) { player in
                                Button {
                                    if selectedWinners.contains(player.userId) {
                                        selectedWinners.remove(player.userId)
                                    } else {
                                        selectedWinners.insert(player.userId)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedWinners.contains(player.userId) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedWinners.contains(player.userId) ? Color.mtgSuccess : Color.mtgTextSecondary)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(player.displayName)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            if let commanderName = player.commanderName, !commanderName.isEmpty {
                                                Text(commanderName)
                                                    .font(.system(.caption, design: .serif))
                                                    .italic()
                                                    .foregroundStyle(Color.mtgTextSecondary)
                                            }
                                        }

                                        Spacer()

                                        if let hex = player.playerColor {
                                            Circle()
                                                .fill(Color(hex: hex))
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)

                                if player.id != players.last?.id {
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

                    VStack(spacing: 8) {
                        Button {
                            onConfirm()
                        } label: {
                            if isPending {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(Color.mtgBackground)
                                    Text("Ending Game...")
                                }
                            } else {
                                Text("End Game")
                            }
                        }
                        .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isPending))
                        .disabled(isPending)
                        .padding(.horizontal)

                        Text("You can skip winner selection — ELO won't be updated.")
                            .font(.caption2)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                    .padding(.bottom)
                }
            }
            .navigationTitle("End Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(Color.mtgGold)
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

#Preview("Identity Card Header - Leader (always visible)") {
    IdentityCardHeader(
        card: .sampleLeaderCard,
        player: .sampleLeader
    )
}

#Preview("Identity Card Header - Hidden (tap to peek)") {
    IdentityCardHeader(
        card: .sampleGuardianCard,
        player: .sampleGuardian
    )
}

#Preview("Identity Card Header - Unveiled") {
    IdentityCardHeader(
        card: .sampleAssassinCard,
        player: .sampleAssassin
    )
}

#Preview("Player Row - Active") {
    let vm = GameBoardViewModel(
        gameId: "preview",
        previewPlayers: Player.sampleGamePlayers,
        previewGame: .sampleInProgress,
        currentUserId: "user2"
    )
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        VStack(spacing: 0) {
            PlayerRow(
                player: .sampleGuardian,
                viewModel: vm,
                showColorPicker: .constant(false)
            )
            PlayerRow(
                player: .sampleAssassin,
                viewModel: vm,
                showColorPicker: .constant(false)
            )
            PlayerRow(
                player: .sampleEliminated,
                viewModel: vm,
                showColorPicker: .constant(false)
            )
        }
        .mtgCardFrame()
        .padding()
    }
}
#endif
