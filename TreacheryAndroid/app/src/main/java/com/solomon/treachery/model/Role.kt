package com.solomon.treachery.model

import androidx.compose.ui.graphics.Color

enum class Role(val value: String) {
    LEADER("leader"),
    GUARDIAN("guardian"),
    ASSASSIN("assassin"),
    TRAITOR("traitor");

    val displayName: String
        get() = when (this) {
            LEADER -> "Leader"
            GUARDIAN -> "Guardian"
            ASSASSIN -> "Assassin"
            TRAITOR -> "Traitor"
        }

    val roleColor: Color
        get() = when (this) {
            LEADER -> Color(0xFFE4C96A)
            GUARDIAN -> Color(0xFF4C8CC9)
            ASSASSIN -> Color(0xFFC94C4C)
            TRAITOR -> Color(0xFF9C4CC9)
        }

    val winConditionText: String
        get() = when (this) {
            LEADER -> "Eliminate all Assassins and Traitors to win."
            GUARDIAN -> "Keep the Leader alive. Eliminate all Assassins and Traitors."
            ASSASSIN -> "Eliminate the Leader while at least one Assassin survives."
            TRAITOR -> "Be the last player standing."
        }

    companion object {
        const val MINIMUM_PLAYER_COUNT = 4

        fun fromValue(value: String): Role? = entries.find { it.value == value }

        fun distribution(playerCount: Int): RoleDistribution = when (playerCount) {
            4 -> RoleDistribution(1, 0, 2, 1)
            5 -> RoleDistribution(1, 1, 2, 1)
            6 -> RoleDistribution(1, 1, 3, 1)
            7 -> RoleDistribution(1, 2, 3, 1)
            8 -> RoleDistribution(1, 2, 3, 2)
            else -> RoleDistribution(1, 0, 2, 1)
        }
    }
}

data class RoleDistribution(
    val leaders: Int,
    val guardians: Int,
    val assassins: Int,
    val traitors: Int
)
