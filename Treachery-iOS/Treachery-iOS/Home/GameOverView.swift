//
//  GameOverView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct GameOverView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: GameBoardViewModel
    @Binding var navigationPath: NavigationPath

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

    @State private var trophyScale: CGFloat = 0.3
    @State private var contentOpacity: Double = 0
    // The titles and symbols keep their sizes at the default text size and
    // grow with it.
    @ScaledMetric(relativeTo: .largeTitle) private var symbolSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var summaryTitleSize: CGFloat = 36
    @ScaledMetric(relativeTo: .title) private var inProgressTitleSize: CGFloat = 28
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            // Dynamic radial glow based on winning team color
            if let winningTeam = viewModel.winningTeam {
                RadialGradient(
                    colors: [
                        winningTeam.color.opacity(0.15),
                        Color.mtgBackground
                    ],
                    center: .top,
                    startRadius: 20,
                    endRadius: 420
                )
                .ignoresSafeArea()
            } else {
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
            }

            switch viewModel.gameOverContent {
            case .status:
                statusContent
            case .stillInProgress:
                stillInProgress
            case .results:
                results
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            AnalyticsService.trackScreen("GameOver")
            viewModel.currentUserId = authViewModel.currentUserId
            // With Reduce Motion the trophy is simply there; the rest still
            // fades in.
            if !reduceMotion {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.2)) {
                    trophyScale = 1.0
                }
            }
            withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
                contentOpacity = 1.0
            }
        }
    }

    // MARK: - Layout

    /// `content` centred in the space above `pinned` when it fits, and
    /// scrolling when more players or larger text make it taller. `pinned`
    /// stays on screen, since this screen hides the back button and the tab
    /// bar: it's the only way out.
    private func scrolling<Content: View, Pinned: View>(
        @ViewBuilder _ content: () -> Content,
        @ViewBuilder pinned: () -> Pinned
    ) -> some View {
        let content = content()
        let pinned = pinned()
        return GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pinned
                .padding(.top, 12)
                .padding(.bottom)
                .background(Color.mtgBackground)
        }
    }

    // MARK: - Still in Progress

    private var stillInProgress: some View {
        scrolling {
            VStack(spacing: 16) {
                Image(systemName: "clock")
                    .font(.system(size: symbolSize))
                    .foregroundStyle(Color.mtgGold)
                Text("Game Still In Progress")
                    .font(.system(size: inProgressTitleSize, weight: .bold, design: .serif))
                    .foregroundStyle(Color.mtgTextPrimary)
                    .multilineTextAlignment(.center)
                Text("Results are available only after the game finishes.")
                    .font(.subheadline)
                    .foregroundStyle(Color.mtgTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        } pinned: {
            Button {
                if !navigationPath.isEmpty {
                    navigationPath.removeLast()
                }
            } label: {
                Text("Return to Game")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(MtgPrimaryButtonStyle())
            .padding(.horizontal, 32)
        }
    }

    // MARK: - Results

    private var results: some View {
        scrolling {
            VStack(spacing: 24) {
                if viewModel.game?.gameMode.includesTreachery ?? true {
                    treacheryResults
                } else {
                    summaryResults
                }
            }
            .padding(.vertical, 24)
        } pinned: {
            Button("Return to Home") {
                goHome()
            }
            .buttonStyle(MtgPrimaryButtonStyle())
            .padding(.horizontal)
            .accessibilityLabel("Return to home screen")
        }
    }

    /// The winning team, and every player's revealed role (Treachery modes).
    @ViewBuilder
    private var treacheryResults: some View {
        // Winner announcement (treachery modes only)
        if let winningTeam = viewModel.winningTeam {
            VStack(spacing: 16) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: symbolSize))
                    .foregroundStyle(winningTeam.color)
                    .shadow(color: winningTeam.color.opacity(0.5), radius: 16, x: 0, y: 0)
                    .shadow(color: winningTeam.color.opacity(0.3), radius: 32, x: 0, y: 0)
                    .scaleEffect(reduceMotion ? 1 : trophyScale)

                Text("Game Over")
                    .font(.system(size: titleSize, weight: .bold, design: .serif))
                    .foregroundStyle(Color.mtgTextPrimary)

                OrnateDivider()
                    .padding(.horizontal, 40)

                HStack(spacing: 8) {
                    Circle()
                        .fill(winningTeam.color)
                        .frame(width: 16, height: 16)
                        .shadow(color: winningTeam.color.opacity(0.6), radius: 6)
                    Text("\(winningTeam.displayName) Wins!")
                        .font(.system(.title, design: .serif))
                        .fontWeight(.bold)
                        .foregroundStyle(winningTeam.color)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(winningTeam.displayName) team wins")
            }
            .opacity(contentOpacity)
        }

        // All players revealed (treachery modes only)
        VStack(spacing: 0) {
            ForEach(viewModel.players) { player in
                HStack {
                    // Left accent bar for player color
                    if let hex = player.playerColor {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: hex))
                            .frame(width: 3)
                            .padding(.vertical, 2)
                            .padding(.trailing, 4)
                    }

                    Circle()
                        .fill(player.role?.color ?? .gray)
                        .frame(width: 12, height: 12)
                        .shadow(color: (player.role?.color ?? .gray).opacity(0.4), radius: 4)

                    // At the accessibility text sizes the name needs the
                    // row's width, so the role goes underneath it.
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            nameAndCommander(of: player)
                            roleAndCard(of: player, alignment: .leading)
                        }
                        Spacer()
                    } else {
                        nameAndCommander(of: player)
                        Spacer()
                        roleAndCard(of: player, alignment: .trailing)
                    }

                    if player.isEliminated {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.mtgError)
                            .font(.caption)
                            .padding(.leading, 4)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    "\(player.displayName), \(player.role?.displayName ?? "Unknown")\(player.isEliminated ? ", eliminated" : "")"
                )

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

    private func nameAndCommander(of player: Player) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(player.displayName)
                .fontWeight(.medium)
                .foregroundStyle(Color.mtgTextPrimary)

            if let commanderName = player.commanderName, !commanderName.isEmpty {
                Text(commanderName)
                    .font(.system(.caption, design: .serif))
                    .italic()
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
    }

    private func roleAndCard(of player: Player, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(player.role?.displayName ?? "Unknown")
                .font(.subheadline)
                .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)

            if let card = viewModel.identityCard(for: player) {
                Text(card.name)
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }
        }
    }

    /// A simple summary for the modes without roles.
    @ViewBuilder
    private var summaryResults: some View {
        VStack(spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.system(size: symbolSize))
                .foregroundStyle(Color.mtgGold)
                .shadow(color: Color.mtgGold.opacity(0.4), radius: 16, x: 0, y: 0)
                .scaleEffect(reduceMotion ? 1 : trophyScale)

            Text("Game Over")
                .font(.system(size: summaryTitleSize, weight: .bold, design: .serif))
                .foregroundStyle(Color.mtgTextPrimary)

            OrnateDivider()
                .padding(.horizontal, 40)

            if let mode = viewModel.game?.gameMode {
                MtgBadge(text: mode.displayName, font: .caption, fontWeight: .semibold)
            }

            Text("\(viewModel.players.count) player\(viewModel.players.count == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
        }

        // Player list without roles
        VStack(spacing: 0) {
            ForEach(viewModel.players) { player in
                HStack {
                    // Left accent bar for player color
                    if let hex = player.playerColor {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(Color(hex: hex))
                            .frame(width: 3)
                            .padding(.vertical, 2)
                            .padding(.trailing, 4)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(player.displayName)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.mtgTextPrimary)

                        if let commanderName = player.commanderName, !commanderName.isEmpty {
                            Text(commanderName)
                                .font(.system(.caption, design: .serif))
                                .italic()
                                .foregroundStyle(Color.mtgTextSecondary)
                        }
                    }

                    Spacer()

                    if player.isEliminated {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.mtgError)
                            .font(.caption)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(player.displayName)\(player.isEliminated ? ", eliminated" : "")")

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

    // MARK: - Status

    /// Everything but the results. Each state offers a way home, since this
    /// screen hides the back button and the tab bar.
    @ViewBuilder
    private var statusContent: some View {
        switch viewModel.status {
        case .ready:
            EmptyView() // the results are shown instead
        case .loading:
            GameLoadingView(message: "Loading results...", onGoHome: { goHome() })
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
                title: "Couldn't Load the Results",
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
}

#if DEBUG
#Preview("Treachery") {
    NavigationStack {
        GameOverView(
            viewModel: GameBoardViewModel(
                gameId: "preview-game",
                previewPlayers: Player.sampleGamePlayers,
                previewGame: .sampleFinishedLeaderWin,
                currentUserId: "user2"
            ),
            navigationPath: .preview
        )
    }
    .environmentObject(AuthViewModel())
}

#Preview("Treachery, AX5") {
    NavigationStack {
        GameOverView(
            viewModel: GameBoardViewModel(
                gameId: "preview-game",
                previewPlayers: Player.sampleGamePlayers,
                previewGame: .sampleFinishedLeaderWin,
                currentUserId: "user2"
            ),
            navigationPath: .preview
        )
    }
    .environmentObject(AuthViewModel())
    .dynamicTypeSize(.accessibility5)
}
#endif
