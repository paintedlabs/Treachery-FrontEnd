package com.solomon.treachery.data

import com.solomon.treachery.ui.util.PlayerColors
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

/**
 * Tests for the PlayerColors palette.
 * Mirrors iOS PlayerColorsTests.
 */
class PlayerColorsTests {

    @Test
    fun `palette has 10 colors`() {
        assertEquals(10, PlayerColors.palette.size)
    }

    @Test
    fun `all colors have non-empty names`() {
        PlayerColors.palette.forEach { color ->
            assertTrue(color.name.isNotBlank(), "Color should have a name")
        }
    }

    @Test
    fun `all colors have valid hex values`() {
        PlayerColors.palette.forEach { color ->
            assertTrue(color.hex.isNotBlank(), "Color '${color.name}' should have a hex value")
            // Hex should be 6 or 7 chars (with or without #)
            val cleaned = color.hex.removePrefix("#")
            assertEquals(6, cleaned.length, "Color '${color.name}' hex should be 6 digits, got '${color.hex}'")
        }
    }

    @Test
    fun `all hex values are unique`() {
        val hexValues = PlayerColors.palette.map { it.hex }
        assertEquals(hexValues.size, hexValues.toSet().size, "Duplicate hex values found")
    }

    @Test
    fun `all names are unique`() {
        val names = PlayerColors.palette.map { it.name }
        assertEquals(names.size, names.toSet().size, "Duplicate color names found")
    }
}
