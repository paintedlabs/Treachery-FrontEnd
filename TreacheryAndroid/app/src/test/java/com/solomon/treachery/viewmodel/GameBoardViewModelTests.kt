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
class GameBoardViewModelTests {

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

    private fun makeVM(gameId: String = "game-1"): GameBoardViewModel {
        val savedState = SavedStateHandle(mapOf("gameId" to gameId))
        return GameBoardViewModel(firestore, cloudFunctions, cardDb, planeDb, savedState).also {
            it.currentUserId = "user-1"
        }
    }

    private fun makeGame(
        state: GameState = GameState.IN_PROGRESS,
        gameMode: GameMode = GameMode.TREACHERY,
        hostId: String = "user-1",
        winningTeam: String? = null,
        planechase: PlanechaseState? = null,
    ) = Game(
        id = "game-1", code = "ABCD", hostId = hostId,
        state = state, gameMode = gameMode,
        maxPlayers = 8, startingLife = 40, playerIds = listOf("user-1", "user-2"),
        createdAt = now, winningTeam = winningTeam, planechase = planechase,
    )

    private fun makePlayers() = listOf(
        Player(id = "p-1", orderId = 0, userId = "user-1", displayName = "Host",
            role = Role.LEADER, identityCardId = "card-1", lifeTotal = 40,
            isEliminated = false, isUnveiled = false, joinedAt = now),
        Player(id = "p-2", orderId = 1, userId = "user-2", displayName = "Player 2",
            role = Role.ASSASSIN, identityCardId = "card-2", lifeTotal = 35,
            isEliminated = false, isUnveiled = false, joinedAt = now),
        Player(id = "p-3", orderId = 2, userId = "user-3", displayName = "Player 3",
            role = Role.TRAITOR, identityCardId = "card-3", lifeTotal = 0,
            isEliminated = true, isUnveiled = true, joinedAt = now),
        Player(id = "p-4", orderId = 3, userId = "user-4", displayName = "Player 4",
            role = Role.GUARDIAN, identityCardId = "card-4", lifeTotal = 40,
            isEliminated = false, isUnveiled = true, joinedAt = now),
    )

    // ── currentPlayer ──

