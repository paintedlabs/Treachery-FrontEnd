package com.solomon.treachery.model

import com.google.firebase.Timestamp
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

/**
 * Robustness tests: verify models handle missing fields, extra fields,
 * and unknown enum values gracefully.
 */
class ModelRobustnessTests {

    private val now = Timestamp.now()

    // ── Player ──

    @Nested
    inner class PlayerRobustnessTests {

        @Test
        fun `missing fields use safe defaults`() {
            val player = Player.fromMap("p", emptyMap())
            assertEquals("p", player.id)
            assertEquals(0, player.orderId)
            assertEquals("", player.userId)
            assertEquals("", player.displayName)
            assertEquals(40, player.lifeTotal)
            assertFalse(player.isEliminated)
            assertFalse(player.isUnveiled)
            assertNull(player.role)
            assertNull(player.identityCardId)
            assertNull(player.playerColor)
            assertNull(player.commanderName)
        }

        @Test
        fun `unknown role string decodes as null`() {
            val data = mapOf<String, Any?>(
                "role" to "wizard",
                "joined_at" to now,
            )
            val player = Player.fromMap("p", data)
            assertNull(player.role)
        }

        @Test
        fun `extra unknown fields are ignored`() {
            val data = mapOf<String, Any?>(
                "order_id" to 0L,
                "user_id" to "u",
                "display_name" to "Test",
                "life_total" to 40L,
                "is_eliminated" to false,
                "is_unveiled" to false,
                "joined_at" to now,
                "unknown_field" to "should be ignored",
                "another_extra" to 42L,
            )
            // Should not throw
            val player = Player.fromMap("p", data)
            assertEquals("Test", player.displayName)
        }

        @Test
        fun `numeric fields handle Long from Firestore`() {
            val data = mapOf<String, Any?>(
                "order_id" to 5L,
                "life_total" to 100L,
                "joined_at" to now,
            )
            val player = Player.fromMap("p", data)
            assertEquals(5, player.orderId)
            assertEquals(100, player.lifeTotal)
        }

        @Test
        fun `numeric fields handle Int`() {
            val data = mapOf<String, Any?>(
                "order_id" to 3,
                "life_total" to 25,
                "joined_at" to now,
            )
            val player = Player.fromMap("p", data)
            assertEquals(3, player.orderId)
            assertEquals(25, player.lifeTotal)
        }

        @Test
        fun `numeric fields handle Double`() {
            val data = mapOf<String, Any?>(
                "order_id" to 2.0,
                "life_total" to 40.0,
                "joined_at" to now,
            )
            val player = Player.fromMap("p", data)
            assertEquals(2, player.orderId)
            assertEquals(40, player.lifeTotal)
        }
    }

    // ── Game ──

    @Nested
    inner class GameRobustnessTests {

        @Test
        fun `missing fields use safe defaults`() {
            val game = Game.fromMap("g", emptyMap())
            assertEquals("g", game.id)
            assertEquals("", game.code)
            assertEquals("", game.hostId)
            assertEquals(GameState.WAITING, game.state)
            assertEquals(8, game.maxPlayers)
            assertEquals(40, game.startingLife)
            assertNull(game.winningTeam)
            assertEquals(emptyList<String>(), game.playerIds)
            assertEquals(emptyList<String>(), game.winnerUserIds)
        }

        @Test
        fun `unknown state falls back to WAITING`() {
            val data = mapOf<String, Any?>(
                "state" to "unknown_state",
                "created_at" to now,
            )
            val game = Game.fromMap("g", data)
            assertEquals(GameState.WAITING, game.state)
        }

        @Test
        fun `unknown game_mode falls back to TREACHERY`() {
            val data = mapOf<String, Any?>(
                "game_mode" to "custom_mode",
                "created_at" to now,
            )
            val game = Game.fromMap("g", data)
            // fromValue returns null for unknown, then ?: defaults to TREACHERY
            assertEquals(GameMode.TREACHERY, game.gameMode)
        }

        @Test
        fun `extra unknown fields are ignored`() {
            val data = mapOf<String, Any?>(
                "code" to "TEST",
                "host_id" to "h",
                "state" to "waiting",
                "created_at" to now,
                "future_field" to "ignored",
                "new_feature" to true,
            )
            val game = Game.fromMap("g", data)
            assertEquals("TEST", game.code)
        }

        @Test
        fun `player_ids handles mixed types in list gracefully`() {
            val data = mapOf<String, Any?>(
                "player_ids" to listOf("valid", 123, null, "also_valid"),
                "created_at" to now,
            )
            val game = Game.fromMap("g", data)
            // filterIsInstance<String>() should keep only strings
            assertEquals(listOf("valid", "also_valid"), game.playerIds)
        }

        @Test
        fun `planechase null does not crash`() {
            val data = mapOf<String, Any?>(
                "planechase" to null,
                "created_at" to now,
            )
            val game = Game.fromMap("g", data)
            assertNull(game.planechase)
        }
    }

