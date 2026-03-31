//
//  ColorPickerRow.swift
//  Treachery-iOS
//

import SwiftUI

struct ColorPickerRow: View {
    let selectedHex: String?
    let onSelect: (String?) -> Void

    var body: some View {
        HStack(spacing: 8) {
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
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playerColor.name)
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
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear color")
        }
        .padding(.vertical, 4)
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
