//
//  LobbyViewModel.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/13/26.
//

import Foundation
import os
import SwiftUI

private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "Lobby")

@MainActor
final class LobbyViewModel: ObservableObject {

    /// What the lobby screen can show, given what its listeners have reported.
    enum Status: Equatable {
        /// Waiting for the first game snapshot.
        case loading
        /// The lobby is open. Once the game is in progress the view moves on
        /// to the board.
        case loaded(Game)
        /// The game was played to the end, for instance while the app was in
        /// the background. There's no lobby left, only its results.
        case finished
        /// The game is in a state this build doesn't know, or its data can't
        /// be read, so the lobby can't be shown safely. An unknown game mode
        /// still loads the lobby.
        case needsNewerVersion
        /// The server confirmed the game no longer exists: its last player
        /// left, or the hourly cleanup removed it after a day without
        /// activity. Nothing re-creates a deleted game, so this is final.
        case disbanded
        /// The server refused to show the user this game's players: they're
        /// no longer in it, for instance because a leave got through but its
        /// reply was lost. Retrying would be refused again, so this is final.
        case notInGame
        /// A listener failed. Firestore stops delivering after an error, so
        /// only `retry()` leaves this state.
        case failed
    }

    /// A lobby request that is waiting on the server. Only one runs at a
    /// time, so a repeat tap can't send a second start or leave.
    enum PendingAction: Equatable {
        case starting
        case leaving
    }

    /// What happens when the host leaves, mirroring leaveGame on the server:
    /// the earliest remaining seat becomes host, and a lobby with nobody else
    /// in it is deleted.
    enum HostLeaveOutcome: Equatable {
        case passesHost(to: String)
        case closesLobby
    }

    /// A request that failed, shown at the end of the lobby's scrolling
    /// content, just above its pinned buttons, until the next request starts.
    enum RequestFailure: Equatable {
        /// Leaving failed, so the player still has their seat. The lobby then
        /// also offers a way home that keeps it: Leave is otherwise the
        /// screen's only way out, and it can keep failing (offline, say).
        case leave(String)
        /// Starting the game, or changing a setting or the player's color
        /// failed.
        case other(String)

        var message: String {
            switch self {
            case .leave(let message), .other(let message): return message
            }
        }
    }

    /// A listener outcome that leaves no lobby to show. All of them stick:
    /// Firestore stops delivering after an error (only `retry()` clears
    /// that), unreadable data would only arrive again, a refused read would
    /// be refused again, and nothing re-creates a deleted game. Ordered by
    /// precedence, lowest first; see `interrupt(_:)`.
    private enum Interruption: Comparable {
        case listenerFailed
        case unreadable
        case notInGame
        case gameMissing
    }

    /// What the commander name field holds, and what it held when it was
    /// filled or last saved. The player has edited it since when the two
    /// differ, and only then is it saved: a name changed elsewhere (on
    /// another device, say) mustn't be overwritten by a draft nobody
    /// touched.
    private struct CommanderNameField {
        var draft: String
        var synced: String

        var isEdited: Bool { draft != synced }
    }

    @Published private(set) var players: [Player] = []
    @Published private(set) var requestFailure: RequestFailure?
    /// Why the last commander name save failed, until the next save starts.
    /// Kept apart from `requestFailure`: saves run by themselves whenever
    /// typing pauses, so they must neither clear nor replace a failure the
    /// player is still reading, such as a failed leave's.
    @Published private(set) var commanderNameFailure: String?
    @Published private(set) var pendingAction: PendingAction?
    /// Host's selected max traitor rarity. Seeded from the live game snapshot
    /// (absent on the doc means the server default, "special") so a lobby
    /// opened after creation shows the real value, not a hardcoded default.
    @Published var maxTraitorRarity: Rarity = .special
    /// The commander name field, or nil until the first players snapshot
    /// that includes the current player. Later snapshots bring in a name
    /// changed elsewhere (on another device, say), but only while the
    /// player hasn't edited the field: a snapshot must never refill a field
    /// the player has just edited or cleared.
    @Published private var commanderNameField: CommanderNameField?
    /// The last game snapshot that decoded; `status` decides what to show.
    @Published private var latestGame: Game?
    @Published private var interruption: Interruption?

