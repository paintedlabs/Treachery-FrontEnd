package com.solomon.treachery.model

import com.google.firebase.Timestamp
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

class ModelSerializationTests {

    private val now = Timestamp.now()

    // ── Game ──

    @Nested
    inner class GameSerializationTests {

        @Test
        fun `toMap includes all fields`() {
            val game = Game(
                id = "game-1",
                code = "ABCD",
                hostId = "host-1",
                state = GameState.WAITING,
                maxPlayers = 8,
                startingLife = 40,
                gameMode = GameMode.TREACHERY,
                playerIds = listOf("p1", "p2"),
                createdAt = now,
                lastActivityAt = now,
            )
            val map = game.toMap()
            assertEquals("game-1", map["id"])
            assertEquals("ABCD", map["code"])
            assertEquals("host-1", map["host_id"])
            assertEquals("waiting", map["state"])
            assertEquals(8, map["max_players"])
            assertEquals(40, map["starting_life"])
            assertEquals("treachery", map["game_mode"])
            assertEquals(listOf("p1", "p2"), map["player_ids"])
            assertEquals(now, map["created_at"])
        }

        @Test
        fun `fromMap parses all fields`() {
            val data = mapOf<String, Any?>(
                "code" to "WXYZ",
                "host_id" to "host-2",
                "state" to "in_progress",
                "max_players" to 6L,
                "starting_life" to 30L,
                "game_mode" to "planechase",
                "player_ids" to listOf("a", "b", "c"),
                "created_at" to now,
                "last_activity_at" to now,
                "winning_team" to "assassin",
                "winner_user_ids" to listOf("a"),
            )
            val game = Game.fromMap("game-2", data)
            assertEquals("game-2", game.id)
            assertEquals("WXYZ", game.code)
            assertEquals("host-2", game.hostId)
            assertEquals(GameState.IN_PROGRESS, game.state)
            assertEquals(6, game.maxPlayers)
            assertEquals(30, game.startingLife)
            assertEquals(GameMode.PLANECHASE, game.gameMode)
            assertEquals(listOf("a", "b", "c"), game.playerIds)
            assertEquals("assassin", game.winningTeam)
            assertEquals(listOf("a"), game.winnerUserIds)
        }

        @Test
        fun `fromMap uses defaults for missing optional fields`() {
            val data = mapOf<String, Any?>(
                "code" to "TEST",
                "host_id" to "h",
                "state" to "waiting",
                "max_players" to 8L,
                "starting_life" to 40L,
                "created_at" to now,
            )
            val game = Game.fromMap("g1", data)
            assertEquals(emptyList<String>(), game.playerIds)
            assertEquals(GameMode.TREACHERY, game.gameMode) // default from unknown ""
            assertNull(game.winningTeam)
            assertEquals(emptyList<String>(), game.winnerUserIds)
            assertNull(game.planechase)
        }

        @Test
        fun `fromMap with planechase data`() {
            val data = mapOf<String, Any?>(
                "code" to "TEST",
                "host_id" to "h",
                "state" to "waiting",
                "max_players" to 8L,
                "starting_life" to 40L,
                "created_at" to now,
                "game_mode" to "treachery_planechase",
                "player_ids" to listOf("p1"),
                "planechase" to mapOf(
                    "use_own_deck" to true,
                    "current_plane_id" to "plane-1",
                    "used_plane_ids" to listOf("plane-0"),
                    "die_roll_count" to 3L,
                ),
            )
            val game = Game.fromMap("g2", data)
            assertNotNull(game.planechase)
            assertTrue(game.planechase!!.useOwnDeck)
            assertEquals("plane-1", game.planechase!!.currentPlaneId)
            assertEquals(listOf("plane-0"), game.planechase!!.usedPlaneIds)
            assertEquals(3, game.planechase!!.dieRollCount)
        }

        @Test
        fun `toMap and fromMap round-trip`() {
            val original = Game(
                id = "rt-1",
                code = "RTST",
                hostId = "h1",
                state = GameState.FINISHED,
                maxPlayers = 6,
                startingLife = 30,
                winningTeam = "leader",
                gameMode = GameMode.TREACHERY,
                playerIds = listOf("a", "b"),
                createdAt = now,
                winnerUserIds = listOf("a"),
            )
            val restored = Game.fromMap(original.id, original.toMap())
            assertEquals(original.id, restored.id)
            assertEquals(original.code, restored.code)
            assertEquals(original.hostId, restored.hostId)
            assertEquals(original.state, restored.state)
            assertEquals(original.maxPlayers, restored.maxPlayers)
            assertEquals(original.startingLife, restored.startingLife)
            assertEquals(original.winningTeam, restored.winningTeam)
            assertEquals(original.gameMode, restored.gameMode)
            assertEquals(original.playerIds, restored.playerIds)
            assertEquals(original.winnerUserIds, restored.winnerUserIds)
        }
    }

