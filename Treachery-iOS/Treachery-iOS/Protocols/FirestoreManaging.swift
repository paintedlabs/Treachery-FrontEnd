import Foundation

/// A read that found nothing it could show, where an empty or missing
/// answer would otherwise pass for real data.
enum FirestoreReadError: Error, Hashable {
    /// The user's own profile, `users/{uid}`, is missing, incomplete or
    /// can't be decoded: `getUser(id:)` returns nil for it. Signing in
    /// creates or repairs it, so trying again can help.
    case profileUnavailable
    /// The read was made offline and the local cache held nothing for it.
    /// Firestore answers such a query with an empty list, which would read
    /// as "no games" or "no friends" rather than "couldn't load".
    case nothingCachedOffline
}

protocol FirestoreManaging {
    // Users

    /// Creates the public profile `users/{uid}`, and stores the account's
    /// email and phone number, if any, only in the owner-only
    /// `users/{uid}/private/data`.
    func createUser(_ user: TreacheryUser, email: String?, phoneNumber: String?) async throws
    /// The profile for display, or nil when it is missing, incomplete or
    /// can't be decoded. `getUserDocument(id:)` tells those apart.
    func getUser(id: String) async throws -> TreacheryUser?
    /// What `users/{id}` holds, read from the server and never from the local
    /// cache: provisioning decides from it whether to create or repair the
    /// profile, and a stale cached copy could make it overwrite a newer one.
    func getUserDocument(id: String) async throws -> UserDocument
    /// Writes the repair's fields onto an existing `users/{id}` and touches
    /// nothing else. Fails, rather than create the document, if it no longer
    /// exists.
    func repairUserProfile(id: String, with repair: ProfileRepair) async throws
    /// Renames the user by writing `display_name` and nothing else. Fails,
    /// rather than create the document, if the profile doesn't exist.
    func updateDisplayName(_ name: String, forUserId userId: String) async throws
    /// Players whose names start with `name`. Throws
    /// `FirestoreReadError.nothingCachedOffline`, rather than report none,
    /// when offline with no match in the local cache.
    func searchUsers(byDisplayName name: String) async throws -> [TreacheryUser]

    // Friend Requests
    func sendFriendRequest(_ request: FriendRequest) async throws
    func getPendingFriendRequests(forUserId userId: String) async throws -> [FriendRequest]
    func updateFriendRequest(_ request: FriendRequest) async throws
    func addFriend(userId: String, friendId: String) async throws
    func removeFriend(userId: String, friendId: String) async throws
    /// The user's friends, by name. Rather than report no friends, throws
    /// `FirestoreReadError.profileUnavailable` when the user's own profile
    /// is missing or can't be read, and `.nothingCachedOffline` when
    /// offline with none of the friends' profiles in the local cache.
    /// Offline with only some of them cached, returns those.
    func getFriends(forUserId userId: String) async throws -> [TreacheryUser]

    // Games
    func createGame(_ game: Game) async throws
    func getGame(id: String) async throws -> Game?
    func getGame(byCode code: String) async throws -> Game?
    func updateGame(_ game: Game) async throws
    func deleteGame(id: String) async throws
    func addPlayerIdToGame(gameId: String, userId: String) async throws
    func getActiveGame(forUserId userId: String) async throws -> Game?
    /// The user's finished games, newest first. Throws
    /// `FirestoreReadError.nothingCachedOffline`, rather than report none,
    /// when offline with none of them in the local cache.
    func getFinishedGames(forUserId userId: String) async throws -> [Game]
    func listenToGame(id: String, onChange: @escaping (Game?) -> Void) -> ListenerCancellable

    // Players
    func addPlayer(_ player: Player, toGame gameId: String) async throws
    func getPlayers(gameId: String) async throws -> [Player]
    func updatePlayer(_ player: Player, inGame gameId: String) async throws
    func removePlayer(id: String, fromGame gameId: String) async throws
    func listenToPlayers(gameId: String, onChange: @escaping ([Player]) -> Void) -> ListenerCancellable

    // Batch Updates
    func batchUpdatePlayers(_ players: [Player], inGame gameId: String) async throws

    // Player Customization
    func updatePlayerColor(gameId: String, playerId: String, color: String?) async throws
    func updateCommanderName(gameId: String, playerId: String, name: String?) async throws
}
