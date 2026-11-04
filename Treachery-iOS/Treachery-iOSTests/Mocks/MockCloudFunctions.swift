import Foundation
@testable import Treachery_iOS

final class MockCloudFunctions: CloudFunctionsProtocol {

    var errorToThrow: Error?
    var rollPlanarDieResult = "blank"
    var resolvePhenomenonResult = PhenomenonResult(
        type: "resolved", newPlaneId: nil, isPhenomenon: nil, options: nil, secondaryPlaneId: nil
    )

    var joinGameResult = JoinGameResult(action: "joined", gameId: "mock-game-id")
    /// When set, joinGame parses this server-shaped payload with the
    /// production parser instead of returning `joinGameResult`.
    var joinGamePayload: [String: Any]?
    var createGameResult = "mock-created-game-id"

    /// When set, these calls wait at the gate until the test releases them,
    /// so a test can act while one is in flight.
    var startGameGate: CallGate?
    var leaveGameGate: CallGate?
    var adjustLifeGate: CallGate?

    /// What adjustLife answers with as the server's new total. Read when the
    /// call returns, so a test can set it while the call is held.
    var adjustLifeNewLife: Int?

    // Call tracking
    var createGameCalls: [(gameMode: String, maxPlayers: Int, startingLife: Int, maxTraitorRarity: String?)] = []
    var joinGameCalls: [String] = []
    var startGameCalls: [String] = []
    var adjustLifeCalls: [(gameId: String, playerId: String, amount: Int)] = []
    var eliminatePlayerCalls: [String] = []
    var unveilPlayerCalls: [String] = []
    var leaveGameCalls: [String] = []
    var endGameCalls: [(gameId: String, winnerUserIds: [String]?)] = []
    var acceptFriendRequestCalls: [String] = []
    var removeFriendCalls: [String] = []

    func createGame(
        gameMode: String,
        maxPlayers: Int,
        startingLife: Int,
        maxTraitorRarity: String?,
        useOwnDeck: Bool,
        displayName: String?
    ) async throws -> String {
        if let error = errorToThrow { throw error }
        createGameCalls.append((gameMode, maxPlayers, startingLife, maxTraitorRarity))
        return createGameResult
    }

    func joinGame(gameCode: String) async throws -> JoinGameResult {
        if let error = errorToThrow { throw error }
        joinGameCalls.append(gameCode)
        if let joinGamePayload {
            return try JoinGameResult(payload: joinGamePayload)
        }
        return joinGameResult
    }

    func startGame(gameId: String) async throws {
        if let startGameGate { await startGameGate.hold() }
        if let error = errorToThrow { throw error }
        startGameCalls.append(gameId)
    }

    /// On the main actor, where the tests read the call log: the board sends
    /// each player's changes separately, so calls can overlap and would
    /// otherwise append to it from several threads at once.
    @MainActor
    func adjustLife(gameId: String, playerId: String, amount: Int) async throws -> Int? {
        if let adjustLifeGate { await adjustLifeGate.hold() }
        if let error = errorToThrow { throw error }
        adjustLifeCalls.append((gameId, playerId, amount))
        return adjustLifeNewLife
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
        if let leaveGameGate { await leaveGameGate.hold() }
        if let error = errorToThrow { throw error }
        leaveGameCalls.append(gameId)
    }

    // Traitor Abilities
    var resolveMetamorphCalls: [(gameId: String, targetPlayerId: String)] = []
    var resolvePuppetMasterCalls: [(gameId: String, redistributions: [String: String])] = []
    var resolveWearerOfMasksCalls: [(gameId: String, chosenCardId: String?)] = []

    func resolveMetamorph(gameId: String, targetPlayerId: String) async throws {
        if let error = errorToThrow { throw error }
        resolveMetamorphCalls.append((gameId, targetPlayerId))
    }

    func resolvePuppetMaster(gameId: String, redistributions: [String: String]) async throws {
        if let error = errorToThrow { throw error }
        resolvePuppetMasterCalls.append((gameId, redistributions))
    }

    func resolveWearerOfMasks(gameId: String, chosenCardId: String?) async throws {
        if let error = errorToThrow { throw error }
        resolveWearerOfMasksCalls.append((gameId, chosenCardId))
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

    struct UpdateGameSettingsCall {
        let gameId: String
        let maxPlayers: Int?
        let startingLife: Int?
        let gameMode: String?
        let maxTraitorRarity: String?
    }

    var updateGameSettingsCalls: [UpdateGameSettingsCall] = []

    func updateGameSettings(gameId: String, maxPlayers: Int?, startingLife: Int?, gameMode: String?, maxTraitorRarity: String?) async throws {
        if let error = errorToThrow { throw error }
        updateGameSettingsCalls.append(UpdateGameSettingsCall(
            gameId: gameId, maxPlayers: maxPlayers, startingLife: startingLife,
            gameMode: gameMode, maxTraitorRarity: maxTraitorRarity
        ))
    }

    func acceptFriendRequest(requestId: String) async throws {
        if let error = errorToThrow { throw error }
        acceptFriendRequestCalls.append(requestId)
    }

    func removeFriend(friendId: String) async throws {
        if let error = errorToThrow { throw error }
        removeFriendCalls.append(friendId)
    }
}
