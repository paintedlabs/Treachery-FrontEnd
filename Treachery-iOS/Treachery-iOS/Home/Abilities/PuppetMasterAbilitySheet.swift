//
//  PuppetMasterAbilitySheet.swift
//  Treachery-iOS
//

import SwiftUI

struct PuppetMasterAbilitySheet: View {
    @ObservedObject var viewModel: GameBoardViewModel
    let players: [Player]
    @Environment(\.dismiss) var dismiss

    // Local swap state: playerId -> cardId
    @State private var assignments: [String: String] = [:]
    @State private var firstSelection: String?
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        abilityReminderSection
                        instructionBadge
                        playerListSection
                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        viewModel.dismissAbility()
                        dismiss()
                    }
                    .foregroundStyle(Color.mtgTextSecondary)
                }
            }
            .onAppear {
                // Initialize assignments from current state
                for player in players {
                    if let cardId = player.identityCardId {
                        assignments[player.id] = cardId
                    }
                }
            }
            .confirmationDialog(
                "Confirm Redistribution",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                Button("Redistribute Cards") {
                    Task {
                        await viewModel.resolvePuppetMaster(redistributions: assignments)
                    }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                let swapCount = countSwaps()
                Text("\(swapCount) card\(swapCount == 1 ? "" : "s") will be redistributed. Non-Leader cards will be turned face down.")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 40))
                .foregroundStyle(Color.mtgTraitor)

            Text("The Puppet Master")
                .font(.system(.title2, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgTextPrimary)
        }
    }

    private var abilityReminderSection: some View {
        Text("Redistribute control of any number of other identity cards. Each player must control one identity card. Non-Leader cards are turned face down.")
            .font(.caption)
            .foregroundStyle(Color.mtgTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var instructionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: firstSelection == nil ? "hand.tap" : "hand.tap.fill")
                .foregroundStyle(Color.mtgGold)
            Text(firstSelection == nil
                 ? "Tap a player's card to select it for swapping"
                 : "Now tap another player to swap with")
                .font(.caption)
                .foregroundStyle(Color.mtgTextPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.mtgCardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var playerListSection: some View {
        VStack(spacing: 8) {
            ForEach(players) { player in
                playerSwapRow(player)
            }
        }
    }

    private func playerSwapRow(_ player: Player) -> some View {
        let currentCardId = assignments[player.id]
        let card = currentCardId.flatMap { viewModel.identityCard(withId: $0) }
        let originalCardId = players.first(where: { $0.id == player.id })?.identityCardId
        let wasSwapped = currentCardId != originalCardId
        let isFirstSelected = firstSelection == player.id

        return Button {
            handleTap(playerId: player.id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(player.displayName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Color.mtgTextPrimary)

                        if wasSwapped {
                            MtgBadge(
                                text: "SWAPPED",
                                foregroundColor: .mtgBackground,
                                backgroundColor: Color.mtgTraitor
                            )
                        }
                    }

                    if let card {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(card.role.color)
                                .frame(width: 8, height: 8)
                            Text(card.name)
                                .font(.caption)
                                .foregroundStyle(card.role.color)
                        }
                    }
                }

                Spacer()

                if isFirstSelected {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .foregroundStyle(Color.mtgGold)
                        .font(.title3)
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                        .foregroundStyle(Color.mtgTextSecondary)
                        .font(.caption)
                }
            }
            .padding(12)
            .background(isFirstSelected ? Color.mtgTraitor.opacity(0.15) : Color.mtgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isFirstSelected ? Color.mtgTraitor : (wasSwapped ? Color.mtgTraitor.opacity(0.5) : Color.mtgDivider),
                            lineWidth: isFirstSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if countSwaps() > 0 {
                Button {
                    showConfirmation = true
                } label: {
                    Text("Confirm Redistribution")
                        .fontWeight(.semibold)
                }
                .buttonStyle(MtgPrimaryButtonStyle())

                Button {
                    withAnimation {
                        resetAssignments()
                    }
                } label: {
                    Text("Undo All Swaps")
                        .fontWeight(.medium)
                }
                .buttonStyle(MtgSecondaryButtonStyle())
            }

            Button {
                viewModel.dismissAbility()
                dismiss()
            } label: {
                Text("Decline")
                    .fontWeight(.medium)
            }
            .buttonStyle(MtgSecondaryButtonStyle())
        }
    }

    // MARK: - Swap Logic

    private func handleTap(playerId: String) {
        if let first = firstSelection {
            if first == playerId {
                // Deselect
                withAnimation(.easeInOut(duration: 0.2)) {
                    firstSelection = nil
                }
            } else {
                // Swap cards
                withAnimation(.easeInOut(duration: 0.2)) {
                    let cardA = assignments[first]
                    let cardB = assignments[playerId]
                    assignments[first] = cardB
                    assignments[playerId] = cardA
                    firstSelection = nil
                }
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                firstSelection = playerId
            }
        }
    }

    private func resetAssignments() {
        for player in players {
            if let cardId = player.identityCardId {
                assignments[player.id] = cardId
            }
        }
        firstSelection = nil
    }

    private func countSwaps() -> Int {
        var count = 0
        for player in players {
            if assignments[player.id] != player.identityCardId {
                count += 1
            }
        }
        return count
    }
}

#if DEBUG
#Preview("Puppet Master") {
    let vm = GameBoardViewModel(
        gameId: "preview",
        previewPlayers: Player.sampleGamePlayers,
        previewGame: .sampleInProgress,
        currentUserId: "user4"
    )
    PuppetMasterAbilitySheet(
        viewModel: vm,
        players: [.sampleLeader, .sampleGuardian, .sampleAssassin]
    )
}
#endif
