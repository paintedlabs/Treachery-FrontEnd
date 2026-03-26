package com.solomon.treachery.model

enum class Rarity(val value: String) {
    UNCOMMON("uncommon"),
    RARE("rare"),
    MYTHIC("mythic"),
    SPECIAL("special");

    val displayName: String
        get() = when (this) {
            UNCOMMON -> "Uncommon"
            RARE -> "Rare"
            MYTHIC -> "Mythic"
            SPECIAL -> "Special"
        }

    companion object {
        fun fromValue(value: String): Rarity? = entries.find { it.value == value }
    }
}
