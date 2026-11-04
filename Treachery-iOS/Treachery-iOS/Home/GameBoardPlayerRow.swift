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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // The life controls grow with the text, following the large-title
    // style, so the total stays the largest text in the row.
    @ScaledMetric(relativeTo: .largeTitle) private var lifeTotalSize: CGFloat = 36
    @ScaledMetric(relativeTo: .largeTitle) private var lifeTotalMinWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .largeTitle) private var lifeButtonSize: CGFloat = 32
    @ScaledMetric(relativeTo: .largeTitle) private var lifeButtonCircle: CGFloat = 40
    @ScaledMetric(relativeTo: .largeTitle) private var lifeSpacing: CGFloat = 12
    /// How far above the role's baseline its dot is centered: the middle of
    /// a caption line.
    @ScaledMetric(relativeTo: .caption) private var roleDotLift: CGFloat = 4.5

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

                // Color picker toggle for current user. Its tap area reaches
                // over the start of the name, so it's drawn above the name.
                if isCurrentUser {
                    colorPickerToggle
                        .zIndex(1)
                }

                // The life controls sit beside the name and role while
                // those fit on their lines there, and go underneath them
                // when they don't: with a long name, or larger text.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        playerInfo
                            .frame(maxWidth: .infinity, alignment: .leading)
                        lifeStatus
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        playerInfo
                        lifeStatus
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    // Always fits, so it's laid out at the row's width and
                    // its lines wrap there, even with a name too long for it.
                    .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity)
                }
            }
            .padding(.vertical, 4)

            // Color picker row (current user only)
            if isCurrentUser && showColorPicker {
                ColorPickerRow(selectedHex: player.playerColor) { hex in
                    Task { await viewModel.updatePlayerColor(hex) }
                }
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .asymmetric(
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
            Group {
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
            // The dot keeps its size and place; the area around it takes
            // the tap too.
            .minimumTapTarget()
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
                        .fixedSize(horizontal: false, vertical: true)

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

                // Commander name. It wraps to the width the name and role
                // leave, rather than moving the life controls underneath:
                // with no ideal width, it doesn't count in the row's fit.
                if let commanderName = player.commanderName, !commanderName.isEmpty {
                    Text(commanderName)
                        .font(.system(.caption, design: .serif))
                        .italic()
                        .foregroundStyle(Color.mtgTextSecondary)
                        // All its lines: the stack would otherwise cut it
                        // short at the largest sizes.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minWidth: 0, idealWidth: 0, maxWidth: .infinity, alignment: .leading)
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
                    // The role sits where it does in the other rows; its
                    // tap area reaches above and below it to a full 44pt.
                    roleLabel(showsInfoIcon: true)
                        .minimumTapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View \(player.displayName)'s identity card")
                .accessibilityValue(roleDescription)
                .accessibilityHint("Shows their role ability and card details")
            }
        }
    }

    private func roleLabel(showsInfoIcon: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Circle()
                .fill(player.role?.color ?? .gray)
                .frame(width: 8, height: 8)
                // Centered on the first line of the text, as it is on a
                // line of its own.
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + roleDotLift }
            roleText(showsInfoIcon: showsInfoIcon)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The role, "(Unveiled)" and the info icon as one text, so at the
    /// largest sizes it wraps between them rather than inside a word.
    private func roleText(showsInfoIcon: Bool) -> Text {
        var text = Text(player.role?.displayName ?? "")
            .foregroundStyle(player.role?.textColor ?? Color.mtgTextSecondary)
        if player.isUnveiled && player.role != .leader {
            let unveiled = Text("(Unveiled)")
                .font(.caption2)
                .foregroundStyle(Color.mtgTextSecondary)
            text = Text("\(text) \(unveiled)")
        }
        if showsInfoIcon {
            let icon = Text(Image(systemName: "info.circle"))
                .font(.caption2)
                .foregroundStyle(player.role?.color ?? Color.mtgTextSecondary)
            text = Text("\(text) \(icon)")
        }
        // The role, and the spaces, in caption; the parts above keep theirs.
        return text.font(.caption)
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
            HStack(spacing: lifeSpacing) {
                lifeButton("minus.circle.fill", color: .mtgAssassin, amount: -1)

                Text("\(player.lifeTotal)")
                    .font(.system(size: lifeTotalSize, weight: .bold, design: .serif))
                    .foregroundStyle(Color.mtgTextPrimary)
                    // A total never wraps; the name beside it does instead.
                    .fixedSize()
                    .frame(minWidth: lifeTotalMinWidth)
                    // Rolling digits and a spring, or with Reduce Motion a
                    // cross-fade.
                    .contentTransition(reduceMotion ? .opacity : .numericText())
                    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.3, dampingFraction: 0.6), value: player.lifeTotal)

                lifeButton("plus.circle.fill", color: .mtgSuccess, amount: 1)
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
                .foregroundStyle(Color.mtgErrorText)
                .accessibilityHidden(true)
        }
    }

    /// A − or + beside the total: its circle as before, and a tap area of
    /// at least 44pt that reaches into the spacing around it.
    private func lifeButton(_ systemName: String, color: Color, amount: Int) -> some View {
        Button {
            viewModel.adjustLife(for: player.id, by: amount)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: lifeButtonSize))
                .foregroundStyle(color)
                .background(
                    Circle()
                        .fill(color.opacity(0.1))
                        .frame(width: lifeButtonCircle, height: lifeButtonCircle)
                )
                .minimumTapTarget()
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canAdjustLife)
        .opacity(viewModel.canAdjustLife ? 1 : 0.35)
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
