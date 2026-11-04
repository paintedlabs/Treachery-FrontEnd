//
//  GameBoardViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/14/26.
//

import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "GameBoard")

@MainActor
final class GameBoardViewModel: ObservableObject {

    // MARK: - Published State

    @Published var game: Game?
    @Published var players: [Player] = []
    @Published var errorMessage: String?
    @Published var isPending = false
    @Published var pendingAbilityResolution: AbilityResolution?

    // Planechase transient state
    @Published var dieRollResult: String?
    @Published var isRollingDie = false
    @Published var tunnelOptions: [PlaneCard]?

    // MARK: - Optimistic Life Tracking

    /// This device's life changes the server hasn't confirmed yet. `players`
    /// is `serverPlayers` with these laid over it.
    private var lifeLedger = LifeLedger()
    /// Per player: the debounce running since their latest tap. Visible to
    /// tests, which await it rather than sleep.
    private(set) var lifeChangeDebounces: [String: Task<Void, Never>] = [:]
    /// Per player: the adjustLife call under way. Visible to tests, which
    /// await it rather than sleep.
    private(set) var lifeChangeSends: [String: Task<Void, Never>] = [:]
    private var serverPlayers: [Player] = []
    /// Times the debounce.
    private let clock: any Clock<Duration>

    // MARK: - Properties

    let gameId: String
    var currentUserId: String?
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private let cardDatabase: CardLookupProviding
    private let planeDatabase: PlaneLookupProviding
    private var gameListener: ListenerCancellable?
    private var playersListener: ListenerCancellable?
    /// A listener outcome that leaves nothing to show; see `status`.
    @Published private var interruption: ListenerInterruption?

    // MARK: - Computed Properties

    var currentPlayer: Player? {
        guard let userId = currentUserId else { return nil }
        return players.first { $0.userId == userId }
    }

    /// Unveiled traitor ability that has not been resolved yet.
    /// Decline/Skip leaves `ability_resolved` unset on the server, so this
    /// stays non-nil and the Action Bar can reopen the sheet.
    var resolvableAbility: ExecutableAbility? {
        guard let player = currentPlayer,
              player.isUnveiled,
              !player.isEliminated,
              !player.abilityResolved,
              let cardId = player.identityCardId else { return nil }
        return ExecutableAbility(cardId: cardId)
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
        planeDatabase: PlaneLookupProviding = PlaneDatabase.shared,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.gameId = gameId
        self.currentUserId = currentUserId
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.cardDatabase = cardDatabase
        self.planeDatabase = planeDatabase
        self.clock = clock
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
        planeDatabase: PlaneLookupProviding = PlaneDatabase.shared,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.gameId = gameId
        self.firestoreManager = firestoreManager
        self.cloudFunctions = cloudFunctions
        self.cardDatabase = cardDatabase
        self.planeDatabase = planeDatabase
        self.clock = clock
        self.currentUserId = currentUserId
        self.serverPlayers = previewPlayers
        self.players = previewPlayers
        self.game = previewGame
    }
    #endif

    deinit {
        gameListener?.remove()
        playersListener?.remove()
        // Sends under way don't hold the view model and are left to finish.
        for debounce in lifeChangeDebounces.values {
            debounce.cancel()
        }
    }

    // MARK: - Listeners

