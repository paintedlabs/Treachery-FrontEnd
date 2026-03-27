package com.solomon.treachery.data

import com.solomon.treachery.model.PlaneCard
import kotlinx.serialization.json.Json
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeAll
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test
import org.junit.jupiter.api.TestInstance

/**
 * Tests for the plane database using the bundled plane_cards.json.
 * Mirrors iOS PlaneDatabaseTests.
 */
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
class PlaneDatabaseTests {

    private val json = Json { ignoreUnknownKeys = true }
    private lateinit var allCards: List<PlaneCard>

    @BeforeAll
    fun loadCards() {
        val jsonString = this::class.java.classLoader!!
            .getResourceAsStream("plane_cards.json")!!
            .bufferedReader()
            .use { it.readText() }
        allCards = json.decodeFromString<List<PlaneCard>>(jsonString)
    }

    // ── Loading ──

    @Nested
    inner class LoadingTests {
        @Test
        fun `loads cards successfully`() {
            assertTrue(allCards.isNotEmpty(), "Should load at least one card")
        }

        @Test
        fun `has both planes and phenomena`() {
            val planes = allCards.filter { !it.isPhenomenon }
            val phenomena = allCards.filter { it.isPhenomenon }
            assertTrue(planes.isNotEmpty(), "Should have at least one plane")
            assertTrue(phenomena.isNotEmpty(), "Should have at least one phenomenon")
        }
    }

    // ── Separation ──

    @Nested
    inner class SeparationTests {
        @Test
        fun `allPlanes excludes phenomena`() {
            val planes = allCards.filter { !it.isPhenomenon }
            assertTrue(planes.none { it.isPhenomenon })
        }

        @Test
        fun `allCards includes both types`() {
            val planeCount = allCards.count { !it.isPhenomenon }
            val phenomenonCount = allCards.count { it.isPhenomenon }
            assertEquals(allCards.size, planeCount + phenomenonCount)
        }
    }

    // ── Lookup ──

    @Nested
    inner class LookupTests {
        @Test
        fun `find plane by id`() {
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

    // ── Random Selection ──

    @Nested
    inner class RandomSelectionTests {
        @Test
        fun `random plane excluding empty set returns a plane`() {
            val planes = allCards.filter { !it.isPhenomenon }
            val random = planes.filter { it.id !in emptySet<String>() }.randomOrNull()
            assertNotNull(random)
            assertFalse(random!!.isPhenomenon)
        }

        @Test
        fun `random plane excludes specified ids`() {
            val planes = allCards.filter { !it.isPhenomenon }
            val excludeIds = planes.take(2).map { it.id }.toSet()
            val available = planes.filter { it.id !in excludeIds }
            if (available.isNotEmpty()) {
                val random = available.random()
                assertFalse(random.id in excludeIds)
            }
        }

        @Test
        fun `returns null when all planes excluded`() {
            val planes = allCards.filter { !it.isPhenomenon }
            val allIds = planes.map { it.id }.toSet()
            val available = planes.filter { it.id !in allIds }
            assertNull(available.randomOrNull())
        }
    }

    // ── Data Integrity ──

    @Nested
    inner class DataIntegrityTests {
        @Test
        fun `all cards have unique IDs`() {
            val ids = allCards.map { it.id }
            assertEquals(ids.size, ids.toSet().size, "Duplicate plane card IDs found")
        }

        @Test
        fun `all cards have non-empty names`() {
            allCards.forEach { card ->
                assertTrue(card.name.isNotBlank(), "Card ${card.id} has blank name")
            }
        }

        @Test
        fun `all cards have non-empty oracle text`() {
            allCards.forEach { card ->
                assertTrue(card.oracleText.isNotBlank(), "Card '${card.name}' has blank oracle text")
            }
        }
    }
}
