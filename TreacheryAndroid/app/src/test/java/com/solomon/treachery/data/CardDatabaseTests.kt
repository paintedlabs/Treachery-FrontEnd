package com.solomon.treachery.data

import com.solomon.treachery.model.IdentityCard
import com.solomon.treachery.model.Rarity
import com.solomon.treachery.model.Role
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

/**
 * Tests for the card database using the bundled identity_cards.json.
 * Mirrors iOS CardDatabaseTests.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class CardDatabaseTests {

    private val json = Json { ignoreUnknownKeys = true }
    private lateinit var allCards: List<IdentityCard>

    @BeforeAll
    fun loadCards() {
        val jsonString = this::class.java.classLoader!!
            .getResourceAsStream("identity_cards.json")!!
            .bufferedReader()
            .use { it.readText() }
        allCards = json.decodeFromString<List<IdentityCard>>(jsonString)
    }

    // ── Loading ──

    @Nested
    inner class LoadingTests {
        @Test
        fun `loads 62 cards`() {
            assertEquals(62, allCards.size)
        }
    }

    // ── Role Filtering ──

    @Nested
    inner class RoleFilteringTests {
        @Test
        fun `13 leaders`() {
            assertEquals(13, allCards.count { it.role == Role.LEADER.value })
        }

        @Test
        fun `18 guardians`() {
            assertEquals(18, allCards.count { it.role == Role.GUARDIAN.value })
        }

        @Test
        fun `18 assassins`() {
            assertEquals(18, allCards.count { it.role == Role.ASSASSIN.value })
        }

        @Test
        fun `13 traitors`() {
            assertEquals(13, allCards.count { it.role == Role.TRAITOR.value })
        }

        @Test
        fun `all cards have a valid role`() {
            allCards.forEach { card ->
                assertNotNull(Role.fromValue(card.role), "Card '${card.name}' has invalid role '${card.role}'")
            }
        }
    }

    // ── Lookup ──

    @Nested
    inner class LookupTests {
        @Test
        fun `find card by id`() {
            val first = allCards.first()
            val found = allCards.find { it.id == first.id }
            assertNotNull(found)
            assertEquals(first.name, found!!.name)
        }

        @Test
        fun `unknown id returns null`() {
            val found = allCards.find { it.id == "nonexistent-id" }
            assertNull(found)
        }
    }

    // ── Rarity Filtering ──

    @Nested
    inner class RarityFilteringTests {
        @Test
        fun `all cards have a valid rarity`() {
            allCards.forEach { card ->
                assertNotNull(Rarity.fromValue(card.rarity), "Card '${card.name}' has invalid rarity '${card.rarity}'")
            }
        }

        @Test
        fun `each rarity has at least one card`() {
            Rarity.entries.forEach { rarity ->
                assertTrue(
                    allCards.any { it.rarity == rarity.value },
                    "No cards found for rarity ${rarity.value}"
                )
            }
        }
    }

    // ── Random Selection ──

    @Nested
    inner class RandomSelectionTests {
        @Test
        fun `random selection respects count`() {
            val leaderCards = allCards.filter { it.role == Role.LEADER.value }
            val selected = leaderCards.shuffled().take(3)
            assertEquals(3, selected.size)
        }

        @Test
        fun `random selection never exceeds available`() {
            val leaderCards = allCards.filter { it.role == Role.LEADER.value }
            val selected = leaderCards.shuffled().take(100)
            assertEquals(leaderCards.size, selected.size)
        }

        @Test
        fun `random selection returns unique cards`() {
            val selected = allCards.filter { it.role == Role.ASSASSIN.value }.shuffled().take(5)
            assertEquals(selected.size, selected.distinctBy { it.id }.size)
        }
    }

    // ── Data Integrity ──

    @Nested
    inner class DataIntegrityTests {
        @Test
        fun `all cards have unique IDs`() {
            val ids = allCards.map { it.id }
            assertEquals(ids.size, ids.toSet().size, "Duplicate card IDs found")
        }

        @Test
        fun `all cards have unique card numbers`() {
            val numbers = allCards.map { it.cardNumber }
            assertEquals(numbers.size, numbers.toSet().size, "Duplicate card numbers found")
        }

        @Test
        fun `all cards have non-empty names`() {
            allCards.forEach { card ->
                assertTrue(card.name.isNotBlank(), "Card ${card.id} has blank name")
            }
        }

        @Test
        fun `all cards have non-empty ability text`() {
            allCards.forEach { card ->
                assertTrue(card.abilityText.isNotBlank(), "Card '${card.name}' has blank ability text")
            }
        }

        @Test
        fun `all cards have non-empty unveil cost`() {
            allCards.forEach { card ->
                assertTrue(card.unveilCost.isNotBlank(), "Card '${card.name}' has blank unveil cost")
            }
        }
    }
}
