package com.solomon.treachery.mocks

import com.solomon.treachery.data.CloudFunctionsRepository

class MockCloudFunctionsRepository : CloudFunctionsRepository {

    // Configurable results
    var rollPlanarDieResult: String = "blank"
    var resolvePhenomenonResult: Map<String, Any?> = mapOf("type" to "resolved")
    var errorToThrow: Exception? = null

    // Call tracking
    val startGameCalls = mutableListOf<String>()
    val adjustLifeCalls = mutableListOf<Triple<String, String, Int>>()
    val eliminatePlayerCalls = mutableListOf<String>()
    val unveilPlayerCalls = mutableListOf<String>()
    val leaveGameCalls = mutableListOf<String>()
    val registerFcmTokenCalls = mutableListOf<String>()
    val rollPlanarDieCalls = mutableListOf<String>()
    val resolvePhenomenonCalls = mutableListOf<String>()
    val selectPlaneCalls = mutableListOf<Pair<String, String>>()
    val endGameCalls = mutableListOf<Pair<String, List<String>?>>()

    private fun throwIfNeeded() {
        errorToThrow?.let { throw it }
    }

    override suspend fun startGame(gameId: String) {
        throwIfNeeded()
        startGameCalls.add(gameId)
    }

    override suspend fun adjustLife(gameId: String, playerId: String, amount: Int) {
        throwIfNeeded()
        adjustLifeCalls.add(Triple(gameId, playerId, amount))
    }

    override suspend fun eliminatePlayer(gameId: String) {
        throwIfNeeded()
        eliminatePlayerCalls.add(gameId)
    }

    override suspend fun unveilPlayer(gameId: String) {
        throwIfNeeded()
        unveilPlayerCalls.add(gameId)
    }

    override suspend fun leaveGame(gameId: String) {
        throwIfNeeded()
        leaveGameCalls.add(gameId)
    }

    override suspend fun registerFcmToken(token: String) {
        throwIfNeeded()
        registerFcmTokenCalls.add(token)
    }

    override suspend fun rollPlanarDie(gameId: String): String {
        throwIfNeeded()
        rollPlanarDieCalls.add(gameId)
        return rollPlanarDieResult
    }

    override suspend fun resolvePhenomenon(gameId: String): Map<String, Any?> {
        throwIfNeeded()
        resolvePhenomenonCalls.add(gameId)
        return resolvePhenomenonResult
    }

    override suspend fun selectPlane(gameId: String, planeId: String) {
        throwIfNeeded()
        selectPlaneCalls.add(gameId to planeId)
    }

    override suspend fun endGame(gameId: String, winnerUserIds: List<String>?) {
        throwIfNeeded()
        endGameCalls.add(gameId to winnerUserIds)
    }
}
