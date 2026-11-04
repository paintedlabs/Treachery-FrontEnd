//
//  GameBoardViewModel+Accessibility.swift
//  Treachery-iOS
//

import SwiftUI

extension GameBoardViewModel {

    /// VoiceOver's swipe up or down on a player's life total: the same
    /// 1-point change as their + and − buttons, through the same checks and
    /// debounce.
    func adjustLife(for playerId: String, _ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment:
            adjustLife(for: playerId, by: 1)
        case .decrement:
            adjustLife(for: playerId, by: -1)
        @unknown default:
            break
        }
    }
}
