package com.solomon.treachery.model

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class RarityTests {

    @Test
    fun `all cases exist`() {
        assertEquals(4, Rarity.entries.size)
    }

    @Test
    fun `raw values match expected strings`() {
        assertEquals("uncommon", Rarity.UNCOMMON.value)
        assertEquals("rare", Rarity.RARE.value)
        assertEquals("mythic", Rarity.MYTHIC.value)
        assertEquals("special", Rarity.SPECIAL.value)
    }

    @Test
    fun `display names are human readable`() {
        assertEquals("Uncommon", Rarity.UNCOMMON.displayName)
        assertEquals("Rare", Rarity.RARE.displayName)
        assertEquals("Mythic", Rarity.MYTHIC.displayName)
        assertEquals("Special", Rarity.SPECIAL.displayName)
    }

    @Test
    fun `fromValue returns correct rarity`() {
        Rarity.entries.forEach { rarity ->
            assertEquals(rarity, Rarity.fromValue(rarity.value))
        }
    }

    @Test
    fun `fromValue returns null for unknown value`() {
        assertNull(Rarity.fromValue("unknown"))
        assertNull(Rarity.fromValue(""))
    }
}
