package com.solomon.treachery.model

import com.google.firebase.Timestamp

data class Game(
    val id: String = "",
    val code: String = "",
    val hostId: String = "",
    val state: GameState = GameState.WAITING,
    val maxPlayers: Int = 8,
    val startingLife: Int = 40,
    val winningTeam: String? = null,
    val gameMode: GameMode = GameMode.TREACHERY,
    val playerIds: List<String> = emptyList(),
    val createdAt: Timestamp = Timestamp.now(),
    val lastActivityAt: Timestamp? = null,
    val planechase: PlanechaseState? = null,
    val winnerUserIds: List<String> = emptyList()
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "code" to code,
        "host_id" to hostId,
        "state" to state.value,
        "max_players" to maxPlayers,
        "starting_life" to startingLife,
        "winning_team" to winningTeam,
        "game_mode" to gameMode.value,
        "player_ids" to playerIds,
        "created_at" to createdAt,
        "last_activity_at" to lastActivityAt,
        "planechase" to planechase?.toMap(),
        "winner_user_ids" to winnerUserIds
    )

    companion object {
        fun fromMap(id: String, data: Map<String, Any?>): Game = Game(
            id = id,
            code = data["code"] as? String ?: "",
            hostId = data["host_id"] as? String ?: "",
            state = GameState.fromValue(data["state"] as? String ?: "") ?: GameState.WAITING,
            maxPlayers = (data["max_players"] as? Number)?.toInt() ?: 8,
            startingLife = (data["starting_life"] as? Number)?.toInt() ?: 40,
            winningTeam = data["winning_team"] as? String,
            gameMode = GameMode.fromValue(data["game_mode"] as? String ?: "") ?: GameMode.TREACHERY,
            playerIds = (data["player_ids"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            createdAt = data["created_at"] as? Timestamp ?: Timestamp.now(),
            lastActivityAt = data["last_activity_at"] as? Timestamp,
            planechase = (data["planechase"] as? Map<*, *>)?.let {
                @Suppress("UNCHECKED_CAST")
                PlanechaseState.fromMap(it as Map<String, Any?>)
            },
            winnerUserIds = (data["winner_user_ids"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
        )
    }
}
