//
//  CloudFunctions.swift
//  Treachery-iOS
//
//  Thin wrapper around Firebase Cloud Functions callables.
//

import Foundation
import FirebaseFunctions

struct JoinGameResult {
    let action: String // "joined" or "already_joined"
    let gameId: String
}

extension JoinGameResult {
    /// joinGame answered without a game id, so there is no lobby to open.
    /// JoinGameViewModel words it for the player.
    struct MissingGameIdError: Error {}

    /// Reads the joinGame callable's payload. A missing or empty `gameId`
    /// throws: opening the lobby with "" would hand Firestore an empty
    /// document path, which raises an Objective-C exception Swift can't catch.
    init(payload: Any?) throws {
        let data = payload as? [String: Any] ?? [:]
        guard let gameId = data["gameId"] as? String, !gameId.isEmpty else {
            throw MissingGameIdError()
        }
        self.init(action: data["action"] as? String ?? "joined", gameId: gameId)
    }
}

/// What adjustLife answers with.
struct AdjustLifeResult {
    /// The total the server stored, or nil if the response doesn't say.
    let newLife: Int?
}

extension AdjustLifeResult {
    /// Reads the adjustLife callable's payload, `{ newLife, eliminated,
    /// winner }`. A response without a whole number for `newLife` still
    /// means the change was applied, so it reads as nil instead of throwing.
    init(payload: Any?) {
        let data = payload as? [String: Any]
        self.init(newLife: data?["newLife"] as? Int)
    }
}

/// A callable the server turned down for a reason it explains, as opposed
/// to one that never got an answer. CloudFunctions throws this in place of
/// the SDK error for these codes, so view models can act on the reason
/// without knowing about Firebase; any other failure (offline, a timeout,
/// an internal error) is thrown unchanged.
struct CallableRefusal: Error {
    enum Reason: Equatable {
        /// The game, or the player's seat in it, doesn't exist.
        case notFound
        /// The game isn't in a state that allows the request: it has
        /// started, it's full, it's over, and so on.
        case failedPrecondition
    }

    let reason: Reason
    /// The server's explanation. The callables write these for players,
    /// e.g. "This game is full." or "Player is already eliminated."
    let message: String
}

extension CallableRefusal {
    /// The refusal `error` describes, or nil for any other kind of failure.
    init?(_ error: any Error) {
        let error = error as NSError
        guard error.domain == FunctionsErrorDomain else { return nil }
        let reason: Reason
        let sdkPlaceholder: String
        switch FunctionsErrorCode(rawValue: error.code) {
        case .notFound:
            (reason, sdkPlaceholder) = (.notFound, "NOT FOUND")
        case .failedPrecondition:
            (reason, sdkPlaceholder) = (.failedPrecondition, "FAILED PRECONDITION")
        default:
            return nil
        }
        // Only an answer from a callable explains itself. A bare HTTP
        // status, such as a 404 for a function that isn't deployed, carries
        // just the SDK's placeholder text and must not pass for a refusal:
        // leave() would take a 404 like that as "already gone".
        let message = error.localizedDescription
        guard message != sdkPlaceholder else { return nil }
        self.init(reason: reason, message: message)
    }

    /// The server's own explanation when it turned a request down because
    /// of the game's state, such as "Game is not in progress."; nil for any
    /// other failure, which most likely never reached the server.
    static func explanation(of error: any Error) -> String? {
        guard let refusal = error as? CallableRefusal, refusal.reason == .failedPrecondition else { return nil }
        return refusal.message
    }
}

struct PhenomenonResult {
    let type: String // "resolved" or "choose"
    let newPlaneId: String?
    let isPhenomenon: Bool?
    let options: [[String: Any]]? // For Interplanar Tunnel
    let secondaryPlaneId: String? // For Spatial Merging
}

struct CloudFunctions: CloudFunctionsProtocol {
    private let functions = Functions.functions()

    func createGame(
        gameMode: String,
        maxPlayers: Int,
        startingLife: Int,
        maxTraitorRarity: String? = nil,
        useOwnDeck: Bool = false,
        displayName: String? = nil
    ) async throws -> String {
        let callable = functions.httpsCallable("createGame")
        var data: [String: Any] = [
            "gameMode": gameMode,
            "maxPlayers": maxPlayers,
            "startingLife": startingLife,
            "useOwnDeck": useOwnDeck,
        ]
        if let maxTraitorRarity { data["maxTraitorRarity"] = maxTraitorRarity }
        if let displayName { data["displayName"] = displayName }
        let result = try await callable.call(data)
        let payload = result.data as? [String: Any] ?? [:]
        guard let gameId = payload["gameId"] as? String, !gameId.isEmpty else {
            throw NSError(
                domain: "CloudFunctions",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid createGame response"]
            )
        }
        return gameId
    }

    func joinGame(gameCode: String) async throws -> JoinGameResult {
        let result = try await callFunction("joinGame", ["gameCode": gameCode])
        return try JoinGameResult(payload: result.data)
    }

