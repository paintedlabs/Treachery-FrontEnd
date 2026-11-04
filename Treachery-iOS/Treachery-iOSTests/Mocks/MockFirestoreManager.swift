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
    /// Runs once inside `getUser(id:)` after the profile is read and before
    /// it's returned, so a test can change things while an answer that is
    /// now out of date is on its way.
    var whileReturningUser: (@MainActor () async -> Void)?
    /// Thrown only by `getUserDocument(id:)`.
    var userDocumentError: Error?
    /// Thrown only by the profile writes: `createUser`, `repairUserProfile`
    /// and `updateDisplayName`.
    var userWriteError: Error?
    /// Runs once inside `updateDisplayName` while the write is in flight, so
    /// a test can act mid-save.
    var whileUpdatingDisplayName: (@MainActor () async -> Void)?
    /// Thrown only by `getFinishedGames(forUserId:)`.
    var finishedGamesError: Error?
    /// Runs once inside `getFinishedGames(forUserId:)` while the read is in
    /// flight, so a test can look at a screen mid-load.
    var whileGettingFinishedGames: (@MainActor () async -> Void)?
    /// Thrown only by `getFriends(forUserId:)`.
    var friendsError: Error?
    /// Runs once inside `getFriends(forUserId:)` while the read is in flight.
    var whileGettingFriends: (@MainActor () async -> Void)?
    /// Thrown only by `searchUsers(byDisplayName:)`.
    var searchError: Error?
    /// Thrown only by the friend request writes: `sendFriendRequest` and
    /// `updateFriendRequest`.
    var friendRequestWriteError: Error?
    /// Runs once inside `getPendingFriendRequests(forUserId:)` after the
    /// requests are read and before they're returned, so a test can change
    /// things while an answer that is now out of date is on its way.
    var whileReturningPendingFriendRequests: (@MainActor () async -> Void)?

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
        let user = usersToReturn[id]
        if let inFlight = whileReturningUser {
            // One-shot, so a test can't recurse into it by accident.
            whileReturningUser = nil
            await inFlight()
        }
        return user
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

    private(set) var searchUsersCalls: [String] = []

    func searchUsers(byDisplayName name: String) async throws -> [TreacheryUser] {
        searchUsersCalls.append(name)
        if let searchError { throw searchError }
        return searchResultsToReturn
    }

    // MARK: - Friend Requests

    private(set) var sendFriendRequestCalls: [FriendRequest] = []
    private(set) var updateFriendRequestCalls: [FriendRequest] = []

    func sendFriendRequest(_ request: FriendRequest) async throws {
        if let friendRequestWriteError { throw friendRequestWriteError }
        sendFriendRequestCalls.append(request)
    }

    func getPendingFriendRequests(forUserId userId: String) async throws -> [FriendRequest] {
        let requests = pendingRequestsToReturn
        if let inFlight = whileReturningPendingFriendRequests {
            // One-shot, so a test can't recurse into it by accident.
            whileReturningPendingFriendRequests = nil
            await inFlight()
        }
        return requests
    }

    func updateFriendRequest(_ request: FriendRequest) async throws {
        if let friendRequestWriteError { throw friendRequestWriteError }
        updateFriendRequestCalls.append(request)
    }

    func addFriend(userId: String, friendId: String) async throws {}
    func removeFriend(userId: String, friendId: String) async throws {}

    private(set) var getFriendsCallCount = 0

    /// Like the real one, fails when `usersToReturn` has no profile for
    /// `userId`; otherwise returns `friendsToReturn`.
    func getFriends(forUserId userId: String) async throws -> [TreacheryUser] {
        getFriendsCallCount += 1
        if let inFlight = whileGettingFriends {
            // One-shot, so a test can't recurse into it by accident.
            whileGettingFriends = nil
            await inFlight()
        }
        if let friendsError { throw friendsError }
        guard usersToReturn[userId] != nil else { throw FirestoreReadError.profileUnavailable }
        return friendsToReturn
    }

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
    func getFinishedGames(forUserId userId: String) async throws -> [Game] {
        if let inFlight = whileGettingFinishedGames {
            // One-shot, so a test can't recurse into it by accident.
            whileGettingFinishedGames = nil
            await inFlight()
        }
        if let finishedGamesError { throw finishedGamesError }
        return finishedGamesToReturn
    }

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
