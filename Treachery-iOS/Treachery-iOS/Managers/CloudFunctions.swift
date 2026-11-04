//
//  CloudFunctions.swift
//  Treachery-iOS
//
//  Thin wrapper around Firebase Cloud Functions callables.
//

import Foundation
import FirebaseAuth
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

/// The `deleteAccount` failures the app tells apart. Every other failure (a
/// server error, or a network failure that can come once the request was
/// sent, such as a lost connection or going offline) propagates unchanged
/// and is treated as retryable.
enum AccountDeletionError: Error, Equatable {
    /// The server refused because the user is in a game that is still in
    /// progress. `message` is the server's sentence telling them they can delete
    /// the account once that game ends; show it verbatim.
    case inProgressGame(message: String)
    /// The request never left this device, so the server deleted nothing.
    /// Only failures that can't come after the request was written count:
    /// - Firebase Auth's: the SDK gets the sign-in token the request
    ///   carries before it builds the request.
    /// - The server's name not resolving (`cannotFindHost`,
    ///   `dnsLookupFailed`), or no connection to it being made
    ///   (`cannotConnectToHost`).
    ///
    /// Being offline (`notConnectedToInternet`) or barred from cellular
    /// data (`dataNotAllowed`, `internationalRoamingOff`) doesn't count:
    /// URLSession also fails a request it already wrote with these when the
    /// network drops mid-request. The server may have that request, so like
    /// a lost connection (`networkConnectionLost`) they're left unmapped:
    /// the outcome is unknown.
    case notSent
    /// The request ran out of time, on the server or on the way there. The
    /// server may have finished anyway; deletion is idempotent, so retrying
    /// completes it either way.
    case timedOut
    /// The server answered with something other than `{ success: true }`.
    case unexpectedResponse
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

    func updateGameSettings(gameId: String, maxPlayers: Int?, startingLife: Int?, gameMode: String?, maxTraitorRarity: String?) async throws {
        let callable = functions.httpsCallable("updateGameSettings")
        var data: [String: Any] = ["gameId": gameId]
        if let maxPlayers { data["maxPlayers"] = maxPlayers }
        if let startingLife { data["startingLife"] = startingLife }
        if let gameMode { data["gameMode"] = gameMode }
        if let maxTraitorRarity { data["maxTraitorRarity"] = maxTraitorRarity }
        _ = try await callable.call(data)
    }

    func acceptFriendRequest(requestId: String) async throws {
        let callable = functions.httpsCallable("acceptFriendRequest")
        _ = try await callable.call(["requestId": requestId])
    }

    func removeFriend(friendId: String) async throws {
        let callable = functions.httpsCallable("removeFriend")
        _ = try await callable.call(["friendId": friendId])
    }

    // MARK: - Account

    func deleteAccount() async throws {
        // The SDK's default 70 s timeout is kept on purpose: it outlasts the
        // function's own 60 s default, so the app normally hears the server's
        // outcome instead of giving up while the server is still working.
        let callable = functions.httpsCallable("deleteAccount")
        let result: HTTPSCallableResult
        do {
            // No arguments: send `{}`, as the contract specifies, rather than null.
            result = try await callable.call([String: Any]())
        } catch {
            throw AccountDeletionError(callableError: error) ?? error
        }
        try Self.validateDeleteAccountResponse(result.data)
    }

    /// Accepts only an explicit `{ success: true }`, the one answer that means
    /// the account is gone, and throws `AccountDeletionError.unexpectedResponse`
    /// for anything else. The caller signs out on success, which must never
    /// happen for an account that still exists.
    static func validateDeleteAccountResponse(_ data: Any?) throws {
        guard let payload = data as? [String: Any], payload["success"] as? Bool == true else {
            throw AccountDeletionError.unexpectedResponse
        }
    }
}

extension AccountDeletionError {
    /// Recognizes the callable errors the app tells apart: the server's
    /// refusal during a live game (`failed-precondition`, whose localized
    /// description is the server's message), a timeout
    /// (`deadline-exceeded`, which the SDK also reports when the request
    /// itself times out), and a request that never left this device.
    /// Returns nil for any other error.
    init?(callableError error: Error) {
        let nsError = error as NSError
        switch nsError.domain {
        case FunctionsErrorDomain:
            switch FunctionsErrorCode(rawValue: nsError.code) {
            case .failedPrecondition:
                self = .inProgressGame(message: nsError.localizedDescription)
            case .deadlineExceeded:
                self = .timedOut
            default:
                return nil
            }
        case AuthErrors.domain:
            // The SDK gets the sign-in token before it builds the request.
            self = .notSent
        case NSURLErrorDomain where Self.noConnectionCodes.contains(URLError.Code(rawValue: nsError.code)):
            self = .notSent
        default:
            return nil
        }
    }

    /// The URL errors that come only before a connection to the server is
    /// made, so before the request is written. See `notSent` for those left
    /// out, and why.
    private static let noConnectionCodes: Set<URLError.Code> = [
        .cannotFindHost,
        .dnsLookupFailed,
        .cannotConnectToHost,
    ]
}
