//
//  GameBoardViewModel+Abilities.swift
//  Treachery-iOS
//

import Foundation

// MARK: - Traitor Abilities
//
// Which traitor ability the signed-in player can use, and the sheet that
// uses it. The resolvers' calls are in GameBoardViewModel.swift.

extension GameBoardViewModel {

    /// Unveiled traitor ability that has not been resolved yet.
    /// Decline/Skip leaves `ability_resolved` unset on the server, so this
    /// stays non-nil and the Action Bar can reopen the sheet.
    var resolvableAbility: ExecutableAbility? {
        guard let player = currentPlayer,
              player.isUnveiled,
              !player.isEliminated,
              !player.abilityResolved else { return nil }
        return ExecutableAbility(heldBy: player)
    }

    func presentAbilityResolver() {
        guard let player = currentPlayer, resolvableAbility != nil else { return }
        pendingAbilityResolution = makeAbilityResolution(for: player)
    }

    /// Opens the ability sheet after the reveal when the card just unveiled
    /// has an ability left to use. The unveil may not have reached a players
    /// snapshot yet, so unlike `resolvableAbility` this doesn't wait for it.
    /// A game that ended during the reveal gets no sheet: Game Over is up,
    /// and the server would refuse ("Game is not in progress.").
    func presentAbilityAfterUnveil() {
        guard pendingAbilityResolution == nil, game?.state == .inProgress,
              let player = currentPlayer, !player.isEliminated, !player.abilityResolved,
              ExecutableAbility(heldBy: player) != nil else { return }
        pendingAbilityResolution = makeAbilityResolution(for: player)
    }

    func dismissAbility() {
        pendingAbilityResolution = nil
    }

    private func makeAbilityResolution(for player: Player) -> AbilityResolution? {
        guard let ability = ExecutableAbility(heldBy: player) else { return nil }

        switch ability {
        case .metamorph:
            // resolveMetamorph's target checks; a card another Metamorph
            // has already taken leaves nothing to steal.
            let eliminated = players.filter {
                $0.isEliminated && $0.role != .leader && $0.userId != player.userId && $0.identityCardId != nil
            }
            return AbilityResolution(
                abilityType: .metamorph,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: eliminated
            )
        case .puppetMaster:
            let otherAlive = players.filter { !$0.isEliminated && $0.userId != player.userId }
            return AbilityResolution(
                abilityType: .puppetMaster,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: otherAlive
            )
        case .wearerOfMasks:
            return AbilityResolution(
                abilityType: .wearerOfMasks,
                actingPlayerId: player.id,
                candidateCards: [],
                candidatePlayers: []
            )
        }
    }
}
