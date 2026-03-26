package com.solomon.treachery.model

enum class GameMode(val value: String) {
    TREACHERY("treachery"),
    PLANECHASE("planechase"),
    TREACHERY_PLANECHASE("treachery_planechase"),
    NONE("none");

    val displayName: String
        get() = when (this) {
            TREACHERY -> "Treachery"
            PLANECHASE -> "Planechase"
            TREACHERY_PLANECHASE -> "Both"
            NONE -> "Life Tracker"
        }

    val includesTreachery: Boolean
        get() = this == TREACHERY || this == TREACHERY_PLANECHASE

    val includesPlanechase: Boolean
        get() = this == PLANECHASE || this == TREACHERY_PLANECHASE

    companion object {
        fun fromValue(value: String): GameMode? = entries.find { it.value == value }
    }
}
