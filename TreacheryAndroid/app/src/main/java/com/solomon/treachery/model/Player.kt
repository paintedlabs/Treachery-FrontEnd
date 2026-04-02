package com.solomon.treachery.model

import com.google.firebase.Timestamp

data class Player(
    val id: String = "",
    val orderId: Int = 0,
    val userId: String = "",
    val displayName: String = "",
    val role: Role? = null,
    val identityCardId: String? = null,
    val lifeTotal: Int = 40,
    val isEliminated: Boolean = false,
    val isUnveiled: Boolean = false,
    val joinedAt: Timestamp = Timestamp.now(),
    val playerColor: String? = null,
    val commanderName: String? = null,
    val originalIdentityCardId: String? = null,
    val isFaceDown: Boolean = false
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "order_id" to orderId,
        "user_id" to userId,
        "display_name" to displayName,
        "role" to role?.value,
        "identity_card_id" to identityCardId,
        "life_total" to lifeTotal,
        "is_eliminated" to isEliminated,
        "is_unveiled" to isUnveiled,
        "joined_at" to joinedAt,
        "player_color" to playerColor,
        "commander_name" to commanderName,
        "original_identity_card_id" to originalIdentityCardId,
        "is_face_down" to isFaceDown
    )

    companion object {
        fun fromMap(id: String, data: Map<String, Any?>): Player = Player(
            id = id,
            orderId = (data["order_id"] as? Number)?.toInt() ?: 0,
            userId = data["user_id"] as? String ?: "",
            displayName = data["display_name"] as? String ?: "",
            role = (data["role"] as? String)?.let { Role.fromValue(it) },
            identityCardId = data["identity_card_id"] as? String,
            lifeTotal = (data["life_total"] as? Number)?.toInt() ?: 40,
            isEliminated = data["is_eliminated"] as? Boolean ?: false,
            isUnveiled = data["is_unveiled"] as? Boolean ?: false,
            joinedAt = data["joined_at"] as? Timestamp ?: Timestamp.now(),
            playerColor = data["player_color"] as? String,
            commanderName = data["commander_name"] as? String,
            originalIdentityCardId = data["original_identity_card_id"] as? String,
            isFaceDown = data["is_face_down"] as? Boolean ?: false
        )
    }
}