    // ── Player ──

    @Nested
    inner class PlayerSerializationTests {

        @Test
        fun `toMap includes all fields`() {
            val player = Player(
                id = "p-1",
                orderId = 2,
                userId = "u-1",
                displayName = "Alice",
                role = Role.ASSASSIN,
                identityCardId = "card-1",
                lifeTotal = 35,
                isEliminated = false,
                isUnveiled = true,
                joinedAt = now,
                playerColor = "#e74c3c",
                commanderName = "Atraxa",
            )
            val map = player.toMap()
            assertEquals("p-1", map["id"])
            assertEquals(2, map["order_id"])
            assertEquals("u-1", map["user_id"])
            assertEquals("Alice", map["display_name"])
            assertEquals("assassin", map["role"])
            assertEquals("card-1", map["identity_card_id"])
            assertEquals(35, map["life_total"])
            assertEquals(false, map["is_eliminated"])
            assertEquals(true, map["is_unveiled"])
            assertEquals("#e74c3c", map["player_color"])
            assertEquals("Atraxa", map["commander_name"])
        }

        @Test
        fun `fromMap parses all fields`() {
            val data = mapOf<String, Any?>(
                "order_id" to 1L,
                "user_id" to "u-2",
                "display_name" to "Bob",
                "role" to "leader",
                "identity_card_id" to "card-2",
                "life_total" to 40L,
                "is_eliminated" to true,
                "is_unveiled" to false,
                "joined_at" to now,
                "player_color" to "#3498db",
                "commander_name" to "Kenrith",
            )
            val player = Player.fromMap("p-2", data)
            assertEquals("p-2", player.id)
            assertEquals(1, player.orderId)
            assertEquals("u-2", player.userId)
            assertEquals("Bob", player.displayName)
            assertEquals(Role.LEADER, player.role)
            assertEquals("card-2", player.identityCardId)
            assertEquals(40, player.lifeTotal)
            assertTrue(player.isEliminated)
            assertFalse(player.isUnveiled)
            assertEquals("#3498db", player.playerColor)
            assertEquals("Kenrith", player.commanderName)
        }

        @Test
        fun `fromMap defaults for missing optional fields`() {
            val data = mapOf<String, Any?>(
                "order_id" to 0L,
                "user_id" to "u",
                "display_name" to "Test",
                "life_total" to 40L,
                "is_eliminated" to false,
                "is_unveiled" to false,
                "joined_at" to now,
            )
            val player = Player.fromMap("p", data)
            assertNull(player.role)
            assertNull(player.identityCardId)
            assertNull(player.playerColor)
            assertNull(player.commanderName)
        }

        @Test
        fun `toMap and fromMap round-trip`() {
            val original = Player(
                id = "rt-p",
                orderId = 3,
                userId = "u-rt",
                displayName = "RoundTrip",
                role = Role.GUARDIAN,
                identityCardId = "c-rt",
                lifeTotal = 25,
                isEliminated = true,
                isUnveiled = true,
                joinedAt = now,
                playerColor = "#2ecc71",
                commanderName = "Korvold",
            )
            val restored = Player.fromMap(original.id, original.toMap())
            assertEquals(original.id, restored.id)
            assertEquals(original.orderId, restored.orderId)
            assertEquals(original.userId, restored.userId)
            assertEquals(original.displayName, restored.displayName)
            assertEquals(original.role, restored.role)
            assertEquals(original.identityCardId, restored.identityCardId)
            assertEquals(original.lifeTotal, restored.lifeTotal)
            assertEquals(original.isEliminated, restored.isEliminated)
            assertEquals(original.isUnveiled, restored.isUnveiled)
            assertEquals(original.playerColor, restored.playerColor)
            assertEquals(original.commanderName, restored.commanderName)
        }
    }

