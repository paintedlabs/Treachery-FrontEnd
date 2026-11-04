import Foundation
@testable import Treachery_iOS

final class MockListenerCancellable: ListenerCancellable {
    var removeCalled = false
    func remove() { removeCalled = true }
}

final class MockFirestoreManager: FirestoreManaging {

    // MARK: - Stub data

    var usersToReturn: [String: TreacheryUser] = [:]
    /// What `getUserDocument(id:)` reports. A user id with no entry is
    /// `.complete` when `usersToReturn` holds it, else `.missing`.
    var userDocumentsToReturn: [String: UserDocument] = [:]
    var gamesToReturn: [String: Game] = [:]
    var gameByCodeToReturn: Game?
    var activeGameToReturn: Game?
    var playersToReturn: [Player] = []
    /// Players per game id for `getPlayers(gameId:)`; a game with no entry
    /// gets `playersToReturn`.
    var playersByGameToReturn: [String: [Player]] = [:]
    /// Thrown by `getPlayers(gameId:)` for these game ids only.
    var playersErrorsByGame: [String: Error] = [:]
    var finishedGamesToReturn: [Game] = []
    var friendsToReturn: [TreacheryUser] = []
    var pendingRequestsToReturn: [FriendRequest] = []
    var searchResultsToReturn: [TreacheryUser] = []
    var errorToThrow: Error?
    /// Thrown only by `getUserDocument(id:)`.
    var userDocumentError: Error?
    /// Thrown only by the profile writes: `createUser`, `repairUserProfile`
    /// and `updateDisplayName`.
    var userWriteError: Error?
    /// Runs once inside `updateDisplayName` while the write is in flight, so
    /// a test can act mid-save.
    var whileUpdatingDisplayName: (@MainActor () async -> Void)?

    // MARK: - Call tracking

    var createUserCalls: [(user: TreacheryUser, email: String?, phoneNumber: String?)] = []
    private(set) var repairUserProfileCalls: [(id: String, repair: ProfileRepair)] = []
    private(set) var updateDisplayNameCalls: [(name: String, userId: String)] = []
    var createGameCalls: [Game] = []
    var addPlayerCalls: [(Player, String)] = []
    var updatePlayerColorCalls: [(gameId: String, playerId: String, color: String?)] = []
    var updateCommanderNameCalls: [(gameId: String, playerId: String, name: String?)] = []

    /// How many profile writes were made, so a test can assert there were none.
    var userWriteCount: Int {
        createUserCalls.count + repairUserProfileCalls.count + updateDisplayNameCalls.count
    }

    // MARK: - Users

    func createUser(_ user: TreacheryUser, email: String?, phoneNumber: String?) async throws {
        if let error = errorToThrow ?? userWriteError { throw error }
        createUserCalls.append((user, email, phoneNumber))
    }

    func getUser(id: String) async throws -> TreacheryUser? {
        if let error = errorToThrow { throw error }
        return usersToReturn[id]
    }

    func getUserDocument(id: String) async throws -> UserDocument {
        if let error = errorToThrow ?? userDocumentError { throw error }
        if let document = userDocumentsToReturn[id] { return document }
        return usersToReturn[id].map { .complete($0) } ?? .missing
    }

    func repairUserProfile(id: String, with repair: ProfileRepair) async throws {
        if let error = errorToThrow ?? userWriteError { throw error }
        repairUserProfileCalls.append((id, repair))
    }

    func updateDisplayName(_ name: String, forUserId userId: String) async throws {
        if let inFlight = whileUpdatingDisplayName {
            // One-shot, so a test can't recurse into it by accident.
            whileUpdatingDisplayName = nil
            await inFlight()
        }
        if let error = errorToThrow ?? userWriteError { throw error }
        updateDisplayNameCalls.append((name, userId))
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

    func getPlayers(gameId: String) async throws -> [Player] {
        if let error = playersErrorsByGame[gameId] { throw error }
        return playersByGameToReturn[gameId] ?? playersToReturn
    }

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
