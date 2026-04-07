package com.solomon.treachery.data

interface CloudFunctionsRepository {
    suspend fun startGame(gameId: String)
    suspend fun adjustLife(gameId: String, playerId: String, amount: Int)
    suspend fun eliminatePlayer(gameId: String)
    suspend fun unveilPlayer(gameId: String)
    suspend fun leaveGame(gameId: String)
    suspend fun registerFcmToken(token: String)
    suspend fun rollPlanarDie(gameId: String): String
    suspend fun resolvePhenomenon(gameId: String): Map<String, Any?>
    suspend fun selectPlane(gameId: String, planeId: String)
    suspend fun joinGame(gameCode: String): Map<String, Any?>
    suspend fun endGame(gameId: String, winnerUserIds: List<String>?)
    suspend fun updateGameSettings(gameId: String, maxPlayers: Int?, startingLife: Int?, gameMode: String?)
}
