//
//  JoinGameViewModel.swift
//  Treachery-iOS
//

import Foundation
import os

private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "JoinGame")

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
            logger.error("joinGame failed: \(String(describing: error), privacy: .public)")
            errorMessage = Self.message(for: error)
            isJoining = false
            return nil
        }
    }

    /// A plain sentence for a failed join: the server's own reason when it
    /// turned the join down ("Game not found. Check the code and try again.",
    /// "This game is full."), otherwise what to try next.
    private static func message(for error: any Error) -> String {
        switch error {
        case let refusal as CallableRefusal:
            return refusal.message
        case is JoinGameResult.MissingGameIdError:
            return "Couldn't join the game. Please try again."
        default:
            return "Couldn't join the game. Check your connection and try again."
        }
    }
}
