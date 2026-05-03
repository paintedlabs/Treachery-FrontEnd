package com.solomon.treachery.data

import com.solomon.treachery.model.*
import kotlinx.coroutines.flow.Flow

interface FirestoreRepository {
    // Users
    suspend fun createUser(user: TreacheryUser)
    suspend fun getUser(id: String): TreacheryUser?
    suspend fun updateUser(user: TreacheryUser)
    suspend fun searchUsers(byDisplayName: String): List<TreacheryUser>

    // Friend Requests
    suspend fun sendFriendRequest(request: FriendRequest)
    suspend fun getPendingFriendRequests(forUserId: String): List<FriendRequest>
    suspend fun updateFriendRequest(request: FriendRequest)
    suspend fun addFriend(userId: String, friendId: String)
    suspend fun removeFriend(userId: String, friendId: String)
    suspend fun getFriends(forUserId: String): List<TreacheryUser>

    // Games
    suspend fun createGame(game: Game)
    suspend fun getGame(id: String): Game?
    suspend fun getGameByCode(code: String): Game?
    suspend fun updateGame(game: Game)
    suspend fun deleteGame(id: String)
    suspend fun addPlayerIdToGame(gameId: String, userId: String)
    suspend fun getActiveGame(forUserId: String): Game?
    suspend fun getFinishedGames(forUserId: String): List<Game>
    fun gameFlow(id: String): Flow<Game?>

    // Players
    suspend fun addPlayer(player: Player, gameId: String)
    suspend fun getPlayers(gameId: String): List<Player>
    suspend fun updatePlayer(player: Player, gameId: String)
    suspend fun removePlayer(id: String, gameId: String)
    fun playersFlow(gameId: String): Flow<List<Player>>

    // Player customization
    suspend fun updatePlayerColor(gameId: String, playerId: String, color: String?)
    suspend fun updateCommanderName(gameId: String, playerId: String, name: String?)
}
