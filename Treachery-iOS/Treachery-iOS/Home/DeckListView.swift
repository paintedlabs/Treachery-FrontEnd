//
//  DeckListView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/18/26.
//

import SwiftUI

struct DeckListView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var decks: [Deck] = []
    @State private var deckStats: [String: DeckStatLine] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let firestoreManager = FirestoreManager()

    var body: some View {
        ZStack {
            Color.mtgBackground.ignoresSafeArea()

            if isLoading {
                ProgressView("Loading decks...")
                    .tint(Color.mtgGold)
                    .foregroundStyle(Color.mtgTextSecondary)
            } else if decks.isEmpty {
                emptyState
            } else {
                deckList
            }
        }
        .navigationTitle("My Decks")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    AddEditDeckView(onSave: { _ in
                        Task { await loadData() }
                    })
                } label: {
                    Image(systemName: "plus")
                        .foregroundStyle(Color.mtgGold)
                }
                .accessibilityLabel("Add new deck")
            }
        }
        .task {
            await loadData()
        }
    }

    // MARK: - Subviews

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 48))
                .foregroundStyle(Color.mtgGold.opacity(0.5))

            Text("No Decks Yet")
                .font(.system(.title2, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgTextPrimary)

            Text("Add your first deck to track your commanders and game stats.")
                .font(.subheadline)
                .foregroundStyle(Color.mtgTextSecondary)
                .multilineTextAlignment(.center)

            NavigationLink {
                AddEditDeckView(onSave: { _ in
                    Task { await loadData() }
                })
            } label: {
                Text("Add Deck")
            }
            .buttonStyle(MtgPrimaryButtonStyle())
            .padding(.horizontal, 40)
            .padding(.top, 8)
        }
        .padding()
    }

    private var deckList: some View {
        ScrollView {
            VStack(spacing: 12) {
                if let error = errorMessage {
                    MtgErrorBanner(message: error)
                        .padding(.horizontal)
                }

                ForEach(decks) { deck in
                    NavigationLink {
                        AddEditDeckView(deck: deck, onSave: { _ in
                            Task { await loadData() }
                        })
                    } label: {
                        DeckRow(deck: deck, stats: deckStats[deck.id])
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await deleteDeck(deck) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Data

    private func loadData() async {
        guard let userId = authViewModel.currentUserId else { return }
        isLoading = true
        errorMessage = nil

        do {
            decks = try await firestoreManager.getDecks(forUserId: userId)

            // Compute stats from game history
            let games = try await firestoreManager.getFinishedGames(forUserId: userId)
            var stats: [String: DeckStatLine] = [:]

            for game in games {
                if let players = try? await firestoreManager.getPlayers(gameId: game.id),
                   let myPlayer = players.first(where: { $0.userId == userId }),
                   let deckId = myPlayer.deckId {

                    var stat = stats[deckId] ?? DeckStatLine()
                    stat.gamesPlayed += 1

                    if let winTeamString = game.winningTeam,
                       let winRole = Role(rawValue: winTeamString),
                       let myRole = myPlayer.role {
                        let didWin: Bool
                        if winRole == .leader {
                            didWin = myRole == .leader || myRole == .guardian
                        } else {
                            didWin = myRole == winRole
                        }
                        if didWin {
                            stat.wins += 1
                        } else {
                            stat.losses += 1
                        }
                    }

                    stats[deckId] = stat
                }
            }
            deckStats = stats
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func deleteDeck(_ deck: Deck) async {
        do {
            try await firestoreManager.deleteDeck(id: deck.id, userId: deck.userId)
            decks.removeAll { $0.id == deck.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Deck Row

private struct DeckRow: View {
    let deck: Deck
    let stats: DeckStatLine?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deck.name)
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(Color.mtgTextPrimary)

                    Text(deck.commanderDisplayName)
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgGold)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.mtgTextSecondary)
            }

            HStack {
                if !deck.colorIdentity.isEmpty {
                    ColorIdentityPips(colors: deck.colorIdentity)
                }

                Spacer()

                if let stats = stats {
                    HStack(spacing: 12) {
                        StatPill(label: "G", value: "\(stats.gamesPlayed)", color: .mtgTextPrimary)
                        StatPill(label: "W", value: "\(stats.wins)", color: .mtgSuccess)
                        StatPill(label: "L", value: "\(stats.losses)", color: .mtgError)
                        if stats.gamesPlayed > 0 {
                            StatPill(label: "%", value: "\(stats.winPercent)", color: .mtgGuardian)
                        }
                    }
                }
            }
        }
        .padding(16)
        .mtgCardFrame()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.name), commander \(deck.commanderDisplayName)")
    }
}

// MARK: - Stat Pill

private struct StatPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.mtgTextSecondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Deck Stat

struct DeckStatLine {
    var gamesPlayed: Int = 0
    var wins: Int = 0
    var losses: Int = 0

    var winPercent: Int {
        guard gamesPlayed > 0 else { return 0 }
        return Int(Double(wins) / Double(gamesPlayed) * 100)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        DeckListView()
    }
    .environmentObject(AuthViewModel())
}
#endif