    let gameId: String
    /// Navigation fallback only; prefer `isHost` which reads live `game.hostId`.
    private let navIsHost: Bool
    var currentUserId: String? {
        didSet { loadCommanderNameIfNeeded() }
    }
    private let firestoreManager: FirestoreManaging
    private let cloudFunctions: CloudFunctionsProtocol
    private var gameListener: ListenerCancellable?
    private var playersListener: ListenerCancellable?

    var status: Status {
        switch interruption {
        case .gameMissing: return .disbanded
        case .notInGame: return .notInGame
        case .unreadable: return .needsNewerVersion
        case .listenerFailed: return .failed
        case nil: break
        }
        guard let latestGame else { return .loading }
        switch latestGame.state {
        case .waiting, .inProgress: return .loaded(latestGame)
        case .finished: return .finished
        case .unknown: return .needsNewerVersion
        }
    }

    /// The open lobby's game; nil unless `status` is `.loaded`.
    var game: Game? {
        if case .loaded(let game) = status { return game }
        return nil
    }

    /// What went wrong, in a plain sentence: the last request's failure, or
    /// else the last commander name save's.
    var errorMessage: String? {
        requestFailure?.message ?? commanderNameFailure
    }

    /// True after a failed leave: the lobby then offers Back to Home, which
    /// keeps the player's seat.
    var offersHomeWithoutLeaving: Bool {
        if case .leave = requestFailure { return true }
        return false
    }

    var currentPlayer: Player? {
        guard let userId = currentUserId else { return nil }
        return players.first { $0.userId == userId }
    }

    /// True when the signed-in user is the live host (updates after host promotion).
    var isHost: Bool {
        guard let userId = currentUserId else { return navIsHost }
        if let hostId = game?.hostId {
            return hostId == userId
        }
        return navIsHost
    }

    /// A mode this build doesn't know can't be played here (the board would
    /// ask for an update), so it can't be started from here either.
    var canStartGame: Bool {
        guard let game, !game.gameMode.isUnknown else { return false }
        return isHost && players.count >= minimumPlayerCount
    }

    var minimumPlayerCount: Int {
        guard let game = game else { return Role.minimumPlayerCount }
        return game.gameMode.includesTreachery ? Role.minimumPlayerCount : 1
    }

    /// The lowest max-players setting the server accepts: 2, or the number of
    /// players already seated when that's more. Never above the highest
    /// setting, 8.
    var smallestMaxPlayers: Int {
        min(8, max(2, game?.playerIds.count ?? 0))
    }

    var isGameStarted: Bool {
        game?.state == .inProgress
    }

    /// Why the host can't start yet; nil once they can (and always for
    /// guests).
    var startRequirement: String? {
        guard isHost else { return nil }
        if game?.gameMode.isUnknown == true {
            return "Update Treachery or choose another game mode to start"
        }
        guard players.count < minimumPlayerCount else { return nil }
        let count = minimumPlayerCount
        return "Need at least \(count) player\(count == 1 ? "" : "s") to start"
    }

    var isStartingGame: Bool { pendingAction == .starting }
    var isLeaving: Bool { pendingAction == .leaving }

    /// What leaving does when the current user is the host. Nil for everyone
    /// else: their leaving changes nothing for the others, so it needs no
    /// confirmation.
    var hostLeaveOutcome: HostLeaveOutcome? {
        guard isHost else { return nil }
        let nextHost = players
            .filter { $0.userId != currentUserId }
            .min { $0.orderId < $1.orderId }
        guard let nextHost else { return .closesLobby }
        return .passesHost(to: nextHost.displayName)
    }

    /// Bound to the commander name field. The field shows only in the
    /// current player's row, which needs the snapshot that fills it, so
    /// there's nothing to edit before then.
    var commanderNameDraft: String {
        get { commanderNameField?.draft ?? "" }
        set { commanderNameField?.draft = newValue }
    }

