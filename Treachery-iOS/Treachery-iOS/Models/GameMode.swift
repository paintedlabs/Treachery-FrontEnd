//
//  GameMode.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/16/26.
//

import Foundation

enum GameMode: String, Codable, CaseIterable {
    case treachery
    case planechase
    case treacheryPlanechase = "treachery_planechase"
    case none

    var displayName: String {
        switch self {
        case .treachery: return "Treachery"
        case .planechase: return "Planechase"
        case .treacheryPlanechase: return "Both"
        case .none: return "Life Tracker"
        }
    }

    var includesTreachery: Bool {
        self == .treachery || self == .treacheryPlanechase
    }

    var includesPlanechase: Bool {
        self == .planechase || self == .treacheryPlanechase
    }
}
