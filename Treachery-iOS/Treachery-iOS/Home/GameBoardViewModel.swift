//
//  GameBoardViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Foundation
import SwiftUI
import FirebaseFirestore

@MainActor
final class GameBoardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var game: Game?
    @Published var players: [Player] = []
    @Published var errorMessage: String?
    @Published var isGameUnavailable = false

    // MARK: - Properties

    let gameId: String
    var currentUserId: String?
    private let firestoreManager = FirestoreManager()
    private var gameListener: ListenerRegistration?
    private var playersListener: ListenerRegistration?
    private var hasReceivedFirstGameSnapshot = false

    // MARK: - Computed Properties

    var currentPlayer: Player? {
        guard let userId = currentUserId else { return nil }
        return players.first { $0.userId == userId }
    }

    var currentIdentityCard: IdentityCard? {
        guard let cardId = currentPlayer?.identityCardId else { return nil }
        return CardDatabase.shared.card(withId: cardId)
    }

    var isGameFinished: Bool {
        game?.state == .finished
    }

    var winningTeam: Role? {
        guard let teamString = game?.winningTeam else { return nil }
        return Role(rawValue: teamString)
    }

    var alivePlayers: [Player] {
        players.filter { !$0.isEliminated }
    }

    // MARK: - Init / Deinit

    init(gameId: String) {
        self.gameId = gameId
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
                if game == nil && self.hasReceivedFirstGameSnapshot {
                    // Game was deleted mid-game
                    self.isGameUnavailable = true
                }
                self.game = game
                self.hasReceivedFirstGameSnapshot = true
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

    // MARK: - Life Adjustment

    func adjustLife(for playerId: String, by amount: Int) async {
        guard var player = players.first(where: { $0.id == playerId }) else { return }
        guard !player.isEliminated else { return }
        errorMessage = nil

        player.lifeTotal += amount

        // Check for elimination
        if player.lifeTotal <= 0 {
            player.lifeTotal = 0
            player.isEliminated = true
        }

        do {
            try await firestoreManager.updatePlayer(player, inGame: gameId)

            // After elimination, check win conditions
            if player.isEliminated {
                await checkWinConditions()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Unveil

    func unveilCurrentPlayer() async {
        guard var player = currentPlayer else { return }
        guard !player.isUnveiled else { return }
        errorMessage = nil

        player.isUnveiled = true

        do {
            try await firestoreManager.updatePlayer(player, inGame: gameId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Win Condition Checking

    func checkWinConditions() async {
        let alive = alivePlayers

        // Traitor wins: last player standing and is a traitor
        if alive.count == 1, alive.first?.role == .traitor {
            await endGame(winningTeam: .traitor)
            return
        }

        let leaderAlive = alive.contains { $0.role == .leader }
        let assassinAlive = alive.contains { $0.role == .assassin }
        let traitorAlive = alive.contains { $0.role == .traitor }

        // Assassin wins: Leader is eliminated AND at least 1 assassin survives
        if !leaderAlive && assassinAlive {
            await endGame(winningTeam: .assassin)
            return
        }

        // Leader/Guardian wins: Leader alive + all assassins AND all traitors eliminated
        if leaderAlive && !assassinAlive && !traitorAlive {
            await endGame(winningTeam: .leader)
            return
        }

        // Edge: Leader dead + no assassins alive + no traitors alive
        // Assassins get credit (their mission to kill the leader succeeded)
        if !leaderAlive && !assassinAlive && !traitorAlive {
            await endGame(winningTeam: .assassin)
            return
        }
    }

    // MARK: - End Game

    private func endGame(winningTeam: Role) async {
        guard var game = game else { return }
        game.state = .finished
        game.winningTeam = winningTeam.rawValue

        do {
            try await firestoreManager.updateGame(game)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Leave Game

    func eliminateAndLeave() async {
        guard var player = currentPlayer else { return }
        errorMessage = nil

        // Mark player as eliminated before leaving
        player.isEliminated = true
        player.lifeTotal = 0

        do {
            try await firestoreManager.updatePlayer(player, inGame: gameId)
            await checkWinConditions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    func identityCard(for player: Player) -> IdentityCard? {
        guard let cardId = player.identityCardId else { return nil }
        return CardDatabase.shared.card(withId: cardId)
    }

    func canSeeRole(of player: Player) -> Bool {
        // You can always see your own role
        if player.userId == currentUserId { return true }
        // You can see unveiled players' roles
        if player.isUnveiled { return true }
        // Leaders are always face-up (visible to everyone)
        if player.role == .leader { return true }
        return false
    }
}
