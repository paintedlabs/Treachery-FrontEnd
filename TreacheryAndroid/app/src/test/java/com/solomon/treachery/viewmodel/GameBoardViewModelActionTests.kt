package com.solomon.treachery.viewmodel

import androidx.lifecycle.SavedStateHandle
import com.google.firebase.Timestamp
import com.solomon.treachery.mocks.*
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.game.GameBoardViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GameBoardViewModelActionTests {

    private val testDispatcher = UnconfinedTestDispatcher()
    private lateinit var firestore: MockFirestoreRepository
    private lateinit var cloudFunctions: MockCloudFunctionsRepository
    private lateinit var cardDb: MockCardDatabase
    private lateinit var planeDb: MockPlaneDatabase

    private val now = Timestamp.now()

    @BeforeEach
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        firestore = MockFirestoreRepository()
        cloudFunctions = MockCloudFunctionsRepository()
        cardDb = MockCardDatabase()
        planeDb = MockPlaneDatabase()
    }

    @AfterEach
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun makeVM(): GameBoardViewModel {
        val savedState = SavedStateHandle(mapOf("gameId" to "game-1"))
        return GameBoardViewModel(firestore, cloudFunctions, cardDb, planeDb, savedState).also {
            it.currentUserId = "user-1"
        }
    }

    private fun makePlayers() = listOf(
        Player(id = "p-1", orderId = 0, userId = "user-1", displayName = "Host",
            role = Role.LEADER, identityCardId = "card-1", lifeTotal = 40,
            isEliminated = false, isUnveiled = false, joinedAt = now),
        Player(id = "p-2", orderId = 1, userId = "user-2", displayName = "Player 2",
            role = Role.ASSASSIN, lifeTotal = 35,
            isEliminated = false, isUnveiled = false, joinedAt = now),
    )

    // ── Unveil ──

    @Nested
    inner class UnveilTests {

        @Test
        fun `unveilCurrentPlayer calls cloud function`() = runTest {
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            vm.unveilCurrentPlayer()
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.unveilPlayerCalls.size)
            assertEquals("game-1", cloudFunctions.unveilPlayerCalls.first())
        }

        @Test
        fun `unveil does nothing if already unveiled`() = runTest {
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers().map {
                if (it.userId == "user-1") it.copy(isUnveiled = true) else it
            }
            advanceUntilIdle()

            vm.unveilCurrentPlayer()
            advanceUntilIdle()

            assertTrue(cloudFunctions.unveilPlayerCalls.isEmpty())
        }

        @Test
        fun `unveil does nothing if no current player`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "not-in-game"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            vm.unveilCurrentPlayer()
            advanceUntilIdle()

            assertTrue(cloudFunctions.unveilPlayerCalls.isEmpty())
        }

        @Test
        fun `unveil sets error on failure`() = runTest {
            cloudFunctions.errorToThrow = RuntimeException("Failed")
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            vm.unveilCurrentPlayer()
            advanceUntilIdle()

            assertNotNull(vm.errorMessage.value)
        }
    }

    // ── Eliminate ──

    @Nested
    inner class EliminateTests {

        @Test
        fun `eliminateAndLeave calls cloud function`() = runTest {
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            vm.eliminateAndLeave()
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.eliminatePlayerCalls.size)
        }

        @Test
        fun `eliminate does nothing without current player`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "not-in-game"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            vm.eliminateAndLeave()
            advanceUntilIdle()

            assertTrue(cloudFunctions.eliminatePlayerCalls.isEmpty())
        }

        @Test
        fun `eliminate sets error on failure`() = runTest {
            cloudFunctions.errorToThrow = RuntimeException("Failed")
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            vm.eliminateAndLeave()
            advanceUntilIdle()

            assertNotNull(vm.errorMessage.value)
        }
    }

    // ── Roll Die ──

    @Nested
    inner class RollDieTests {

        @Test
        fun `rollDie calls cloud function and sets result`() = runTest {
            cloudFunctions.rollPlanarDieResult = "planeswalk"
            val vm = makeVM()
            advanceUntilIdle()

            vm.rollDie()
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.rollPlanarDieCalls.size)
        }

        @Test
        fun `rollDie sets error on failure`() = runTest {
            cloudFunctions.errorToThrow = RuntimeException("Die roll failed")
            val vm = makeVM()
            advanceUntilIdle()

            vm.rollDie()
            advanceUntilIdle()

            assertNotNull(vm.errorMessage.value)
            assertFalse(vm.isRollingDie.value)
        }
    }

    // ── End Game ──

    @Nested
    inner class EndGameTests {

        @Test
        fun `endGame calls cloud function`() = runTest {
            val vm = makeVM()
            advanceUntilIdle()

            vm.endGame(listOf("user-1"))
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.endGameCalls.size)
            assertEquals(listOf("user-1"), cloudFunctions.endGameCalls.first().second)
        }

        @Test
        fun `endGame with null winners`() = runTest {
            val vm = makeVM()
            advanceUntilIdle()

            vm.endGame(null)
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.endGameCalls.size)
            assertNull(cloudFunctions.endGameCalls.first().second)
        }

        @Test
        fun `endGame sets error on failure`() = runTest {
            cloudFunctions.errorToThrow = RuntimeException("Failed")
            val vm = makeVM()
            advanceUntilIdle()

            vm.endGame()
            advanceUntilIdle()

            assertNotNull(vm.errorMessage.value)
        }
    }

    // ── Resolve Phenomenon ──

    @Nested
    inner class ResolvePhenomenonTests {

        @Test
        fun `resolvePhenomenon calls cloud function`() = runTest {
            val vm = makeVM()
            advanceUntilIdle()

            vm.resolvePhenomenon()
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.resolvePhenomenonCalls.size)
        }

        @Test
        fun `resolvePhenomenon with choose result sets tunnel options`() = runTest {
            val plane1 = PlaneCard(id = "p1", name = "Plane 1", typeLine = "Plane", oracleText = "Text", isPhenomenon = false)
            val plane2 = PlaneCard(id = "p2", name = "Plane 2", typeLine = "Plane", oracleText = "Text", isPhenomenon = false)
            planeDb.cards = listOf(plane1, plane2)

            cloudFunctions.resolvePhenomenonResult = mapOf(
                "type" to "choose",
                "options" to listOf(
                    mapOf("id" to "p1"),
                    mapOf("id" to "p2"),
                ),
            )

            val vm = makeVM()
            advanceUntilIdle()

            vm.resolvePhenomenon()
            advanceUntilIdle()

            val options = vm.tunnelOptions.value
            assertNotNull(options)
            assertEquals(2, options!!.size)
        }
    }

    // ── Select Tunnel Plane ──

    @Nested
    inner class SelectTunnelPlaneTests {

        @Test
        fun `selectTunnelPlane calls cloud function and clears options`() = runTest {
            val plane = PlaneCard(id = "p1", name = "Target", typeLine = "Plane", oracleText = "Text", isPhenomenon = false)
            val vm = makeVM()
            advanceUntilIdle()

            vm.selectTunnelPlane(plane)
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.selectPlaneCalls.size)
            assertEquals("p1", cloudFunctions.selectPlaneCalls.first().second)
            assertNull(vm.tunnelOptions.value)
        }
    }
}
