//
//  GameBoardViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Foundation
import SwiftUI

@MainActor
final class GameBoardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var game: Game?
    @Published var players: [Player] = []
    @Published var errorMessage: String?
    @Published var isGameUnavailable = false
    @Published var isPending = false
    @Published var pendingAbilityResolution: AbilityResolution?

    // Planechase transient state
    @Published var dieRollResult: String?
    @Published var isRollingDie = false
    @Published var tunnelOptions: [PlaneCard]?

    // MARK: - Optimistic Life Tracking

    private var lifeDeltas: [String: Int] = [:]
    private var debounceTimers: [String: Task<Void, Never>] = [:]
    private var serverPlayers: [Player] = []

    // MARK: - Properties

    let gameId: String
    var currentUserId: String?
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let cardDatabase: CardLookupProviding
    private let planeDatabase: PlaneLookupProviding
    private var gameListener: ListenerCancellable?
    private var playersListener: ListenerCancellable?
    private var hasReceivedFirstGameSnapshot = false

    // MARK: - Computed Properties

    var currentPlayer: Player? {
        guard let userId = currentUserId else { return nil }
        return players.first { $0.userId == userId }
    }

    var currentIdentityCard: IdentityCard? {
        guard let cardId = currentPlayer?.identityCardId else { return nil }
        return cardDatabase.card(withId: cardId)
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

    // MARK: - Game Mode Booleans

    var isPlanechaseActive: Bool {
        game?.gameMode.includesPlanechase ?? false
    }

    var isTreacheryActive: Bool {
        game?.gameMode.includesTreachery ?? false
    }

    var isOwnDeckMode: Bool {
        game?.planechase?.useOwnDeck ?? false
    }

    var isHost: Bool {
        guard let userId = currentUserId else { return false }
        return game?.hostId == userId
    }

    // MARK: - Planechase Computed Properties

    var currentPlane: PlaneCard? {
        guard let planeId = game?.planechase?.currentPlaneId else { return nil }
        return planeDatabase.plane(withId: planeId)
    }

    var secondaryPlane: PlaneCard? {
        guard let planeId = game?.planechase?.secondaryPlaneId else { return nil }
        return planeDatabase.plane(withId: planeId)
    }

    var isChaoticAetherActive: Bool {
        game?.planechase?.chaoticAetherActive ?? false
    }

    /// The mana cost for the next planar die roll.
    /// First roll each turn is free, each subsequent costs 1 more.
    var dieRollCost: Int {
        let count = game?.planechase?.dieRollCount ?? 0
        return max(0, count - 1)
    }

    var lastDieRollerName: String? {
        guard let rollerId = game?.planechase?.lastDieRollerId else { return nil }
        return players.first { $0.userId == rollerId }?.displayName
    }

    // MARK: - Init / Deinit

    init(
        gameId: String,
        currentUserId: String? = nil,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions(),
        cardDatabase: CardLookupProviding = CardDatabase.shared,
        planeDatabase: PlaneLookupProviding = PlaneDatabase.shared
    ) {
        self.gameId = gameId
        self.currentUserId = currentUserId
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.cardDatabase = cardDatabase
        self.planeDatabase = planeDatabase
        startListening()
    }

    #if DEBUG
    /// Preview-only initializer that populates with sample data and skips Firestore.
    init(
        gameId: String,
        previewPlayers: [Player],
        previewGame: Game?,
        currentUserId: String?,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions(),
        cardDatabase: CardLookupProviding = CardDatabase.shared,
        planeDatabase: PlaneLookupProviding = PlaneDatabase.shared
    ) {
        self.gameId = gameId
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.cardDatabase = cardDatabase
        self.planeDatabase = planeDatabase
        self.currentUserId = currentUserId
        self.serverPlayers = previewPlayers
        self.players = previewPlayers
        self.game = previewGame
        self.hasReceivedFirstGameSnapshot = true
    }
    #endif

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
            AnalyticsService.trackEvent("unveil_identity")
            checkForAbilityTrigger(player: player)
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
    }

    private func checkForAbilityTrigger(player: Player) {
        guard let cardId = player.identityCardId,
              let ability = ExecutableAbility(cardId: cardId) else { return }

        let resolution: AbilityResolution
        switch ability {
        case .metamorph:
            let eliminated = players.filter { $0.isEliminated && $0.role != .leader && $0.userId != player.userId }
            resolution = AbilityResolution(
                abilityType: .metamorph,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: eliminated
            )
        case .puppetMaster:
            let otherAlive = players.filter { !$0.isEliminated && $0.userId != player.userId }
            resolution = AbilityResolution(
                abilityType: .puppetMaster,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: otherAlive
            )
        case .wearerOfMasks:
            resolution = AbilityResolution(
                abilityType: .wearerOfMasks,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: []
            )
        }
        pendingAbilityResolution = resolution
    }

    // MARK: - Leave Game (via Cloud Function)

    func eliminateAndLeave() async {
        guard currentPlayer != nil else { return }
        guard !isPending else { return }
        errorMessage = nil
        isPending = true

        do {
            try await cloudFunctions.eliminatePlayer(gameId: gameId)
            AnalyticsService.trackEvent("forfeit_game")
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
    }

    // MARK: - Planechase Actions

    func rollDie() async {
        guard !isRollingDie else { return }
        errorMessage = nil
        isRollingDie = true
        dieRollResult = nil

        do {
            let result = try await cloudFunctions.rollPlanarDie(gameId: gameId)
            dieRollResult = result
            AnalyticsService.trackEvent("roll_planar_die", params: ["result": result])

            // Auto-clear the die result after a delay so the animation resets
            Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                dieRollResult = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isRollingDie = false
    }

    func resolvePhenomenon() async {
        guard !isPending else { return }
        errorMessage = nil
        isPending = true

        do {
            let result = try await cloudFunctions.resolvePhenomenon(gameId: gameId)
            if result.type == "choose", let options = result.options {
                // Interplanar Tunnel — show picker
                tunnelOptions = options.compactMap { dict in
                    guard let id = dict["id"] as? String else { return nil }
                    return planeDatabase.plane(withId: id)
                }
            }
            // For other types, Firestore listener will update the state
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
    }

    func selectTunnelPlane(_ plane: PlaneCard) async {
        guard !isPending else { return }
        errorMessage = nil
        isPending = true
        tunnelOptions = nil

        do {
            try await cloudFunctions.selectPlane(gameId: gameId, planeId: plane.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
    }

    func endGame(winnerUserIds: [String]? = nil) async {
        guard !isPending else { return }
        errorMessage = nil
        isPending = true

        do {
            try await cloudFunctions.endGame(gameId: gameId, winnerUserIds: winnerUserIds)
            AnalyticsService.trackEvent("end_game")
        } catch {
            errorMessage = error.localizedDescription
        }
        isPending = false
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

    // MARK: - Ability Resolution

    func resolveMetamorph(targetPlayerId: String) async {
        guard currentPlayer != nil else { return }
        errorMessage = nil

        do {
            try await cloudFunctions.resolveMetamorph(gameId: gameId, targetPlayerId: targetPlayerId)
            AnalyticsService.trackEvent("ability_metamorph", params: ["target": targetPlayerId])
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingAbilityResolution = nil
    }

    func resolvePuppetMaster(redistributions: [String: String]) async {
        errorMessage = nil

        // Filter out unchanged assignments
        let changes = redistributions.filter { playerId, newCardId in
            players.first(where: { $0.id == playerId })?.identityCardId != newCardId
        }

        guard !changes.isEmpty else {
            pendingAbilityResolution = nil
            return
        }

        do {
            try await cloudFunctions.resolvePuppetMaster(gameId: gameId, redistributions: changes)
            AnalyticsService.trackEvent("ability_puppet_master", params: ["swaps": changes.count])
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingAbilityResolution = nil
    }

    func resolveWearerOfMasks(chosenCardId: String?) async {
        guard currentPlayer != nil else {
            pendingAbilityResolution = nil
            return
        }
        errorMessage = nil

        do {
            try await cloudFunctions.resolveWearerOfMasks(gameId: gameId, chosenCardId: chosenCardId)
            if chosenCardId != nil {
                AnalyticsService.trackEvent("ability_wearer_of_masks", params: ["chosen_card": chosenCardId ?? ""])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        pendingAbilityResolution = nil
    }

    func dismissAbility() {
        pendingAbilityResolution = nil
    }

    /// Returns non-Leader cards not currently assigned to any player in this game.
    func cardsOutsideGame() -> [IdentityCard] {
        let usedIds = Set(players.compactMap(\.identityCardId))
        return cardDatabase.allCards.filter { card in
            card.role != .leader && !usedIds.contains(card.id)
        }
    }

    // MARK: - Helpers

    func identityCard(for player: Player) -> IdentityCard? {
        guard let cardId = player.identityCardId else { return nil }
        return cardDatabase.card(withId: cardId)
    }

    func identityCard(withId cardId: String) -> IdentityCard? {
        cardDatabase.card(withId: cardId)
    }

    func canSeeRole(of player: Player) -> Bool {
        // You can always see your own role
        if player.userId == currentUserId { return true }
        // Leaders are always face-up (visible to everyone)
        if player.role == .leader { return true }
        // Unveiled but face-down cards are hidden (Puppet Master / Metamorph swap)
        if player.isUnveiled && !player.isFaceDown { return true }
        // Puppet Master can peek at all face-down cards
        if let myCardId = currentPlayer?.identityCardId,
           myCardId == ExecutableAbility.puppetMaster.rawValue,
           currentPlayer?.isUnveiled == true {
            return true
        }
        return false
    }
}
