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

struct PhenomenonResult {
    let type: String // "resolved" or "choose"
    let newPlaneId: String?
    let isPhenomenon: Bool?
    let options: [[String: Any]]? // For Interplanar Tunnel
    let secondaryPlaneId: String? // For Spatial Merging
}

struct CloudFunctions: CloudFunctionsProtocol {
    private let functions = Functions.functions()

    func joinGame(gameCode: String) async throws -> JoinGameResult {
        let callable = functions.httpsCallable("joinGame")
        let result = try await callable.call(["gameCode": gameCode])
        let data = result.data as? [String: Any] ?? [:]
        return JoinGameResult(
            action: data["action"] as? String ?? "joined",
            gameId: data["gameId"] as? String ?? ""
        )
    }

    func startGame(gameId: String) async throws {
        let callable = functions.httpsCallable("startGame")
        _ = try await callable.call(["gameId": gameId])
    }

    func adjustLife(gameId: String, playerId: String, amount: Int) async throws {
        let callable = functions.httpsCallable("adjustLife")
        _ = try await callable.call([
            "gameId": gameId,
            "playerId": playerId,
            "amount": amount,
        ])
    }

    func eliminatePlayer(gameId: String) async throws {
        let callable = functions.httpsCallable("eliminatePlayer")
        _ = try await callable.call(["gameId": gameId])
    }

    func unveilPlayer(gameId: String) async throws {
        let callable = functions.httpsCallable("unveilPlayer")
        _ = try await callable.call(["gameId": gameId])
    }

    func leaveGame(gameId: String) async throws {
        let callable = functions.httpsCallable("leaveGame")
        _ = try await callable.call(["gameId": gameId])
    }

    // MARK: - Traitor Abilities

    func resolveMetamorph(gameId: String, targetPlayerId: String) async throws {
        let callable = functions.httpsCallable("resolveMetamorph")
        _ = try await callable.call([
            "gameId": gameId,
            "targetPlayerId": targetPlayerId,
        ])
    }

    func resolvePuppetMaster(gameId: String, redistributions: [String: String]) async throws {
        let callable = functions.httpsCallable("resolvePuppetMaster")
        _ = try await callable.call([
            "gameId": gameId,
            "redistributions": redistributions,
        ])
    }

    func resolveWearerOfMasks(gameId: String, chosenCardId: String?) async throws {
        let callable = functions.httpsCallable("resolveWearerOfMasks")
        var data: [String: Any] = ["gameId": gameId]
        if let cardId = chosenCardId {
            data["chosenCardId"] = cardId
        }
        _ = try await callable.call(data)
    }

    func registerFcmToken(_ token: String) async throws {
        let callable = functions.httpsCallable("registerFcmToken")
        _ = try await callable.call(["token": token])
    }

    // MARK: - Planechase

    /// Roll the planar die for the given game. Returns the result string
    /// ("blank", "chaos", or "planeswalk") from the Cloud Function.
    func rollPlanarDie(gameId: String) async throws -> String {
        let callable = functions.httpsCallable("rollPlanarDie")
        let result = try await callable.call(["gameId": gameId])
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
        let callable = functions.httpsCallable("resolvePhenomenon")
        let result = try await callable.call(["gameId": gameId])
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
        let callable = functions.httpsCallable("selectPlane")
        _ = try await callable.call(["gameId": gameId, "planeId": planeId])
    }

    /// End a non-treachery game (host only). Optionally pass winner user IDs for ELO tracking.
    func endGame(gameId: String, winnerUserIds: [String]? = nil) async throws {
        let callable = functions.httpsCallable("endGame")
        var data: [String: Any] = ["gameId": gameId]
        if let winners = winnerUserIds, !winners.isEmpty {
            data["winnerUserIds"] = winners
        }
        _ = try await callable.call(data)
    }
}
