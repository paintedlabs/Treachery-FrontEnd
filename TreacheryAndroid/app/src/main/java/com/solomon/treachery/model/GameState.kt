package com.solomon.treachery.model

enum class GameState(val value: String) {
    WAITING("waiting"),
    IN_PROGRESS("in_progress"),
    FINISHED("finished");

    companion object {
        fun fromValue(value: String): GameState? = entries.find { it.value == value }
    }
}