    init(
        gameId: String,
        isHost: Bool,
        firestoreManager: FirestoreManaging = FirestoreManager(),
        cloudFunctions: CloudFunctionsProtocol = CloudFunctions()
    ) {
        self.gameId = gameId
        self.navIsHost = isHost
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
        gameListener = firestoreManager.listenToGame(id: gameId) { [weak self] event in
            self?.receiveGame(event)
        }
        playersListener = firestoreManager.listenToPlayers(gameId: gameId) { [weak self] result in
            self?.receivePlayers(result)
        }
    }

    private func stopListening() {
        gameListener?.remove()
        playersListener?.remove()
        gameListener = nil
        playersListener = nil
    }

    private func receiveGame(_ event: DocumentEvent<Game>) {
        switch event {
        case .loaded(let game):
            latestGame = game
            maxTraitorRarity = game.maxTraitorRarity ?? .special
        case .missing:
            interrupt(.gameMissing)
        case .failed(let failure):
            record(failure, listener: "game")
        }
    }

    private func receivePlayers(_ result: Result<[Player], ListenerFailure>) {
        switch result {
        case .success(let players):
            withAnimation(.easeInOut(duration: 0.3)) {
                self.players = players
            }
            loadCommanderNameIfNeeded()
        case .failure(let failure):
            record(failure, listener: "players")
        }
    }

    private func record(_ failure: ListenerFailure, listener: String) {
        switch failure {
        case .listenerStopped(let error):
            logger.error("Lobby \(listener, privacy: .public) listener failed: \(String(describing: error), privacy: .public)")
            interrupt(.listenerFailed)
        case .unreadable(let error):
            logger.error("Lobby \(listener, privacy: .public) data unreadable: \(String(describing: error), privacy: .public)")
            interrupt(.unreadable)
        case .accessDenied(let error):
            logger.error("Lobby \(listener, privacy: .public) read denied: \(String(describing: error), privacy: .public)")
            interrupt(.notInGame)
        }
    }

    /// Keeps the more telling interruption. A missing game wins, because once
    /// it's deleted the players read is denied too, in whichever order the
    /// two arrive. A denied read beats unreadable data, since a newer version
    /// wouldn't give the player their seat back, and unreadable data beats a
    /// listener failure, because retrying can't fix it.
    private func interrupt(_ new: Interruption) {
        interruption = max(interruption ?? new, new)
    }

    /// Re-attaches both listeners after a failure.
    func retry() {
        guard interruption == .listenerFailed else { return }
        interruption = nil
        // Show loading, not the stale game, until the new listener reports.
        latestGame = nil
        stopListening()
        startListening()
    }

    // MARK: - Actions

    func startGame() async {
        guard isHost, canStartGame, pendingAction == nil else { return }
        requestFailure = nil
        pendingAction = .starting
        do {
            try await cloudFunctions.startGame(gameId: gameId)
            AnalyticsService.trackEvent("start_game", params: [
                "player_count": players.count,
                "game_mode": game?.gameMode.rawValue ?? "unknown"
            ])
            // Stay .starting: the started game's snapshot moves everyone to
            // the board, and Start must not come back in the meantime.
        } catch {
            logger.error("startGame failed: \(String(describing: error), privacy: .public)")
            pendingAction = nil
            requestFailure = .other(Self.message(
                for: error, otherwise: "Couldn't start the game. Check your connection and try again."
            ))
        }
    }

    /// Leaves the lobby and returns whether the player is out of it. On
    /// failure the player is still in the lobby, its listeners are running
    /// again, and `requestFailure` says what went wrong.
    func leave() async -> Bool {
        guard pendingAction == nil else { return false }
        requestFailure = nil
        pendingAction = .leaving
        // Stop listening first. A successful leave removes our seat, and the
        // whole lobby when the host was alone; the listeners would flash that
        // up as "failed" or "disbanded" just before the view navigates away.
        stopListening()
        do {
            try await cloudFunctions.leaveGame(gameId: gameId)
            AnalyticsService.trackEvent("leave_lobby")
            // Stay .leaving while the view navigates home.
            return true
        } catch let refusal as CallableRefusal where refusal.reason == .notFound {
            // The lobby, or our seat in it, is already gone: it closed in the
            // meantime, or an earlier leave got through but its reply was
            // lost. Either way there's nothing left to leave.
            logger.info("leaveGame found nothing to leave: \(refusal.message, privacy: .public)")
            return true
        } catch {
            logger.error("leaveGame failed: \(String(describing: error), privacy: .public)")
            startListening()
            pendingAction = nil
            requestFailure = .leave(Self.leaveFailureMessage(for: error))
            return false
        }
    }

