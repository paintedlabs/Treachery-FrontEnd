package com.solomon.treachery.data

import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.firestore.Query
import com.solomon.treachery.model.*
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class FirestoreRepositoryImpl @Inject constructor(
    private val firestore: FirebaseFirestore
) : FirestoreRepository {

    // MARK: - Users

    override suspend fun createUser(user: TreacheryUser) {
        firestore.collection("users")
            .document(user.id)
            .set(user.toMap())
            .await()
    }

    override suspend fun getUser(id: String): TreacheryUser? {
        val doc = firestore.collection("users").document(id).get().await()
        val data = doc.data ?: return null
        return TreacheryUser.fromMap(doc.id, data)
    }

    override suspend fun updateUser(user: TreacheryUser) {
        firestore.collection("users")
            .document(user.id)
            .set(user.toMap())
            .await()
    }

    override suspend fun searchUsers(byDisplayName: String): List<TreacheryUser> {
        val snapshot = firestore.collection("users")
            .whereGreaterThanOrEqualTo("display_name", byDisplayName)
            .whereLessThanOrEqualTo("display_name", byDisplayName + "\uf8ff")
            .limit(20)
            .get()
            .await()
        return snapshot.documents.mapNotNull { doc ->
            doc.data?.let { TreacheryUser.fromMap(doc.id, it) }
        }
    }

    // MARK: - Friend Requests

    override suspend fun sendFriendRequest(request: FriendRequest) {
        firestore.collection("friend_requests")
            .document(request.id)
            .set(request.toMap())
            .await()
    }

    override suspend fun getPendingFriendRequests(forUserId: String): List<FriendRequest> {
        val snapshot = firestore.collection("friend_requests")
            .whereEqualTo("to_user_id", forUserId)
            .whereEqualTo("status", "pending")
            .get()
            .await()
        return snapshot.documents.mapNotNull { doc ->
            doc.data?.let { FriendRequest.fromMap(doc.id, it) }
        }
    }

    override suspend fun updateFriendRequest(request: FriendRequest) {
        firestore.collection("friend_requests")
            .document(request.id)
            .set(request.toMap())
            .await()
    }

    override suspend fun addFriend(userId: String, friendId: String) {
        val usersRef = firestore.collection("users")
        firestore.runBatch { batch ->
            batch.update(usersRef.document(userId), "friend_ids", FieldValue.arrayUnion(friendId))
            batch.update(usersRef.document(friendId), "friend_ids", FieldValue.arrayUnion(userId))
        }.await()
    }

    override suspend fun removeFriend(userId: String, friendId: String) {
        val usersRef = firestore.collection("users")
        firestore.runBatch { batch ->
            batch.update(usersRef.document(userId), "friend_ids", FieldValue.arrayRemove(friendId))
            batch.update(usersRef.document(friendId), "friend_ids", FieldValue.arrayRemove(userId))
        }.await()
    }

    override suspend fun getFriends(forUserId: String): List<TreacheryUser> {
        val user = getUser(forUserId) ?: return emptyList()
        if (user.friendIds.isEmpty()) return emptyList()

        // Firestore whereIn limited to 30 per query
        return user.friendIds.chunked(30).flatMap { chunk ->
            val snapshot = firestore.collection("users")
                .whereIn("__name__", chunk.map { firestore.collection("users").document(it) })
                .get()
                .await()
            snapshot.documents.mapNotNull { doc ->
                doc.data?.let { TreacheryUser.fromMap(doc.id, it) }
            }
        }
    }

    // MARK: - Games

    override suspend fun createGame(game: Game) {
        firestore.collection("games")
            .document(game.id)
            .set(game.toMap())
            .await()
    }

    override suspend fun getGame(id: String): Game? {
        val doc = firestore.collection("games").document(id).get().await()
        val data = doc.data ?: return null
        return Game.fromMap(doc.id, data)
    }

    override suspend fun getGameByCode(code: String): Game? {
        val snapshot = firestore.collection("games")
            .whereEqualTo("code", code)
            .whereEqualTo("state", "waiting")
            .limit(1)
            .get()
            .await()
        val doc = snapshot.documents.firstOrNull() ?: return null
        val data = doc.data ?: return null
        return Game.fromMap(doc.id, data)
    }

    override suspend fun updateGame(game: Game) {
        firestore.collection("games")
            .document(game.id)
            .set(game.toMap())
            .await()
    }

    override suspend fun deleteGame(id: String) {
        firestore.collection("games").document(id).delete().await()
    }

    override suspend fun addPlayerIdToGame(gameId: String, userId: String) {
        firestore.collection("games").document(gameId)
            .update("player_ids", FieldValue.arrayUnion(userId))
            .await()
    }

    override suspend fun getActiveGame(forUserId: String): Game? {
        // Check for waiting games
        val waiting = firestore.collection("games")
            .whereArrayContains("player_ids", forUserId)
            .whereEqualTo("state", "waiting")
            .limit(1)
            .get()
            .await()

        waiting.documents.firstOrNull()?.let { doc ->
            doc.data?.let { return Game.fromMap(doc.id, it) }
        }

        // Check for in-progress games
        val inProgress = firestore.collection("games")
            .whereArrayContains("player_ids", forUserId)
            .whereEqualTo("state", "in_progress")
            .limit(1)
            .get()
            .await()

        inProgress.documents.firstOrNull()?.let { doc ->
            doc.data?.let { return Game.fromMap(doc.id, it) }
        }

        return null
    }

    override suspend fun getFinishedGames(forUserId: String): List<Game> {
        val snapshot = firestore.collection("games")
            .whereArrayContains("player_ids", forUserId)
            .whereEqualTo("state", "finished")
            .orderBy("created_at", Query.Direction.DESCENDING)
            .get()
            .await()
        return snapshot.documents.mapNotNull { doc ->
            doc.data?.let { Game.fromMap(doc.id, it) }
        }
    }

    override fun gameFlow(id: String): Flow<Game?> = callbackFlow {
        val registration = firestore.collection("games").document(id)
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }
                val data = snapshot?.data
                val game = if (data != null) Game.fromMap(snapshot.id, data) else null
                trySend(game)
            }
        awaitClose { registration.remove() }
    }

    // MARK: - Players

    override suspend fun addPlayer(player: Player, gameId: String) {
        firestore.collection("games").document(gameId)
            .collection("players").document(player.id)
            .set(player.toMap())
            .await()
    }

    override suspend fun getPlayers(gameId: String): List<Player> {
        val snapshot = firestore.collection("games").document(gameId)
            .collection("players")
            .orderBy("order_id")
            .get()
            .await()
        return snapshot.documents.mapNotNull { doc ->
            doc.data?.let { Player.fromMap(doc.id, it) }
        }
    }

    override suspend fun updatePlayer(player: Player, gameId: String) {
        firestore.collection("games").document(gameId)
            .collection("players").document(player.id)
            .set(player.toMap())
            .await()
    }

    override suspend fun removePlayer(id: String, gameId: String) {
        firestore.collection("games").document(gameId)
            .collection("players").document(id)
            .delete()
            .await()
    }

    override fun playersFlow(gameId: String): Flow<List<Player>> = callbackFlow {
        val registration = firestore.collection("games").document(gameId)
            .collection("players")
            .orderBy("order_id")
            .addSnapshotListener { snapshot, error ->
                if (error != null) {
                    close(error)
                    return@addSnapshotListener
                }
                val players = snapshot?.documents?.mapNotNull { doc ->
                    doc.data?.let { Player.fromMap(doc.id, it) }
                } ?: emptyList()
                trySend(players)
            }
        awaitClose { registration.remove() }
    }

    // MARK: - Player Customization

    override suspend fun updatePlayerColor(gameId: String, playerId: String, color: String?) {
        val update = if (color != null) {
            mapOf("player_color" to color)
        } else {
            mapOf("player_color" to FieldValue.delete())
        }
        firestore.collection("games").document(gameId)
            .collection("players").document(playerId)
            .update(update)
            .await()
    }

    override suspend fun updateCommanderName(gameId: String, playerId: String, name: String?) {
        val update = if (name != null) {
            mapOf("commander_name" to name)
        } else {
            mapOf("commander_name" to FieldValue.delete())
        }
        firestore.collection("games").document(gameId)
            .collection("players").document(playerId)
            .update(update)
            .await()
    }

}
