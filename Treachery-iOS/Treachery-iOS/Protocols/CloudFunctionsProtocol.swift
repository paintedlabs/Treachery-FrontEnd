import Foundation

protocol CloudFunctionsProtocol {
    func createGame(
        gameMode: String,
        maxPlayers: Int,
        startingLife: Int,
        maxTraitorRarity: String?,
        useOwnDeck: Bool,
        displayName: String?
    ) async throws -> String
    func joinGame(gameCode: String) async throws -> JoinGameResult
    func startGame(gameId: String) async throws
    func adjustLife(gameId: String, playerId: String, amount: Int) async throws
    func eliminatePlayer(gameId: String) async throws
    func unveilPlayer(gameId: String) async throws
    func leaveGame(gameId: String) async throws
    func resolveMetamorph(gameId: String, targetPlayerId: String) async throws
    func resolvePuppetMaster(gameId: String, redistributions: [String: String]) async throws
    func resolveWearerOfMasks(gameId: String, chosenCardId: String?) async throws
    func registerFcmToken(_ token: String) async throws
    func rollPlanarDie(gameId: String) async throws -> String
    func resolvePhenomenon(gameId: String) async throws -> PhenomenonResult
    func selectPlane(gameId: String, planeId: String) async throws
    func endGame(gameId: String, winnerUserIds: [String]?) async throws
    func updateGameSettings(gameId: String, maxPlayers: Int?, startingLife: Int?, gameMode: String?, maxTraitorRarity: String?) async throws
    func acceptFriendRequest(requestId: String) async throws
    func removeFriend(friendId: String) async throws
    /// Permanently deletes the signed-in user's account and data on the
    /// server. Returns only once the server confirms. Throws
    /// `AccountDeletionError.inProgressGame` while the user is in a game that
    /// is still in progress, `.notSent` only when the request certainly never
    /// left this device (see `AccountDeletionError.notSent`: Auth token
    /// failures and DNS or connect failures, not being offline), `.timedOut`
    /// when it ran out of time, and `.unexpectedResponse` when the call
    /// returns a result other than `{ success: true }`. Any other error,
    /// including the server's own error answers, leaves the outcome unknown.
    /// Safe to retry: the server side is idempotent.
    func deleteAccount() async throws
}
