package com.solomon.treachery.model

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class GameStateTests {

    @Test
    fun `all cases exist`() {
        assertEquals(3, GameState.entries.size)
    }

    @Test
    fun `raw values match expected strings`() {
        assertEquals("waiting", GameState.WAITING.value)
        assertEquals("in_progress", GameState.IN_PROGRESS.value)
        assertEquals("finished", GameState.FINISHED.value)
    }

    @Test
    fun `fromValue returns correct state`() {
        assertEquals(GameState.WAITING, GameState.fromValue("waiting"))
        assertEquals(GameState.IN_PROGRESS, GameState.fromValue("in_progress"))
        assertEquals(GameState.FINISHED, GameState.fromValue("finished"))
    }

    @Test
    fun `fromValue returns null for unknown value`() {
        assertNull(GameState.fromValue("unknown"))
        assertNull(GameState.fromValue(""))
    }
}
