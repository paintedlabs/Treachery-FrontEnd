package com.solomon.treachery.model

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class GameModeTests {

    @Test
    fun `all cases exist`() {
        assertEquals(4, GameMode.entries.size)
    }

    @Test
    fun `raw values match expected strings`() {
        assertEquals("treachery", GameMode.TREACHERY.value)
        assertEquals("planechase", GameMode.PLANECHASE.value)
        assertEquals("treachery_planechase", GameMode.TREACHERY_PLANECHASE.value)
        assertEquals("none", GameMode.NONE.value)
    }

    @Test
    fun `display names are human readable`() {
        assertEquals("Treachery", GameMode.TREACHERY.displayName)
        assertEquals("Planechase", GameMode.PLANECHASE.displayName)
        assertEquals("Both", GameMode.TREACHERY_PLANECHASE.displayName)
        assertEquals("Life Tracker", GameMode.NONE.displayName)
    }

    @Test
    fun `includesTreachery is correct`() {
        assertTrue(GameMode.TREACHERY.includesTreachery)
        assertFalse(GameMode.PLANECHASE.includesTreachery)
        assertTrue(GameMode.TREACHERY_PLANECHASE.includesTreachery)
        assertFalse(GameMode.NONE.includesTreachery)
    }

    @Test
    fun `includesPlanechase is correct`() {
        assertFalse(GameMode.TREACHERY.includesPlanechase)
        assertTrue(GameMode.PLANECHASE.includesPlanechase)
        assertTrue(GameMode.TREACHERY_PLANECHASE.includesPlanechase)
        assertFalse(GameMode.NONE.includesPlanechase)
    }

    @Test
    fun `fromValue returns correct mode`() {
        assertEquals(GameMode.TREACHERY, GameMode.fromValue("treachery"))
        assertEquals(GameMode.PLANECHASE, GameMode.fromValue("planechase"))
        assertEquals(GameMode.TREACHERY_PLANECHASE, GameMode.fromValue("treachery_planechase"))
        assertEquals(GameMode.NONE, GameMode.fromValue("none"))
    }

    @Test
    fun `fromValue returns null for unknown value`() {
        assertNull(GameMode.fromValue("unknown"))
        assertNull(GameMode.fromValue(""))
    }
}
