//
//  Player.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

struct Player: Codable, Identifiable {
    let id: String
    let orderId: Int
    let userId: String
    var displayName: String
    var role: Role?
    var identityCardId: String?
    var lifeTotal: Int
    var isEliminated: Bool
    var isUnveiled: Bool
    let joinedAt: Date

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
    }
}
