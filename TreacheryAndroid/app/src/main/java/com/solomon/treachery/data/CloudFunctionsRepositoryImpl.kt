package com.solomon.treachery.data

import com.google.firebase.functions.FirebaseFunctions
import kotlinx.coroutines.tasks.await
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class CloudFunctionsRepositoryImpl @Inject constructor(
    private val functions: FirebaseFunctions
) : CloudFunctionsRepository {

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

    override suspend fun endGame(gameId: String, winnerUserIds: List<String>?) {
        val data = mutableMapOf<String, Any>("gameId" to gameId)
        winnerUserIds?.let { data["winnerUserIds"] = it }
        functions.getHttpsCallable("endGame")
            .call(data)
            .await()
    }
}