    private func startListening() {
        gameListener = firestoreManager.listenToGame(id: gameId) { [weak self] event in
            self?.receiveGame(event)
        }
        playersListener = firestoreManager.listenToPlayers(gameId: gameId) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let players):
                self.receivePlayers(players)
            case .failure(let failure):
                self.recordListenerFailure(failure, listener: "players")
            }
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

    func presentAbilityResolver() {
        guard let player = currentPlayer, resolvableAbility != nil else { return }
        pendingAbilityResolution = makeAbilityResolution(for: player)
    }

    private func checkForAbilityTrigger(player: Player) {
        guard !player.abilityResolved else { return }
        guard ExecutableAbility(cardId: player.identityCardId ?? "") != nil else { return }
        pendingAbilityResolution = makeAbilityResolution(for: player)
    }

    private func makeAbilityResolution(for player: Player) -> AbilityResolution? {
        guard let cardId = player.identityCardId,
              let ability = ExecutableAbility(cardId: cardId) else { return nil }

        switch ability {
        case .metamorph:
            let eliminated = players.filter { $0.isEliminated && $0.role != .leader && $0.userId != player.userId }
            return AbilityResolution(
                abilityType: .metamorph,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: eliminated
            )
        case .puppetMaster:
            let otherAlive = players.filter { !$0.isEliminated && $0.userId != player.userId }
            return AbilityResolution(
                abilityType: .puppetMaster,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: otherAlive
            )
        case .wearerOfMasks:
            return AbilityResolution(
                abilityType: .wearerOfMasks,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: []
            )
        }
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

    /// Callable-backed traitors the server refuses to hand out as a copy —
    /// mirrors BLOCKED_COPY_IDS in resolveWearerOfMasks (functions/index.js).
    private static let blockedCopyCardIds = Set(ExecutableAbility.allCases.map(\.rawValue))

    /// Returns non-Leader cards not currently assigned to any player in this game.
    func cardsOutsideGame() -> [IdentityCard] {
        let usedIds = Set(players.compactMap(\.identityCardId))
        return cardDatabase.allCards.filter { card in
            card.role != .leader
                && !usedIds.contains(card.id)
                && !Self.blockedCopyCardIds.contains(card.id)
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

// MARK: - Life Tracking (optimistic + debounced)
//
// A tap shows at once and goes to the server in a batch with the taps that
// follow it. LifeLedger decides what the board shows until the server
// confirms a batch; this extension feeds it taps, snapshots and call
// outcomes, and times and makes the calls.

extension GameBoardViewModel {

    /// How long a player's taps must pause before they're sent as one call.
    static let lifeChangeDebounce: Duration = .milliseconds(500)

    /// Shows the tap at once, then sends it with any taps on the same player
    /// that follow within `lifeChangeDebounce`, as one adjustLife call.
    func adjustLife(for playerId: String, by amount: Int) {
        guard let player = serverPlayers.first(where: { $0.id == playerId }) else { return }
        guard !player.isEliminated else { return }
        errorMessage = nil

        lifeLedger.record(amount, for: playerId)
        refreshPlayers()
        restartLifeChangeDebounce(for: playerId)
    }

    /// Sends every tap still waiting out its debounce, straight away. The
    /// board calls this as it goes away: the debounce ends with the view
    /// model, and would take those taps with it.
    ///
    /// These sends aren't tracked, since nothing will show them. Nor do they
    /// wait for a call still under way for the same player: adjustLife adds
    /// whatever it's given, so two calls at once still add up.
    ///
    /// - Returns: The sends, for tests to await.
    @discardableResult
    func sendPendingLifeChanges() -> [Task<Void, Never>] {
        for debounce in lifeChangeDebounces.values {
            debounce.cancel()
        }
        lifeChangeDebounces.removeAll()
        let pendingTaps = lifeLedger.takePendingTaps()
        refreshPlayers()

        let cloudFunctions = cloudFunctions
        let gameId = gameId
        return pendingTaps.map { playerId, amount in
            // Holds what the call needs, not the view model, which is
            // usually gone before the call returns.
            Task { [weak self] in
                do {
                    _ = try await cloudFunctions.adjustLife(gameId: gameId, playerId: playerId, amount: amount)
                } catch {
                    self?.reportLifeChangeFailure(for: playerId, error: error)
                }
            }
        }
    }

    /// A players snapshot: settles the batches it shows, redraws the board,
    /// and sends any taps that were waiting on a batch it settled.
    private func receivePlayers(_ players: [Player]) {
        serverPlayers = players
        lifeLedger.reconcile(with: players)
        withAnimation(.easeInOut(duration: 0.3)) {
            refreshPlayers()
        }
        for playerId in lifeLedger.playersWithPendingTaps {
            sendPendingLifeChange(for: playerId)
        }
    }

    /// Rebuilds `players`: the latest snapshot with the ledger laid over it.
    private func refreshPlayers() {
        players = lifeLedger.displayedPlayers(from: serverPlayers)
    }

    private func restartLifeChangeDebounce(for playerId: String) {
        lifeChangeDebounces[playerId]?.cancel()
        lifeChangeDebounces[playerId] = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: Self.lifeChangeDebounce)
            } catch {
                return // A later tap restarted it, or the board went away.
            }
            // Cancelled after waking but before getting here: the later
            // tap's debounce takes over.
            guard !Task.isCancelled else { return }
            self?.lifeChangeDebounceEnded(for: playerId)
        }
    }

    private func lifeChangeDebounceEnded(for playerId: String) {
        lifeChangeDebounces[playerId] = nil
        sendPendingLifeChange(for: playerId)
    }

    /// Sends the player's pending taps as one batch once nothing holds them
    /// back: their debounce has ended and their previous batch has settled.
    /// Each of those calls this, and the later one finds the taps pending.
    private func sendPendingLifeChange(for playerId: String) {
        guard lifeChangeDebounces[playerId] == nil,
              let serverLife = serverPlayers.first(where: { $0.id == playerId })?.lifeTotal,
              let batch = lifeLedger.beginBatch(for: playerId, serverLife: serverLife) else { return }
        let cloudFunctions = cloudFunctions
        let gameId = gameId
        // Holds what the call needs, not the view model, so the call still
        // completes if the board closes first.
        lifeChangeSends[playerId] = Task { [weak self] in
            do {
                let newLife = try await cloudFunctions.adjustLife(gameId: gameId, playerId: playerId, amount: batch.amount)
                self?.batchSucceeded(batch, newLife: newLife)
            } catch {
                self?.batchFailed(batch, error: error)
            }
        }
    }

    private func batchSucceeded(_ batch: LifeLedger.Batch, newLife: Int?) {
        lifeChangeSends[batch.playerId] = nil
        lifeLedger.recordSuccess(of: batch, newLife: newLife)
        refreshPlayers()
        sendPendingLifeChange(for: batch.playerId)
    }

    /// The batch comes off the board and is never resent; see
    /// `LifeLedger.recordFailure(of:)`. Taps made since it was sent go out
    /// as a change of their own.
    private func batchFailed(_ batch: LifeLedger.Batch, error: Error) {
        lifeChangeSends[batch.playerId] = nil
        lifeLedger.recordFailure(of: batch)
        refreshPlayers()
        reportLifeChangeFailure(for: batch.playerId, error: error)
        sendPendingLifeChange(for: batch.playerId)
    }

    private func reportLifeChangeFailure(for playerId: String, error: Error) {
        logger.error("adjustLife failed: \(String(describing: error), privacy: .public)")
        let name = serverPlayers.first { $0.id == playerId }?.displayName ?? "the player"
        errorMessage = "Couldn't update \(name)'s life. Check your connection and try again."
    }
}

