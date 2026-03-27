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
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class OptimisticLifeTrackingTests {

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var firestore: MockFirestoreRepository
    private lateinit var cloudFunctions: MockCloudFunctionsRepository

    private val now = Timestamp.now()

    @BeforeEach
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        firestore = MockFirestoreRepository()
        cloudFunctions = MockCloudFunctionsRepository()
    }

    @AfterEach
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun makeVM(): GameBoardViewModel {
        val savedState = SavedStateHandle(mapOf("gameId" to "game-1"))
        return GameBoardViewModel(
            firestore, cloudFunctions, MockCardDatabase(), MockPlaneDatabase(), savedState
        ).also {
            it.currentUserId = "user-1"
        }
    }

    private fun makePlayer(id: String = "p-1", userId: String = "user-1", life: Int = 40, eliminated: Boolean = false) =
        Player(id = id, orderId = 0, userId = userId, displayName = "Test",
            lifeTotal = life, isEliminated = eliminated, joinedAt = now)

    @Test
    fun `adjustLife applies delta optimistically`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer())
        advanceUntilIdle()

        vm.adjustLife("p-1", -5)
        advanceUntilIdle()

        assertEquals(35, vm.players.value.first().lifeTotal)
    }

    @Test
    fun `multiple adjustments accumulate`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer())
        advanceUntilIdle()

        vm.adjustLife("p-1", -3)
        vm.adjustLife("p-1", -2)
        advanceUntilIdle()

        assertEquals(35, vm.players.value.first().lifeTotal)
    }

    @Test
    fun `life is clamped at zero`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer(life = 5))
        advanceUntilIdle()

        vm.adjustLife("p-1", -10)
        advanceUntilIdle()

        assertEquals(0, vm.players.value.first().lifeTotal)
    }

    @Test
    fun `eliminated players are ignored`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer(eliminated = true))
        advanceUntilIdle()

        vm.adjustLife("p-1", 5)
        advanceUntilIdle()

        // Life unchanged because player is eliminated
        assertEquals(40, vm.players.value.first().lifeTotal)
    }

    @Test
    fun `invalid player id is safe`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer())
        advanceUntilIdle()

        // Should not throw
        vm.adjustLife("nonexistent", 5)
        advanceUntilIdle()

        assertEquals(40, vm.players.value.first().lifeTotal)
    }

    @Test
    fun `independent players have independent deltas`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(
            makePlayer(id = "p-1", userId = "u-1"),
            makePlayer(id = "p-2", userId = "u-2"),
        )
        advanceUntilIdle()

        vm.adjustLife("p-1", -10)
        vm.adjustLife("p-2", 5)
        advanceUntilIdle()

        assertEquals(30, vm.players.value.find { it.id == "p-1" }?.lifeTotal)
        assertEquals(45, vm.players.value.find { it.id == "p-2" }?.lifeTotal)
    }

    @Test
    fun `adjustLife clears error`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer())
        advanceUntilIdle()

        vm.adjustLife("p-1", 1)
        advanceUntilIdle()

        assertNull(vm.errorMessage.value)
    }

    @Test
    fun `debounce flushes delta to cloud function`() = runTest {
        val vm = makeVM()
        firestore.playersFlowSource.value = listOf(makePlayer())
        advanceUntilIdle()

        vm.adjustLife("p-1", -5)
        // Advance past 500ms debounce
        advanceTimeBy(600)
        advanceUntilIdle()

        assertEquals(1, cloudFunctions.adjustLifeCalls.size)
        assertEquals(-5, cloudFunctions.adjustLifeCalls.first().third)
    }
}
