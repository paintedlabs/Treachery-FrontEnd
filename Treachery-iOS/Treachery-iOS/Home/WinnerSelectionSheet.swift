//
//  WinnerSelectionSheet.swift
//  Treachery-iOS
//

import SwiftUI

struct WinnerSelectionSheet: View {
    let players: [Player]
    @Binding var selectedWinners: Set<String>
    let isPending: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                VStack(spacing: 16) {
                    Text("Select the winner(s) of this game for ELO tracking.")
                        .font(.subheadline)
                        .foregroundStyle(Color.mtgTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(players) { player in
                                Button {
                                    if selectedWinners.contains(player.userId) {
                                        selectedWinners.remove(player.userId)
                                    } else {
                                        selectedWinners.insert(player.userId)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selectedWinners.contains(player.userId) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedWinners.contains(player.userId) ? Color.mtgSuccess : Color.mtgTextSecondary)
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(player.displayName)
                                                .foregroundStyle(Color.mtgTextPrimary)
                                            if let commanderName = player.commanderName, !commanderName.isEmpty {
                                                Text(commanderName)
                                                    .font(.system(.caption, design: .serif))
                                                    .italic()
                                                    .foregroundStyle(Color.mtgTextSecondary)
                                            }
                                        }

                                        Spacer()

                                        if let hex = player.playerColor {
                                            Circle()
                                                .fill(Color(hex: hex))
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }
                                .buttonStyle(.plain)

                                if player.id != players.last?.id {
                                    Rectangle()
                                        .fill(Color.mtgDivider)
                                        .frame(height: 1)
                                        .padding(.horizontal, 16)
                                }
                            }
                        }
                        .mtgCardFrame()
                        .padding(.horizontal)
                    }

                    VStack(spacing: 8) {
                        Button {
                            onConfirm()
                        } label: {
                            if isPending {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small).tint(Color.mtgBackground)
                                    Text("Ending Game...")
                                }
                            } else {
                                Text("End Game")
                            }
                        }
                        .buttonStyle(MtgPrimaryButtonStyle(isDisabled: isPending))
                        .disabled(isPending)
                        .padding(.horizontal)

                        Text("You can skip winner selection — ELO won't be updated.")
                            .font(.caption2)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                    .padding(.bottom)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .foregroundStyle(Color.mtgGold)
                }
            }
        }
    }
}
