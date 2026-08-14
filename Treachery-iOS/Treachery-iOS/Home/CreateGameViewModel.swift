//
//  CreateGameViewModel.swift
//  Treachery-iOS
//

import Foundation

@MainActor
final class CreateGameViewModel: ObservableObject {

    // MARK: - Published State

    @Published var gameMode: GameMode = .treachery
    @Published var useOwnDeck = false
    @Published var startingLife = 40
    /// "special" (all traitors) is the server default, matching web.
    @Published var maxTraitorRarity: Rarity = .special
    @Published var isCreating = false
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    var maxPlayers: Int {
        // Server caps at 8 for every mode (createGame callable).
        8
    }

    // MARK: - Properties

    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol

    // MARK: - Init

    init(
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions()
    ) {
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
    }

    // MARK: - Game Creation

    /// Creates a new game and returns the navigation destination on success, or nil on failure.
    func createGame(userId: String) async -> AppDestination? {
        isCreating = true
        errorMessage = nil

        do {
            let user = try await firestoreManager.getUser(id: userId)
            let gameId = try await cloudFunctions.createGame(
                gameMode: gameMode.rawValue,
                maxPlayers: maxPlayers,
                startingLife: startingLife,
                maxTraitorRarity: gameMode.includesTreachery ? maxTraitorRarity.rawValue : nil,
                useOwnDeck: useOwnDeck,
                displayName: user?.displayName
            )

            AnalyticsService.trackEvent("create_game", params: [
                "game_mode": gameMode.rawValue
            ])

            isCreating = false
            return .lobby(gameId: gameId, isHost: true)
        } catch {
            errorMessage = error.localizedDescription
            isCreating = false
            return nil
        }
    }

    // MARK: - Helpers

    func resetOwnDeckIfNeeded() {
        if !gameMode.includesPlanechase {
            useOwnDeck = false
        }
    }
}
