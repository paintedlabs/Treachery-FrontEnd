//
//  GameBoardPlayerRow.swift
//  Treachery-iOS
//

import SwiftUI

struct GameBoardPlayerRow: View {
    let player: Player
    @ObservedObject var viewModel: GameBoardViewModel
    @Binding var showColorPicker: Bool
    var onViewCard: ((Player) -> Void)?

    private var isCurrentUser: Bool {
        player.userId == viewModel.currentUserId
    }

    /// Whether this player's card can be inspected by the current user.
    /// True for unveiled players and leaders (but not yourself -- you have the header).
    private var canInspectCard: Bool {
        guard !isCurrentUser else { return false }
        guard viewModel.identityCard(for: player) != nil else { return false }
        return player.isUnveiled || player.role == .leader
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Left accent bar for player color
                if let hex = player.playerColor {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color(hex: hex))
                        .frame(width: 3)
                        .padding(.vertical, 2)
                        .padding(.trailing, 8)
                }

                // Color picker toggle for current user
                if isCurrentUser {
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

                // Player info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(player.displayName)
                            .fontWeight(isCurrentUser ? .bold : .regular)
                            .strikethrough(player.isEliminated)
                            .foregroundStyle(player.isEliminated ? Color.mtgTextSecondary : Color.mtgTextPrimary)

                        if isCurrentUser {
                            MtgBadge(text: "You", foregroundColor: .mtgGold, backgroundColor: Color.mtgGold.opacity(0.15), fontWeight: .regular)
                        }

                        if player.isEliminated {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.mtgError)
                                .font(.caption)
                        }
                    }

                    // Commander name
                    if let commanderName = player.commanderName, !commanderName.isEmpty {
                        Text(commanderName)
                            .font(.system(.caption, design: .serif))
                            .italic()
                            .foregroundStyle(Color.mtgTextSecondary)
                    }

                    // Role visibility — only show for unveiled players and leaders
                    // to prevent leaking info when the phone is on the table
                    if player.isUnveiled || player.role == .leader {
                        if canInspectCard {
                            Button {
                                onViewCard?(player)
                            } label: {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(player.role?.color ?? .gray)
                                        .frame(width: 8, height: 8)
                                    Text(player.role?.displayName ?? "")
                                        .font(.caption)
                                        .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
                                    if player.isUnveiled && player.role != .leader {
                                        Text("(Unveiled)")
                                            .font(.caption2)
                                            .foregroundStyle(Color.mtgTextSecondary)
                                    }
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                        .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("View \(player.displayName)'s identity card")
                            .accessibilityHint("Shows their role ability and card details")
                        } else {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(player.role?.color ?? .gray)
                                    .frame(width: 8, height: 8)
                                Text(player.role?.displayName ?? "")
                                    .font(.caption)
                                    .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
                                if player.isUnveiled && player.role != .leader {
                                    Text("(Unveiled)")
                                        .font(.caption2)
                                        .foregroundStyle(Color.mtgTextSecondary)
                                }
                            }
                        }
                    } else if viewModel.isTreacheryActive {
                        Text("Role Hidden")
                            .font(.caption)
                            .foregroundStyle(Color.mtgTextSecondary)
                    }
                }

                Spacer()

                // Life controls
                if !player.isEliminated {
                    HStack(spacing: 12) {
                        Button {
                            viewModel.adjustLife(for: player.id, by: -1)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.mtgAssassin)
                                .background(
                                    Circle()
                                        .fill(Color.mtgAssassin.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Decrease \(player.displayName)'s life")

                        Text("\(player.lifeTotal)")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .foregroundStyle(Color.mtgTextPrimary)
                            .frame(minWidth: 52)
                            .multilineTextAlignment(.center)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: player.lifeTotal)
                            .accessibilityLabel("\(player.lifeTotal) life")

                        Button {
                            viewModel.adjustLife(for: player.id, by: 1)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.mtgSuccess)
                                .background(
                                    Circle()
                                        .fill(Color.mtgSuccess.opacity(0.1))
                                        .frame(width: 40, height: 40)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Increase \(player.displayName)'s life")
                    }
                } else {
                    Text("Eliminated")
                        .font(.caption)
                        .foregroundStyle(Color.mtgError)
                }
            }
            .padding(.vertical, 4)

            // Color picker row (current user only)
            if isCurrentUser && showColorPicker {
                ColorPickerRow(selectedHex: player.playerColor) { hex in
                    Task { await viewModel.updatePlayerColor(hex) }
                }
                .padding(.top, 8)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Player Rows") {
    let vm = GameBoardViewModel(
        gameId: "preview",
        previewPlayers: Player.sampleGamePlayers,
        previewGame: .sampleInProgress,
        currentUserId: "user2"
    )
    ZStack {
        Color.mtgBackground.ignoresSafeArea()
        VStack(spacing: 0) {
            GameBoardPlayerRow(
                player: .sampleGuardian,
                viewModel: vm,
                showColorPicker: .constant(false)
            )
            GameBoardPlayerRow(
                player: .sampleAssassin,
                viewModel: vm,
                showColorPicker: .constant(false)
            )
            GameBoardPlayerRow(
                player: .sampleEliminated,
                viewModel: vm,
                showColorPicker: .constant(false)
            )
        }
        .mtgCardFrame()
        .padding()
    }
}
#endif
