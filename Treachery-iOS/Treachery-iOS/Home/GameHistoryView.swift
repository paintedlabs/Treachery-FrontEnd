//
//  GameHistoryView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct GameHistoryView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @StateObject private var viewModel: GameHistoryViewModel

    /// `viewModel` is built once, the first time this view is installed.
    init(viewModel: @autoclosure @escaping () -> GameHistoryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    init() {
        self.init(viewModel: GameHistoryViewModel())
    }

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.top)
            }
            // Offline, what's shown may be out of date; this says so.
            .safeAreaInset(edge: .top, spacing: 0) {
                ConnectionBanner()
                    .background(Color.mtgBackground)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear { AnalyticsService.trackScreen("GameHistory") }
        .task { await reload() }
        .refreshable { await reload() }
    }

    /// Games only once they've loaded, "No games yet" only when a load
    /// succeeded with none, and a failure with Try Again above any games
    /// kept from an earlier load.
    @ViewBuilder private var content: some View {
        switch viewModel.history {
        case .idle, .loading(previous: nil):
            MtgLoadingView(message: "Loading game history...")
                .padding(.top, 100)
        case .failed(let failure, let previous):
            LoadFailureCard(title: "Couldn't Load Game History", failure: failure) {
                Task { await reload() }
            }
            .padding(.horizontal)
            if let previous {
                rows(for: previous)
            }
        case .loading(previous: let history?), .loaded(let history):
            if history.games.isEmpty {
                emptyState
            } else {
                rows(for: history)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.questionmark")
                .font(.largeTitle)
                .foregroundStyle(Color.mtgTextSecondary)
                .accessibilityHidden(true)
            Text("No games yet")
                .font(.system(.headline, design: .serif))
                .foregroundStyle(Color.mtgTextPrimary)
            Text("Finished games will appear here.")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
        .padding(.vertical, 32)
    }

    private func rows(for history: GameHistory) -> some View {
        ForEach(history.games) { game in
            GameHistoryRow(
                game: game,
                players: history.playersByGame[game.id] ?? [],
                currentUserId: authViewModel.currentUserId
            )
            .padding(.horizontal)
        }
    }

    private func reload() async {
        guard let userId = authViewModel.currentUserId else { return }
        await viewModel.loadHistory(userId: userId)
    }
}

// MARK: - Game History Row

private struct GameHistoryRow: View {
    let game: Game
    let players: [Player]
    let currentUserId: String?

    private var winningRole: Role? {
        guard let teamString = game.winningTeam else { return nil }
        return Role(rawValue: teamString)
    }

    private var currentPlayerInGame: Player? {
        guard let userId = currentUserId else { return nil }
        return players.first { $0.userId == userId }
    }

    /// "Victory" or "Defeat", or nil when the game had no winner or the
    /// user's result isn't known (their seat didn't load, say): the row then
    /// claims neither.
    private var result: (label: String, color: Color)? {
        guard let currentUserId else { return nil }
        switch game.outcome(forUserId: currentUserId, role: currentPlayerInGame?.role) {
        case .won: return ("Victory", Color.mtgSuccess)
        case .lost: return ("Defeat", Color.mtgError)
        case .noWinner, .unknown: return nil
        }
    }

    private var resultAccessibilityLabel: String {
        var parts = ["Game on \(game.createdAt.formatted(.dateTime))"]
        if let result {
            parts.append(result.label)
        }
        if let winningRole {
            parts.append("\(winningRole.displayName) team won")
        }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: date + result
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.createdAt, style: .date)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(Color.mtgTextPrimary)
                    Text(game.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(Color.mtgTextSecondary)
                }

                Spacer()

                // Win/Loss badge
                if result != nil || winningRole != nil {
                    VStack(alignment: .trailing, spacing: 2) {
                        if let result {
                            Text(result.label)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(result.color)
                        }

                        if let winRole = winningRole {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(winRole.color)
                                    .frame(width: 8, height: 8)
                                Text("\(winRole.displayName) Won")
                                    .font(.caption)
                                    .foregroundStyle(winRole.color)
                            }
                        }
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(resultAccessibilityLabel)

            // Player summary
            if !players.isEmpty {
                OrnateDivider()

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], alignment: .leading, spacing: 4) {
                    ForEach(players) { player in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(player.role?.color ?? .gray)
                                .frame(width: 6, height: 6)
                            Text(player.displayName)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(player.userId == currentUserId ? Color.mtgTextPrimary : Color.mtgTextSecondary)
                                .fontWeight(player.userId == currentUserId ? .semibold : .regular)
                            if player.isEliminated {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Color.mtgError)
                                    .font(.system(size: 8))
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(player.displayName), \(player.role?.displayName ?? "unknown")\(player.isEliminated ? ", eliminated" : "")")
                    }
                }
            }

            // Your role
            if let myPlayer = currentPlayerInGame,
               let role = myPlayer.role {
                HStack(spacing: 4) {
                    Text("Your role:")
                        .font(.caption2)
                        .foregroundStyle(Color.mtgTextSecondary)
                    Text(role.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(role.color)
                    if let cardId = myPlayer.identityCardId,
                       let card = CardDatabase.shared.card(withId: cardId) {
                        Text("(\(card.name))")
                            .font(.caption2)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                }
            }
        }
        .padding()
        .mtgCardFrame()
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        GameHistoryView()
    }
    .environmentObject(AuthViewModel())
}
#endif
