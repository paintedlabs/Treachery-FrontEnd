package com.solomon.treachery.model

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class RoleTests {

    @Test
    fun `all cases exist`() {
        assertEquals(4, Role.entries.size)
    }

    @Test
    fun `raw values match expected strings`() {
        assertEquals("leader", Role.LEADER.value)
        assertEquals("guardian", Role.GUARDIAN.value)
        assertEquals("assassin", Role.ASSASSIN.value)
        assertEquals("traitor", Role.TRAITOR.value)
    }

    @Test
    fun `display names are human readable`() {
        assertEquals("Leader", Role.LEADER.displayName)
        assertEquals("Guardian", Role.GUARDIAN.displayName)
        assertEquals("Assassin", Role.ASSASSIN.displayName)
        assertEquals("Traitor", Role.TRAITOR.displayName)
    }

    @Test
    fun `win condition text is non-empty for all roles`() {
        Role.entries.forEach { role ->
            assertTrue(role.winConditionText.isNotEmpty(), "${role.name} should have win condition text")
        }
    }

    @Test
    fun `fromValue returns correct role`() {
        assertEquals(Role.LEADER, Role.fromValue("leader"))
        assertEquals(Role.ASSASSIN, Role.fromValue("assassin"))
    }

    @Test
    fun `fromValue returns null for unknown value`() {
        assertNull(Role.fromValue("unknown"))
        assertNull(Role.fromValue(""))
    }

    @Test
    fun `minimum player count is 4`() {
        assertEquals(4, Role.MINIMUM_PLAYER_COUNT)
    }

    // ── Role Distribution ──

    @Test
    fun `distribution for 4 players`() {
        val dist = Role.distribution(4)
        assertEquals(1, dist.leaders)
        assertEquals(0, dist.guardians)
        assertEquals(2, dist.assassins)
        assertEquals(1, dist.traitors)
    }

    @Test
    fun `distribution for 5 players`() {
        val dist = Role.distribution(5)
        assertEquals(1, dist.leaders)
        assertEquals(1, dist.guardians)
        assertEquals(2, dist.assassins)
        assertEquals(1, dist.traitors)
    }

    @Test
    fun `distribution for 6 players`() {
        val dist = Role.distribution(6)
        assertEquals(1, dist.leaders)
        assertEquals(1, dist.guardians)
        assertEquals(3, dist.assassins)
        assertEquals(1, dist.traitors)
    }

    @Test
    fun `distribution for 7 players`() {
        val dist = Role.distribution(7)
        assertEquals(1, dist.leaders)
        assertEquals(2, dist.guardians)
        assertEquals(3, dist.assassins)
        assertEquals(1, dist.traitors)
    }

    @Test
    fun `distribution for 8 players`() {
        val dist = Role.distribution(8)
        assertEquals(1, dist.leaders)
        assertEquals(2, dist.guardians)
        assertEquals(3, dist.assassins)
        assertEquals(2, dist.traitors)
    }

    @Test
    fun `distribution total equals player count for all valid counts`() {
        for (count in 4..8) {
            val dist = Role.distribution(count)
            val total = dist.leaders + dist.guardians + dist.assassins + dist.traitors
            assertEquals(count, total, "Distribution for $count players should total $count")
        }
    }

    @Test
    fun `distribution for out-of-range defaults to 4-player`() {
        val dist = Role.distribution(3)
        val default4 = Role.distribution(4)
        assertEquals(default4, dist)
    }

    @Test
    fun `each role has a distinct color`() {
        val colors = Role.entries.map { it.roleColor }
        assertEquals(colors.size, colors.toSet().size, "All role colors should be unique")
    }
}
