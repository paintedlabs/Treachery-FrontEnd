package com.solomon.treachery.data

import com.google.firebase.functions.FirebaseFunctions
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CloudFunctionsRepositoryImpl @Inject constructor(
    private val functions: FirebaseFunctions
) : CloudFunctionsRepository {

    override suspend fun createGame(
        gameMode: String,
        maxPlayers: Int,
        startingLife: Int,
        maxTraitorRarity: String?,
        useOwnDeck: Boolean,
        displayName: String?
    ): String {
        val data = mutableMapOf<String, Any>(
            "gameMode" to gameMode,
            "maxPlayers" to maxPlayers,
            "startingLife" to startingLife,
            "useOwnDeck" to useOwnDeck
        )
        maxTraitorRarity?.let { data["maxTraitorRarity"] = it }
        displayName?.let { data["displayName"] = it }
        val result = functions.getHttpsCallable("createGame")
            .call(data)
            .await()
        @Suppress("UNCHECKED_CAST")
        val payload = result.getData() as? Map<String, Any?> ?: emptyMap()
        val gameId = payload["gameId"] as? String
            ?: throw IllegalStateException("Invalid createGame response")
        return gameId
    }

    override suspend fun startGame(gameId: String) {
        functions.getHttpsCallable("startGame")
            .call(mapOf("gameId" to gameId))
            .await()
    }

    override suspend fun adjustLife(gameId: String, playerId: String, amount: Int) {
        functions.getHttpsCallable("adjustLife")
            .call(mapOf("gameId" to gameId, "playerId" to playerId, "amount" to amount))
            .await()
    }

    override suspend fun eliminatePlayer(gameId: String) {
        functions.getHttpsCallable("eliminatePlayer")
            .call(mapOf("gameId" to gameId))
            .await()
    }

    override suspend fun unveilPlayer(gameId: String) {
        functions.getHttpsCallable("unveilPlayer")
            .call(mapOf("gameId" to gameId))
            .await()
    }

    override suspend fun resolveMetamorph(gameId: String, targetPlayerId: String) {
        functions.getHttpsCallable("resolveMetamorph")
            .call(mapOf("gameId" to gameId, "targetPlayerId" to targetPlayerId))
            .await()
    }

    override suspend fun resolvePuppetMaster(gameId: String, redistributions: Map<String, String>) {
        functions.getHttpsCallable("resolvePuppetMaster")
            .call(mapOf("gameId" to gameId, "redistributions" to redistributions))
            .await()
    }

    override suspend fun resolveWearerOfMasks(gameId: String, chosenCardId: String?) {
        // Null chosenCardId means the player declined; the server returns early
        // without burning the once-per-game ability_resolved flag.
        val data = mutableMapOf<String, Any>("gameId" to gameId)
        chosenCardId?.let { data["chosenCardId"] = it }
        functions.getHttpsCallable("resolveWearerOfMasks")
            .call(data)
            .await()
    }

    override suspend fun leaveGame(gameId: String) {
        functions.getHttpsCallable("leaveGame")
            .call(mapOf("gameId" to gameId))
            .await()
    }

    override suspend fun registerFcmToken(token: String) {
        functions.getHttpsCallable("registerFcmToken")
            .call(mapOf("token" to token))
            .await()
    }

    override suspend fun rollPlanarDie(gameId: String): String {
        val result = functions.getHttpsCallable("rollPlanarDie")
            .call(mapOf("gameId" to gameId))
            .await()
        @Suppress("UNCHECKED_CAST")
        val data = result.getData() as? Map<String, Any?> ?: emptyMap()
        return data["result"] as? String ?: "blank"
    }

    override suspend fun resolvePhenomenon(gameId: String): Map<String, Any?> {
        val result = functions.getHttpsCallable("resolvePhenomenon")
            .call(mapOf("gameId" to gameId))
            .await()
        @Suppress("UNCHECKED_CAST")
        return result.getData() as? Map<String, Any?> ?: emptyMap()
    }

    override suspend fun selectPlane(gameId: String, planeId: String) {
        functions.getHttpsCallable("selectPlane")
            .call(mapOf("gameId" to gameId, "planeId" to planeId))
            .await()
    }

    override suspend fun joinGame(gameCode: String): Map<String, Any?> {
        val result = functions.getHttpsCallable("joinGame")
            .call(mapOf("gameCode" to gameCode))
            .await()
        @Suppress("UNCHECKED_CAST")
        return result.getData() as? Map<String, Any?> ?: emptyMap()
    }

    override suspend fun endGame(gameId: String, winnerUserIds: List<String>?) {
        val data = mutableMapOf<String, Any>("gameId" to gameId)
        winnerUserIds?.let { data["winnerUserIds"] = it }
        functions.getHttpsCallable("endGame")
            .call(data)
            .await()
    }

    override suspend fun updateGameSettings(gameId: String, maxPlayers: Int?, startingLife: Int?, gameMode: String?, maxTraitorRarity: String?) {
        val data = mutableMapOf<String, Any>("gameId" to gameId)
        maxPlayers?.let { data["maxPlayers"] = it }
        startingLife?.let { data["startingLife"] = it }
        gameMode?.let { data["gameMode"] = it }
        maxTraitorRarity?.let { data["maxTraitorRarity"] = it }
        functions.getHttpsCallable("updateGameSettings")
            .call(data)
            .await()
    }

    override suspend fun acceptFriendRequest(requestId: String) {
        functions.getHttpsCallable("acceptFriendRequest")
            .call(mapOf("requestId" to requestId))
            .await()
    }

    override suspend fun removeFriend(friendId: String) {
        functions.getHttpsCallable("removeFriend")
            .call(mapOf("friendId" to friendId))
            .await()
    }
}
