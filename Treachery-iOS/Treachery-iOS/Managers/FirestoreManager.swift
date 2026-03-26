//
//  FirestoreManager.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation
import FirebaseFirestore

/// Wraps a Firebase ListenerRegistration as a ListenerCancellable.
private struct FirestoreListenerHandle: ListenerCancellable {
    let registration: ListenerRegistration
    func remove() { registration.remove() }
}

final class FirestoreManager: FirestoreManaging {
    private let db = Firestore.firestore()

    // MARK: - Collection References

    private var usersCollection: CollectionReference { db.collection("users") }
    private var gamesCollection: CollectionReference { db.collection("games") }

    private func playersCollection(gameId: String) -> CollectionReference {
        gamesCollection.document(gameId).collection("players")
    }

    // MARK: - Users

    func createUser(_ user: TreacheryUser) async throws {
        try usersCollection.document(user.id).setData(from: user)
    }

    func getUser(id: String) async throws -> TreacheryUser? {
        let snapshot = try await usersCollection.document(id).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: TreacheryUser.self)
    }

    func updateUser(_ user: TreacheryUser) async throws {
        try usersCollection.document(user.id).setData(from: user, merge: true)
    }

    func searchUsers(byDisplayName name: String) async throws -> [TreacheryUser] {
        let end = name + "\u{f8ff}"
        let snapshot = try await usersCollection
            .whereField("display_name", isGreaterThanOrEqualTo: name)
            .whereField("display_name", isLessThan: end)
            .limit(to: 20)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: TreacheryUser.self) }
    }

    // MARK: - Friend Requests

    private var friendRequestsCollection: CollectionReference {
        db.collection("friend_requests")
    }

    func sendFriendRequest(_ request: FriendRequest) async throws {
        try friendRequestsCollection.document(request.id).setData(from: request)
    }

    func getPendingFriendRequests(forUserId userId: String) async throws -> [FriendRequest] {
        let snapshot = try await friendRequestsCollection
            .whereField("to_user_id", isEqualTo: userId)
            .whereField("status", isEqualTo: "pending")
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: FriendRequest.self) }
    }

    func updateFriendRequest(_ request: FriendRequest) async throws {
        try friendRequestsCollection.document(request.id).setData(from: request, merge: true)
    }

    func addFriend(userId: String, friendId: String) async throws {
        try await usersCollection.document(userId).updateData([
            "friend_ids": FieldValue.arrayUnion([friendId])
        ])
        try await usersCollection.document(friendId).updateData([
            "friend_ids": FieldValue.arrayUnion([userId])
        ])
    }

    func removeFriend(userId: String, friendId: String) async throws {
        try await usersCollection.document(userId).updateData([
            "friend_ids": FieldValue.arrayRemove([friendId])
        ])
        try await usersCollection.document(friendId).updateData([
            "friend_ids": FieldValue.arrayRemove([userId])
        ])
    }

    func getFriends(forUserId userId: String) async throws -> [TreacheryUser] {
        guard let user = try await getUser(id: userId) else { return [] }
        guard !user.friendIds.isEmpty else { return [] }

        // Run all batch queries in parallel
        let chunks = stride(from: 0, to: user.friendIds.count, by: 30).map { start in
            Array(user.friendIds[start..<min(start + 30, user.friendIds.count)])
        }

        let friends = try await withThrowingTaskGroup(of: [TreacheryUser].self) { group in
            for ids in chunks {
                group.addTask {
                    let snapshot = try await self.usersCollection
                        .whereField(FieldPath.documentID(), in: ids)
                        .getDocuments()
                    return snapshot.documents.compactMap { try? $0.data(as: TreacheryUser.self) }
                }
            }
            var result: [TreacheryUser] = []
            for try await batch in group {
                result += batch
            }
            return result
        }
        return friends.sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Games

    func createGame(_ game: Game) async throws {
        try gamesCollection.document(game.id).setData(from: game)
    }

    func getGame(id: String) async throws -> Game? {
        let snapshot = try await gamesCollection.document(id).getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: Game.self)
    }

    func getGame(byCode code: String) async throws -> Game? {
        let snapshot = try await gamesCollection
            .whereField("code", isEqualTo: code)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first?.data(as: Game.self)
    }

    func updateGame(_ game: Game) async throws {
        try gamesCollection.document(game.id).setData(from: game, merge: true)
    }

    func deleteGame(id: String) async throws {
        try await gamesCollection.document(id).delete()
    }

    func addPlayerIdToGame(gameId: String, userId: String) async throws {
        try await gamesCollection.document(gameId).updateData([
            "player_ids": FieldValue.arrayUnion([userId])
        ])
    }

    func getActiveGame(forUserId userId: String) async throws -> Game? {
        // Check in_progress games first
        let inProgressSnapshot = try await gamesCollection
            .whereField("player_ids", arrayContains: userId)
            .whereField("state", isEqualTo: "in_progress")
            .limit(to: 1)
            .getDocuments()
        if let doc = inProgressSnapshot.documents.first {
            return try doc.data(as: Game.self)
        }

        // Then check waiting games
        let waitingSnapshot = try await gamesCollection
            .whereField("player_ids", arrayContains: userId)
            .whereField("state", isEqualTo: "waiting")
            .limit(to: 1)
            .getDocuments()
        if let doc = waitingSnapshot.documents.first {
            return try doc.data(as: Game.self)
        }

        return nil
    }

    func getFinishedGames(forUserId userId: String) async throws -> [Game] {
        let snapshot = try await gamesCollection
            .whereField("player_ids", arrayContains: userId)
            .whereField("state", isEqualTo: "finished")
            .order(by: "created_at", descending: true)
            .limit(to: 50)
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Game.self) }
    }

    func listenToGame(id: String, onChange: @escaping (Game?) -> Void) -> ListenerCancellable {
        let reg = gamesCollection.document(id).addSnapshotListener { snapshot, _ in
            guard let snapshot = snapshot else { return }
            let game = try? snapshot.data(as: Game.self)
            onChange(game)
        }
        return FirestoreListenerHandle(registration: reg)
    }

    // MARK: - Players

    func addPlayer(_ player: Player, toGame gameId: String) async throws {
        try playersCollection(gameId: gameId)
            .document(player.id)
            .setData(from: player)
    }

    func getPlayers(gameId: String) async throws -> [Player] {
        let snapshot = try await playersCollection(gameId: gameId)
            .order(by: "order_id")
            .getDocuments()
        return snapshot.documents.compactMap { try? $0.data(as: Player.self) }
    }

    func updatePlayer(_ player: Player, inGame gameId: String) async throws {
        try playersCollection(gameId: gameId)
            .document(player.id)
            .setData(from: player, merge: true)
    }

    func removePlayer(id: String, fromGame gameId: String) async throws {
        try await playersCollection(gameId: gameId).document(id).delete()
    }

    func listenToPlayers(
        gameId: String,
        onChange: @escaping ([Player]) -> Void
    ) -> ListenerCancellable {
        let reg = playersCollection(gameId: gameId)
            .order(by: "order_id")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot = snapshot else { return }
                let players = snapshot.documents.compactMap {
                    try? $0.data(as: Player.self)
                }
                onChange(players)
            }
        return FirestoreListenerHandle(registration: reg)
    }

    // MARK: - Player Customization

    func updatePlayerColor(gameId: String, playerId: String, color: String?) async throws {
        if let color = color {
            try await playersCollection(gameId: gameId).document(playerId).updateData(["player_color": color])
        } else {
            try await playersCollection(gameId: gameId).document(playerId).updateData(["player_color": FieldValue.delete()])
        }
    }

    func updateCommanderName(gameId: String, playerId: String, name: String?) async throws {
        if let name = name, !name.isEmpty {
            try await playersCollection(gameId: gameId).document(playerId).updateData(["commander_name": name])
        } else {
            try await playersCollection(gameId: gameId).document(playerId).updateData(["commander_name": FieldValue.delete()])
        }
    }
}
