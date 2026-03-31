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
    @Published var isCreating = false
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    var maxPlayers: Int {
        gameMode.includesTreachery ? 8 : 12
    }

    // MARK: - Properties

    private let firestoreManager: FirestoreManaging

    // MARK: - Init

    init(firestoreManager: FirestoreManaging = FirestoreManager()) {
        self.firestoreManager = firestoreManager
    }

    // MARK: - Game Creation

    /// Creates a new game and returns the navigation destination on success, or nil on failure.
    func createGame(userId: String) async -> AppDestination? {
        isCreating = true
        errorMessage = nil

        do {
            let code = try await generateUniqueCode()
            let game = Game(
                id: UUID().uuidString,
                code: code,
                hostId: userId,
                state: .waiting,
                gameMode: gameMode,
                maxPlayers: maxPlayers,
                startingLife: startingLife,
                winningTeam: nil,
                playerIds: [userId],
                createdAt: Date(),
                lastActivityAt: Date(),
                planechase: gameMode.includesPlanechase ? PlanechaseState(
                    useOwnDeck: useOwnDeck,
                    currentPlaneId: nil,
                    usedPlaneIds: [],
                    lastDieRollerId: nil,
                    dieRollCount: 0
                ) : nil
            )
            try await firestoreManager.createGame(game)

            let user = try await firestoreManager.getUser(id: userId)
            let player = Player(
                id: UUID().uuidString,
                orderId: 0,
                userId: userId,
                displayName: user?.displayName ?? "Host",
                role: nil,
                identityCardId: nil,
                lifeTotal: startingLife,
                isEliminated: false,
                isUnveiled: false,
                joinedAt: Date()
            )
            try await firestoreManager.addPlayer(player, toGame: game.id)

            AnalyticsService.trackEvent("create_game", params: [
                "game_mode": gameMode.rawValue
            ])

            isCreating = false
            return .lobby(gameId: game.id, isHost: true)
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

    private func generateUniqueCode() async throws -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        for _ in 0..<10 {
            let code = String((0..<4).map { _ in characters.randomElement()! })
            let existing = try await firestoreManager.getGame(byCode: code)
            if existing == nil {
                return code
            }
        }
        throw GameError.codeGenerationFailed
    }
}
