//
//  GameHistoryView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import SwiftUI

struct GameHistoryView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var games: [Game] = []
    @State private var gamePlayers: [String: [Player]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if isLoading {
                        Spacer(minLength: 100)
                        ProgressView("Loading game history...")
                            .tint(Color.mtgGold)
                            .foregroundStyle(Color.mtgTextSecondary)
                        Spacer()
                    } else if games.isEmpty {
                        Spacer(minLength: 80)
                        VStack(spacing: 12) {
                            Image(systemName: "clock.badge.questionmark")
                                .font(.largeTitle)
                                .foregroundStyle(Color.mtgTextSecondary)
                            Text("No games yet")
                                .font(.system(.headline, design: .serif))
                                .foregroundStyle(Color.mtgTextPrimary)
                            Text("Finished games will appear here.")
                                .font(.subheadline)
                                .foregroundStyle(Color.mtgTextSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    } else {
                        ForEach(games) { game in
                            GameHistoryRow(
                                game: game,
                                players: gamePlayers[game.id] ?? [],
                                currentUserId: authViewModel.currentUserId
                            )
                            .padding(.horizontal)
                        }
                    }

                    if let error = errorMessage {
                        MtgErrorBanner(message: error)
                            .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
        }
        .navigationTitle("Game History")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            await loadHistory()
        }
        .refreshable {
            await loadHistory()
        }
    }

    private func loadHistory() async {
        guard let userId = authViewModel.currentUserId else { return }
        isLoading = true
        errorMessage = nil

        do {
            games = try await firestoreManager.getFinishedGames(forUserId: userId)

            // Load players for each game
            for game in games {
                let players = try await firestoreManager.getPlayers(gameId: game.id)
                gamePlayers[game.id] = players
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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

    private var didWin: Bool {
        guard let myRole = currentPlayerInGame?.role,
              let winRole = winningRole else { return false }
        // Leader and Guardian share a win condition
        if winRole == .leader {
            return myRole == .leader || myRole == .guardian
        }
        return myRole == winRole
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
                if let winRole = winningRole {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(didWin ? "Victory" : "Defeat")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(didWin ? Color.mtgSuccess : Color.mtgError)

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
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Game on \(game.createdAt, format: .dateTime), \(didWin ? "Victory" : "Defeat"), \(winningRole?.displayName ?? "Unknown") team won")

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
