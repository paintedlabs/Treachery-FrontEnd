import Foundation

protocol CloudFunctionsProtocol {
    func joinGame(gameCode: String) async throws -> JoinGameResult
    func startGame(gameId: String) async throws
    func adjustLife(gameId: String, playerId: String, amount: Int) async throws
    func eliminatePlayer(gameId: String) async throws
    func unveilPlayer(gameId: String) async throws
    func leaveGame(gameId: String) async throws
    func registerFcmToken(_ token: String) async throws
    func rollPlanarDie(gameId: String) async throws -> String
    func resolvePhenomenon(gameId: String) async throws -> PhenomenonResult
    func selectPlane(gameId: String, planeId: String) async throws
    func endGame(gameId: String, winnerUserIds: [String]?) async throws
}
