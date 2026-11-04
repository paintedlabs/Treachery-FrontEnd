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
    /// Life changes whose calls failed, one per player in the order they
    /// failed. Each stays until that player's life is changed again here or
    /// a snapshot settles it; see `receivePlayers(_:)`. Kept apart from
    /// `errorMessage`, which any tap clears, so tapping someone else doesn't
    /// hide them.
    @Published private(set) var lifeChangeFailures: [LifeChangeFailure] = []
    @Published var isPending = false
    /// Unveiling has its own progress, so another action under way can't
    /// make an unveil silently do nothing.
    @Published private(set) var unveilProgress: UnveilProgress = .idle
    /// The reveal under way; see `playReveal()`. Visible to tests, which
    /// await it rather than sleep.
    private(set) var unveilReveal: Task<Void, Never>?
    @Published var pendingAbilityResolution: AbilityResolution?

    // Planechase transient state
    @Published var dieRollResult: String?
    /// Takes the die result down; see `showDieResult(_:)`. Visible to tests,
    /// which await it rather than sleep.
    private(set) var dieResultClear: Task<Void, Never>?
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
    /// Per player: the wait for a confirmed change to show up in a
    /// snapshot. Visible to tests, which await it rather than sleep.
    private(set) var lifeChangeEchoWaits: [String: Task<Void, Never>] = [:]
    private var serverPlayers: [Player] = []
    /// Times the debounce and the wait for a confirmed change's echo.
    private let clock: any Clock<Duration>

    // MARK: - Properties

    let gameId: String
    /// Published because the board sets it as it appears, possibly after
    /// the first snapshots: the seat, and with it the life controls, must
    /// follow.
    @Published var currentUserId: String?
    private let firestoreManager: FirestoreManaging
    /// Not private: the ability resolvers in GameBoardViewModel+Abilities.swift
    /// call it too.
    let cloudFunctions: CloudFunctionsProtocol
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

    /// The mana the signed-in user's next planar die roll costs; see
    /// `PlanechaseState.nextRollCost(for:)`.
    var dieRollCost: Int {
        game?.planechase?.nextRollCost(for: currentUserId) ?? 0
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
        for echoWait in lifeChangeEchoWaits.values {
            echoWait.cancel()
        }
        dieResultClear?.cancel()
        unveilReveal?.cancel()
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
            logger.error("eliminatePlayer failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't forfeit the game. Check your connection and try again."
        }
        isPending = false
    }

    // MARK: - Planechase Actions

    func rollDie() async {
        guard canRollDie, !isRollingDie else { return }
        errorMessage = nil
        isRollingDie = true
        dieRollResult = nil

        do {
            let result = try await cloudFunctions.rollPlanarDie(gameId: gameId)
            showDieResult(result)
            AnalyticsService.trackEvent("roll_planar_die", params: ["result": result])
        } catch {
            logger.error("rollPlanarDie failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't roll the planar die. Check your connection and try again."
        }
        isRollingDie = false
    }

    /// How long a die result stays up, so its animation can play again.
    static let dieResultDuration: Duration = .seconds(3)

    /// Shows `result` for `dieResultDuration`. It cancels the clear still
    /// waiting for the previous result, which would otherwise take this one
    /// down early.
    private func showDieResult(_ result: String) {
        dieResultClear?.cancel()
        dieRollResult = result
        dieResultClear = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: Self.dieResultDuration)
            } catch {
                return // A newer result replaced this one, or the board went away.
            }
            // Cancelled after waking but before getting here: the newer
            // result's clear takes over.
            guard !Task.isCancelled else { return }
            self?.dieRollResult = nil
            self?.dieResultClear = nil
        }
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
            logger.error("resolvePhenomenon failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't resolve the phenomenon. Check your connection and try again."
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
            logger.error("selectPlane failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't planeswalk to \(plane.name). Check your connection and try again."
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
            logger.error("endGame failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't end the game. Check your connection and try again."
        }
        isPending = false
    }

    // MARK: - Player Customization

    func updatePlayerColor(_ hex: String?) async {
        guard let player = currentPlayer else { return }
        do {
            try await firestoreManager.updatePlayerColor(gameId: gameId, playerId: player.id, color: hex)
        } catch {
            logger.error("updatePlayerColor failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't change your color. Check your connection and try again."
        }
    }

    // MARK: - Ability Cards

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
}

// MARK: - Unveil (via Cloud Function)
//
// `UnveilProgress` is in GameBoardViewModel+Unveil.swift.

extension GameBoardViewModel {

    /// Unveils the signed-in player, then plays the reveal; see
    /// `playReveal()`. Nothing plays unless the server has unveiled them.
    ///
    /// - Returns: The call, for tests to await, or nil when Unveil isn't on
    ///   offer or is being sent. Like a life change's send, the call holds
    ///   what it needs, not the view model, and is left to finish if the
    ///   board goes away.
    @discardableResult
    func unveilCurrentPlayer() -> Task<Void, Never>? {
        guard offersUnveil, unveilProgress != .sending else { return nil }
        errorMessage = nil
        unveilProgress = .sending
        let cloudFunctions = cloudFunctions
        let gameId = gameId
        return Task { [weak self] in
            do {
                try await cloudFunctions.unveilPlayer(gameId: gameId)
                self?.playReveal()
            } catch {
                self?.unveilCallFailed(error)
            }
        }
    }

    /// The reply can be lost after the server has unveiled them. A players
    /// snapshot that shows the unveil, already or later, settles that.
    private func unveilCallFailed(_ error: any Error) {
        logger.error("unveilPlayer failed: \(String(describing: error), privacy: .public)")
        unveilProgress = .failed(message: CallableRefusal.explanation(of: error)
            ?? "Couldn't unveil your identity. Check your connection and try again.")
        settleUnveil()
    }

    /// Settles what the call left open, once a players snapshot shows the
    /// signed-in player unveiled. After a failed call the unveil went
    /// through after all, unless what marked them unveiled was being
    /// eliminated; and a reveal that ended first lets Unveil go.
    private func settleUnveil() {
        guard let player = currentPlayer, player.isUnveiled else { return }
        switch unveilProgress {
        case .failed where !player.isEliminated:
            playReveal()
        case .failed, .awaitingSnapshot:
            unveilProgress = .idle
        case .idle, .sending, .flippingAway, .revealing:
            break
        }
    }

    /// Plays the reveal, timed on the injected clock: the header turns
    /// edge-on, then back face-up under the "IDENTITY REVEALED" banner.
    /// Then the ability sheet opens, when their card has an ability to use.
    /// The board owns the reveal: when the board goes away, it ends there.
    /// It ends after the flip once the game is over: Game Over covers it.
    private func playReveal() {
        AnalyticsService.trackEvent("unveil_identity")
        unveilProgress = .flippingAway
        unveilReveal = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: UnveilProgress.flipDuration)
                if self?.game?.state == .inProgress {
                    self?.unveilProgress = .revealing
                    try await clock.sleep(for: UnveilProgress.bannerDuration)
                }
            } catch {
                return // The board went away.
            }
            self?.revealEnded()
        }
    }

    private func revealEnded() {
        unveilReveal = nil
        unveilProgress = currentPlayer?.isUnveiled == true ? .idle : .awaitingSnapshot
        presentAbilityAfterUnveil()
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

    /// How long a change the server has confirmed stays on screen waiting
    /// for a snapshot to show it; see `LifeLedger.recordEchoTimeout(of:)`.
    /// The echo usually comes within moments of the response, often before
    /// it. This is far longer, because ending the wait while snapshots are
    /// slow shows the old total again until they catch up. It starts again
    /// for as long as no snapshot has come since the response.
    static let lifeChangeEchoTimeout: Duration = .seconds(5)

    /// The banner for `lifeChangeFailures`, naming everyone affected.
    var lifeChangeMessage: String? {
        LifeChangeFailure.bannerMessage(for: lifeChangeFailures)
    }

    /// Shows the tap at once, then sends it with any taps on the same player
    /// that follow within `lifeChangeDebounce`, as one adjustLife call.
    func adjustLife(for playerId: String, by amount: Int) {
        guard canAdjustLife,
              let player = serverPlayers.first(where: { $0.id == playerId }) else { return }
        guard !player.isEliminated else { return }
        errorMessage = nil
        lifeChangeFailures.removeAll { $0.playerId == playerId }

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
    /// whatever it's given, so two calls at once still add up. Once the game
    /// is over, as when Game Over replaces the board, the taps are dropped:
    /// the server refuses any change to a finished game.
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
        guard !isGameFinished else { return [] }

        let cloudFunctions = cloudFunctions
        let gameId = gameId
        return pendingTaps.map { playerId, amount in
            // Taps are only made on players on the board; a failure for one
            // no longer there isn't reported.
            let baseline = serverPlayers.first { $0.id == playerId }?.lifeTotal ?? 0
            // Holds what the call needs, not the view model, which is
            // usually gone before the call returns.
            return Task { [weak self] in
                do {
                    _ = try await cloudFunctions.adjustLife(gameId: gameId, playerId: playerId, amount: amount)
                } catch {
                    self?.reportLifeChangeFailure(.reverted, amount: amount, from: baseline, for: playerId, error: error)
                }
            }
        }
    }

    /// A players snapshot: settles the batches it shows, redraws the board,
    /// sends any taps that were waiting on a batch it settled, and settles
    /// an unveil whose call couldn't. A player it shows eliminated loses
    /// their unsent taps: the server refuses changes to them. What the
    /// board says about failed changes follows the snapshot too; see
    /// `revisedLifeChangeFailures(by:)`.
    private func receivePlayers(_ players: [Player]) {
        serverPlayers = players
        lifeLedger.reconcile(with: players)
        for player in players where player.isEliminated {
            lifeChangeDebounces.removeValue(forKey: player.id)?.cancel()
        }
        lifeChangeFailures = revisedLifeChangeFailures(by: players)
        withAnimation(.easeInOut(duration: 0.3)) {
            refreshPlayers()
        }
        // A snapshot that settles a confirmed batch ends its wait.
        let settled = lifeChangeEchoWaits.keys.filter { !lifeLedger.isWaitingForEcho(for: $0) }
        for playerId in settled {
            lifeChangeEchoWaits.removeValue(forKey: playerId)?.cancel()
        }
        for playerId in lifeLedger.playersWithPendingTaps {
            sendPendingLifeChange(for: playerId)
        }
        settleUnveil()
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
    /// Nothing goes out once the game is over; the server would refuse it.
    private func sendPendingLifeChange(for playerId: String) {
        guard !isGameFinished, lifeChangeDebounces[playerId] == nil,
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
        if lifeLedger.isWaitingForEcho(for: batch.playerId) {
            waitForEcho(of: batch)
        }
        sendPendingLifeChange(for: batch.playerId)
    }

    /// Gives a confirmed batch `lifeChangeEchoTimeout` to show up in a
    /// snapshot. A snapshot that shows it ends the wait early.
    private func waitForEcho(of batch: LifeLedger.Batch) {
        lifeChangeEchoWaits[batch.playerId]?.cancel()
        lifeChangeEchoWaits[batch.playerId] = Task { [weak self, clock] in
            do {
                try await clock.sleep(for: Self.lifeChangeEchoTimeout)
            } catch {
                return // A snapshot showed the batch, or the board went away.
            }
            guard !Task.isCancelled else { return }
            self?.echoWaitEnded(for: batch)
        }
    }

    /// The batch comes off the board, which shows the latest snapshot's
    /// total, and taps held behind it go out. While no snapshot has come
    /// since the response, the listener may be behind, so the wait starts
    /// again instead.
    private func echoWaitEnded(for batch: LifeLedger.Batch) {
        lifeChangeEchoWaits[batch.playerId] = nil
        switch lifeLedger.recordEchoTimeout(of: batch) {
        case .settled:
            refreshPlayers()
            sendPendingLifeChange(for: batch.playerId)
        case .waitAgain:
            // Nothing needs the batch settled once the game is over.
            guard !isGameFinished else { return }
            waitForEcho(of: batch)
        case .notWaiting:
            break
        }
    }

    /// The batch comes off the board and is never resent; see
    /// `LifeLedger.recordFailure(of:)`. Taps made since it was sent go out
    /// as a change of their own.
    private func batchFailed(_ batch: LifeLedger.Batch, error: Error) {
        lifeChangeSends[batch.playerId] = nil
        // Never nil here: a batch can't settle before its call returns.
        let outcome = lifeLedger.recordFailure(of: batch) ?? .reverted
        refreshPlayers()
        reportLifeChangeFailure(outcome, amount: batch.amount, from: batch.baseline, for: batch.playerId, error: error)
        sendPendingLifeChange(for: batch.playerId)
    }

    /// - Parameter baseline: The player's server life when the change was
    ///   sent.
    private func reportLifeChangeFailure(
        _ outcome: LifeLedger.FailureOutcome, amount: Int, from baseline: Int, for playerId: String, error: Error
    ) {
        logger.error("adjustLife failed: \(String(describing: error), privacy: .public)")
        // Once the game is over or the player is out, the board shows that,
        // and no tap could clear the message. A player no longer on the
        // board has no row to explain.
        guard !isGameFinished, let player = serverPlayers.first(where: { $0.id == playerId }),
              !player.isEliminated else { return }
        let kind: LifeChangeFailure.Kind
        if let reason = CallableRefusal.explanation(of: error) {
            kind = .refused(reason: reason)
        } else {
            switch outcome {
            case .reverted:
                kind = .notApplied(baseline: baseline, amount: amount)
            case .unconfirmed:
                // The total shown most likely includes the change already.
                kind = .unconfirmed
            }
        }
        let failure = LifeChangeFailure(playerId: playerId, playerName: player.displayName, kind: kind)
        // One per player, kept in the order they first failed.
        if let index = lifeChangeFailures.firstIndex(where: { $0.playerId == playerId }) {
            lifeChangeFailures[index] = lifeChangeFailures[index].followed(by: failure)
        } else {
            lifeChangeFailures.append(failure)
        }
    }
}

// MARK: - Listener Status
//
// `Status` itself is in GameBoardViewModel+Status.swift.

extension GameBoardViewModel {

    /// Outcomes that come with nothing to show. All of them stick: Firestore
    /// stops delivering after a listener error, unreadable data would only
    /// arrive again, a refused read would be refused again, and nothing
    /// re-creates a deleted game. Ordered by precedence, lowest first; see
    /// `interrupt(_:)`.
    private enum ListenerInterruption: Comparable {
        case failed
        case unreadable
        case notInGame
        case gameMissing
    }

    var status: Status {
        switch interruption {
        case .gameMissing: return .unavailable
        case .notInGame: return .notInGame
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
        case .accessDenied(let error):
            logger.error("Game board \(listener, privacy: .public) read denied: \(String(describing: error), privacy: .public)")
            interrupt(.notInGame)
        }
    }

    /// Keeps the more telling interruption. A missing game wins, because once
    /// it's deleted the players read is denied too, in whichever order the
    /// two arrive. A denied read beats unreadable data, since a newer version
    /// wouldn't give the player their seat back, and unreadable data beats a
    /// listener failure, because retrying can't fix it.
    private func interrupt(_ new: ListenerInterruption) {
        interruption = max(interruption ?? new, new)
    }
}