    // ── TreacheryUser ──

    @Nested
    inner class TreacheryUserSerializationTests {

        @Test
        fun `toMap includes all fields`() {
            val user = TreacheryUser(
                id = "u-1",
                displayName = "TestUser",
                email = "test@example.com",
                phoneNumber = "+1234567890",
                friendIds = listOf("f1", "f2"),
                fcmToken = "token-123",
                createdAt = now,
                elo = 1600,
            )
            val map = user.toMap()
            assertEquals("u-1", map["id"])
            assertEquals("TestUser", map["display_name"])
            assertEquals("test@example.com", map["email"])
            assertEquals("+1234567890", map["phone_number"])
            assertEquals(listOf("f1", "f2"), map["friend_ids"])
            assertEquals("token-123", map["fcm_token"])
            assertEquals(1600, map["elo"])
        }

        @Test
        fun `fromMap parses all fields`() {
            val data = mapOf<String, Any?>(
                "display_name" to "FromMap",
                "email" to "from@map.com",
                "phone_number" to null,
                "friend_ids" to listOf("x"),
                "fcm_token" to "tok",
                "created_at" to now,
                "elo" to 1800L,
            )
            val user = TreacheryUser.fromMap("u-2", data)
            assertEquals("u-2", user.id)
            assertEquals("FromMap", user.displayName)
            assertEquals("from@map.com", user.email)
            assertNull(user.phoneNumber)
            assertEquals(listOf("x"), user.friendIds)
            assertEquals(1800, user.elo)
        }

        @Test
        fun `fromMap defaults for missing fields`() {
            val data = mapOf<String, Any?>(
                "display_name" to "Minimal",
                "created_at" to now,
            )
            val user = TreacheryUser.fromMap("u-3", data)
            assertEquals(emptyList<String>(), user.friendIds)
            assertEquals(1500, user.elo)
            assertNull(user.email)
            assertNull(user.phoneNumber)
            assertNull(user.fcmToken)
        }

        @Test
        fun `toMap and fromMap round-trip`() {
            val original = TreacheryUser(
                id = "rt-u",
                displayName = "RT",
                email = "rt@test.com",
                friendIds = listOf("a", "b"),
                createdAt = now,
                elo = 1700,
            )
            val restored = TreacheryUser.fromMap(original.id, original.toMap())
            assertEquals(original.id, restored.id)
            assertEquals(original.displayName, restored.displayName)
            assertEquals(original.email, restored.email)
            assertEquals(original.friendIds, restored.friendIds)
            assertEquals(original.elo, restored.elo)
        }
    }

    // ── FriendRequest ──

    @Nested
    inner class FriendRequestSerializationTests {

        @Test
        fun `status enum raw values`() {
            assertEquals("pending", FriendRequestStatus.PENDING.value)
            assertEquals("accepted", FriendRequestStatus.ACCEPTED.value)
            assertEquals("declined", FriendRequestStatus.DECLINED.value)
        }

        @Test
        fun `toMap includes all fields`() {
            val req = FriendRequest(
                id = "fr-1",
                fromUserId = "u-a",
                fromDisplayName = "Alice",
                toUserId = "u-b",
                status = FriendRequestStatus.PENDING,
                createdAt = now,
            )
            val map = req.toMap()
            assertEquals("fr-1", map["id"])
            assertEquals("u-a", map["from_user_id"])
            assertEquals("Alice", map["from_display_name"])
            assertEquals("u-b", map["to_user_id"])
            assertEquals("pending", map["status"])
        }

        @Test
        fun `fromMap parses all fields`() {
            val data = mapOf<String, Any?>(
                "from_user_id" to "u-x",
                "from_display_name" to "X",
                "to_user_id" to "u-y",
                "status" to "accepted",
                "created_at" to now,
            )
            val req = FriendRequest.fromMap("fr-2", data)
            assertEquals("fr-2", req.id)
            assertEquals("u-x", req.fromUserId)
            assertEquals("X", req.fromDisplayName)
            assertEquals("u-y", req.toUserId)
            assertEquals(FriendRequestStatus.ACCEPTED, req.status)
        }

        @Test
        fun `toMap and fromMap round-trip`() {
            val original = FriendRequest(
                id = "fr-rt",
                fromUserId = "a",
                fromDisplayName = "A",
                toUserId = "b",
                status = FriendRequestStatus.DECLINED,
                createdAt = now,
            )
            val restored = FriendRequest.fromMap(original.id, original.toMap())
            assertEquals(original.id, restored.id)
            assertEquals(original.fromUserId, restored.fromUserId)
            assertEquals(original.fromDisplayName, restored.fromDisplayName)
            assertEquals(original.toUserId, restored.toUserId)
            assertEquals(original.status, restored.status)
        }
    }

