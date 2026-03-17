//
//  PlanechaseState.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import Foundation

struct PlanechaseState: Codable, Hashable {
    var useOwnDeck: Bool
    var currentPlaneId: String?
    var usedPlaneIds: [String]
    var lastDieRollerId: String?
    var dieRollCount: Int
    var chaoticAetherActive: Bool
    var secondaryPlaneId: String?

    enum CodingKeys: String, CodingKey {
        case useOwnDeck = "use_own_deck"
        case currentPlaneId = "current_plane_id"
        case usedPlaneIds = "used_plane_ids"
        case lastDieRollerId = "last_die_roller_id"
        case dieRollCount = "die_roll_count"
        case chaoticAetherActive = "chaotic_aether_active"
        case secondaryPlaneId = "secondary_plane_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        useOwnDeck = try container.decodeIfPresent(Bool.self, forKey: .useOwnDeck) ?? false
        currentPlaneId = try container.decodeIfPresent(String.self, forKey: .currentPlaneId)
        usedPlaneIds = try container.decodeIfPresent([String].self, forKey: .usedPlaneIds) ?? []
        lastDieRollerId = try container.decodeIfPresent(String.self, forKey: .lastDieRollerId)
        dieRollCount = try container.decodeIfPresent(Int.self, forKey: .dieRollCount) ?? 0
        chaoticAetherActive = try container.decodeIfPresent(Bool.self, forKey: .chaoticAetherActive) ?? false
        secondaryPlaneId = try container.decodeIfPresent(String.self, forKey: .secondaryPlaneId)
    }

    init(
        useOwnDeck: Bool,
        currentPlaneId: String?,
        usedPlaneIds: [String],
        lastDieRollerId: String?,
        dieRollCount: Int,
        chaoticAetherActive: Bool = false,
        secondaryPlaneId: String? = nil
    ) {
        self.useOwnDeck = useOwnDeck
        self.currentPlaneId = currentPlaneId
        self.usedPlaneIds = usedPlaneIds
        self.lastDieRollerId = lastDieRollerId
        self.dieRollCount = dieRollCount
        self.chaoticAetherActive = chaoticAetherActive
        self.secondaryPlaneId = secondaryPlaneId
    }
}