    func startGame(gameId: String) async throws {
        _ = try await callFunction("startGame", ["gameId": gameId])
    }

    /// Calls a callable, throwing a CallableRefusal when the server turns
    /// the request down with a reason the screens can act on or show.
    private func callFunction(_ name: String, _ data: [String: Any]) async throws -> HTTPSCallableResult {
        do {
            return try await functions.httpsCallable(name).call(data)
        } catch {
            throw CallableRefusal(error) ?? error
        }
    }

    /// Returns the `newLife` adjustLife answers with. A response without it
    /// still means the change was applied, so it isn't treated as a failure.
    func adjustLife(gameId: String, playerId: String, amount: Int) async throws -> Int? {
        let result = try await callFunction("adjustLife", [
            "gameId": gameId,
            "playerId": playerId,
            "amount": amount,
        ])
        return AdjustLifeResult(payload: result.data).newLife
    }

    func eliminatePlayer(gameId: String) async throws {
        _ = try await callFunction("eliminatePlayer", ["gameId": gameId])
    }

    func unveilPlayer(gameId: String) async throws {
        _ = try await callFunction("unveilPlayer", ["gameId": gameId])
    }

    func leaveGame(gameId: String) async throws {
        _ = try await callFunction("leaveGame", ["gameId": gameId])
    }

    // MARK: - Traitor Abilities

    func resolveMetamorph(gameId: String, targetPlayerId: String) async throws {
        _ = try await callFunction("resolveMetamorph", [
            "gameId": gameId,
            "targetPlayerId": targetPlayerId,
        ])
    }

    func resolvePuppetMaster(gameId: String, redistributions: [String: String]) async throws {
        _ = try await callFunction("resolvePuppetMaster", [
            "gameId": gameId,
            "redistributions": redistributions,
        ])
    }

    func resolveWearerOfMasks(gameId: String, chosenCardId: String?) async throws {
        var data: [String: Any] = ["gameId": gameId]
        if let cardId = chosenCardId {
            data["chosenCardId"] = cardId
        }
        _ = try await callFunction("resolveWearerOfMasks", data)
    }

    func registerFcmToken(_ token: String) async throws {
        let callable = functions.httpsCallable("registerFcmToken")
        _ = try await callable.call(["token": token])
    }

    // MARK: - Planechase

    /// Roll the planar die for the given game. Returns the result string
    /// ("blank", "chaos", or "planeswalk") from the Cloud Function.
    func rollPlanarDie(gameId: String) async throws -> String {
        let result = try await callFunction("rollPlanarDie", ["gameId": gameId])
        guard let data = result.data as? [String: Any],
              let dieResult = data["result"] as? String else {
            throw NSError(domain: "CloudFunctions", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid rollPlanarDie response"])
        }
        return dieResult
    }

    /// Resolve the current phenomenon, advancing to the next plane.
    /// Returns a `PhenomenonResult` so the caller can handle Interplanar Tunnel
    /// (choose from options) and Spatial Merging (secondary plane).
    func resolvePhenomenon(gameId: String) async throws -> PhenomenonResult {
        let result = try await callFunction("resolvePhenomenon", ["gameId": gameId])
        let data = result.data as? [String: Any] ?? [:]
        return PhenomenonResult(
            type: data["type"] as? String ?? "resolved",
            newPlaneId: data["newPlaneId"] as? String,
            isPhenomenon: data["isPhenomenon"] as? Bool,
            options: data["options"] as? [[String: Any]],
            secondaryPlaneId: data["secondaryPlaneId"] as? String
        )
    }

    /// Select a specific plane (e.g., from Interplanar Tunnel options).
    func selectPlane(gameId: String, planeId: String) async throws {
        _ = try await callFunction("selectPlane", ["gameId": gameId, "planeId": planeId])
    }

    /// End a non-treachery game (host only). Optionally pass winner user IDs for ELO tracking.
    func endGame(gameId: String, winnerUserIds: [String]? = nil) async throws {
        var data: [String: Any] = ["gameId": gameId]
        if let winners = winnerUserIds, !winners.isEmpty {
            data["winnerUserIds"] = winners
        }
        _ = try await callFunction("endGame", data)
    }

    func updateGameSettings(gameId: String, maxPlayers: Int?, startingLife: Int?, gameMode: String?, maxTraitorRarity: String?) async throws {
        var data: [String: Any] = ["gameId": gameId]
        if let maxPlayers { data["maxPlayers"] = maxPlayers }
        if let startingLife { data["startingLife"] = startingLife }
        if let gameMode { data["gameMode"] = gameMode }
        if let maxTraitorRarity { data["maxTraitorRarity"] = maxTraitorRarity }
        _ = try await callFunction("updateGameSettings", data)
    }

    func acceptFriendRequest(requestId: String) async throws {
        let callable = functions.httpsCallable("acceptFriendRequest")
        _ = try await callable.call(["requestId": requestId])
    }

    func removeFriend(friendId: String) async throws {
        let callable = functions.httpsCallable("removeFriend")
        _ = try await callable.call(["friendId": friendId])
    }
}
