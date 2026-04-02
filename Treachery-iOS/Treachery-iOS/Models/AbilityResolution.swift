//
//  AbilityResolution.swift
//  Treachery-iOS
//

import Foundation

struct AbilityResolution: Identifiable {
    let id = UUID()
    let abilityType: ExecutableAbility
    let actingPlayerId: String
    var candidateCards: [IdentityCard]
    var candidatePlayers: [Player]
}
