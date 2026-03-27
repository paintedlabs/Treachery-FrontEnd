package com.solomon.treachery.model

import com.google.firebase.Timestamp
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Nested
import org.junit.jupiter.api.Test

/**
 * Cross-platform compatibility tests.
 *
 * The web app (and previously iOS) writes `id` as a field in the Firestore document data.
 * Android's toMap() now also includes `id`. These tests verify that fromMap() works correctly
 * both WITH and WITHOUT the `id` field in the document data (since the id is always passed
 * separately as the document reference ID).
 */
class CrossPlatformTests {

    private val now = Timestamp.now()

    // ── Player ──

    @Nested
    inner class CrossPlatformPlayerTests {

        @Test
        fun `fromMap works without id in data - Android legacy format`() {
            val data = mapOf<String, Any?>(
                "order_id" to 0L,
                "user_id" to "u-1",
                "display_name" to "Player One",
                "role" to null,
                "identity_card_id" to null,
                "life_total" to 40L,
                "is_eliminated" to false,
                "is_unveiled" to false,
                "joined_at" to now,
                "player_color" to null,
                "commander_name" to null,
            )
            // id comes from document reference, not data
            val player = Player.fromMap("player-doc-id", data)
            assertEquals("player-doc-id", player.id)
            assertEquals("u-1", player.userId)
            assertEquals("Player One", player.displayName)
        }

        @Test
        fun `fromMap works with id in data - web and iOS format`() {
            val data = mapOf<String, Any?>(
                "id" to "embedded-id",
                "order_id" to 1L,
                "user_id" to "u-2",
                "display_name" to "Player Two",
                "life_total" to 40L,
                "is_eliminated" to false,
                "is_unveiled" to false,
                "joined_at" to now,
            )
            // fromMap always uses the passed id, not data["id"]
            val player = Player.fromMap("doc-ref-id", data)
            assertEquals("doc-ref-id", player.id)
        }

        @Test
        fun `full Android payload decodes correctly`() {
            val data = mapOf<String, Any?>(
                "order_id" to 2L,
                "user_id" to "android-user",
                "display_name" to "Droid",
                "role" to "assassin",
                "identity_card_id" to "card-42",
                "life_total" to 35L,
                "is_eliminated" to false,
                "is_unveiled" to true,
                "joined_at" to now,
                "player_color" to "#e74c3c",
                "commander_name" to "Atraxa",
            )
            val player = Player.fromMap("p-android", data)
            assertEquals(Role.ASSASSIN, player.role)
            assertEquals("card-42", player.identityCardId)
            assertEquals(35, player.lifeTotal)
            assertTrue(player.isUnveiled)
            assertEquals("#e74c3c", player.playerColor)
            assertEquals("Atraxa", player.commanderName)
        }
    }

    // ── Game ──

