import Testing
import Foundation
@testable import Treachery_iOS

struct GameStateTests {

    @Test func rawValues() {
        #expect(GameState.waiting.rawValue == "waiting")
        #expect(GameState.inProgress.rawValue == "in_progress")
        #expect(GameState.finished.rawValue == "finished")
    }

    @Test func decodesInProgress() throws {
        let json = Data(#""in_progress""#.utf8)
        let state = try JSONDecoder().decode(GameState.self, from: json)
        #expect(state == .inProgress)
    }
}

struct GameDecodingTests {

    private func makeGameJSON(
        playerIds: String? = #"["user1"]"#,
        gameMode: String? = #""treachery""#,
        winnerUserIds: String? = nil
    ) -> Data {
        var fields = """
        "id": "game1",
        "code": "ABCD",
        "host_id": "user1",
        "state": "waiting",
        "max_players": 8,
        "starting_life": 40,
        "created_at": 1000000
        """
        if let playerIds { fields += #", "player_ids": \#(playerIds)"# }
        if let gameMode { fields += #", "game_mode": \#(gameMode)"# }
        if let winnerUserIds { fields += #", "winner_user_ids": \#(winnerUserIds)"# }
        return Data("{\(fields)}".utf8)
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    @Test func decodesFullGame() throws {
        let game = try decoder.decode(Game.self, from: makeGameJSON())
        #expect(game.id == "game1")
        #expect(game.code == "ABCD")
        #expect(game.hostId == "user1")
        #expect(game.state == .waiting)
        #expect(game.maxPlayers == 8)
        #expect(game.startingLife == 40)
        #expect(game.playerIds == ["user1"])
        #expect(game.gameMode == .treachery)
    }

    @Test func defaultsPlayerIdsToEmpty() throws {
        let game = try decoder.decode(Game.self, from: makeGameJSON(playerIds: nil))
        #expect(game.playerIds.isEmpty)
    }

    @Test func defaultsGameModeToTreachery() throws {
        let game = try decoder.decode(Game.self, from: makeGameJSON(gameMode: nil))
        #expect(game.gameMode == .treachery)
    }

    @Test func defaultsWinnerUserIdsToEmpty() throws {
        let game = try decoder.decode(Game.self, from: makeGameJSON(winnerUserIds: nil))
        #expect(game.winnerUserIds.isEmpty)
    }

    @Test func decodesWinnerUserIds() throws {
        let game = try decoder.decode(Game.self, from: makeGameJSON(winnerUserIds: #"["u1","u2"]"#))
        #expect(game.winnerUserIds == ["u1", "u2"])
    }
}

struct GameErrorTests {

    @Test func allErrorsHaveDescriptions() {
        let errors: [GameError] = [
            .codeGenerationFailed, .gameFull, .gameNotFound,
            .gameAlreadyStarted, .cardAssignmentFailed
        ]
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
}

struct PlayerDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    @Test func decodesPlayer() throws {
        let json = Data("""
        {
            "id": "p1",
            "order_id": 2,
            "user_id": "u1",
            "display_name": "Alice",
            "role": "leader",
            "identity_card_id": "card1",
            "life_total": 40,
            "is_eliminated": false,
            "is_unveiled": true,
            "joined_at": 1000000
        }
        """.utf8)
        let player = try decoder.decode(Player.self, from: json)
        #expect(player.id == "p1")
        #expect(player.orderId == 2)
        #expect(player.userId == "u1")
        #expect(player.displayName == "Alice")
        #expect(player.role == .leader)
        #expect(player.identityCardId == "card1")
        #expect(player.lifeTotal == 40)
        #expect(player.isEliminated == false)
        #expect(player.isUnveiled == true)
    }

    @Test func decodesPlayerWithNilOptionals() throws {
        let json = Data("""
        {
            "id": "p1",
            "order_id": 0,
            "user_id": "u1",
            "display_name": "Bob",
            "life_total": 40,
            "is_eliminated": false,
            "is_unveiled": false,
            "joined_at": 1000000
        }
        """.utf8)
        let player = try decoder.decode(Player.self, from: json)
        #expect(player.role == nil)
        #expect(player.identityCardId == nil)
        #expect(player.playerColor == nil)
        #expect(player.commanderName == nil)
    }

    @Test func playerEquality() {
        let p1 = Player(id: "p1", orderId: 0, userId: "u1", displayName: "A",
                         role: nil, identityCardId: nil, lifeTotal: 40,
                         isEliminated: false, isUnveiled: false, joinedAt: Date())
        let p2 = Player(id: "p1", orderId: 0, userId: "u1", displayName: "A",
                         role: nil, identityCardId: nil, lifeTotal: 40,
                         isEliminated: false, isUnveiled: false, joinedAt: p1.joinedAt)
        #expect(p1 == p2)
    }
}

struct TreacheryUserDecodingTests {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }

    @Test func decodesFullUser() throws {
        let json = Data("""
        {
            "id": "u1",
            "display_name": "Alice",
            "email": "alice@test.com",
            "phone_number": "+1555",
            "friend_ids": ["f1", "f2"],
            "created_at": 1000000,
            "elo": 1600
        }
        """.utf8)
        let user = try decoder.decode(TreacheryUser.self, from: json)
        #expect(user.id == "u1")
        #expect(user.displayName == "Alice")
        #expect(user.email == "alice@test.com")
        #expect(user.phoneNumber == "+1555")
        #expect(user.friendIds == ["f1", "f2"])
        #expect(user.elo == 1600)
    }

    @Test func defaultsFriendIdsToEmpty() throws {
        let json = Data("""
        {"id": "u1", "display_name": "Bob", "created_at": 1000000}
        """.utf8)
        let user = try decoder.decode(TreacheryUser.self, from: json)
        #expect(user.friendIds.isEmpty)
    }

    @Test func defaultsEloTo1500() throws {
        let json = Data("""
        {"id": "u1", "display_name": "Bob", "created_at": 1000000}
        """.utf8)
        let user = try decoder.decode(TreacheryUser.self, from: json)
        #expect(user.elo == 1500)
    }

    @Test func initializerDefaults() {
        let user = TreacheryUser(id: "u1", displayName: "Test", email: nil,
                                  phoneNumber: nil, friendIds: [], createdAt: Date())
        #expect(user.elo == 1500)
        #expect(user.deckStats == nil)
        #expect(user.fcmToken == nil)
    }
}

struct IdentityCardDecodingTests {

    @Test func decodesCard() throws {
        let json = Data("""
        {
            "id": "c1",
            "card_number": 1,
            "name": "The Sovereign",
            "role": "leader",
            "ability_text": "Draw a card",
            "unveil_cost": "Pay 3 life",
            "rarity": "mythic",
            "has_undercover": false,
            "undercover_condition": null,
            "timing_restriction": null,
            "life_modifier": 5,
            "hand_size_modifier": null,
            "flavor_text": "All hail.",
            "image_asset_name": null
        }
        """.utf8)
        let card = try JSONDecoder().decode(IdentityCard.self, from: json)
        #expect(card.id == "c1")
        #expect(card.cardNumber == 1)
        #expect(card.name == "The Sovereign")
        #expect(card.role == .leader)
        #expect(card.rarity == .mythic)
        #expect(card.hasUndercover == false)
        #expect(card.lifeModifier == 5)
        #expect(card.handSizeModifier == nil)
    }
}

struct PlaneCardDecodingTests {

    @Test func decodesPlane() throws {
        let json = Data("""
        {
            "id": "plane1",
            "name": "Naya",
            "type_line": "Plane — Alara",
            "oracle_text": "Big creatures.",
            "image_uri": "https://example.com/naya.jpg",
            "is_phenomenon": false
        }
        """.utf8)
        let card = try JSONDecoder().decode(PlaneCard.self, from: json)
        #expect(card.id == "plane1")
        #expect(card.typeLine == "Plane — Alara")
        #expect(card.isPhenomenon == false)
        #expect(card.imageUri != nil)
    }

    @Test func decodesPhenomenon() throws {
        let json = Data("""
        {
            "id": "phenom1",
            "name": "Chaotic Aether",
            "type_line": "Phenomenon",
            "oracle_text": "Chaos ensues.",
            "image_uri": null,
            "is_phenomenon": true
        }
        """.utf8)
        let card = try JSONDecoder().decode(PlaneCard.self, from: json)
        #expect(card.isPhenomenon == true)
        #expect(card.imageUri == nil)
    }
}

struct PlanechaseStateDecodingTests {

    @Test func decodesWithDefaults() throws {
        let json = Data("{}".utf8)
        let state = try JSONDecoder().decode(PlanechaseState.self, from: json)
        #expect(state.useOwnDeck == false)
        #expect(state.usedPlaneIds.isEmpty)
        #expect(state.dieRollCount == 0)
        #expect(state.chaoticAetherActive == false)
        #expect(state.currentPlaneId == nil)
    }

    @Test func decodesFullState() throws {
        let json = Data("""
        {
            "use_own_deck": true,
            "current_plane_id": "p1",
            "used_plane_ids": ["p1", "p2"],
            "last_die_roller_id": "u1",
            "die_roll_count": 3,
            "chaotic_aether_active": true,
            "secondary_plane_id": "p3"
        }
        """.utf8)
        let state = try JSONDecoder().decode(PlanechaseState.self, from: json)
        #expect(state.useOwnDeck == true)
        #expect(state.currentPlaneId == "p1")
        #expect(state.usedPlaneIds.count == 2)
        #expect(state.dieRollCount == 3)
        #expect(state.chaoticAetherActive == true)
        #expect(state.secondaryPlaneId == "p3")
    }

    @Test func initializerDefaults() {
        let state = PlanechaseState(useOwnDeck: false, currentPlaneId: nil,
                                     usedPlaneIds: [], lastDieRollerId: nil, dieRollCount: 0)
        #expect(state.chaoticAetherActive == false)
        #expect(state.secondaryPlaneId == nil)
    }
}

struct FriendRequestTests {

    @Test func statusRawValues() {
        #expect(FriendRequestStatus.pending.rawValue == "pending")
        #expect(FriendRequestStatus.accepted.rawValue == "accepted")
        #expect(FriendRequestStatus.declined.rawValue == "declined")
    }

    @Test func decodesFriendRequest() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let json = Data("""
        {
            "id": "fr1",
            "from_user_id": "u1",
            "from_display_name": "Alice",
            "to_user_id": "u2",
            "status": "pending",
            "created_at": 1000000
        }
        """.utf8)
        let request = try decoder.decode(FriendRequest.self, from: json)
        #expect(request.id == "fr1")
        #expect(request.fromUserId == "u1")
        #expect(request.fromDisplayName == "Alice")
        #expect(request.toUserId == "u2")
        #expect(request.status == .pending)
    }
}

struct DeckStatTests {

    @Test func codableRoundTrip() throws {
        let stat = DeckStat(elo: 1600, wins: 5, losses: 3, games: 8)
        let data = try JSONEncoder().encode(stat)
        let decoded = try JSONDecoder().decode(DeckStat.self, from: data)
        #expect(decoded.elo == 1600)
        #expect(decoded.wins == 5)
        #expect(decoded.losses == 3)
        #expect(decoded.games == 8)
    }
}