// MARK: - Listener Status

extension GameBoardViewModel {

    /// What the board and Game Over can show, given what the listeners have
    /// reported. The data itself lives in `game` and `players`.
    enum Status: Equatable {
        /// Waiting for the game and its players.
        case loading
        /// The game and its players are here to show.
        case ready
        /// The game's state or mode is one this build doesn't know, or its
        /// data can't be read. Playing it here could show the wrong controls
        /// or hide the right ones.
        case needsNewerVersion
        /// The server confirmed the game no longer exists.
        case unavailable
        /// A listener failed; `retry()` re-attaches.
        case failed
    }

    /// Outcomes that come with nothing to show. All of them stick: Firestore
    /// stops delivering after a listener error, unreadable data would only
    /// arrive again, and nothing re-creates a deleted game. Ordered by
    /// precedence, lowest first; see `interrupt(_:)`.
    private enum ListenerInterruption: Comparable {
        case failed
        case unreadable
        case gameMissing
    }

    var status: Status {
        switch interruption {
        case .gameMissing: return .unavailable
        case .unreadable: return .needsNewerVersion
        case .failed: return .failed
        case nil: break
        }
        guard let game else { return .loading }
        if game.state.isUnknown || game.gameMode.isUnknown { return .needsNewerVersion }
        return players.isEmpty ? .loading : .ready
    }

    /// Re-attaches both listeners after a failure.
    func retry() {
        guard interruption == .failed else { return }
        interruption = nil
        // Show loading, not the stale game, until the new listener reports.
        game = nil
        gameListener?.remove()
        playersListener?.remove()
        startListening()
    }

    private func receiveGame(_ event: DocumentEvent<Game>) {
        switch event {
        case .loaded(let game):
            self.game = game
        case .missing:
            interrupt(.gameMissing)
        case .failed(let failure):
            recordListenerFailure(failure, listener: "game")
        }
    }

    private func recordListenerFailure(_ failure: ListenerFailure, listener: String) {
        switch failure {
        case .listenerStopped(let error):
            logger.error("Game board \(listener, privacy: .public) listener failed: \(String(describing: error), privacy: .public)")
            interrupt(.failed)
        case .unreadable(let error):
            logger.error("Game board \(listener, privacy: .public) data unreadable: \(String(describing: error), privacy: .public)")
            interrupt(.unreadable)
        }
    }

    /// Keeps the more telling interruption. A missing game wins, because once
    /// it's deleted the players read is denied too, in whichever order the
    /// two arrive; unreadable data beats a listener failure, because retrying
    /// can't fix it.
    private func interrupt(_ new: ListenerInterruption) {
        interruption = max(interruption ?? new, new)
    }
}
