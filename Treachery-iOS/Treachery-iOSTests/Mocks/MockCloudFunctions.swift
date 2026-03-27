import Foundation
@testable import Treachery_iOS

final class MockCloudFunctions: CloudFunctionsProtocol {

    var errorToThrow: Error?
    var rollPlanarDieResult = "blank"
    var resolvePhenomenonResult = PhenomenonResult(
        type: "resolved", newPlaneId: nil, isPhenomenon: nil, options: nil, secondaryPlaneId: nil
    )

    var joinGameResult = JoinGameResult(action: "joined", gameId: "mock-game-id")

    // Call tracking
    var joinGameCalls: [String] = []
    var startGameCalls: [String] = []
    var adjustLifeCalls: [(gameId: String, playerId: String, amount: Int)] = []
    var eliminatePlayerCalls: [String] = []
    var unveilPlayerCalls: [String] = []
    var leaveGameCalls: [String] = []
    var endGameCalls: [(gameId: String, winnerUserIds: [String]?)] = []

    func joinGame(gameCode: String) async throws -> JoinGameResult {
        if let error = errorToThrow { throw error }
        joinGameCalls.append(gameCode)
        return joinGameResult
    }

    func startGame(gameId: String) async throws {
        if let error = errorToThrow { throw error }
        startGameCalls.append(gameId)
    }

    func adjustLife(gameId: String, playerId: String, amount: Int) async throws {
        if let error = errorToThrow { throw error }
        adjustLifeCalls.append((gameId, playerId, amount))
    }

    func eliminatePlayer(gameId: String) async throws {
        if let error = errorToThrow { throw error }
        eliminatePlayerCalls.append(gameId)
    }

    func unveilPlayer(gameId: String) async throws {
        if let error = errorToThrow { throw error }
        unveilPlayerCalls.append(gameId)
    }

    func leaveGame(gameId: String) async throws {
        if let error = errorToThrow { throw error }
        leaveGameCalls.append(gameId)
    }

    func registerFcmToken(_ token: String) async throws {
        if let error = errorToThrow { throw error }
    }

    func rollPlanarDie(gameId: String) async throws -> String {
        if let error = errorToThrow { throw error }
        return rollPlanarDieResult
    }

    func resolvePhenomenon(gameId: String) async throws -> PhenomenonResult {
        if let error = errorToThrow { throw error }
        return resolvePhenomenonResult
    }

    func selectPlane(gameId: String, planeId: String) async throws {
        if let error = errorToThrow { throw error }
    }

    func endGame(gameId: String, winnerUserIds: [String]?) async throws {
        if let error = errorToThrow { throw error }
        endGameCalls.append((gameId, winnerUserIds))
    }
}
