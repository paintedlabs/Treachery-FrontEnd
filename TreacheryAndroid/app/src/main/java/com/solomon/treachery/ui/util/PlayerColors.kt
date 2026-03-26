package com.solomon.treachery.ui.util

import androidx.compose.ui.graphics.Color

data class PlayerColor(
    val name: String,
    val hex: String
) {
    val color: Color
        get() {
            val cleaned = hex.removePrefix("#")
            return Color(android.graphics.Color.parseColor("#$cleaned"))
        }
}

object PlayerColors {
    val palette = listOf(
        PlayerColor("Crimson", "#e74c3c"),
        PlayerColor("Sunset", "#e67e22"),
        PlayerColor("Amber", "#f1c40f"),
        PlayerColor("Emerald", "#2ecc71"),
        PlayerColor("Teal", "#1abc9c"),
        PlayerColor("Sky", "#3498db"),
        PlayerColor("Indigo", "#6c5ce7"),
        PlayerColor("Orchid", "#a855f7"),
        PlayerColor("Rose", "#ec4899"),
        PlayerColor("Silver", "#95a5a6"),
    )
}
