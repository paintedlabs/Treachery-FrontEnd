//
//  Player.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

struct Player: Codable, Identifiable, Equatable {
    var id: String
    let orderId: Int
    let userId: String
    var displayName: String
    var role: Role?
    var identityCardId: String?
    var lifeTotal: Int
    var isEliminated: Bool
    var isUnveiled: Bool
    let joinedAt: Date
    var playerColor: String?
    var commanderName: String?
    var originalIdentityCardId: String?
    var isFaceDown: Bool
    var isReady: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case orderId = "order_id"
        case userId = "user_id"
        case displayName = "display_name"
        case role
        case identityCardId = "identity_card_id"
        case lifeTotal = "life_total"
        case isEliminated = "is_eliminated"
        case isUnveiled = "is_unveiled"
        case joinedAt = "joined_at"
        case playerColor = "player_color"
        case commanderName = "commander_name"
        case originalIdentityCardId = "original_identity_card_id"
        case isFaceDown = "is_face_down"
        case isReady = "is_ready"
    }

    // Custom decoder: uses decodeIfPresent for 'id' to handle documents
    // created by other clients (e.g. Android) that store the player ID
    // only as the Firestore document ID, not as a field in the data.
    // The actual document ID is injected after decoding in FirestoreManager.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        orderId = try container.decode(Int.self, forKey: .orderId)
        userId = try container.decode(String.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        role = try container.decodeIfPresent(Role.self, forKey: .role)
        identityCardId = try container.decodeIfPresent(String.self, forKey: .identityCardId)
        lifeTotal = try container.decode(Int.self, forKey: .lifeTotal)
        isEliminated = try container.decode(Bool.self, forKey: .isEliminated)
        isUnveiled = try container.decode(Bool.self, forKey: .isUnveiled)
        joinedAt = try container.decode(Date.self, forKey: .joinedAt)
        playerColor = try container.decodeIfPresent(String.self, forKey: .playerColor)
        commanderName = try container.decodeIfPresent(String.self, forKey: .commanderName)
        originalIdentityCardId = try container.decodeIfPresent(String.self, forKey: .originalIdentityCardId)
        isFaceDown = try container.decodeIfPresent(Bool.self, forKey: .isFaceDown) ?? false
        isReady = try container.decodeIfPresent(Bool.self, forKey: .isReady) ?? false
    }

    init(
        id: String,
        orderId: Int,
        userId: String,
        displayName: String,
        role: Role?,
        identityCardId: String?,
        lifeTotal: Int,
        isEliminated: Bool,
        isUnveiled: Bool,
        joinedAt: Date,
        playerColor: String? = nil,
        commanderName: String? = nil,
        originalIdentityCardId: String? = nil,
        isFaceDown: Bool = false,
        isReady: Bool = false
    ) {
        self.id = id
        self.orderId = orderId
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.identityCardId = identityCardId
        self.lifeTotal = lifeTotal
        self.isEliminated = isEliminated
        self.isUnveiled = isUnveiled
        self.joinedAt = joinedAt
        self.playerColor = playerColor
        self.commanderName = commanderName
        self.originalIdentityCardId = originalIdentityCardId
        self.isFaceDown = isFaceDown
        self.isReady = isReady
    }
}