    // ── TreacheryUser ──

    @Nested
    inner class TreacheryUserRobustnessTests {

        @Test
        fun `missing fields use safe defaults`() {
            val user = TreacheryUser.fromMap("u", emptyMap())
            assertEquals("u", user.id)
            assertEquals("", user.displayName)
            assertEquals(emptyList<String>(), user.friendIds)
            assertEquals(1500, user.elo)
            assertNull(user.email)
            assertNull(user.phoneNumber)
            assertNull(user.fcmToken)
        }

        @Test
        fun `extra unknown fields are ignored`() {
            val data = mapOf<String, Any?>(
                "display_name" to "Test",
                "created_at" to now,
                "some_new_field" to "value",
            )
            val user = TreacheryUser.fromMap("u", data)
            assertEquals("Test", user.displayName)
        }

        @Test
        fun `friend_ids handles mixed types gracefully`() {
            val data = mapOf<String, Any?>(
                "friend_ids" to listOf("f1", 42, null, "f2"),
                "created_at" to now,
            )
            val user = TreacheryUser.fromMap("u", data)
            assertEquals(listOf("f1", "f2"), user.friendIds)
        }

        @Test
        fun `deck_stats null is safe`() {
            val data = mapOf<String, Any?>(
                "display_name" to "Test",
                "deck_stats" to null,
                "created_at" to now,
            )
            val user = TreacheryUser.fromMap("u", data)
            assertNull(user.deckStats)
        }
    }

    // ── FriendRequest ──

    @Nested
    inner class FriendRequestRobustnessTests {

        @Test
        fun `missing fields use safe defaults`() {
            val req = FriendRequest.fromMap("fr", emptyMap())
            assertEquals("fr", req.id)
            assertEquals("", req.fromUserId)
            assertEquals("", req.fromDisplayName)
            assertEquals("", req.toUserId)
            assertEquals(FriendRequestStatus.PENDING, req.status)
        }

        @Test
        fun `unknown status falls back to PENDING`() {
            val data = mapOf<String, Any?>(
                "status" to "unknown_status",
                "created_at" to now,
            )
            val req = FriendRequest.fromMap("fr", data)
            assertEquals(FriendRequestStatus.PENDING, req.status)
        }

        @Test
        fun `extra unknown fields are ignored`() {
            val data = mapOf<String, Any?>(
                "from_user_id" to "a",
                "from_display_name" to "A",
                "to_user_id" to "b",
                "status" to "pending",
                "created_at" to now,
                "extra" to "ignored",
            )
            val req = FriendRequest.fromMap("fr", data)
            assertEquals("A", req.fromDisplayName)
        }
    }

    // ── IdentityCard (kotlinx.serialization) ──

    @Nested
    inner class IdentityCardRobustnessTests {

        @Test
        fun `roleEnum returns correct enum`() {
            val card = IdentityCard(
                id = "c1", cardNumber = 1, name = "Test",
                role = "leader", abilityText = "Test ability",
                unveilCost = "3", rarity = "rare", hasUndercover = false,
            )
            assertEquals(Role.LEADER, card.roleEnum)
        }

        @Test
        fun `roleEnum returns null for unknown role`() {
            val card = IdentityCard(
                id = "c1", cardNumber = 1, name = "Test",
                role = "wizard", abilityText = "Test ability",
                unveilCost = "3", rarity = "rare", hasUndercover = false,
            )
            assertNull(card.roleEnum)
        }

        @Test
        fun `rarityEnum returns correct enum`() {
            val card = IdentityCard(
                id = "c1", cardNumber = 1, name = "Test",
                role = "leader", abilityText = "Test ability",
                unveilCost = "3", rarity = "mythic", hasUndercover = false,
            )
            assertEquals(Rarity.MYTHIC, card.rarityEnum)
        }

        @Test
        fun `rarityEnum returns null for unknown rarity`() {
            val card = IdentityCard(
                id = "c1", cardNumber = 1, name = "Test",
                role = "leader", abilityText = "Test ability",
                unveilCost = "3", rarity = "legendary", hasUndercover = false,
            )
            assertNull(card.rarityEnum)
        }
    }
}
