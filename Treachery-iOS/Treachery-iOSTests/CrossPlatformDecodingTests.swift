import Testing
import Foundation
@testable import Treachery_iOS

// MARK: - Cross-Platform Decoding Tests
// These tests simulate the exact Firestore document payloads that each platform writes.
// Android's toMap() methods omit "id" from the document data — the ID is only stored
// as the Firestore document reference. These tests ensure iOS decodes such documents
// without silently dropping them.

struct CrossPlatformPlayerDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    // THE test that would have caught the shipped bug.
    @Test func decodesPlayerWithoutIdField() throws {
        let json = Data("""
        {
            "order_id": 1,
            "user_id": "android-user-1",
            "display_name": "DroidPlayer",
            "life_total": 40,
            "is_eliminated": false,
            "is_unveiled": false,
            "joined_at": 1000000
        }
        """.utf8)
        let player = try decoder.decode(Player.self, from: json)
        #expect(player.id == "")
        #expect(player.userId == "android-user-1")
        #expect(player.displayName == "DroidPlayer")
    }

    @Test func decodesPlayerWithIdField() throws {
        let json = Data("""
        {
            "id": "ios-p1",
            "order_id": 0,
            "user_id": "ios-user-1",
            "display_name": "iOSPlayer",
            "life_total": 40,
            "is_eliminated": false,
            "is_unveiled": false,
            "joined_at": 1000000
        }
        """.utf8)
        let player = try decoder.decode(Player.self, from: json)
        #expect(player.id == "ios-p1")
    }

    @Test func androidPlayerFullPayload() throws {
        // Matches Android Player.toMap() exactly — all fields present, no "id"
        let json = Data("""
        {
            "order_id": 2,
            "user_id": "u42",
            "display_name": "AndroidUser",
            "role": "assassin",
            "identity_card_id": "card7",
            "life_total": 35,
            "is_eliminated": false,
            "is_unveiled": true,
            "joined_at": 1700000000,
            "player_color": "#FF5733",
            "commander_name": "Krenko, Mob Boss"
        }
        """.utf8)
        let player = try decoder.decode(Player.self, from: json)
        #expect(player.id == "")
        #expect(player.orderId == 2)
        #expect(player.userId == "u42")
        #expect(player.role == .assassin)
        #expect(player.identityCardId == "card7")
        #expect(player.lifeTotal == 35)
        #expect(player.isUnveiled == true)
        #expect(player.playerColor == "#FF5733")
        #expect(player.commanderName == "Krenko, Mob Boss")
    }

    @Test func androidPlayerWithNullOptionals() throws {
        // Android writes null for optional fields
        let json = Data("""
        {
            "order_id": 0,
            "user_id": "u1",
            "display_name": "Bob",
            "role": null,
            "identity_card_id": null,
            "life_total": 40,
            "is_eliminated": false,
            "is_unveiled": false,
            "joined_at": 1000000,
            "player_color": null,
            "commander_name": null
        }
        """.utf8)
        let player = try decoder.decode(Player.self, from: json)
        #expect(player.role == nil)
        #expect(player.identityCardId == nil)
        #expect(player.playerColor == nil)
        #expect(player.commanderName == nil)
    }
}

