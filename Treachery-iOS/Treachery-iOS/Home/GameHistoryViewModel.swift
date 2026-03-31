//
//  GameHistoryViewModel.swift
//  Treachery-iOS
//

import Foundation

@MainActor
final class GameHistoryViewModel: ObservableObject {

    // MARK: - Published State

    @Published var games: [Game] = []
    @Published var gamePlayers: [String: [Player]] = [:]
    @Published var isLoading = true
    @Published var errorMessage: String?

    // MARK: - Properties

    private let firestoreManager: FirestoreManaging

    // MARK: - Init

    init(firestoreManager: FirestoreManaging = FirestoreManager()) {
        self.firestoreManager = firestoreManager
    }

    // MARK: - Data Loading

    func loadHistory(userId: String) async {
        isLoading = true
        errorMessage = nil

        do {
            games = try await firestoreManager.getFinishedGames(forUserId: userId)

            await withTaskGroup(of: (String, [Player])?.self) { group in
                for game in games {
                    group.addTask { [firestoreManager] in
                        guard let players = try? await firestoreManager.getPlayers(gameId: game.id) else {
                            return nil
                        }
                        return (game.id, players)
                    }
                }
                for await result in group {
                    if let (gameId, players) = result {
                        gamePlayers[gameId] = players
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
