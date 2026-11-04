//
//  GameBoardViewModel+Abilities.swift
//  Treachery-iOS
//

import Foundation
import os

private let logger = Logger(subsystem: "com.Solomon.Treachery-iOS", category: "GameBoard")

// MARK: - Traitor Abilities
//
// Which traitor ability the signed-in player can use, the sheet that uses
// it, and the calls that resolve it.

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

    // MARK: - Resolving

    func resolveMetamorph(targetPlayerId: String) async {
        guard currentPlayer != nil else { return }
        errorMessage = nil

        do {
            try await cloudFunctions.resolveMetamorph(gameId: gameId, targetPlayerId: targetPlayerId)
            AnalyticsService.trackEvent("ability_metamorph", params: ["target": targetPlayerId])
        } catch {
            logger.error("resolveMetamorph failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't steal that identity. Check your connection and try again."
        }
        pendingAbilityResolution = nil
    }

    func resolvePuppetMaster(redistributions: [String: String]) async {
        errorMessage = nil

        // Filter out unchanged assignments
        let changes = redistributions.filter { playerId, newCardId in
            players.first(where: { $0.id == playerId })?.identityCardId != newCardId
        }

        guard !changes.isEmpty else {
            pendingAbilityResolution = nil
            return
        }

        do {
            try await cloudFunctions.resolvePuppetMaster(gameId: gameId, redistributions: changes)
            AnalyticsService.trackEvent("ability_puppet_master", params: ["swaps": changes.count])
        } catch {
            logger.error("resolvePuppetMaster failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error)
                ?? "Couldn't redistribute the cards. Check your connection and try again."
        }
        pendingAbilityResolution = nil
    }

    func resolveWearerOfMasks(chosenCardId: String?) async {
        guard currentPlayer != nil else {
            pendingAbilityResolution = nil
            return
        }
        errorMessage = nil

        do {
            try await cloudFunctions.resolveWearerOfMasks(gameId: gameId, chosenCardId: chosenCardId)
            if chosenCardId != nil {
                AnalyticsService.trackEvent("ability_wearer_of_masks", params: ["chosen_card": chosenCardId ?? ""])
            }
        } catch {
            logger.error("resolveWearerOfMasks failed: \(String(describing: error), privacy: .public)")
            errorMessage = CallableRefusal.explanation(of: error) ?? (chosenCardId == nil
                ? "Couldn't decline the ability. Check your connection and try again."
                : "Couldn't become that identity. Check your connection and try again.")
        }
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
