//
//  LobbyViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import Foundation
import SwiftUI

@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var game: Game?
    @Published var players: [Player] = []
    @Published var errorMessage: String?
    @Published var isStartingGame = false
    @Published var isGameDisbanded = false

    let gameId: String
    let isHost: Bool
    var currentUserId: String?
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private var gameListener: ListenerCancellable?
    private var playersListener: ListenerCancellable?
    private var hasReceivedFirstSnapshot = false

    var currentPlayer: Player? {
        guard let userId = currentUserId else { return nil }
        return players.first { $0.userId == userId }
    }

    var canStartGame: Bool {
        guard let game = game else { return false }
        let minPlayers = game.gameMode.includesTreachery ? Role.minimumPlayerCount : 1
        return isHost && players.count >= minPlayers
    }

    var minimumPlayerCount: Int {
        guard let game = game else { return Role.minimumPlayerCount }
        return game.gameMode.includesTreachery ? Role.minimumPlayerCount : 1
    }

    var isGameStarted: Bool {
        game?.state == .inProgress
    }

    init(
        gameId: String,
        isHost: Bool,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions()
    ) {
        self.gameId = gameId
        self.isHost = isHost
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        startListening()
    }

    deinit {
        gameListener?.remove()
        playersListener?.remove()
    }

    // MARK: - Listeners

    private func startListening() {
        gameListener = firestoreManager.listenToGame(id: gameId) { [weak self] game in
            Task { @MainActor in
                guard let self else { return }
                if game == nil && self.hasReceivedFirstSnapshot {
                    // Game was deleted (host left)
                    self.isGameDisbanded = true
                }
                self.game = game
                self.hasReceivedFirstSnapshot = true
            }
        }
        playersListener = firestoreManager.listenToPlayers(gameId: gameId) { [weak self] players in
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.3)) {
                    self?.players = players
                }
            }
        }
    }

    private func stopListening() {
        gameListener?.remove()
        playersListener?.remove()
    }

    // MARK: - Actions

    func startGame() async {
        guard isHost else { return }
        errorMessage = nil
        isStartingGame = true
        do {
            try await cloudFunctions.startGame(gameId: gameId)
            AnalyticsService.trackEvent("start_game", params: [
                "player_count": players.count,
                "game_mode": game?.gameMode.rawValue ?? "unknown"
            ])
        } catch {
            errorMessage = error.localizedDescription
        }
        isStartingGame = false
    }

    func leaveGame(userId: String) async {
        errorMessage = nil
        // Stop listeners before leaving to prevent race conditions
        // where the snapshot update re-renders the view mid-navigation
        stopListening()
        do {
            try await cloudFunctions.leaveGame(gameId: gameId)
            AnalyticsService.trackEvent("leave_lobby")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Player Customization

    func updatePlayerColor(_ hex: String?) async {
        guard let player = currentPlayer else { return }
        do {
            try await firestoreManager.updatePlayerColor(gameId: gameId, playerId: player.id, color: hex)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateCommanderName(_ name: String?) async {
        guard let player = currentPlayer else { return }
        do {
            try await firestoreManager.updateCommanderName(gameId: gameId, playerId: player.id, name: name)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
