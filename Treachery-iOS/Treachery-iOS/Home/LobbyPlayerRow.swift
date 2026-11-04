//
//  LobbyPlayerRow.swift
//  Treachery-iOS
//

import SwiftUI

struct LobbyPlayerRow: View {
    let player: Player
    let isMe: Bool
    let isHost: Bool
    @Binding var showColorPicker: Bool
    @Binding var commanderNameInput: String
    var onColorChange: (String?) -> Void
    /// Typing is debounced by LobbyView through the bound text; submitting
    /// saves straight away.
    var onCommanderNameSubmit: () -> Void
    @FocusState private var isEditingCommanderName: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if let hex = player.playerColor {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: hex))
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .padding(.trailing, 8)
                }

                if isMe {
                    colorPickerToggle
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(player.displayName)
                        .fontWeight(isHost ? .semibold : .regular)
                        .foregroundStyle(Color.mtgTextPrimary)

                    if !isMe, let commanderName = player.commanderName, !commanderName.isEmpty {
                        Text(commanderName)
                            .font(.system(.caption, design: .serif))
                            .italic()
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                }

                Spacer()

                if isHost {
                    MtgBadge(text: "Host", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15), font: .caption)
                }
            }

            if isMe {
                commanderNameField
            }

            if isMe && showColorPicker {
                ColorPickerRow(selectedHex: player.playerColor) { hex in
                    onColorChange(hex)
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .accessibilityLabel("\(player.displayName)\(isHost ? ", Host" : "")")
    }

    private var colorPickerToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showColorPicker.toggle()
            }
        } label: {
            if let hex = player.playerColor {
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 16, height: 16)
                    .overlay(
                        Circle().stroke(Color.mtgTextSecondary.opacity(0.3), lineWidth: 1)
                    )
            } else {
                Circle()
                    .stroke(Color.mtgTextSecondary, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
            }
        }
        .buttonStyle(.plain)
        .padding(.trailing, 6)
        .accessibilityLabel("Choose player color")
    }

    private var commanderNameField: some View {
        TextField("Commander name...", text: $commanderNameInput)
            .focused($isEditingCommanderName)
            .font(.system(.caption, design: .serif))
            .italic()
            .foregroundStyle(Color.mtgTextPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // At least 44pt tall so it's easy to hit. The text line sits in
            // the middle; a tap anywhere else in the box focuses it too.
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.mtgCardElevated)
                    .onTapGesture { isEditingCommanderName = true }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.mtgDivider, lineWidth: 1)
            )
            .padding(.top, 6)
            .onSubmit {
                onCommanderNameSubmit()
            }
    }
}
