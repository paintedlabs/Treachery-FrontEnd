import Foundation
@testable import Treachery_iOS

final class MockListenerCancellable: ListenerCancellable {
    var removeCalled = false
    func remove() { removeCalled = true }
}

final class MockFirestoreManager: FirestoreManaging {

    // MARK: - Stub data

    var usersToReturn: [String: TreacheryUser] = [:]
    var gamesToReturn: [String: Game] = [:]
    var gameByCodeToReturn: Game?
    var activeGameToReturn: Game?
    var playersToReturn: [Player] = []
    var finishedGamesToReturn: [Game] = []
    var friendsToReturn: [TreacheryUser] = []
    var pendingRequestsToReturn: [FriendRequest] = []
    var searchResultsToReturn: [TreacheryUser] = []
    var errorToThrow: Error?

    // MARK: - Call tracking

    var createUserCalls: [TreacheryUser] = []
    var createGameCalls: [Game] = []
    var addPlayerCalls: [(Player, String)] = []
    var updatePlayerColorCalls: [(gameId: String, playerId: String, color: String?)] = []
    var updateCommanderNameCalls: [(gameId: String, playerId: String, name: String?)] = []

    // MARK: - Users

    func createUser(_ user: TreacheryUser) async throws {
        if let error = errorToThrow { throw error }
        createUserCalls.append(user)
    }

    func getUser(id: String) async throws -> TreacheryUser? {
        if let error = errorToThrow { throw error }
        return usersToReturn[id]
    }

    func updateUser(_ user: TreacheryUser) async throws {
        if let error = errorToThrow { throw error }
    }

    func searchUsers(byDisplayName name: String) async throws -> [TreacheryUser] {
        return searchResultsToReturn
    }

    // MARK: - Friend Requests

    func sendFriendRequest(_ request: FriendRequest) async throws {}
    func getPendingFriendRequests(forUserId userId: String) async throws -> [FriendRequest] { pendingRequestsToReturn }
    func updateFriendRequest(_ request: FriendRequest) async throws {}
    func addFriend(userId: String, friendId: String) async throws {}
    func removeFriend(userId: String, friendId: String) async throws {}
    func getFriends(forUserId userId: String) async throws -> [TreacheryUser] { friendsToReturn }

    // MARK: - Games

    func createGame(_ game: Game) async throws {
        if let error = errorToThrow { throw error }
        createGameCalls.append(game)
    }

    func getGame(id: String) async throws -> Game? { gamesToReturn[id] }
    func getGame(byCode code: String) async throws -> Game? { gameByCodeToReturn }
    func updateGame(_ game: Game) async throws {}
    func deleteGame(id: String) async throws {}
    func addPlayerIdToGame(gameId: String, userId: String) async throws {}
    func getActiveGame(forUserId userId: String) async throws -> Game? { activeGameToReturn }
    func getFinishedGames(forUserId userId: String) async throws -> [Game] { finishedGamesToReturn }

    /// Delivers `gamesToReturn[id]` straight away when it is set, like a
    /// cached document. Leave it unset to start with nothing delivered, then
    /// drive the listener with `emitGame`.
    func listenToGame(id: String, onChange: @escaping @MainActor (DocumentEvent<Game>) -> Void) -> ListenerCancellable {
        let registration = MockListenerCancellable()
        gameListeners.append(GameListener(gameId: id, registration: registration, onChange: onChange))
        if let game = gamesToReturn[id] {
            // Tests run on the main actor, where the real SDK calls back too.
            MainActor.assumeIsolated { onChange(.loaded(game)) }
        }
        return registration
    }

    // MARK: - Players

    func addPlayer(_ player: Player, toGame gameId: String) async throws {
        if let error = errorToThrow { throw error }
        addPlayerCalls.append((player, gameId))
    }

    func getPlayers(gameId: String) async throws -> [Player] { playersToReturn }

    func updatePlayer(_ player: Player, inGame gameId: String) async throws {}
    func removePlayer(id: String, fromGame gameId: String) async throws {}

    /// Delivers `playersToReturn` straight away, then whatever `emitPlayers` sends.
    func listenToPlayers(gameId: String, onChange: @escaping @MainActor (Result<[Player], ListenerFailure>) -> Void) -> ListenerCancellable {
        let registration = MockListenerCancellable()
        playersListeners.append(PlayersListener(gameId: gameId, registration: registration, onChange: onChange))
        let players = playersToReturn
        MainActor.assumeIsolated { onChange(.success(players)) }
        return registration
    }

    // MARK: - Driving Listeners
    //
    // Listeners stay registered, as in the real SDK, so tests can deliver
    // later snapshots, a deleted game and listener failures. A removed
    // registration receives nothing more.

    private struct GameListener {
        let gameId: String
        let registration: MockListenerCancellable
        let onChange: @MainActor (DocumentEvent<Game>) -> Void
    }

    private struct PlayersListener {
        let gameId: String
        let registration: MockListenerCancellable
        let onChange: @MainActor (Result<[Player], ListenerFailure>) -> Void
    }

    private var gameListeners: [GameListener] = []
    private var playersListeners: [PlayersListener] = []

    /// Game listeners attached for `gameId` and not removed since.
    func activeGameListenerCount(gameId: String) -> Int {
        gameListeners.filter { $0.gameId == gameId && !$0.registration.removeCalled }.count
    }

    /// Players listeners attached for `gameId` and not removed since.
    func activePlayersListenerCount(gameId: String) -> Int {
        playersListeners.filter { $0.gameId == gameId && !$0.registration.removeCalled }.count
    }

    /// Sends `event` to every active game listener for `gameId`.
    @MainActor
    func emitGame(_ event: DocumentEvent<Game>, gameId: String) {
        for listener in gameListeners where listener.gameId == gameId && !listener.registration.removeCalled {
            listener.onChange(event)
        }
    }

    /// Sends `result` to every active players listener for `gameId`.
    @MainActor
    func emitPlayers(_ result: Result<[Player], ListenerFailure>, gameId: String) {
        for listener in playersListeners where listener.gameId == gameId && !listener.registration.removeCalled {
            listener.onChange(result)
        }
    }

    // MARK: - Batch Updates

    var batchUpdatePlayersCalls: [([Player], String)] = []

    func batchUpdatePlayers(_ players: [Player], inGame gameId: String) async throws {
        if let error = errorToThrow { throw error }
        batchUpdatePlayersCalls.append((players, gameId))
    }

    // MARK: - Player Customization

    func updatePlayerColor(gameId: String, playerId: String, color: String?) async throws {
        if let error = errorToThrow { throw error }
        updatePlayerColorCalls.append((gameId, playerId, color))
    }
    func updateCommanderName(gameId: String, playerId: String, name: String?) async throws {
        if let error = errorToThrow { throw error }
        updateCommanderNameCalls.append((gameId, playerId, name))
    }
}