    @Nested
    inner class CurrentPlayerTests {

        @Test
        fun `returns correct player for userId`() = runTest {
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            assertEquals("user-1", vm.currentPlayer?.userId)
            assertEquals("Host", vm.currentPlayer?.displayName)
        }

        @Test
        fun `returns null when userId not in players`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "not-in-game"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            assertNull(vm.currentPlayer)
        }
    }

    // ── Game state ──

    @Nested
    inner class GameStateTests {

        @Test
        fun `isGameFinished true when finished`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(state = GameState.FINISHED)
            advanceUntilIdle()

            assertTrue(vm.isGameFinished)
        }

        @Test
        fun `isGameFinished false when in_progress`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(state = GameState.IN_PROGRESS)
            advanceUntilIdle()

            assertFalse(vm.isGameFinished)
        }

        @Test
        fun `winningTeam parses role`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(winningTeam = "assassin")
            advanceUntilIdle()

            assertEquals(Role.ASSASSIN, vm.winningTeam)
        }

        @Test
        fun `winningTeam null when no winner`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame()
            advanceUntilIdle()

            assertNull(vm.winningTeam)
        }
    }

    // ── Alive players ──

    @Nested
    inner class AlivePlayersTests {

        @Test
        fun `excludes eliminated players`() = runTest {
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            assertEquals(3, vm.alivePlayers.size)
            assertTrue(vm.alivePlayers.none { it.isEliminated })
        }

        @Test
        fun `returns all when none eliminated`() = runTest {
            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers().map { it.copy(isEliminated = false) }
            advanceUntilIdle()

            assertEquals(4, vm.alivePlayers.size)
        }
    }

    // ── Game mode flags ──

    @Nested
    inner class GameModeFlagTests {

        @Test
        fun `treachery mode flags`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(gameMode = GameMode.TREACHERY)
            advanceUntilIdle()

            assertTrue(vm.isTreacheryActive)
            assertFalse(vm.isPlanechaseActive)
        }

        @Test
        fun `planechase mode flags`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(gameMode = GameMode.PLANECHASE)
            advanceUntilIdle()

            assertFalse(vm.isTreacheryActive)
            assertTrue(vm.isPlanechaseActive)
        }

        @Test
        fun `combined mode flags`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(gameMode = GameMode.TREACHERY_PLANECHASE)
            advanceUntilIdle()

            assertTrue(vm.isTreacheryActive)
            assertTrue(vm.isPlanechaseActive)
        }

        @Test
        fun `none mode flags`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(gameMode = GameMode.NONE)
            advanceUntilIdle()

            assertFalse(vm.isTreacheryActive)
            assertFalse(vm.isPlanechaseActive)
        }
    }

    // ── Host detection ──

    @Nested
    inner class HostDetectionTests {

        @Test
        fun `isHost true when userId matches`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "user-1"
            firestore.gameFlowSource.value = makeGame(hostId = "user-1")
            advanceUntilIdle()

            assertTrue(vm.isHost)
        }

        @Test
        fun `isHost false when userId does not match`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "user-2"
            firestore.gameFlowSource.value = makeGame(hostId = "user-1")
            advanceUntilIdle()

            assertFalse(vm.isHost)
        }
    }

    // ── Role visibility ──

    @Nested
    inner class RoleVisibilityTests {

        @Test
        fun `can always see own role`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "user-1"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            val ownPlayer = vm.players.value.find { it.userId == "user-1" }!!
            assertTrue(vm.canSeeRole(ownPlayer))
        }

        @Test
        fun `can see unveiled player role`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "user-1"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            val unveiledPlayer = vm.players.value.find { it.userId == "user-4" }!!
            assertTrue(unveiledPlayer.isUnveiled)
            assertTrue(vm.canSeeRole(unveiledPlayer))
        }

        @Test
        fun `can see leader role even if not unveiled`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "user-2"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            val leaderPlayer = vm.players.value.find { it.role == Role.LEADER }!!
            assertFalse(leaderPlayer.isUnveiled)
            assertTrue(vm.canSeeRole(leaderPlayer))
        }

        @Test
        fun `cannot see hidden non-leader role`() = runTest {
            val vm = makeVM()
            vm.currentUserId = "user-1"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            val hiddenAssassin = vm.players.value.find { it.userId == "user-2" }!!
            assertFalse(hiddenAssassin.isUnveiled)
            assertNotEquals(Role.LEADER, hiddenAssassin.role)
            assertFalse(vm.canSeeRole(hiddenAssassin))
        }
    }

    // ── Planechase computed properties ──

    @Nested
    inner class PlanechaseTests {

        @Test
        fun `dieRollCost is 0 when no rolls`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(
                gameMode = GameMode.PLANECHASE,
                planechase = PlanechaseState(dieRollCount = 0),
            )
            advanceUntilIdle()

            assertEquals(0, vm.dieRollCost)
        }

        @Test
        fun `dieRollCost is 0 for first roll`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(
                gameMode = GameMode.PLANECHASE,
                planechase = PlanechaseState(dieRollCount = 1),
            )
            advanceUntilIdle()

            assertEquals(0, vm.dieRollCost)
        }

        @Test
        fun `dieRollCost increments after first`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(
                gameMode = GameMode.PLANECHASE,
                planechase = PlanechaseState(dieRollCount = 3),
            )
            advanceUntilIdle()

            assertEquals(2, vm.dieRollCost)
        }

        @Test
        fun `currentPlane returns plane from database`() = runTest {
            val plane = PlaneCard(id = "plane-1", name = "Test Plane", typeLine = "Plane", oracleText = "Test", isPhenomenon = false)
            planeDb.cards = listOf(plane)

            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(
                gameMode = GameMode.PLANECHASE,
                planechase = PlanechaseState(currentPlaneId = "plane-1"),
            )
            advanceUntilIdle()

            assertEquals(plane, vm.currentPlane)
        }

        @Test
        fun `isOwnDeckMode reads from planechase state`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(
                gameMode = GameMode.PLANECHASE,
                planechase = PlanechaseState(useOwnDeck = true),
            )
            advanceUntilIdle()

            assertTrue(vm.isOwnDeckMode)
        }

        @Test
        fun `lastDieRollerName finds player name`() = runTest {
            val vm = makeVM()
            firestore.gameFlowSource.value = makeGame(
                gameMode = GameMode.PLANECHASE,
                planechase = PlanechaseState(lastDieRollerId = "user-2"),
            )
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            assertEquals("Player 2", vm.lastDieRollerName)
        }
    }

    // ── Identity card lookup ──

    @Nested
    inner class IdentityCardTests {

        @Test
        fun `identityCard returns card from database`() = runTest {
            val card = IdentityCard(
                id = "card-1", cardNumber = 1, name = "Test Card",
                role = "leader", abilityText = "Test", unveilCost = "3",
                rarity = "rare", hasUndercover = false,
            )
            cardDb.cards = listOf(card)

            val vm = makeVM()
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            val player = vm.players.value.find { it.identityCardId == "card-1" }!!
            assertEquals(card, vm.identityCard(player))
        }

        @Test
        fun `identityCard returns null for player without card`() = runTest {
            val vm = makeVM()
            val player = Player(
                id = "p-x", orderId = 0, userId = "u-x", displayName = "No Card",
                lifeTotal = 40, joinedAt = now,
            )

            assertNull(vm.identityCard(player))
        }

        @Test
        fun `currentIdentityCard returns card for current player`() = runTest {
            val card = IdentityCard(
                id = "card-1", cardNumber = 1, name = "Leader Card",
                role = "leader", abilityText = "Lead", unveilCost = "3",
                rarity = "rare", hasUndercover = false,
            )
            cardDb.cards = listOf(card)

            val vm = makeVM()
            vm.currentUserId = "user-1"
            firestore.playersFlowSource.value = makePlayers()
            advanceUntilIdle()

            assertEquals(card, vm.currentIdentityCard())
        }
    }
}
