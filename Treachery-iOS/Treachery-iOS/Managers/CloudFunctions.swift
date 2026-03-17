//
//  CloudFunctions.swift
//  Treachery-iOS
//
//  Thin wrapper around Firebase Cloud Functions callables.
//

import Foundation
import FirebaseFunctions

struct CloudFunctions {
    private let functions = Functions.functions()

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
    func resolvePhenomenon(gameId: String) async throws {
        let callable = functions.httpsCallable("resolvePhenomenon")
        _ = try await callable.call(["gameId": gameId])
    }

    /// End a non-treachery game (host only).
    func endGame(gameId: String) async throws {
        let callable = functions.httpsCallable("endGame")
        _ = try await callable.call(["gameId": gameId])
    }
}