    @Nested
    inner class CrossPlatformGameTests {

        @Test
        fun `fromMap works without id in data`() {
            val data = mapOf<String, Any?>(
                "code" to "ABCD",
                "host_id" to "h1",
                "state" to "waiting",
                "max_players" to 8L,
                "starting_life" to 40L,
                "player_ids" to listOf("h1"),
                "created_at" to now,
                "game_mode" to "treachery",
            )
            val game = Game.fromMap("game-doc-id", data)
            assertEquals("game-doc-id", game.id)
            assertEquals("ABCD", game.code)
        }

        @Test
        fun `fromMap works with id in data`() {
            val data = mapOf<String, Any?>(
                "id" to "embedded-game-id",
                "code" to "WXYZ",
                "host_id" to "h2",
                "state" to "waiting",
                "max_players" to 8L,
                "starting_life" to 40L,
                "created_at" to now,
            )
            val game = Game.fromMap("doc-ref-id", data)
            assertEquals("doc-ref-id", game.id)
        }

        @Test
        fun `complete web payload with planechase decodes`() {
            val data = mapOf<String, Any?>(
                "id" to "web-game",
                "code" to "WEB1",
                "host_id" to "web-host",
                "state" to "in_progress",
                "max_players" to 6L,
                "starting_life" to 30L,
                "winning_team" to null,
                "player_ids" to listOf("a", "b", "c"),
                "created_at" to now,
                "last_activity_at" to now,
                "game_mode" to "treachery_planechase",
                "planechase" to mapOf(
                    "use_own_deck" to false,
                    "current_plane_id" to "plane-x",
                    "used_plane_ids" to listOf("plane-y"),
                    "last_die_roller_id" to "a",
                    "die_roll_count" to 2L,
                ),
                "winner_user_ids" to emptyList<String>(),
            )
            val game = Game.fromMap("web-game", data)
            assertEquals(GameState.IN_PROGRESS, game.state)
            assertEquals(GameMode.TREACHERY_PLANECHASE, game.gameMode)
            assertNotNull(game.planechase)
            assertEquals("plane-x", game.planechase!!.currentPlaneId)
        }

        @Test
        fun `missing optional fields use safe defaults`() {
            val data = mapOf<String, Any?>(
                "code" to "MIN",
                "host_id" to "h",
                "state" to "waiting",
                "max_players" to 8L,
                "starting_life" to 40L,
                "created_at" to now,
            )
            val game = Game.fromMap("g", data)
            assertEquals(emptyList<String>(), game.playerIds)
            assertNull(game.winningTeam)
            assertNull(game.lastActivityAt)
            assertNull(game.planechase)
            assertEquals(emptyList<String>(), game.winnerUserIds)
        }
    }

    // ── TreacheryUser ──

    @Nested
    inner class CrossPlatformUserTests {

        @Test
        fun `fromMap works without id in data`() {
            val data = mapOf<String, Any?>(
                "display_name" to "NoIdUser",
                "created_at" to now,
            )
            val user = TreacheryUser.fromMap("user-doc-id", data)
            assertEquals("user-doc-id", user.id)
            assertEquals("NoIdUser", user.displayName)
        }

        @Test
        fun `full web payload with deck stats decodes`() {
            val data = mapOf<String, Any?>(
                "id" to "web-user",
                "display_name" to "WebPlayer",
                "email" to "web@test.com",
                "phone_number" to null,
                "friend_ids" to listOf("f1"),
                "fcm_token" to "web-token",
                "created_at" to now,
                "elo" to 1650L,
                "deck_stats" to mapOf(
                    "Atraxa" to mapOf(
                        "elo" to 1700L,
                        "wins" to 5L,
                        "losses" to 2L,
                        "games" to 7L,
                    ),
                ),
            )
            val user = TreacheryUser.fromMap("web-user", data)
            assertEquals("WebPlayer", user.displayName)
            assertEquals(1650, user.elo)
            assertNotNull(user.deckStats)
            assertEquals(1, user.deckStats!!.size)
            assertEquals(1700, user.deckStats!!["Atraxa"]!!.elo)
            assertEquals(5, user.deckStats!!["Atraxa"]!!.wins)
        }
    }

    // ── FriendRequest ──

    @Nested
    inner class CrossPlatformFriendRequestTests {

        @Test
        fun `fromMap works without id in data`() {
            val data = mapOf<String, Any?>(
                "from_user_id" to "a",
                "from_display_name" to "A",
                "to_user_id" to "b",
                "status" to "pending",
                "created_at" to now,
            )
            val req = FriendRequest.fromMap("fr-doc-id", data)
            assertEquals("fr-doc-id", req.id)
        }

        @Test
        fun `fromMap works with id in data`() {
            val data = mapOf<String, Any?>(
                "id" to "embedded-fr",
                "from_user_id" to "x",
                "from_display_name" to "X",
                "to_user_id" to "y",
                "status" to "accepted",
                "created_at" to now,
            )
            val req = FriendRequest.fromMap("doc-ref-fr", data)
            assertEquals("doc-ref-fr", req.id)
        }
    }
}
