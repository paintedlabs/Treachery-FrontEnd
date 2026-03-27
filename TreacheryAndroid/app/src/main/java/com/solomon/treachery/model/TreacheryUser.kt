package com.solomon.treachery.model

import com.google.firebase.Timestamp

data class TreacheryUser(
    val id: String = "",
    val displayName: String = "",
    val email: String? = null,
    val phoneNumber: String? = null,
    val friendIds: List<String> = emptyList(),
    val fcmToken: String? = null,
    val createdAt: Timestamp = Timestamp.now(),
    val elo: Int = 1500,
    val deckStats: Map<String, DeckStat>? = null
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "display_name" to displayName,
        "email" to email,
        "phone_number" to phoneNumber,
        "friend_ids" to friendIds,
        "fcm_token" to fcmToken,
        "created_at" to createdAt,
        "elo" to elo,
        "deck_stats" to deckStats?.mapValues { it.value.toMap() }
    )

    companion object {
        fun fromMap(id: String, data: Map<String, Any?>): TreacheryUser = TreacheryUser(
            id = id,
            displayName = data["display_name"] as? String ?: "",
            email = data["email"] as? String,
            phoneNumber = data["phone_number"] as? String,
            friendIds = (data["friend_ids"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            fcmToken = data["fcm_token"] as? String,
            createdAt = data["created_at"] as? Timestamp ?: Timestamp.now(),
            elo = (data["elo"] as? Number)?.toInt() ?: 1500,
            deckStats = (data["deck_stats"] as? Map<*, *>)?.entries?.associate { (k, v) ->
                k.toString() to DeckStat.fromMap(v as? Map<String, Any?> ?: emptyMap())
            }
        )
    }
}

data class DeckStat(
    val elo: Int = 1500,
    val wins: Int = 0,
    val losses: Int = 0,
    val games: Int = 0
) {
    fun toMap(): Map<String, Any> = mapOf(
        "elo" to elo,
        "wins" to wins,
        "losses" to losses,
        "games" to games
    )

    companion object {
        fun fromMap(data: Map<String, Any?>): DeckStat = DeckStat(
            elo = (data["elo"] as? Number)?.toInt() ?: 1500,
            wins = (data["wins"] as? Number)?.toInt() ?: 0,
            losses = (data["losses"] as? Number)?.toInt() ?: 0,
            games = (data["games"] as? Number)?.toInt() ?: 0
        )
    }
}
