package com.solomon.treachery.viewmodel

import androidx.lifecycle.SavedStateHandle
import com.google.firebase.Timestamp
import com.solomon.treachery.mocks.MockCloudFunctionsRepository
import com.solomon.treachery.mocks.MockFirestoreRepository
import com.solomon.treachery.model.*
import com.solomon.treachery.ui.lobby.LobbyViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class LobbyViewModelTests {

    private val testDispatcher = UnconfinedTestDispatcher()
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

    private fun makeVM(gameId: String = "game-1", isHost: Boolean = true): LobbyViewModel {
        val savedState = SavedStateHandle(mapOf("gameId" to gameId, "isHost" to isHost))
        return LobbyViewModel(firestore, cloudFunctions, savedState).also {
            it.currentUserId = "user-1"
        }
    }

    private fun makePlayers(count: Int): List<Player> = (0 until count).map { i ->
        Player(
            id = "p-$i",
            orderId = i,
            userId = "u-$i",
            displayName = "Player $i",
            lifeTotal = 40,
            joinedAt = now,
        )
    }

    private fun makeTreacheryGame() = Game(
        id = "game-1", code = "ABCD", hostId = "user-1",
        state = GameState.WAITING, gameMode = GameMode.TREACHERY,
        maxPlayers = 8, startingLife = 40, playerIds = listOf("user-1"),
        createdAt = now,
    )

    // ── canStartGame ──

    @Nested
    inner class CanStartGameTests {

        @Test
        fun `host with enough players can start treachery game`() = runTest {
            val vm = makeVM(isHost = true)
            firestore.gameFlowSource.value = makeTreacheryGame()
            firestore.playersFlowSource.value = makePlayers(4)
            advanceUntilIdle()

            assertTrue(vm.canStartGame)
        }

        @Test
        fun `host with too few players cannot start treachery game`() = runTest {
            val vm = makeVM(isHost = true)
            firestore.gameFlowSource.value = makeTreacheryGame()
            firestore.playersFlowSource.value = makePlayers(3)
            advanceUntilIdle()

            assertFalse(vm.canStartGame)
        }

        @Test
        fun `non-host cannot start game`() = runTest {
            val vm = makeVM(isHost = false)
            firestore.gameFlowSource.value = makeTreacheryGame()
            firestore.playersFlowSource.value = makePlayers(4)
            advanceUntilIdle()

            assertFalse(vm.canStartGame)
        }

        @Test
        fun `host with 1 player can start life tracker game`() = runTest {
            val vm = makeVM(isHost = true)
            val lifeTrackerGame = makeTreacheryGame().copy(gameMode = GameMode.NONE)
            firestore.gameFlowSource.value = lifeTrackerGame
            firestore.playersFlowSource.value = makePlayers(1)
            advanceUntilIdle()

            assertTrue(vm.canStartGame)
        }

        @Test
        fun `host with 1 player can start planechase-only game`() = runTest {
            val vm = makeVM(isHost = true)
            val planechaseGame = makeTreacheryGame().copy(gameMode = GameMode.PLANECHASE)
            firestore.gameFlowSource.value = planechaseGame
            firestore.playersFlowSource.value = makePlayers(1)
            advanceUntilIdle()

            assertTrue(vm.canStartGame)
        }

        @Test
        fun `treachery+planechase requires 4 players`() = runTest {
            val vm = makeVM(isHost = true)
            val comboGame = makeTreacheryGame().copy(gameMode = GameMode.TREACHERY_PLANECHASE)
            firestore.gameFlowSource.value = comboGame
            firestore.playersFlowSource.value = makePlayers(3)
            advanceUntilIdle()

            assertFalse(vm.canStartGame)
        }
    }

    // ── minimumPlayerCount ──

    @Nested
    inner class MinimumPlayerCountTests {

        @Test
        fun `treachery mode requires 4`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeTreacheryGame()
            advanceUntilIdle()

            assertEquals(4, vm.minimumPlayerCount)
        }

        @Test
        fun `life tracker mode requires 1`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeTreacheryGame().copy(gameMode = GameMode.NONE)
            advanceUntilIdle()

            assertEquals(1, vm.minimumPlayerCount)
        }

        @Test
        fun `no game defaults to 4`() = runTest {
            val vm = makeVM()
            // Don't emit a game
            advanceUntilIdle()

            assertEquals(Role.MINIMUM_PLAYER_COUNT, vm.minimumPlayerCount)
        }
    }

    // ── isGameStarted ──

    @Nested
    inner class IsGameStartedTests {

        @Test
        fun `false when waiting`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeTreacheryGame()
            advanceUntilIdle()

            assertFalse(vm.isGameStarted)
        }

        @Test
        fun `true when in_progress`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeTreacheryGame().copy(state = GameState.IN_PROGRESS)
            advanceUntilIdle()

            assertTrue(vm.isGameStarted)
        }
    }

    // ── currentPlayer ──

    @Nested
    inner class CurrentPlayerTests {

        @Test
        fun `returns matching player`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "u-2"
            firestore.playersFlowSource.value = makePlayers(4)
            advanceUntilIdle()

            assertNotNull(vm.currentPlayer)
            assertEquals("u-2", vm.currentPlayer?.userId)
        }

        @Test
        fun `returns null when not in players list`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "not-in-game"
            firestore.playersFlowSource.value = makePlayers(4)
            advanceUntilIdle()

            assertNull(vm.currentPlayer)
        }
    }

    // ── Actions ──

    @Nested
    inner class ActionTests {

        @Test
        fun `startGame calls cloud function`() = runTest {
            val vm = makeVM(isHost = true)
            firestore.gameFlowSource.value = makeTreacheryGame()
            firestore.playersFlowSource.value = makePlayers(4)
            advanceUntilIdle()

            vm.startGame()
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.startGameCalls.size)
            assertEquals("game-1", cloudFunctions.startGameCalls.first())
        }

        @Test
        fun `startGame sets error on failure`() = runTest {
            cloudFunctions.errorToThrow = RuntimeException("Server error")
            val vm = makeVM(isHost = true)
            firestore.gameFlowSource.value = makeTreacheryGame()
            advanceUntilIdle()

            vm.startGame()
            advanceUntilIdle()

            assertNotNull(vm.errorMessage.value)
        }

        @Test
        fun `non-host startGame is no-op`() = runTest {
            val vm = makeVM(isHost = false)
            firestore.gameFlowSource.value = makeTreacheryGame()
            advanceUntilIdle()

            vm.startGame()
            advanceUntilIdle()

            assertTrue(cloudFunctions.startGameCalls.isEmpty())
        }

        @Test
        fun `leaveGame calls cloud function`() = runTest {
            val vm = makeVM()
            advanceUntilIdle()

            vm.leaveGame()
            advanceUntilIdle()

            assertEquals(1, cloudFunctions.leaveGameCalls.size)
        }

        @Test
        fun `leaveGame sets error on failure`() = runTest {
            cloudFunctions.errorToThrow = RuntimeException("Network error")
            val vm = makeVM()
            advanceUntilIdle()

            vm.leaveGame()
            advanceUntilIdle()

            assertNotNull(vm.errorMessage.value)
        }

        @Test
        fun `updatePlayerColor calls firestore`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "u-0"
            firestore.playersFlowSource.value = makePlayers(2)
            advanceUntilIdle()

            vm.updatePlayerColor("#e74c3c")
            advanceUntilIdle()

            assertEquals(1, firestore.updatePlayerColorCalls.size)
            assertEquals("#e74c3c", firestore.updatePlayerColorCalls.first().third)
        }

        @Test
        fun `updatePlayerColor is no-op without current player`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "not-in-game"
            firestore.playersFlowSource.value = makePlayers(2)
            advanceUntilIdle()

            vm.updatePlayerColor("#e74c3c")
            advanceUntilIdle()

            assertTrue(firestore.updatePlayerColorCalls.isEmpty())
        }

        @Test
        fun `updateCommanderName calls firestore`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "u-0"
            firestore.playersFlowSource.value = makePlayers(2)
            advanceUntilIdle()

            vm.updateCommanderName("Atraxa")
            advanceUntilIdle()

            assertEquals(1, firestore.updateCommanderNameCalls.size)
            assertEquals("Atraxa", firestore.updateCommanderNameCalls.first().third)
        }
    }

    // ── Game Disbanding ──

    @Nested
    inner class GameDisbandingTests {

        @Test
        fun `game becomes null after first snapshot sets isGameDisbanded`() = runTest {
            val vm = makeVM()
            // First snapshot: game exists
            firestore.gameFlowSource.value = makeTreacheryGame()
            advanceUntilIdle()
            assertFalse(vm.isGameDisbanded.value)

            // Second snapshot: game deleted
            firestore.gameFlowSource.value = null
            advanceUntilIdle()
            assertTrue(vm.isGameDisbanded.value)
        }

        @Test
        fun `null game on first snapshot does not trigger disbanded`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = null
            advanceUntilIdle()

            assertFalse(vm.isGameDisbanded.value)
        }
    }
}
