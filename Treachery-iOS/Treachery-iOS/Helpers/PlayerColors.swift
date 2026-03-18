//
//  PlayerColors.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/18/26.
//

import SwiftUI

struct PlayerColor {
    let name: String
    let hex: String
    var color: Color { Color(hex: hex) }
}

enum PlayerColors {
    static let palette: [PlayerColor] = [
        PlayerColor(name: "Crimson", hex: "#e74c3c"),
        PlayerColor(name: "Sunset", hex: "#e67e22"),
        PlayerColor(name: "Amber", hex: "#f1c40f"),
        PlayerColor(name: "Emerald", hex: "#2ecc71"),
        PlayerColor(name: "Teal", hex: "#1abc9c"),
        PlayerColor(name: "Sky", hex: "#3498db"),
        PlayerColor(name: "Indigo", hex: "#6c5ce7"),
        PlayerColor(name: "Orchid", hex: "#a855f7"),
        PlayerColor(name: "Rose", hex: "#ec4899"),
        PlayerColor(name: "Silver", hex: "#95a5a6"),
    ]
}
