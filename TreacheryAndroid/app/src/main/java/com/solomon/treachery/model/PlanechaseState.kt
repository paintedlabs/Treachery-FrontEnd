package com.solomon.treachery.model

data class PlanechaseState(
    val useOwnDeck: Boolean = false,
    val currentPlaneId: String? = null,
    val usedPlaneIds: List<String> = emptyList(),
    val lastDieRollerId: String? = null,
    val dieRollCount: Int = 0,
    val chaoticAetherActive: Boolean = false,
    val secondaryPlaneId: String? = null
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "use_own_deck" to useOwnDeck,
        "current_plane_id" to currentPlaneId,
        "used_plane_ids" to usedPlaneIds,
        "last_die_roller_id" to lastDieRollerId,
        "die_roll_count" to dieRollCount,
        "chaotic_aether_active" to chaoticAetherActive,
        "secondary_plane_id" to secondaryPlaneId
    )

    companion object {
        fun fromMap(data: Map<String, Any?>): PlanechaseState = PlanechaseState(
            useOwnDeck = data["use_own_deck"] as? Boolean ?: false,
            currentPlaneId = data["current_plane_id"] as? String,
            usedPlaneIds = (data["used_plane_ids"] as? List<*>)?.filterIsInstance<String>() ?: emptyList(),
            lastDieRollerId = data["last_die_roller_id"] as? String,
            dieRollCount = (data["die_roll_count"] as? Number)?.toInt() ?: 0,
            chaoticAetherActive = data["chaotic_aether_active"] as? Boolean ?: false,
            secondaryPlaneId = data["secondary_plane_id"] as? String
        )
    }
}