    // ── PlanechaseState ──

    @Nested
    inner class PlanechaseStateSerializationTests {

        @Test
        fun `toMap includes all fields`() {
            val state = PlanechaseState(
                useOwnDeck = true,
                currentPlaneId = "plane-1",
                usedPlaneIds = listOf("plane-0"),
                lastDieRollerId = "u-1",
                dieRollCount = 3,
                chaoticAetherActive = true,
                secondaryPlaneId = "plane-2",
            )
            val map = state.toMap()
            assertEquals(true, map["use_own_deck"])
            assertEquals("plane-1", map["current_plane_id"])
            assertEquals(listOf("plane-0"), map["used_plane_ids"])
            assertEquals("u-1", map["last_die_roller_id"])
            assertEquals(3, map["die_roll_count"])
            assertEquals(true, map["chaotic_aether_active"])
            assertEquals("plane-2", map["secondary_plane_id"])
        }

        @Test
        fun `fromMap defaults for missing optional fields`() {
            val data = mapOf<String, Any?>(
                "use_own_deck" to false,
            )
            val state = PlanechaseState.fromMap(data)
            assertFalse(state.useOwnDeck)
            assertNull(state.currentPlaneId)
            assertEquals(emptyList<String>(), state.usedPlaneIds)
            assertNull(state.lastDieRollerId)
            assertEquals(0, state.dieRollCount)
            assertFalse(state.chaoticAetherActive)
            assertNull(state.secondaryPlaneId)
        }

        @Test
        fun `toMap and fromMap round-trip`() {
            val original = PlanechaseState(
                useOwnDeck = true,
                currentPlaneId = "p1",
                usedPlaneIds = listOf("p0", "p1"),
                lastDieRollerId = "u1",
                dieRollCount = 5,
                chaoticAetherActive = false,
                secondaryPlaneId = null,
            )
            val restored = PlanechaseState.fromMap(original.toMap())
            assertEquals(original.useOwnDeck, restored.useOwnDeck)
            assertEquals(original.currentPlaneId, restored.currentPlaneId)
            assertEquals(original.usedPlaneIds, restored.usedPlaneIds)
            assertEquals(original.lastDieRollerId, restored.lastDieRollerId)
            assertEquals(original.dieRollCount, restored.dieRollCount)
            assertEquals(original.chaoticAetherActive, restored.chaoticAetherActive)
            assertEquals(original.secondaryPlaneId, restored.secondaryPlaneId)
        }
    }

    // ── DeckStat ──

    @Nested
    inner class DeckStatSerializationTests {

        @Test
        fun `toMap and fromMap round-trip`() {
            val original = DeckStat(elo = 1650, wins = 10, losses = 5, games = 15)
            val restored = DeckStat.fromMap(original.toMap())
            assertEquals(original.elo, restored.elo)
            assertEquals(original.wins, restored.wins)
            assertEquals(original.losses, restored.losses)
            assertEquals(original.games, restored.games)
        }

        @Test
        fun `fromMap defaults`() {
            val stat = DeckStat.fromMap(emptyMap())
            assertEquals(1500, stat.elo)
            assertEquals(0, stat.wins)
            assertEquals(0, stat.losses)
            assertEquals(0, stat.games)
        }
    }
}
