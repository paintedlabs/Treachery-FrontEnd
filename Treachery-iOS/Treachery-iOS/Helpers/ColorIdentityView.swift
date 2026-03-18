//
//  ColorIdentityView.swift
//  Treachery-iOS
//
//  Created by Luke Solomon on 3/18/26.
//

import SwiftUI

/// Displays a row of MTG mana color pips for a deck's color identity.
struct ColorIdentityPips: View {
    let colors: [ManaColor]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(colors, id: \.self) { color in
                Circle()
                    .fill(color.color)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Circle()
                            .stroke(Color.mtgDivider, lineWidth: 0.5)
                    )
            }
        }
        .accessibilityLabel(colors.map(\.displayName).joined(separator: ", "))
    }
}

/// Tappable color identity selector in WUBRG order.
struct ColorIdentitySelector: View {
    @Binding var selectedColors: [ManaColor]

    private let allColors: [ManaColor] = [.white, .blue, .black, .red, .green, .colorless]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(allColors, id: \.self) { color in
                Button {
                    toggleColor(color)
                } label: {
                    Circle()
                        .fill(selectedColors.contains(color) ? color.color : color.color.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(
                                    selectedColors.contains(color) ? Color.mtgGold : Color.mtgDivider,
                                    lineWidth: selectedColors.contains(color) ? 2 : 1
                                )
                        )
                        .overlay(
                            Text(color.rawValue)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundStyle(selectedColors.contains(color) ? Color.mtgBackground : Color.mtgTextSecondary)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(color.displayName)
                .accessibilityAddTraits(selectedColors.contains(color) ? .isSelected : [])
            }
        }
    }

    private func toggleColor(_ color: ManaColor) {
        if let index = selectedColors.firstIndex(of: color) {
            selectedColors.remove(at: index)
        } else {
            // Insert in WUBRG order
            let order: [ManaColor] = [.white, .blue, .black, .red, .green, .colorless]
            selectedColors.append(color)
            selectedColors.sort { order.firstIndex(of: $0)! < order.firstIndex(of: $1)! }
        }
    }
}

#if DEBUG
#Preview("Color Identity Pips") {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        VStack(spacing: 12) {
            ColorIdentityPips(colors: [.white, .blue])
            ColorIdentityPips(colors: [.black, .red, .green])
            ColorIdentityPips(colors: [.colorless])
        }
    }
}

#Preview("Color Identity Selector") {
    struct PreviewWrapper: View {
        @State private var colors: [ManaColor] = [.blue, .red]
        var body: some View {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()
                ColorIdentitySelector(selectedColors: $colors)
            }
        }
    }
    return PreviewWrapper()
}
#endif
