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
        guard isHost, let game = game else { return }
        errorMessage = nil
        isStartingGame = true
        do {
            // 1. Get role distribution for player count
            let dist = Role.distribution(forPlayerCount: players.count)

            // 2. Build shuffled role array
            var roles: [Role] = []
            roles += Array(repeating: .leader, count: dist.leaders)
            roles += Array(repeating: .guardian, count: dist.guardians)
            roles += Array(repeating: .assassin, count: dist.assassins)
            roles += Array(repeating: .traitor, count: dist.traitors)
            roles.shuffle()

            // 3. Assign roles and identity cards to each player
            var usedCardIds: Set<String> = []

            for (index, var player) in players.enumerated() {
                let role = roles[index]
                player.role = role

                // Pick a random card for this role (avoid duplicates)
                let availableCards = CardDatabase.shared.cards(forRole: role)
                    .filter { !usedCardIds.contains($0.id) }
                guard let card = availableCards.randomElement() else {
                    throw GameError.cardAssignmentFailed
                }

                player.identityCardId = card.id
                usedCardIds.insert(card.id)

                // Apply card's life modifier if present
                if let lifeModifier = card.lifeModifier {
                    player.lifeTotal = game.startingLife + lifeModifier
                }

                try await firestoreManager.updatePlayer(player, inGame: gameId)
            }

            // 4. Transition game state last (so listeners fire after players have roles)
            var updatedGame = game
            updatedGame.state = .inProgress
            try await firestoreManager.updateGame(updatedGame)
        } catch {
            errorMessage = error.localizedDescription
        }
        isStartingGame = false
    }

    func leaveGame(userId: String) async {
        errorMessage = nil
        do {
            guard let player = players.first(where: { $0.userId == userId }) else { return }
            try await firestoreManager.removePlayer(id: player.id, fromGame: gameId)

            // If host leaves, delete the game
            if isHost {
                try await firestoreManager.deleteGame(id: gameId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
