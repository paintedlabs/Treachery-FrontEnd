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

    func listenToGame(id: String, onChange: @escaping (Game?) -> Void) -> ListenerCancellable {
        onChange(gamesToReturn[id])
        return MockListenerCancellable()
    }

    // MARK: - Players

    func addPlayer(_ player: Player, toGame gameId: String) async throws {
        if let error = errorToThrow { throw error }
        addPlayerCalls.append((player, gameId))
    }

    func getPlayers(gameId: String) async throws -> [Player] { playersToReturn }

    func updatePlayer(_ player: Player, inGame gameId: String) async throws {}
    func removePlayer(id: String, fromGame gameId: String) async throws {}

    func listenToPlayers(gameId: String, onChange: @escaping ([Player]) -> Void) -> ListenerCancellable {
        onChange(playersToReturn)
        return MockListenerCancellable()
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
