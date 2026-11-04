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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCurrentUser: Bool {
        player.userId == viewModel.currentUserId
    }

    /// Whether this player's card can be inspected by the current user.
    /// True for unveiled players and leaders (but not yourself -- you have the header).
    /// Face-down cards (from Puppet Master/Metamorph swap) are not inspectable unless you're the Puppet Master.
    private var canInspectCard: Bool {
        guard !isCurrentUser else { return false }
        guard viewModel.identityCard(for: player) != nil else { return false }
        return viewModel.canSeeRole(of: player)
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
                    colorPickerToggle
                }

                // At the accessibility text sizes the name needs the row's
                // width, so the life controls go underneath it.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        playerInfo
                        lifeStatus
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    playerInfo
                    Spacer()
                    lifeStatus
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

    private var playerInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            // VoiceOver reads these as one: name, commander and role.
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
                            .accessibilityLabel("Eliminated")
                    }
                }

                // Commander name
                if let commanderName = player.commanderName, !commanderName.isEmpty {
                    Text(commanderName)
                        .font(.system(.caption, design: .serif))
                        .italic()
                        .foregroundStyle(Color.mtgTextSecondary)
                }

                // Role visibility — only show for visible players
                // Face-down cards (from ability swaps) stay hidden
                if viewModel.canSeeRole(of: player) {
                    if !canInspectCard {
                        roleLabel(showsInfoIcon: false)
                    }
                } else if viewModel.isTreacheryActive {
                    Text("Role Hidden")
                        .font(.caption)
                        .foregroundStyle(Color.mtgTextSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            // A role whose card can be opened is a button of its own.
            if canInspectCard {
                Button {
                    onViewCard?(player)
                } label: {
                    roleLabel(showsInfoIcon: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(player.displayName)'s identity card")
                .accessibilityValue(roleDescription)
                .accessibilityHint("Shows their role ability and card details")
            }
        }
    }

    private func roleLabel(showsInfoIcon: Bool) -> some View {
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
            if showsInfoIcon {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
            }
        }
    }

    /// The role as the view-card button gives it to VoiceOver.
    private var roleDescription: String {
        let role = player.role?.displayName ?? ""
        return player.isUnveiled && player.role != .leader ? "\(role), unveiled" : role
    }

    @ViewBuilder
    private var lifeStatus: some View {
        // Life controls. A spectator sees the totals but can't
        // change them.
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
                .disabled(!viewModel.canAdjustLife)
                .opacity(viewModel.canAdjustLife ? 1 : 0.35)

                Text("\(player.lifeTotal)")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .foregroundStyle(Color.mtgTextPrimary)
                    .frame(minWidth: 52)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: player.lifeTotal)

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
                .disabled(!viewModel.canAdjustLife)
                .opacity(viewModel.canAdjustLife ? 1 : 0.35)
            }
            // One element for VoiceOver: the total, which a swipe up or
            // down changes by 1, as the buttons do.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(player.displayName) life")
            .accessibilityValue("\(player.lifeTotal)")
            .modifier(LifeAdjustment(isEnabled: viewModel.canAdjustLife) { direction in
                viewModel.adjustLife(for: player.id, direction)
            })
        } else {
            // VoiceOver says so with their name already: the mark beside it
            // reads "Eliminated".
            Text("Eliminated")
                .font(.caption)
                .foregroundStyle(Color.mtgError)
                .accessibilityHidden(true)
        }
    }
}

/// Lets VoiceOver change a life total with a swipe up or down, only while
/// the signed-in player can change it. Otherwise it's read but not offered
/// as adjustable.
private struct LifeAdjustment: ViewModifier {
    let isEnabled: Bool
    let adjust: (AccessibilityAdjustmentDirection) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.accessibilityAdjustableAction(adjust)
        } else {
            content
        }
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
