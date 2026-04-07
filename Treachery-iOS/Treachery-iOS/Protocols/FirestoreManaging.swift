import Foundation

protocol FirestoreManaging {
    // Users
    func createUser(_ user: TreacheryUser) async throws
    func getUser(id: String) async throws -> TreacheryUser?
    func updateUser(_ user: TreacheryUser) async throws
    func searchUsers(byDisplayName name: String) async throws -> [TreacheryUser]

    // Friend Requests
    func sendFriendRequest(_ request: FriendRequest) async throws
    func getPendingFriendRequests(forUserId userId: String) async throws -> [FriendRequest]
    func updateFriendRequest(_ request: FriendRequest) async throws
    func addFriend(userId: String, friendId: String) async throws
    func removeFriend(userId: String, friendId: String) async throws
    func getFriends(forUserId userId: String) async throws -> [TreacheryUser]

    // Games
    func createGame(_ game: Game) async throws
    func getGame(id: String) async throws -> Game?
    func getGame(byCode code: String) async throws -> Game?
    func updateGame(_ game: Game) async throws
    func deleteGame(id: String) async throws
    func addPlayerIdToGame(gameId: String, userId: String) async throws
    func getActiveGame(forUserId userId: String) async throws -> Game?
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
    func updatePlayerReady(gameId: String, playerId: String, isReady: Bool) async throws
}
