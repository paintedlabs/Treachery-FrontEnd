//
//  GameHistoryViewModel.swift
//  Treachery-iOS
//

import Foundation
import os

/// The user's finished games, newest first, with each game's players.
struct GameHistory: Equatable {
    let games: [Game]
    /// Each game's players by game id. A game whose players didn't load is
    /// absent, and its row shows no players.
    let playersByGame: [String: [Player]]
}

@MainActor
final class GameHistoryViewModel: ObservableObject {

    // MARK: - Published State

    @Published private(set) var history: Loadable<GameHistory, UserFacingError> = .idle

    // MARK: - Properties

    private let firestoreManager: FirestoreManaging

    private static let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Profile")

    // MARK: - Init

    init(firestoreManager: FirestoreManaging = FirestoreManager()) {
        self.firestoreManager = firestoreManager
    }

    // MARK: - Data Loading

    /// Loads the user's finished games and their players. What's already
    /// shown stays while this runs and if it fails.
    func loadHistory(userId: String) async {
        history.startLoading()

        do {
            let games = try await firestoreManager.getFinishedGames(forUserId: userId)
            let playersByGame = await firestoreManager.playersByGame(for: games)
            history = .loaded(GameHistory(games: games, playersByGame: playersByGame))
        } catch {
            Self.logger.error("Loading game history failed: \(String(describing: error), privacy: .private)")
            history.fail(with: UserFacingError(error))
        }
    }
}
