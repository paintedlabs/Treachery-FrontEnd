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
        List {
            if isLoading {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading game history...")
                        Spacer()
                    }
                }
            } else if games.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No games yet")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Text("Finished games will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                ForEach(games) { game in
                    Section {
                        GameHistoryRow(
                            game: game,
                            players: gamePlayers[game.id] ?? [],
                            currentUserId: authViewModel.currentUserId
                        )
                    }
                }
            }

            if let error = errorMessage {
                Section {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Game History")
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
                    Text(game.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Win/Loss badge
                if let winRole = winningRole {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(didWin ? "Victory" : "Defeat")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(didWin ? .green : .red)

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
                Divider()

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
                                .foregroundStyle(player.userId == currentUserId ? .primary : .secondary)
                                .fontWeight(player.userId == currentUserId ? .semibold : .regular)
                            if player.isEliminated {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.red)
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
                        .foregroundStyle(.secondary)
                    Text(role.displayName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(role.color)
                    if let cardId = myPlayer.identityCardId,
                       let card = CardDatabase.shared.card(withId: cardId) {
                        Text("(\(card.name))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
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
