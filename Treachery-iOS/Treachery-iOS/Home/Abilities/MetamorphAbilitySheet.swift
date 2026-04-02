//
//  MetamorphAbilitySheet.swift
//  Treachery-iOS
//

import SwiftUI

struct MetamorphAbilitySheet: View {
    @ObservedObject var viewModel: GameBoardViewModel
    let eliminatedPlayers: [Player]
    @Environment(\.dismiss) var dismiss
    @State private var selectedPlayerId: String?
    @State private var showConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.mtgBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        abilityReminderSection

                        if eliminatedPlayers.isEmpty {
                            noTargetsSection
                        } else {
                            targetSelectionSection
                            actionButtons
                        }
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
            .confirmationDialog(
                "Steal Identity",
                isPresented: $showConfirmation,
                titleVisibility: .visible
            ) {
                if let targetId = selectedPlayerId,
                   let target = eliminatedPlayers.first(where: { $0.id == targetId }),
                   let card = viewModel.identityCard(for: target) {
                    Button("Replace The Metamorph with \(card.name)") {
                        Task {
                            await viewModel.resolveMetamorph(targetPlayerId: targetId)
                        }
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your identity card will be removed from the game and replaced with the stolen card. This cannot be undone.")
            }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.swap")
                .font(.system(size: 40))
                .foregroundStyle(Color.mtgTraitor)

            Text("The Metamorph")
                .font(.system(.title2, design: .serif))
                .fontWeight(.bold)
                .foregroundStyle(Color.mtgTextPrimary)
        }
    }

    private var abilityReminderSection: some View {
        Text("As an opponent loses the game, you may remove The Metamorph and gain control of that player's identity card. Turn it face down if it isn't a Leader.")
            .font(.caption)
            .foregroundStyle(Color.mtgTextSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal)
    }

    private var noTargetsSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.slash")
                .font(.system(size: 32))
                .foregroundStyle(Color.mtgTextSecondary)

            Text("No eliminated opponents yet")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color.mtgTextPrimary)

            Text("This ability triggers when an opponent loses the game this turn. Keep this in mind for the rest of the turn.")
                .font(.caption)
                .foregroundStyle(Color.mtgTextSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Color.mtgSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.mtgDivider, lineWidth: 1)
        )
    }

    private var targetSelectionSection: some View {
        VStack(spacing: 12) {
            Text("Steal an Identity")
                .font(.headline)
                .foregroundStyle(Color.mtgGold)

            ForEach(eliminatedPlayers) { player in
                targetRow(player)
            }
        }
    }

    private func targetRow(_ player: Player) -> some View {
        let isSelected = selectedPlayerId == player.id
        let card = viewModel.identityCard(for: player)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedPlayerId = isSelected ? nil : player.id
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.mtgTextPrimary)
                        .strikethrough()

                    if let card {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(card.role.color)
                                .frame(width: 8, height: 8)
                            Text(card.name)
                                .font(.caption)
                                .foregroundStyle(card.role.color)
                        }

                        Text(card.abilityText)
                            .font(.caption2)
                            .foregroundStyle(Color.mtgTextSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.mtgGold)
                        .font(.title3)
                }
            }
            .padding(12)
            .background(isSelected ? Color.mtgTraitor.opacity(0.15) : Color.mtgSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.mtgTraitor : Color.mtgDivider, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if selectedPlayerId != nil {
                Button {
                    showConfirmation = true
                } label: {
                    Text("Steal Identity")
                        .fontWeight(.semibold)
                }
                .buttonStyle(MtgPrimaryButtonStyle())
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
}

#if DEBUG
#Preview("Metamorph - With Targets") {
    let vm = GameBoardViewModel(
        gameId: "preview",
        previewPlayers: Player.sampleGamePlayers,
        previewGame: .sampleInProgress,
        currentUserId: "user4"
    )
    MetamorphAbilitySheet(
        viewModel: vm,
        eliminatedPlayers: [.sampleEliminated]
    )
}

#Preview("Metamorph - No Targets") {
    let vm = GameBoardViewModel(
        gameId: "preview",
        previewPlayers: Player.sampleGamePlayers,
        previewGame: .sampleInProgress,
        currentUserId: "user4"
    )
    MetamorphAbilitySheet(
        viewModel: vm,
        eliminatedPlayers: []
    )
}
#endif