    /// Only a waiting lobby can be left. When the server says the game has
    /// started, the restarted listeners take the player on to the board (or
    /// the results); anything else most likely never reached the server.
    private static func leaveFailureMessage(for error: any Error) -> String {
        if let refusal = error as? CallableRefusal, refusal.reason == .failedPrecondition {
            return "The game has already started, so you can't leave the lobby."
        }
        return "Couldn't leave the lobby. Check your connection and try again."
    }

    /// The server's own explanation when it refused the request because of
    /// the game's state, such as "Cannot set max players below the current
    /// lobby size."; otherwise `fallback`, since the request most likely
    /// never reached the server.
    private static func message(for error: any Error, otherwise fallback: String) -> String {
        CallableRefusal.explanation(of: error) ?? fallback
    }

    // MARK: - Player Customization

    func updatePlayerColor(_ hex: String?) async {
        guard let player = currentPlayer else { return }
        requestFailure = nil
        do {
            try await firestoreManager.updatePlayerColor(gameId: gameId, playerId: player.id, color: hex)
        } catch {
            logger.error("updatePlayerColor failed: \(String(describing: error), privacy: .public)")
            requestFailure = .other("Couldn't change your color. Check your connection and try again.")
        }
    }

    func updateCommanderName(_ name: String?) async {
        guard let player = currentPlayer else { return }
        commanderNameFailure = nil
        do {
            try await firestoreManager.updateCommanderName(gameId: gameId, playerId: player.id, name: name)
            commanderNameField?.synced = name ?? ""
        } catch {
            logger.error("updateCommanderName failed: \(String(describing: error), privacy: .public)")
            commanderNameFailure = "Couldn't save your commander name. Check your connection and try again."
        }
    }

    /// Sends the draft when the player has edited it since it was filled or
    /// last saved, and it differs from the name on the server. The view
    /// calls this once typing pauses, when the field is submitted, and when
    /// the lobby goes off screen (the board replacing it, say), so the last
    /// keystrokes aren't lost. Nothing is sent while leaving or once the
    /// lobby has closed: there's no seat left to name.
    func saveCommanderName() async {
        guard pendingAction != .leaving, game != nil,
              let field = commanderNameField, field.isEdited,
              let player = currentPlayer else { return }
        let name = field.draft.isEmpty ? nil : field.draft
        guard name != player.commanderName else {
            // The server already has it.
            commanderNameField?.synced = field.draft
            return
        }
        await updateCommanderName(name)
    }

    /// Fills the commander name field with the server's name, and refreshes
    /// it when that name changes while the field is unedited. An edited or
    /// cleared field is left alone, and the echo of the player's own save
    /// already matches what they typed.
    private func loadCommanderNameIfNeeded() {
        guard let player = currentPlayer else { return }
        let name = player.commanderName ?? ""
        if let field = commanderNameField, field.isEdited || field.synced == name { return }
        commanderNameField = CommanderNameField(draft: name, synced: name)
    }

    func updateGameSettings(maxPlayers: Int? = nil, startingLife: Int? = nil, gameMode: String? = nil, maxTraitorRarity: String? = nil) async {
        guard isHost else { return }
        requestFailure = nil
        do {
            try await cloudFunctions.updateGameSettings(
                gameId: gameId, maxPlayers: maxPlayers, startingLife: startingLife,
                gameMode: gameMode, maxTraitorRarity: maxTraitorRarity
            )
            if let maxTraitorRarity, let rarity = Rarity(rawValue: maxTraitorRarity) {
                self.maxTraitorRarity = rarity
            }
        } catch {
            logger.error("updateGameSettings failed: \(String(describing: error), privacy: .public)")
            requestFailure = .other(Self.message(
                for: error, otherwise: "Couldn't change the game settings. Check your connection and try again."
            ))
        }
    }

}
