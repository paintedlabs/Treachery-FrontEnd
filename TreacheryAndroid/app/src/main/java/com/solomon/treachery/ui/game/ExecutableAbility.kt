package com.solomon.treachery.ui.game

// The three traitor identities whose unveil triggers a callable-backed
// follow-up (resolveMetamorph / resolvePuppetMaster / resolveWearerOfMasks).
// Card ids mirror ExecutableAbility.swift (iOS) and AbilityResolver.tsx (web).
enum class ExecutableAbility(val cardId: String) {
    METAMORPH("traitor_07"),
    PUPPET_MASTER("traitor_09"),
    WEARER_OF_MASKS("traitor_13");

    val displayName: String
        get() = when (this) {
            METAMORPH -> "The Metamorph"
            PUPPET_MASTER -> "The Puppet Master"
            WEARER_OF_MASKS -> "The Wearer of Masks"
        }

    companion object {
        fun fromCardId(cardId: String?): ExecutableAbility? =
            cardId?.let { id -> entries.find { it.cardId == id } }
    }
}
