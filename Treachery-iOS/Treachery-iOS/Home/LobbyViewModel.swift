//
//  LobbyViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import Foundation
import SwiftUI
import FirebaseFirestore

@MainActor
final class LobbyViewModel: ObservableObject {
    @Published var game: Game?
    @Published var players: [Player] = []
    @Published var errorMessage: String?
    @Published var isStartingGame = false
    @Published var isGameDisbanded = false

    let gameId: String
    let isHost: Bool
    private let firestoreManager = FirestoreManager()
    private let cloudFunctions = CloudFunctions()
    private var gameListener: ListenerRegistration?
    private var playersListener: ListenerRegistration?
    private var hasReceivedFirstSnapshot = false

    var canStartGame: Bool {
        guard let game = game else { return false }
        return isHost && players.count >= Role.minimumPlayerCount && players.count <= game.maxPlayers
    }

    var isGameStarted: Bool {
        game?.state == .inProgress
    }

    init(gameId: String, isHost: Bool) {
        self.gameId = gameId
        self.isHost = isHost
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
