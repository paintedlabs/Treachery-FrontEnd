//
//  JoinGameViewModel.swift
//  Treachery-iOS
//

import Foundation

@MainActor
final class JoinGameViewModel: ObservableObject {

    // MARK: - Published State

    @Published var gameCode = ""
    @Published var isJoining = false
    @Published var errorMessage: String?

    // MARK: - Properties

    private let cloudFunctions: CloudFunctionsProtocol

    // MARK: - Init

    init(cloudFunctions: CloudFunctionsProtocol = CloudFunctions()) {
        self.cloudFunctions = cloudFunctions
    }

    // MARK: - Game Code Formatting

    func formatGameCode(_ newValue: String) {
        gameCode = String(newValue.uppercased().prefix(4))
    }

    // MARK: - Join Game

    /// Joins a game and returns the navigation destination on success, or nil on failure.
    func joinGame() async -> AppDestination? {
        isJoining = true
        errorMessage = nil

        do {
            let result = try await cloudFunctions.joinGame(gameCode: gameCode)
            AnalyticsService.trackEvent("join_game")
            isJoining = false
            return .lobby(gameId: result.gameId, isHost: false)
        } catch {
            errorMessage = error.localizedDescription
            isJoining = false
            return nil
        }
    }
}
