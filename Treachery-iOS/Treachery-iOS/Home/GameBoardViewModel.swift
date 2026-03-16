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
    @Published var isPending = false

    // MARK: - Optimistic Life Tracking

    private var lifeDeltas: [String: Int] = [:]
    private var debounceTimers: [String: Task<Void, Never>] = [:]
    private var serverPlayers: [Player] = []

    // MARK: - Properties

    let gameId: String
    var currentUserId: String?
    private let firestoreManager = FirestoreManager()
    private let cloudFunctions = CloudFunctions()
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
        for timer in debounceTimers.values {
            timer.cancel()
        }
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
                guard let self else { return }
                self.serverPlayers = players
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.applyOptimisticDeltas()
                }
            }
        }
    }

    // MARK: - Optimistic Helpers

    private func applyOptimisticDeltas() {
        players = serverPlayers.map { player in
            guard let delta = lifeDeltas[player.id], delta != 0 else { return player }
            var p = player
            p.lifeTotal = max(0, p.lifeTotal + delta)
            return p
        }
    }

    // MARK: - Life Adjustment (optimistic + debounced)

    func adjustLife(for playerId: String, by amount: Int) {
        guard let player = serverPlayers.first(where: { $0.id == playerId }) else { return }
        guard !player.isEliminated else { return }
        errorMessage = nil

        // Accumulate optimistic delta
        lifeDeltas[playerId, default: 0] += amount
        applyOptimisticDeltas()

        // Cancel existing debounce timer for this player
        debounceTimers[playerId]?.cancel()

        // Flush after 500ms of inactivity
        debounceTimers[playerId] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushLifeDelta(for: playerId)
        }
    }

    private func flushLifeDelta(for playerId: String) async {
        guard let delta = lifeDeltas[playerId], delta != 0 else { return }

        // Clear delta before sending so new taps start fresh
        lifeDeltas[playerId] = 0

        do {
            try await cloudFunctions.adjustLife(gameId: gameId, playerId: playerId, amount: delta)
        } catch {
            // Revert on failure
            lifeDeltas[playerId, default: 0] += delta
            applyOptimisticDeltas()
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Unveil (via Cloud Function)

    func unveilCurrentPlayer() async {
        guard let player = currentPlayer else { return }
        guard !player.isUnveiled else { return }
        guard !isPending else { return }
        errorMessage = nil
        isPending = true

        do {
            try await cloudFunctions.unveilPlayer(gameId: gameId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
    }

    // MARK: - Leave Game (via Cloud Function)

    func eliminateAndLeave() async {
        guard currentPlayer != nil else { return }
        guard !isPending else { return }
        errorMessage = nil
        isPending = true

        do {
            try await cloudFunctions.eliminatePlayer(gameId: gameId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
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
