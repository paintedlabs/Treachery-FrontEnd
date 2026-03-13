//
//  FirestoreManager.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation
import FirebaseFirestore

final class FirestoreManager {
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
        return try snapshot.data(as: TreacheryUser.self)
    }

    func updateUser(_ user: TreacheryUser) async throws {
        try usersCollection.document(user.id).setData(from: user, merge: true)
    }

    // MARK: - Games

    func createGame(_ game: Game) async throws {
        try gamesCollection.document(game.id).setData(from: game)
    }

    func getGame(id: String) async throws -> Game? {
        let snapshot = try await gamesCollection.document(id).getDocument()
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

    func listenToGame(id: String, onChange: @escaping (Game?) -> Void) -> ListenerRegistration {
        gamesCollection.document(id).addSnapshotListener { snapshot, _ in
            guard let snapshot = snapshot else { return }
            let game = try? snapshot.data(as: Game.self)
            onChange(game)
        }
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
    ) -> ListenerRegistration {
        playersCollection(gameId: gameId)
            .order(by: "order_id")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot = snapshot else { return }
                let players = snapshot.documents.compactMap {
                    try? $0.data(as: Player.self)
                }
                onChange(players)
            }
    }
}
