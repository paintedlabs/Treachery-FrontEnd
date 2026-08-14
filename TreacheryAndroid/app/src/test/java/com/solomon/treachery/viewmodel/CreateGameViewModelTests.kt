package com.solomon.treachery.viewmodel

import com.solomon.treachery.mocks.MockCloudFunctionsRepository
import com.solomon.treachery.mocks.MockFirestoreRepository
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.home.CreateGameViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CreateGameViewModelTests {

    private val testDispatcher = UnconfinedTestDispatcher()
    private lateinit var firestore: MockFirestoreRepository
    private lateinit var cloudFunctions: MockCloudFunctionsRepository
    private lateinit var vm: CreateGameViewModel

    @BeforeEach
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        firestore = MockFirestoreRepository()
        cloudFunctions = MockCloudFunctionsRepository()
        vm = CreateGameViewModel(firestore, cloudFunctions)
    }

    @AfterEach
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `treachery game sends maxTraitorRarity`() = runTest {
        var createdGameId: String? = null
        vm.createGame("user-1", GameMode.TREACHERY, 40, Rarity.RARE, false) { createdGameId = it }
        advanceUntilIdle()

        assertEquals("mock-created-game-id", createdGameId)
        assertEquals(1, cloudFunctions.createGameCalls.size)
        assertEquals("rare", cloudFunctions.createGameCalls.first()["maxTraitorRarity"])
    }

    @Test
    fun `non-treachery game omits maxTraitorRarity`() = runTest {
        vm.createGame("user-1", GameMode.PLANECHASE, 40, Rarity.RARE, true) { }
        advanceUntilIdle()

        assertEquals(1, cloudFunctions.createGameCalls.size)
        assertNull(cloudFunctions.createGameCalls.first()["maxTraitorRarity"])
    }

    @Test
    fun `createGame failure sets error message`() = runTest {
        cloudFunctions.errorToThrow = RuntimeException("Server error")
        var succeeded = false
        vm.createGame("user-1", GameMode.TREACHERY, 40, Rarity.SPECIAL, false) { succeeded = true }
        advanceUntilIdle()

        assertFalse(succeeded)
        assertNotNull(vm.errorMessage.value)
    }
}
