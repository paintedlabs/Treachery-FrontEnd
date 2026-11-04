//
//  ColorPickerRow.swift
//  Treachery-iOS
//

import SwiftUI

struct ColorPickerRow: View {
    let selectedHex: String?
    let onSelect: (String?) -> Void

    /// Each swatch has a 44pt target, so the eleven don't fit on one line
    /// across a phone: they wrap onto as many lines as they need, all in
    /// view.
    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 0)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
            ForEach(PlayerColors.palette, id: \.hex) { playerColor in
                Button {
                    if selectedHex == playerColor.hex {
                        onSelect(nil)
                    } else {
                        onSelect(playerColor.hex)
                    }
                } label: {
                    Circle()
                        .fill(playerColor.color)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .stroke(Color.mtgTextPrimary, lineWidth: selectedHex == playerColor.hex ? 2 : 0)
                                .padding(selectedHex == playerColor.hex ? -2 : 0)
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playerColor.name)
                .accessibilityAddTraits(selectedHex == playerColor.hex ? .isSelected : [])
            }

            Button {
                onSelect(nil)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.mtgTextSecondary, lineWidth: 1)
                        .frame(width: 24, height: 24)
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.mtgTextSecondary)
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear color")
        }
    }
}

#if DEBUG
#Preview {
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        ColorPickerRow(selectedHex: nil) { _ in }
    }
}
#endif
