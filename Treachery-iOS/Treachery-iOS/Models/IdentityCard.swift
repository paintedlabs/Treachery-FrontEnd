//
//  IdentityCard.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/12/26.
//

import Foundation

struct IdentityCard: Codable, Identifiable, Hashable {
    let id: String
    let cardNumber: Int
    let name: String
    let role: Role
    let abilityText: String
    let unveilCost: String
    let rarity: Rarity
    let hasUndercover: Bool
    let undercoverCondition: String?
    let timingRestriction: String?
    let lifeModifier: Int?
    let handSizeModifier: Int?
    let flavorText: String?
    let imageAssetName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case cardNumber = "card_number"
        case name
        case role
        case abilityText = "ability_text"
        case unveilCost = "unveil_cost"
        case rarity
        case hasUndercover = "has_undercover"
        case undercoverCondition = "undercover_condition"
        case timingRestriction = "timing_restriction"
        case lifeModifier = "life_modifier"
        case handSizeModifier = "hand_size_modifier"
        case flavorText = "flavor_text"
        case imageAssetName = "image_asset_name"
    }
}
