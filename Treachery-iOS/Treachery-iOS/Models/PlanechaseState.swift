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

    enum CodingKeys: String, CodingKey {
        case useOwnDeck = "use_own_deck"
        case currentPlaneId = "current_plane_id"
        case usedPlaneIds = "used_plane_ids"
        case lastDieRollerId = "last_die_roller_id"
        case dieRollCount = "die_roll_count"
    }
}
