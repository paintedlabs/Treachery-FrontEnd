package com.solomon.treachery.mocks

import com.solomon.treachery.data.FirestoreRepository
import com.solomon.treachery.model.*
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow

class MockFirestoreRepository : FirestoreRepository {

    // Stub data
    var usersToReturn: MutableMap<String, TreacheryUser> = mutableMapOf()
    var gamesToReturn: MutableMap<String, Game> = mutableMapOf()
    var playersByGame: MutableMap<String, MutableList<Player>> = mutableMapOf()
    var friendRequestsToReturn: MutableList<FriendRequest> = mutableListOf()
    var friendsToReturn: MutableList<TreacheryUser> = mutableListOf()
    var searchUsersToReturn: List<TreacheryUser> = emptyList()
    var activeGameToReturn: Game? = null
    var finishedGamesToReturn: List<Game> = emptyList()
    var errorToThrow: Exception? = null

    // Call tracking
    val createUserCalls = mutableListOf<TreacheryUser>()
    val updateUserCalls = mutableListOf<TreacheryUser>()
    val createGameCalls = mutableListOf<Game>()
    val updateGameCalls = mutableListOf<Game>()
    val deleteGameCalls = mutableListOf<String>()
    val addPlayerCalls = mutableListOf<Pair<Player, String>>()
    val updatePlayerCalls = mutableListOf<Pair<Player, String>>()
    val removePlayerCalls = mutableListOf<Pair<String, String>>()
    val addPlayerIdCalls = mutableListOf<Pair<String, String>>()
    val updatePlayerColorCalls = mutableListOf<Triple<String, String, String?>>()
    val updateCommanderNameCalls = mutableListOf<Triple<String, String, String?>>()
    val sendFriendRequestCalls = mutableListOf<FriendRequest>()
    val addFriendCalls = mutableListOf<Pair<String, String>>()
    val removeFriendCalls = mutableListOf<Pair<String, String>>()

    // Flow sources for real-time listeners
    val gameFlowSource = MutableStateFlow<Game?>(null)
    val playersFlowSource = MutableStateFlow<List<Player>>(emptyList())

    private fun throwIfNeeded() {
        errorToThrow?.let { throw it }
    }

    // Users
    override suspend fun createUser(user: TreacheryUser) {
        throwIfNeeded()
        createUserCalls.add(user)
        usersToReturn[user.id] = user
    }

    override suspend fun getUser(id: String): TreacheryUser? {
        throwIfNeeded()
        return usersToReturn[id]
    }

    override suspend fun updateUser(user: TreacheryUser) {
        throwIfNeeded()
        updateUserCalls.add(user)
        usersToReturn[user.id] = user
    }

    override suspend fun searchUsers(byDisplayName: String): List<TreacheryUser> {
        throwIfNeeded()
        return searchUsersToReturn
    }

    // Friend Requests
    override suspend fun sendFriendRequest(request: FriendRequest) {
        throwIfNeeded()
        sendFriendRequestCalls.add(request)
    }

    override suspend fun getPendingFriendRequests(forUserId: String): List<FriendRequest> {
        throwIfNeeded()
        return friendRequestsToReturn.filter { it.toUserId == forUserId && it.status == FriendRequestStatus.PENDING }
    }

    override suspend fun updateFriendRequest(request: FriendRequest) {
        throwIfNeeded()
    }

    override suspend fun addFriend(userId: String, friendId: String) {
        throwIfNeeded()
        addFriendCalls.add(userId to friendId)
    }

    override suspend fun removeFriend(userId: String, friendId: String) {
        throwIfNeeded()
        removeFriendCalls.add(userId to friendId)
    }

    override suspend fun getFriends(forUserId: String): List<TreacheryUser> {
        throwIfNeeded()
        return friendsToReturn
    }

    // Games
    override suspend fun createGame(game: Game) {
        throwIfNeeded()
        createGameCalls.add(game)
        gamesToReturn[game.id] = game
    }

    override suspend fun getGame(id: String): Game? {
        throwIfNeeded()
        return gamesToReturn[id]
    }

    override suspend fun getGameByCode(code: String): Game? {
        throwIfNeeded()
        return gamesToReturn.values.find { it.code == code }
    }

    override suspend fun updateGame(game: Game) {
        throwIfNeeded()
        updateGameCalls.add(game)
        gamesToReturn[game.id] = game
    }

    override suspend fun deleteGame(id: String) {
        throwIfNeeded()
        deleteGameCalls.add(id)
        gamesToReturn.remove(id)
    }

    override suspend fun addPlayerIdToGame(gameId: String, userId: String) {
        throwIfNeeded()
        addPlayerIdCalls.add(gameId to userId)
    }

    override suspend fun getActiveGame(forUserId: String): Game? {
        throwIfNeeded()
        return activeGameToReturn
    }

    override suspend fun getFinishedGames(forUserId: String): List<Game> {
        throwIfNeeded()
        return finishedGamesToReturn
    }

    override fun gameFlow(id: String): Flow<Game?> = gameFlowSource

    // Players
    override suspend fun addPlayer(player: Player, gameId: String) {
        throwIfNeeded()
        addPlayerCalls.add(player to gameId)
        playersByGame.getOrPut(gameId) { mutableListOf() }.add(player)
    }

    override suspend fun getPlayers(gameId: String): List<Player> {
        throwIfNeeded()
        return playersByGame[gameId] ?: emptyList()
    }

    override suspend fun updatePlayer(player: Player, gameId: String) {
        throwIfNeeded()
        updatePlayerCalls.add(player to gameId)
    }

    override suspend fun removePlayer(id: String, gameId: String) {
        throwIfNeeded()
        removePlayerCalls.add(id to gameId)
        playersByGame[gameId]?.removeAll { it.id == id }
    }

    override fun playersFlow(gameId: String): Flow<List<Player>> = playersFlowSource

    // Player customization
    override suspend fun updatePlayerColor(gameId: String, playerId: String, color: String?) {
        throwIfNeeded()
        updatePlayerColorCalls.add(Triple(gameId, playerId, color))
    }

    override suspend fun updateCommanderName(gameId: String, playerId: String, name: String?) {
        throwIfNeeded()
        updateCommanderNameCalls.add(Triple(gameId, playerId, name))
    }

}
