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
}