struct CrossPlatformGameDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    @Test func decodesGameWithoutIdField() throws {
        let json = Data("""
        {
            "code": "XYZW",
            "host_id": "android-host",
            "state": "waiting",
            "max_players": 8,
            "starting_life": 40,
            "game_mode": "treachery",
            "player_ids": ["android-host"],
            "created_at": 1000000
        }
        """.utf8)
        let game = try decoder.decode(Game.self, from: json)
        #expect(game.id == "")
        #expect(game.code == "XYZW")
        #expect(game.hostId == "android-host")
    }

    @Test func androidGameFullPayload() throws {
        // Matches Android Game.toMap() exactly
        let json = Data("""
        {
            "code": "AB12",
            "host_id": "h1",
            "state": "in_progress",
            "max_players": 8,
            "starting_life": 40,
            "winning_team": null,
            "game_mode": "treachery_planechase",
            "player_ids": ["h1", "u1", "u2", "u3"],
            "created_at": 1700000000,
            "last_activity_at": 1700001000,
            "planechase": {
                "use_own_deck": false,
                "current_plane_id": "plane1",
                "used_plane_ids": ["plane1"],
                "last_die_roller_id": "h1",
                "die_roll_count": 2
            },
            "winner_user_ids": []
        }
        """.utf8)
        let game = try decoder.decode(Game.self, from: json)
        #expect(game.id == "")
        #expect(game.gameMode == .treacheryPlanechase)
        #expect(game.playerIds.count == 4)
        #expect(game.planechase?.currentPlaneId == "plane1")
        #expect(game.planechase?.dieRollCount == 2)
    }

    @Test func androidGameMissingOptionalFields() throws {
        // Android may omit last_activity_at, planechase, winning_team, winner_user_ids
        let json = Data("""
        {
            "code": "ABCD",
            "host_id": "h1",
            "state": "waiting",
            "max_players": 12,
            "starting_life": 40,
            "game_mode": "planechase",
            "player_ids": ["h1"],
            "created_at": 1000000
        }
        """.utf8)
        let game = try decoder.decode(Game.self, from: json)
        #expect(game.lastActivityAt == nil)
        #expect(game.planechase == nil)
        #expect(game.winningTeam == nil)
        #expect(game.winnerUserIds.isEmpty)
    }
}

struct CrossPlatformUserDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    @Test func decodesUserWithoutIdField() throws {
        // Android's TreacheryUser.toMap() omits "id"
        let json = Data("""
        {
            "display_name": "AndroidUser",
            "email": "test@example.com",
            "friend_ids": [],
            "created_at": 1000000,
            "elo": 1600
        }
        """.utf8)
        let user = try decoder.decode(TreacheryUser.self, from: json)
        #expect(user.id == "")
        #expect(user.displayName == "AndroidUser")
        #expect(user.elo == 1600)
    }

    @Test func androidUserFullPayload() throws {
        // Matches Android TreacheryUser.toMap() exactly
        let json = Data("""
        {
            "display_name": "Bob",
            "email": null,
            "phone_number": "+15551234567",
            "friend_ids": ["f1", "f2"],
            "fcm_token": "abc123",
            "created_at": 1700000000,
            "elo": 1550,
            "deck_stats": {
                "Krenko": {"elo": 1600, "wins": 5, "losses": 3, "games": 8}
            }
        }
        """.utf8)
        let user = try decoder.decode(TreacheryUser.self, from: json)
        #expect(user.id == "")
        #expect(user.phoneNumber == "+15551234567")
        #expect(user.friendIds == ["f1", "f2"])
        #expect(user.deckStats?["Krenko"]?.wins == 5)
    }
}

struct CrossPlatformFriendRequestDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    @Test func decodesFriendRequestWithoutIdField() throws {
        // Android's FriendRequest.toMap() omits "id"
        let json = Data("""
        {
            "from_user_id": "u1",
            "from_display_name": "Alice",
            "to_user_id": "u2",
            "status": "pending",
            "created_at": 1000000
        }
        """.utf8)
        let request = try decoder.decode(FriendRequest.self, from: json)
        #expect(request.id == "")
        #expect(request.fromUserId == "u1")
        #expect(request.status == .pending)
    }

    @Test func androidFriendRequestFullPayload() throws {
        let json = Data("""
        {
            "from_user_id": "u1",
            "from_display_name": "Alice",
            "to_user_id": "u2",
            "status": "accepted",
            "created_at": 1700000000
        }
        """.utf8)
        let request = try decoder.decode(FriendRequest.self, from: json)
        #expect(request.id == "")
        #expect(request.fromDisplayName == "Alice")
        #expect(request.status == .accepted)
    }
}
